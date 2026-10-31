// Ported from Miniflux internal/cli/scheduler.go `feedScheduler` and internal/worker/pool.go
// (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The jobs the tick hands out, read through a queue instead of a Go channel.
private actor JobQueue: Sendable {
    private var pending: [RefreshJob]

    init(_ jobs: [RefreshJob]) {
        pending = jobs
    }

    func next() -> RefreshJob? {
        guard !pending.isEmpty else { return nil }
        return pending.removeFirst()
    }
}

/// One tick of the scheduler: the due batch and the pool that runs it, as
/// `docs/architecture.md` shapes it — an actor over the seams.
///
/// The reference `feedScheduler` wakes every `pollingFrequency`, builds the batch through the
/// storage layer and pushes the jobs to a channel that `workerPoolSize` workers read, without
/// awaiting the batch. This type is one tick without the loop, because nothing can pin a sleeping
/// loop: `docs/plan/stage-4-ingestion.md` asks tests to drive the scheduler with explicit `tick()`
/// calls, and the loop itself lands with `rivulet serve`. The pool is the same shape as the
/// reference's: workers reading the queue, one per slot the batch can use, which is what
/// `workerPoolSize` goroutines over one channel do there; the cap itself cannot be pinned without a
/// timed wait, which `docs/testing.md` forbids, so the pins state it honestly. A job that fails is
/// reported as the failed outcome and does not stop the rest, which is the worker's rule: it keeps
/// reading the channel after a job that failed.
public actor Scheduler {
    private let storage: SQLiteStorage
    private let clock: any Clock
    private let options: SchedulerOptions
    private let runner: any JobRunner

    /// Creates the scheduler around the seams it runs through.
    public init(storage: SQLiteStorage, clock: any Clock, options: SchedulerOptions,
        runner: any JobRunner) {
        self.storage = storage
        self.clock = clock
        self.options = options
        self.runner = runner
    }

    /// Runs one tick on the clock it was given.
    /// - Returns: One outcome per job of the batch, in the order the workers finished, which
    ///   concurrency does not fix; a pin reads the outcome for each job instead.
    /// - Throws: The storage failure the batch read reported. A failure inside one run is not an
    ///   error here: it becomes the failed outcome, as the worker reports it.
    public func tick() async throws -> [JobOutcome] {
        let jobs = try await storage.withConnection { connection in
            try await FeedRepository(connection).dueBatch(now: self.clock.now(),
                options: self.options)
        }

        var outcomes: [JobOutcome] = []
        await withTaskGroup(of: [JobOutcome].self) { group in
            let queue = JobQueue(jobs)
            // One worker per slot the batch can use. The reference starts the whole pool over one
            // channel and every worker runs nothing when the channel is empty, so a positive pool
            // never runs a job twice.
            for _ in 0..<min(self.options.workerPoolSize, jobs.count) {
                group.addTask {
                    var ran: [JobOutcome] = []
                    while let job = await queue.next() {
                        do {
                            try await self.runner.run(job: job)
                            ran.append(JobOutcome.refreshed(job))
                        } catch {
                            ran.append(JobOutcome.failed(job, error))
                        }
                    }
                    return ran
                }
            }
            for await ran in group {
                outcomes.append(contentsOf: ran)
            }
        }
        return outcomes
    }
}