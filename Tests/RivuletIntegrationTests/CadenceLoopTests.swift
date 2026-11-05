import Foundation
import SQLKit
import Testing
@testable import RivuletCore

/// The cadence loop the reference's `feedScheduler` goroutine is (`internal/cli/scheduler.go` at
/// commit `c4d54f87`), read as the calls the loop and the tick make through the seams they call
/// through.
///
/// The reference waits first — `for range time.Tick(frequency)` fires only after the interval, so
/// the first batch read happens after the first interval — and it reads the batch again on each
/// firing, logging a failure and going on. The port's shape is the same through a seam, which is
/// what the determinism rules need: a test drives the cadence instead of sleeping, so what the pins
/// read is the order and the count of the calls the loop made, and the instant each read was made
/// against.
///
/// What these pins can fail on, each checked by patching the rule and reverting: that the first
/// read happens after the first wait; that every wait is given the interval the loop was built
/// with; that there is one read per wait and no extra read; that each read answers the instant the
/// clock gives at that read, not one instant captured at the start; that a failing read is reported
/// and the loop runs again; that an empty read reports nothing and the loop runs again; that the
/// loop reads nothing after the seam answers that it stops; and that every job of a tick runs
/// before the next read, which is the port's shape, because the reference pushes the batch to a
/// channel without awaiting it.
///
/// What these pins cannot fail on: that any time passes — the seam stands in for a sleep, so a pin
/// can read the interval as the value handed to the seam and nothing about a real interval; the
/// number of iterations, which is the answer the seam gives rather than a rule of the loop; the
/// order the jobs of one tick are recorded in, which concurrency does not fix, so the pins read the
/// calls across the boundary of a tick; the shape and the field names of a report, which are the
/// port's choice; the names the pins read the calls by, which the test writes; that the reference
/// has no stop rule at all — its ticker goroutine runs until the process exits — so these pins read
/// only that the loop obeys the seam's answer, and the stop seam itself is the port's own rule
/// recorded in `docs/parity.md`; the reference's second ticker for the cleanup tasks, which this
/// port has no loop for and which `RetentionTests` pin as storage rules; the pool cap, which no
/// test can assert without a timed wait; the real seam implementation, which sleeps and cannot be
/// observed without one, so it lands with the process harness; the wiring that starts the loop for
/// `serve` and the signal that asks it to stop, which the process-level suite pins; and the
/// reference's log lines, which have no layer here.
@Suite struct CadenceLoopTests {
    /// The instant the loop starts on: after the process clock, so a pin can tell the clock it was
    /// given from the process one.
    private let start = 3_000_000_000

    /// The interval the loop is built with, named apart from the reference's cadence of an hour, so
    /// a pin can tell the value the loop was handed from the value it could have written itself.
    private let interval = Duration.seconds(900)
    private let intervalSeconds = 900

