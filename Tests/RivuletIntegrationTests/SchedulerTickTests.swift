import Foundation
import SQLKit
import Testing
@testable import RivuletCore

/// One tick of the scheduler, read from `internal/cli/scheduler.go` and `internal/worker/pool.go`
/// at commit `c4d54f87`: the tick selects the batch, hands each job to a runner, and reports what
/// each run produced. What these pins can fail on, each checked by patching the rule and
/// reverting: that the tick runs every job of the selected batch exactly once and nothing outside
/// it (the control rows are not due, disabled, or at the error limit), that an empty batch runs
/// nothing, that a failing job does not stop the rest and reports its typed case rather than
/// wording, and that through the real pipeline the tick takes the non-forced path — the worker
/// calls `RefreshFeed` with `forceRefresh: false`, so the request carries the stored validators —
/// and that the schedule the pipeline wrote is the one the next tick reads. What they cannot fail
/// on: the pool-size cap itself, because pinning a cap would need a timed wait, which the
/// determinism rule forbids, so the pins show only that every job runs once; the order the
/// outcomes arrive in, which concurrency does not fix; the reference's logging, because
/// RivuletCore has no logging layer and `tick()` answers with outcomes instead; and that the
/// reference pushes jobs to a channel without awaiting the batch, so a slow batch can overlap the
/// next tick there and not here — both recorded in `docs/parity.md`. The recorder runner stands in
/// for the pipeline in the selection pins, which therefore pin the selection and the outcome
/// mapping, not the fetch path; the pipeline path is pinned by the last test.
@Suite struct SchedulerTickTests {
    /// The injected instant, after the process clock, so a pin can tell the clock it was given from
    /// the process one.
    private let now = 2_000_000_000
    private let options = SchedulerOptions.defaults

