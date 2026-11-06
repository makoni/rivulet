// Ported from Miniflux internal/cli/daemon.go `stop` channel (Apache-2.0); adapted for
// Swift/SQLite.

/// The seam the real cadence waits through: the stop signal the daemon listens for.
///
/// The reference's daemon loop selects on a channel fed by `signal.Notify` for interrupt and
/// SIGTERM (`internal/cli/daemon.go` at commit `c4d54f87`), and its ticker goroutine has no stop
/// rule at all — that part is recorded in `docs/parity.md` as the port's own. This seam is the
/// port's shape of the stop half: it answers the decision the loop reads, so a test can drive the
/// decision without a process and without a timed wait.
public protocol SignalSource: Sendable {
    /// Waits for the first stop signal and answers whether one arrived.
    ///
    /// It never answers before the signal arrives. When the waiting task is cancelled, it answers
    /// `false`, which is what the race in `SystemCadence` reads as "no signal by the decision".
    ///
    /// - Returns: `true` when the signal arrived, `false` when the wait was cancelled instead.
    func signal() async -> Bool

    /// Whether the first stop signal has already arrived.
    func arrived() -> Bool
}
