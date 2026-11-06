import SQLKit
import Testing
@testable import RivuletCore

/// What `serve` does with the cadence loop, read as the calls the wiring makes through its seams.
///
/// The wiring is the piece `docs/plan/stage-4-ingestion.md` left out of stage 4 and the piece
/// `CadenceLoopTests` could not reach: it builds the loop from the values the environment gives,
/// runs it to the end, and runs the shutdown hook after the loop returns, which is the rule the
/// stage-6 process checks read as "no lost refresh batch". The pins drive the wiring with test
/// seams so no pin waits: the cadence answers its decisions on a pattern, the runner records the
/// jobs it was given, and the hook records its call.
///
/// What these pins can fail on, each checked by patching the rule and reverting: that the interval
/// the loop is built with is the value the environment names, not the default; that the wiring runs
/// nothing when the first decision answers stop; that every job of an in-flight tick runs before
/// the hook, which is the hook running after the loop returns; that the batch values the
/// environment names reach the dispatch through the wiring, not through the defaults; and that a
/// failing hook is propagated as the error the caller reads, which is what the CLI reads as the
/// exit code.
///
/// What these pins cannot fail on: that the wiring starts the HTTP server, or the order between the
/// server's stop and the hook, because the server is not a seam here — the process suite reads the
/// response as the event that proves dispatch; that the clean run returns, which the pins read only
/// as the absence of a thrown error in the pins that do not make the hook fail, so the pin that
/// names the propagation asserts only the failing half; that any interval passes, since the pattern
/// seam answers without sleeping; which row the batch picks when two rows are stamped at the same
/// instant, so the pins name one row as the pick by stamping it earlier; the names the pins read
/// the calls by, which the test writes; the real signal source the wiring uses in the binary, which
/// no in-process test reaches, so the pins read the wiring through the seam and the process suite
/// reads the signal path as the event the child exits on; what the wiring does with the reports the
/// loop answers with, which has no layer here, the reference writing them to `slog`; and the other
/// batch values the environment names — the error limit and the per-host limit — which reach the
/// builder as `SchedulerBatchTests` pin, so what the wiring adds is only that the values come from
/// the environment, read through the one value the pins can make fail.
@Suite struct ServeWiringTests {
    @Test func envIntervalReachesTheSeamNotTheDefaults() async throws {
        try await withMigratedStorage { _, storage in
            let recorder = Recorder()
            let wiring = try makeWiring(storage: storage, env: ["POLLING_FREQUENCY": "113"],
                pattern: 1, recorder: recorder)
            _ = try await wiring.run()

            // 113 minutes is not the default hour, so a wiring built from the defaults answered
            // 3600 here.
            #expect(recorder.all() == [.wait(113 * 60), .stop, .hook],
                "the interval the wiring handed the seam: \(recorder.all())")
        }
    }

    @Test func theFirstDecisionAnsweredStopRunsNoTick() async throws {
        try await withMigratedStorage { _, storage in
            let recorder = Recorder()
            // The row is due at any instant, so a wiring that ran the tick before answering the
            // first decision recorded a job here.
            let userID = try await seedAccount(storage, username: "alice")
            let category = try await seedCategoryFor(storage, userID: userID)
            _ = try await seedRow(storage, userID: userID, categoryID: category,
                url: "http://host.test/due-then-stop", nextCheckAt: 1)

            let wiring = try makeWiring(storage: storage, env: ["POLLING_FREQUENCY": "90"],
                pattern: 0, recorder: recorder)
            _ = try await wiring.run()

            #expect(recorder.all() == [.stop, .hook],
                "the first decision answered stop, so nothing ran: \(recorder.all())")
        }
    }

    @Test func everyJobOfTheInFlightTickRunsBeforeTheHook() async throws {
        try await withMigratedStorage { _, storage in
            let recorder = Recorder()
            let userID = try await seedAccount(storage, username: "alice")
            let category = try await seedCategoryFor(storage, userID: userID)
            _ = try await seedRow(storage, userID: userID, categoryID: category,
                url: "http://host.test/in-flight", nextCheckAt: 1)

            // The hook is the shutdown the process suite reads as the WAL fact; here the pins read
            // that a tick the wiring started runs to its end before the hook, which is the rule the
            // reference holds through `pool.Shutdown`.
            let wiring = try makeWiring(storage: storage, env: ["POLLING_FREQUENCY": "90"],
                pattern: 1, recorder: recorder)
            _ = try await wiring.run()

            #expect(recorder.all() == [.wait(90 * 60), .job("http://host.test/in-flight"), .stop,
                .hook], "the wiring ran the tick, then the hook once: \(recorder.all())")
        }
    }

    @Test func envBatchSizeReachesTheDispatchThroughTheWiring() async throws {
        try await withMigratedStorage { _, storage in
            let recorder = Recorder()
            // The two rows are due at any instant; the earlier stamp is the one the batch order
            // answers first, so the single job the pin reads is the env's single-slot batch. A
            // wiring built from the defaults ran both.
            let userID = try await seedAccount(storage, username: "alice")
            let category = try await seedCategoryFor(storage, userID: userID)
            _ = try await seedRow(storage, userID: userID, categoryID: category,
                url: "http://host.test/env-batch-pick", nextCheckAt: 1)
            _ = try await seedRow(storage, userID: userID, categoryID: category,
                url: "http://host.test/env-batch-second", nextCheckAt: 2)

            let wiring = try makeWiring(storage: storage,
                env: ["POLLING_FREQUENCY": "90", "BATCH_SIZE": "1"],
                pattern: 1, recorder: recorder)
            _ = try await wiring.run()

            #expect(recorder.all() == [.wait(90 * 60), .job("http://host.test/env-batch-pick"),
                .stop, .hook], "the env value reached the dispatch: \(recorder.all())")
        }
    }

    @Test func failingHookPropagatesAsTheErrorTheCallerReads() async throws {
        try await withMigratedStorage { _, storage in
            let failing = Recorder()
            let wiring = try makeWiring(storage: storage, env: ["POLLING_FREQUENCY": "90"],
                pattern: 0, recorder: failing, hookThrows: true)
            // The error leaves the wiring, which is the shape the CLI reads as exit 1; a wiring
            // that swallowed the hook failure answered a clean run here.
            var thrown: any Error?
            do {
                _ = try await wiring.run()
            } catch {
                thrown = error
            }
            #expect(thrown as? WiringHookFailure == WiringHookFailure.hookFailed,
                "the hook error the wiring propagated")
            #expect(failing.all() == [.stop, .hook],
                "the hook ran once before the error left: \(failing.all())")
        }
    }

    // MARK: - Setup

    private enum Event: Equatable, Sendable {
        case wait(Int)
        case stop
        case job(String)
        case hook
    }

    enum WiringHookFailure: Error, Equatable {
        case hookFailed
    }

    private final class Recorder: @unchecked Sendable {
        private var calls: [Event] = []

        func record(_ call: Event) {
            calls.append(call)
        }

        func all() -> [Event] {
            calls
        }
    }

    /// The cadence the pins drive: it records the interval it was given and answers keep-going for
    /// the number of decisions the pin names, then stop, so no pin waits for an interval.
    private final class PatternCadence: Cadence, @unchecked Sendable {
        private let keeps: Int
        private let recorder: Recorder
        private var decisions = 0

        init(keeps: Int, recorder: Recorder) {
            self.keeps = keeps
            self.recorder = recorder
        }

        func wait(for interval: Duration) async -> Bool {
            decisions += 1
            if decisions <= keeps {
                recorder.record(.wait(Int(interval.components.seconds)))
                return true
            }
            recorder.record(.stop)
            return false
        }
    }

    private final class RecordingRunner: JobRunner, @unchecked Sendable {
        private let recorder: Recorder

        init(recorder: Recorder) {
            self.recorder = recorder
        }

        func run(job: RefreshJob) async throws {
            recorder.record(.job(job.feedURL))
        }
    }

    private final class RecordingHook: ShutdownHook, @unchecked Sendable {
        private let recorder: Recorder
        private let throwsError: Bool

        init(recorder: Recorder, throwsError: Bool = false) {
            self.recorder = recorder
            self.throwsError = throwsError
        }

        func run() async throws {
            recorder.record(.hook)
            if throwsError { throw WiringHookFailure.hookFailed }
        }
    }

    private func makeWiring(storage: SQLiteStorage, env: [String: String], pattern: Int,
        recorder: Recorder, hookThrows: Bool = false) throws -> ServeWiring {
        // The config value the pins read is the one the wiring hands the seams; the storage is the
        // test's own, so the database path the config names is not read by any pin.
        var fullEnv = env
        fullEnv["DATABASE_URL"] = "/tmp/unused"
        let config = try Config.load(environment: fullEnv)
        return ServeWiring(config: config, storage: storage,
            cadence: PatternCadence(keeps: pattern, recorder: recorder),
            runner: RecordingRunner(recorder: recorder),
            hook: RecordingHook(recorder: recorder, throwsError: hookThrows))
    }

    private func seedAccount(_ storage: SQLiteStorage, username: String) async throws -> Int {
        try await storage.withConnection { connection in
            try await seedUser(connection, username: username)
        }
    }

    /// One feed in the category the pin seeds, with the schedule the pin names as the stamp, so the
    /// batch reads it as due. The row is stamped in the past, so the batch answers against the
    /// process clock the wiring was built with. The category is seeded once per pin because the
    /// storage rule answers a duplicate title for the same account as a conflict, and a pin that
    /// wrote the same title twice could not reach the read it names.
    private func seedRow(_ storage: SQLiteStorage, userID: Int, categoryID: Int, url: String,
        nextCheckAt: Int) async throws -> Int {
        try await storage.withConnection { connection in
            let feedID = try await seedFeed(connection, userID: userID, categoryID: categoryID,
                url: url)
            try await sqlDatabase(connection).raw("""
                UPDATE feeds SET next_check_at = \(bind: nextCheckAt) WHERE id = \(bind: feedID)
                """).run()
            return feedID
        }
    }

    private func seedCategoryFor(_ storage: SQLiteStorage, userID: Int) async throws -> Int {
        try await storage.withConnection { connection in
            try await seedCategory(connection, userID: userID, title: "Tech")
        }
    }
}

