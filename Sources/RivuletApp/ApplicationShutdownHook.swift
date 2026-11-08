import RivuletCore

/// The `serve` shutdown the hook is: the application's own teardown, which closes the fetcher the
/// loop ran through before the checkpoint and the teardown.
///
/// This is the position the reference's stop branch has: the worker pool is shut down after the
/// loop, so the jobs a tick had started are not lost (`internal/cli/daemon.go` at commit
/// `c4d54f87`), and `ServeWiringTests` pins that order as the tick running before the hook. The
/// hook is the run's single shutdown, which is what `ServeProcessTests` reads as the WAL fact after
/// the child exits; a failing hook is the error the wiring propagates, which `main.swift` reads as
/// exit 1 — the reference's clean stop exits 0 and `main.go` exits 1 only on an error.
public struct ApplicationShutdownHook: ShutdownHook {
    private let rivulet: RivuletApplication

    /// Builds the hook around the application whose fetcher and storage it closes.
    public init(rivulet: RivuletApplication) {
        self.rivulet = rivulet
    }

    /// Runs the shutdown once, after the loop returns.
    public func run() async throws {
        try await rivulet.shutdown()
    }
}