    @Test func tickRunsEveryJobOfTheSelectedBatchExactlyOnceAndNothingElse() async throws {
        try await withMigratedStorage { _, storage in
            let alice = try await seedGraph(storage, username: "alice")
            let bob = try await seedGraph(storage, username: "bob")
            let firstDue = try await seedRow(storage, alice, url: "http://host.test/first",
                nextCheckAt: 1_800_000_000)
            let secondDue = try await seedRow(storage, bob, url: "http://host.test/second",
                nextCheckAt: 1_900_000_000)

            // The three controls are selected out by the batch rules the batch suite pins; here
            // they pin that the tick runs what the batch answered with, not the whole table.
            _ = try await seedRow(storage, alice, url: "http://host.test/equal", nextCheckAt: now)
            _ = try await seedRow(storage, alice, url: "http://host.test/disabled",
                nextCheckAt: 1_900_000_001, disabled: true)
            _ = try await seedRow(storage, alice, url: "http://host.test/at-limit",
                nextCheckAt: 1_900_000_002, errorCount: 3)

            let runner = RecorderRunner()
            let scheduler = Scheduler(storage: storage, clock: FixedClock(now: now),
                options: options, runner: runner)
            let outcomes = try await scheduler.tick()

            #expect(await runner.received().sorted { $0.feedID < $1.feedID } == [
                job(firstDue, alice, "http://host.test/first"),
                job(secondDue, bob, "http://host.test/second"),
            ])
            #expect(outcomes.count == 2)
            #expect(outcomes.allSatisfy(isRefreshed))
        }
    }

    @Test func anEmptyBatchRunsNothingAndProducesNoOutcomes() async throws {
        try await withMigratedStorage { _, storage in
            let graph = try await seedGraph(storage, username: "alice")
            // Not due relative to the injected instant, so the batch is empty.
            _ = try await seedRow(storage, graph, url: "http://host.test/not-due",
                nextCheckAt: 2_100_000_000)

            let runner = RecorderRunner()
            let scheduler = Scheduler(storage: storage, clock: FixedClock(now: now),
                options: options, runner: runner)
            let outcomes = try await scheduler.tick()

            #expect(outcomes.isEmpty)
            #expect(await runner.received().isEmpty)
        }
    }

    @Test func aFailingJobDoesNotStopTheRestAndIsReportedAsItsTypedCase() async throws {
        try await withMigratedStorage { _, storage in
            let graph = try await seedGraph(storage, username: "alice")
            let failing = try await seedRow(storage, graph, url: "http://host.test/failing",
                nextCheckAt: 1_800_000_000)
            let succeeding = try await seedRow(storage, graph, url: "http://host.test/succeeding",
                nextCheckAt: 1_900_000_000)

            let runner = RecorderRunner(failures: [failing: FetchError.status(500)])
            let scheduler = Scheduler(storage: storage, clock: FixedClock(now: now),
                options: options, runner: runner)
            let outcomes = try await scheduler.tick()

            // The reference worker logs the failure and keeps reading the channel, so one failed
            // run cannot stop the batch; the failure is reported as the typed case, not as wording.
            #expect(await runner.received().sorted { $0.feedID < $1.feedID } == [
                job(failing, graph, "http://host.test/failing"),
                job(succeeding, graph, "http://host.test/succeeding"),
            ])
            #expect(outcomes.count == 2)

            let failed = try #require(outcomes.compactMap(failureCase).first)
            #expect(failed.job == job(failing, graph, "http://host.test/failing"))
            #expect((failed.error as? FetchError) == FetchError.status(500))
            #expect(outcomes.contains {
                if case .refreshed(let job) = $0 { return job.feedID == succeeding }
                return false
            })
        }
    }

    @Test func theTickTakesTheNonForcedPathAndTheNextTickReadsTheWrittenSchedule() async throws {
        try await withMigratedStorage { _, storage in
            try await FetchTestSupport.withServer(behaviors: ["/feed": answer(rss([
                ("<p>A</p>", "https://example.org/a"),
            ]))]) { server in
                try await FetchTestSupport.withFetcher(options: FetchTestSupport.options()) {
                    fetcher in
                    let graph = try await seedGraph(storage, username: "alice")
                    let feedURL = server.url("/feed").absoluteString
                    let feedID = try await seedRow(storage, graph, url: feedURL,
                        nextCheckAt: 1_800_000_000)
                    try await storeValidators(storage, feedID: feedID, etag: "\"stored-etag\"",
                        lastModified: "Fri, 16 Oct 2026 09:00:00 GMT")

                    // One clock for both, so the schedule the pipeline writes is the one the next
                    // tick reads.
                    let clock = FixedClock(now: now)
                    let pipeline = RefreshPipeline(storage: storage, fetcher: fetcher,
                        options: FetchTestSupport.options(), nextCheck: NextCheckPolicy(),
                        clock: clock)
                    let scheduler = Scheduler(storage: storage, clock: clock, options: options,
                        runner: pipeline)

                    let outcomes = try await scheduler.tick()
                    #expect(outcomes.count == 1)
                    let outcome = try #require(outcomes.first)
                    guard case .refreshed(let runJob) = outcome else {
                        Issue.record("expected the refreshed case")
                        return
                    }
                    #expect(runJob == job(feedID, graph, feedURL))

                    // The worker path: `RefreshFeed` with `forceRefresh` false, so the stored
                    // validators reach the request. The forced path sends none, so the header can
                    // only come from the non-forced call.
                    let sent = try #require(server.received(for: "/feed").first)
                    #expect(sent.headers["If-None-Match"] == "\"stored-etag\"")

                    // The pipeline rescheduled to the injected instant plus the policy interval,
                    // which is past it, so the second tick finds nothing due.
                    #expect(try await scheduler.tick().isEmpty)
                }
            }
        }
    }

    // MARK: - Helpers

    /// The runner the selection pins read: it records what the tick handed it and throws the error
    /// the test names for one feed, standing in for the pipeline so the pin reads the selection and
    /// the outcome mapping instead of the fetch path.
    private actor RecorderRunner: JobRunner {
        private var jobs: [RefreshJob] = []
        private let failures: [Int: any Error]

        init(failures: [Int: any Error] = [:]) {
            self.failures = failures
        }

        func run(job: RefreshJob) async throws {
            jobs.append(job)
            if let error = failures[job.feedID] { throw error }
        }

        func received() -> [RefreshJob] { jobs }
    }

    private func isRefreshed(_ outcome: JobOutcome) -> Bool {
        switch outcome {
        case .refreshed:
            return true
        case .failed:
            return false
        }
    }

    private func failureCase(_ outcome: JobOutcome) -> (job: RefreshJob, error: any Error)? {
        switch outcome {
        case .refreshed:
            return nil
        case .failed(let job, let error):
            return (job, error)
        }
    }

    /// The expected job for a row, in the order the reference's `model.Job` names its fields.
    private func job(_ feedID: Int, _ graph: (userID: Int, categoryID: Int), _ url: String)
        -> RefreshJob {
        RefreshJob(feedID: feedID, userID: graph.userID, feedURL: url)
    }

    private func seedGraph(_ storage: SQLiteStorage, username: String) async throws
        -> (userID: Int, categoryID: Int) {
        try await storage.withConnection { connection in
            let userID = try await seedUser(connection, username: username)
            let categoryID = try await seedCategory(connection, userID: userID, title: "Tech")
            return (userID, categoryID)
        }
    }

    private func seedRow(_ storage: SQLiteStorage, _ graph: (userID: Int, categoryID: Int),
        url: String, nextCheckAt: Int, errorCount: Int = 0, disabled: Bool = false) async throws
        -> Int {
        try await storage.withConnection { connection in
            let feedID = try await seedFeed(connection, userID: graph.userID,
                categoryID: graph.categoryID, url: url)
            try await sqlDatabase(connection).raw("""
                UPDATE feeds SET next_check_at = \(bind: nextCheckAt),
                    parsing_error_count = \(bind: errorCount), disabled = \(bind: disabled)
                WHERE id = \(bind: feedID)
                """).run()
            return feedID
        }
    }

    private func storeValidators(_ storage: SQLiteStorage, feedID: Int, etag: String,
        lastModified: String) async throws {
        try await storage.withConnection { connection in
            let feed = try #require(await FeedRepository(connection).fetch(id: feedID))
            feed.etag = etag
            feed.lastModified = lastModified
            try await feed.update(on: connection)
        }
    }

    private func rss(_ entries: [(content: String, url: String)]) -> String {
        var document = "<rss version=\"2.0\"><channel><title>T</title>"
        for entry in entries {
            document += "<item><title>E</title><link>\(entry.url)</link>"
                + "<description>\(entry.content)</description></item>"
        }
        return document + "</channel></rss>"
    }

    private func answer(_ body: String) -> StubFeedServer.Behavior {
        StubFeedServer.Behavior(body: Data(body.utf8))
    }
}