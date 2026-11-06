import RivuletCore

/// The `serve` shutdown the hook is: the fetcher the loop ran through is closed, then the
/// checkpoint and the teardown run.
///
/// This is the position the reference's stop branch has: the worker pool is shut down after the
/// loop, so the jobs a tick had started are not lost (`internal/cli/daemon.go` at commit
/// `c4d54f87`), and `ServeWiringTests` pins that order as the tick running before the hook. The
/// hook is the run's single shutdown, which is what `ServeProcessTests` reads as the WAL fact after
/// the child exits; a failing hook is the error the wiring propagates, which `main.swift` reads as
/// exit 1 — the reference's clean stop exits 0 and `main.go` exits 1 only on an error.
public struct ApplicationShutdownHook: ShutdownHook {
    private let rivulet: RivuletApplication
    private let fetcher: Fetcher

    /// Builds the hook around the application and the fetcher it closes.
    public init(rivulet: RivuletApplication, fetcher: Fetcher) {
        self.rivulet = rivulet
        self.fetcher = fetcher
    }

    /// Runs the shutdown once, after the loop returns.
    public func run() async throws {
        try await fetcher.shutdown()
        try await rivulet.shutdown()
    }
}
