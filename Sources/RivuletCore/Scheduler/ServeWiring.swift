// Ported from Miniflux internal/cli/daemon.go `startDaemon` (Apache-2.0); adapted for Swift/SQLite.

/// What `serve` runs: the cadence loop built from the values the environment gives, run to its end,
/// and the shutdown hook once after it returns.
///
/// The reference builds the pool and the scheduler from `config.Opts` in `startDaemon`
/// (`internal/cli/daemon.go` at commit `c4d54f87`), starts the scheduler goroutine, and shuts the
/// pool down when the stop channel answers — the teardown after the loop, which is the rule the
/// stage-6 process checks read as "no lost refresh batch". This type is that piece without the HTTP
/// server, which is not a seam here: the wiring takes the values the environment names, so the
/// interval and the batch size the pins read are the ones `Config.load` parsed rather than the
/// defaults, and `ServeWiringTests` pins that through test seams that record each call.
///
/// What the pins read is the hook running after the loop returns. What they cannot read is named by
/// that header: the HTTP server, which is not a seam here, and the reference's stopping the servers
/// before the pool; and the reports the loop answers with have no layer here, the reference writing
/// them to `slog`. A failing hook leaves this type as the error the CLI reads as the exit code, and
/// a clean run returns, which the pins read only as the absence of a thrown error.
public actor ServeWiring {
    private let loop: CadenceLoop
    private let hook: any ShutdownHook

    /// Builds the wiring from the values the environment gives, the storage it reads, and the seams
    /// it runs through.
    /// - Parameters: - config: The loaded configuration; the wiring uses its scheduler values,
    /// which is what the pins read as the environment reaching the loop. - storage: The storage the
    /// batch is read from. - cadence: The seam the loop waits through. - runner: The seam each job
    /// of a tick runs through. - hook: The shutdown the wiring runs once after the loop returns.
    public init(config: Config, storage: SQLiteStorage, cadence: any Cadence,
        runner: any JobRunner, hook: any ShutdownHook) {
        let clock = SystemClock()
        let scheduler = Scheduler(storage: storage, clock: clock, options: config.scheduler, runner: runner)
        loop = CadenceLoop(scheduler: scheduler, cadence: cadence,
            interval: config.scheduler.pollingFrequency)
        self.hook = hook
    }

    /// Runs the loop to its end and the hook once after it returns.
    /// - Throws: The hook's failure, which is what the CLI reads as exit 1. What the loop answers
    /// with is not reported here: this port has no logging layer, and the reference writes the
    /// reads it ran to `slog`.
    public func run() async throws {
        _ = try await loop.run()
        try await hook.run()
    }
}