    @Test func theFirstReadHappensAfterTheFirstWait() async throws {
        try await withMigratedStorage { _, storage in
            let graph = try await seedGraph(storage, username: "alice")
            // Nothing is due at the instant the loop starts on; the row is due at the first
            // interval, so a patch that read before waiting answered it as an empty tick and
            // recorded the read before the wait.
            _ = try await seedRow(storage, graph, url: "http://host.test/first-interval",
                nextCheckAt: start + intervalSeconds - 1)

            let (loop, recorder) = makeLoop(storage: storage, iterations: 1)
            let reports = try await loop.run()

            #expect(recorder.all() == [
                .wait(intervalSeconds),
                .read(start + intervalSeconds),
                .job("http://host.test/first-interval"),
                .stop(intervalSeconds),
            ], "the calls the loop made: \(recorder.all())")
            #expect(reports.count == 1)
            let report = try #require(reports.first)
            #expect(report.readFailure == nil, "the read the pin seeded: \(report)")
            #expect(report.outcomes.count == 1)
        }
    }

    @Test func everyWaitIsGivenTheIntervalTheLoopWasBuiltWith() async throws {
        try await withMigratedStorage { _, storage in
            let graph = try await seedGraph(storage, username: "alice")
            _ = try await seedRow(storage, graph, url: "http://host.test/due",
                nextCheckAt: start + intervalSeconds - 1)

            let (loop, recorder) = makeLoop(storage: storage, iterations: 3)
            _ = try await loop.run()

            // Three waits, each with the interval the loop was built with. A patch that wrote the
            // reference's cadence, or the batch size, answered an hour for all three.
            #expect(recorder.all() == [
                .wait(intervalSeconds), .read(start + intervalSeconds), .job("http://host.test/due"),
                .wait(intervalSeconds), .read(start + 2 * intervalSeconds),
                .job("http://host.test/due"),
                .wait(intervalSeconds), .read(start + 3 * intervalSeconds),
                .job("http://host.test/due"),
                .stop(intervalSeconds),
            ], "the intervals the seam was given: \(recorder.all())")
        }
    }

    @Test func thereIsOneReadPerWaitAndNoExtraRead() async throws {
        try await withMigratedStorage { _, storage in
            let graph = try await seedGraph(storage, username: "alice")
            _ = try await seedRow(storage, graph, url: "http://host.test/due",
                nextCheckAt: start + intervalSeconds - 1)

            let (loop, recorder) = makeLoop(storage: storage, iterations: 2)
            let reports = try await loop.run()

            #expect(recorder.all() == [
                .wait(intervalSeconds), .read(start + intervalSeconds), .job("http://host.test/due"),
                .wait(intervalSeconds), .read(start + 2 * intervalSeconds),
                .job("http://host.test/due"),
                .stop(intervalSeconds),
            ], "the calls the loop made: \(recorder.all())")

            // One report per read, so a patch that read twice per iteration answered four reports
            // with the same jobs run twice.
            #expect(reports.count == 2)
            #expect(reports.allSatisfy { $0.outcomes.count == 1 && $0.readFailure == nil })
        }
    }

    @Test func eachReadAnswersTheInstantTheClockGivesAtThatRead() async throws {
        try await withMigratedStorage { _, storage in
            // The two rows are due at two different instants, so a patch that captured the instant
            // once answered the same row twice and never the second one.
            let graph = try await seedGraph(storage, username: "alice")
            _ = try await seedRow(storage, graph, url: "http://host.test/at-the-first-read",
                nextCheckAt: start + intervalSeconds - 1)
            _ = try await seedRow(storage, graph, url: "http://host.test/at-the-second-read",
                nextCheckAt: start + 2 * intervalSeconds - 1)

            let (loop, recorder) = makeLoop(storage: storage, iterations: 2)
            _ = try await loop.run()

            // The order inside one tick is what the workers answer, so the pins read the calls on
            // either side of the read: what the first read answered, and what the second one added.
            let calls = recorder.all()
            let firstRead = try #require(calls.firstIndex(of: .read(start + intervalSeconds)))
            let secondRead = try #require(calls.firstIndex(of: .read(start + 2 * intervalSeconds)))
            #expect(jobURLs(calls[firstRead + 1 ..< secondRead]).sorted() ==
                ["http://host.test/at-the-first-read"], "the first read answered its own row: \(calls)")
            #expect(jobURLs(calls[secondRead + 1 ..< calls.count]).sorted() == [
                "http://host.test/at-the-first-read", "http://host.test/at-the-second-read",
            ], "the second read answered the rows due at the instant it answered: \(calls)")
        }
    }

    @Test func aFailingReadIsReportedAndTheLoopRunsAgain() async throws {
        try await withMigratedStorage { _, storage in
            let graph = try await seedGraph(storage, username: "alice")
            _ = try await seedRow(storage, graph, url: "http://host.test/due",
                nextCheckAt: start + intervalSeconds - 1)

            // The read the loop makes has no table to read, so the failure is the storage one; a
            // patch that returned on the first failure answered one report.
            try await storage.withConnection { connection in
                try await sqlDatabase(connection).raw("DROP TABLE feeds").run()
            }

            let (loop, recorder) = makeLoop(storage: storage, iterations: 2)
            let reports = try await loop.run()

            #expect(reports.count == 2, "the reports the loop answered: \(reports)")
            #expect(reports.allSatisfy { $0.readFailure != nil },
                "each read failed, and the failure is what the report carries: \(reports)")
            #expect(recorder.all() == [
                .wait(intervalSeconds), .read(start + intervalSeconds),
                .wait(intervalSeconds), .read(start + 2 * intervalSeconds),
                .stop(intervalSeconds),
            ], "the loop went on after the failure: \(recorder.all())")
        }
    }

    @Test func anEmptyReadReportsNothingAndTheLoopRunsAgain() async throws {
        try await withMigratedStorage { _, storage in
            let graph = try await seedGraph(storage, username: "alice")
            _ = try await seedRow(storage, graph, url: "http://host.test/not-due",
                nextCheckAt: start + 10 * intervalSeconds)

            let (loop, recorder) = makeLoop(storage: storage, iterations: 2)
            let reports = try await loop.run()

            #expect(reports.count == 2)
            #expect(reports.allSatisfy { $0.outcomes.isEmpty && $0.readFailure == nil },
                "the reads answered nothing: \(reports)")
            #expect(recorder.all() == [
                .wait(intervalSeconds), .read(start + intervalSeconds),
                .wait(intervalSeconds), .read(start + 2 * intervalSeconds),
                .stop(intervalSeconds),
            ], "no job ran for a read that answered nothing: \(recorder.all())")
        }
    }

    @Test func theLoopReadsNothingAfterTheSeamAnswersThatItStops() async throws {
        try await withMigratedStorage { _, storage in
            let graph = try await seedGraph(storage, username: "alice")
            _ = try await seedRow(storage, graph, url: "http://host.test/due",
                nextCheckAt: start + intervalSeconds - 1)

            // The seam answers stop on the first call, so the loop reads nothing at all: a patch
            // that read before checking the answer, or that ignored it, recorded a read here.
            let (loop, recorder) = makeLoop(storage: storage, iterations: 0)
            let reports = try await loop.run()

            #expect(recorder.all() == [.stop(intervalSeconds)],
                "nothing was read after the seam answered stop: \(recorder.all())")
            #expect(reports.isEmpty, "the loop reported no iteration it did not run: \(reports)")
        }
    }

    @Test func everyJobOfATickRunsBeforeTheNextRead() async throws {
        try await withMigratedStorage { _, storage in
            let graph = try await seedGraph(storage, username: "alice")
            // The rows are due before the read that answers them, because the batch rule is strict
            // `<`.
            _ = try await seedRow(storage, graph, url: "http://host.test/first-tick-a",
                nextCheckAt: start + intervalSeconds - 1)
            _ = try await seedRow(storage, graph, url: "http://host.test/first-tick-b",
                nextCheckAt: start + intervalSeconds - 1)
            _ = try await seedRow(storage, graph, url: "http://host.test/second-tick",
                nextCheckAt: start + 2 * intervalSeconds - 1)

            // The port awaits the batch, which is the difference from the reference pushing the
            // jobs to a channel and going on to the next firing. A patch that started the tick
            // without awaiting it put the second read before the jobs of the first.
            let (loop, recorder) = makeLoop(storage: storage, iterations: 2)
            _ = try await loop.run()

            let calls = recorder.all()
            let firstRead = try #require(calls.firstIndex(of: .read(start + intervalSeconds)))
            let secondRead = try #require(calls.firstIndex(of: .read(start + 2 * intervalSeconds)))
            #expect(secondRead > firstRead + 1, "the reads the loop made: \(calls)")

            // The order inside one tick is what concurrency answers, so the pin reads the calls on
            // either side of the tick boundary: both jobs of the first tick lie between the two
            // reads.
            let between = calls[firstRead + 1 ..< secondRead]
            #expect(jobURLs(between).sorted() == [
                "http://host.test/first-tick-a", "http://host.test/first-tick-b",
            ], "the calls between the two reads: \(between)")
        }
    }

    // MARK: - Setup

    private enum Event: Equatable, Sendable {
        case wait(Int)
        case stop(Int)
        case read(Int)
        case job(String)
    }

    private func jobURLs(_ calls: ArraySlice<Event>) -> [String] {
        calls.compactMap { event in
            if case .job(let url) = event { return url }
            return nil
        }
    }

    /// The calls the loop made, recorded by the seams and the runner. The pins read them after the
    /// loop returns, and the appends run under a lock, because the workers of one tick can record
    /// at the same time; the order inside one tick is not fixed, so the pins that read a tick read
    /// the calls on either side of it.
    private final class Recorder: @unchecked Sendable {
        private var calls: [Event] = []
        private let lock = NSLock()

        func record(_ call: Event) {
            lock.lock()
            calls.append(call)
            lock.unlock()
        }

        func all() -> [Event] {
            calls
        }
    }

    /// Records the instant each read was made against and moves by the interval the seam was given,
    /// so the pins read the clock per read rather than one instant fixed at the start. The loop
    /// reads the clock once per read and the test moves it between reads, so nothing is read while
    /// it is moved; the `Clock` seam has a synchronous `now()`, which an actor cannot conform to.
    private final class RecordingClock: Clock, @unchecked Sendable {
        private var instant: Int
        private let recorder: Recorder

        init(start: Int, recorder: Recorder) {
            instant = start
            self.recorder = recorder
        }

        func now() -> Int {
            recorder.record(.read(instant))
            return instant
        }

        func advance(by seconds: Int) {
            instant += seconds
        }
    }

    /// The seam the loop waits through instead of a sleep: it records the interval it was given,
    /// moves the clock by it, and answers that the loop stops after the number of iterations the
    /// pin names.
    private final class RecordingCadence: Cadence, @unchecked Sendable {
        private let clock: RecordingClock
        private let recorder: Recorder
        private let iterations: Int
        private var waits = 0

        init(clock: RecordingClock, recorder: Recorder, iterations: Int) {
            self.clock = clock
            self.recorder = recorder
            self.iterations = iterations
        }

        func wait(for interval: Duration) async -> Bool {
            waits += 1
            let seconds = Int(interval.components.seconds)
            clock.advance(by: seconds)
            recorder.record(waits <= iterations ? .wait(seconds) : .stop(seconds))
            return waits <= iterations
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

    private func makeLoop(storage: SQLiteStorage, iterations: Int) -> (CadenceLoop, Recorder) {
        let recorder = Recorder()
        let clock = RecordingClock(start: start, recorder: recorder)
        let cadence = RecordingCadence(clock: clock, recorder: recorder, iterations: iterations)
        let scheduler = Scheduler(storage: storage, clock: clock, options: SchedulerOptions.defaults,
            runner: RecordingRunner(recorder: recorder))
        return (CadenceLoop(scheduler: scheduler, cadence: cadence, interval: interval), recorder)
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
        url: String, nextCheckAt: Int) async throws -> Int {
        try await storage.withConnection { connection in
            let feedID = try await seedFeed(connection, userID: graph.userID,
                categoryID: graph.categoryID, url: url)
            try await sqlDatabase(connection).raw("""
                UPDATE feeds SET next_check_at = \(bind: nextCheckAt) WHERE id = \(bind: feedID)
                """).run()
            return feedID
        }
    }
}
