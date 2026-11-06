// Ported from Miniflux internal/cli/daemon.go stop branch (Apache-2.0); adapted for
// Swift/SQLite.

/// The teardown `serve` runs after the cadence loop returns: the seam a test drives instead of the
/// process shutdown.
///
/// The reference's stop branch shuts the HTTP servers, then the worker pool, and returns
/// (`internal/cli/daemon.go` at commit `c4d54f87`), so the jobs a tick had started run to their end
/// before the teardown — the rule `docs/plan/stage-6-cli.md` reads as "no lost refresh batch", and
/// `ServeWiringTests` pins as the tick before the hook. The order parts there: this port runs the
/// hook after the loop, and the hook is what stops the server, which `docs/parity.md` records as
/// the port's own.
///
/// A failing hook is the error the wiring propagates, which is the shape the CLI reads as the exit
/// code: the reference's clean stop returns and `main.go` exits 1 only on an error, so the pins
/// read the propagation and not the code itself, and the process suite reads the code as the event
/// the child exits on.
public protocol ShutdownHook: Sendable {
    /// Runs the shutdown once, after the loop returns.
    func run() async throws
}

