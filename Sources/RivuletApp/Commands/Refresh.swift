// Ported from Miniflux internal/cli/refresh_feeds.go (Apache-2.0); adapted for Swift/SQLite.

import ConsoleKit
import RivuletCore

extension RivuletCLI {
    /// `rivulet refresh` — one pass over the due batch, then exit.
    ///
    /// This is the reference's manual path (`internal/cli/refresh_feeds.go` at commit
    /// `c4d54f87`): read the batch with the values `config.Opts` gives the builder, run
    /// each job of it once through the worker's path, report what ran, and return. The pass
    /// is one pass, not the cadence loop: the loop that reads the batch again belongs to
    /// `serve`, and nothing here sleeps. The pool the jobs run through is the one
    /// `Scheduler` shapes, so the cap is the same one `SchedulerTickTests` names as
    /// unpinnable. A job that fails is reported and does not stop the rest, which is the
    /// worker's rule, and the schedule a job that ran leaves is the one the next pass reads.
    /// The schedule is stamped by `NextCheckPolicy()` with the reference defaults, because
    /// this command does not read the mode or the intervals from the environment. The
    /// reference logs each failed feed and the batch it ran through `slog`; `RivuletCore`
    /// has no logging layer, so those lines have nowhere to go here and what a test can
    /// read is the console report the port writes, whose wording is the port's own. The
    /// reference reports the size of the whole batch, which counts a job it could not
    /// refresh; this report counts what ran without a failure, so the two numbers differ
    /// when a batch has one. A batch read that fails is logged and returned there; here the
    /// error leaves the command. The reference checks that the schema is up to date before
    /// it runs any command; this port runs the migrations when `RUN_MIGRATIONS` is on, as
    /// `serve` does, and does not port that check.
    struct Refresh: AsyncCommand {
        struct Signature: CommandSignature {
            init() {}
        }

        let environment: [String: String]

        var help: String { "Refreshes the feeds that are due and exits." }

        func run(using context: CommandContext, signature: Signature) async throws {
            let config = try Config.load(environment: environment)
            LoggingSetup.bootstrap(logLevel: config.logLevel, format: config.logFormat)

            let rivulet = try await ApplicationFactory.make(config: config)
            try await rivulet.storage.prepare()
            if config.runMigrations {
                try await rivulet.application.autoMigrate()
            }

            let clock = SystemClock()
            let fetcher = Fetcher(options: config.fetcher)
            let pipeline = RefreshPipeline(storage: rivulet.storage, fetcher: fetcher,
                options: config.fetcher, nextCheck: NextCheckPolicy(), clock: clock)
            let scheduler = Scheduler(storage: rivulet.storage, clock: clock,
                options: config.scheduler, runner: pipeline)

            let outcomes: [JobOutcome]
            do {
                outcomes = try await scheduler.tick()
            } catch {
                try? await fetcher.shutdown()
                try? await rivulet.shutdown()
                throw error
            }

            var ran = 0
            var failed = 0
            for outcome in outcomes {
                switch outcome {
                case .refreshed:
                    ran += 1
                case .failed(let job, let error):
                    failed += 1
                    // The reference warns per feed it cannot refresh and
                    // keeps reading the queue; the console line here is what
                    // a pin reads for that rule.
                    context.console.print("Feed \(job.feedID): \(error)")
                }
            }
            context.console.print("Refreshed \(ran) feed(s), \(failed) failed.")

            try await fetcher.shutdown()
            try await rivulet.shutdown()
        }
    }
}
