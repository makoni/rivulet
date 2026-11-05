// Ported from Miniflux internal/cli/scheduler.go `feedScheduler` (Apache-2.0); adapted for
// Swift/SQLite.


/// What one iteration of the cadence loop produced, so the caller reports it.
///
/// The reference writes the failure to `slog` and goes on to the next firing; `RivuletCore` has no
/// logging layer, so the loop answers with a value and the wording a caller prints from it is the
/// caller's own. The reference never reports the outcome of a batch at all, so the outcomes are the
/// port's shape, the same value `tick()` answers with.
public struct CadenceReport: Sendable {
    /// The outcomes the tick produced; empty when the batch answered nothing or when the read
    /// failed.
    public let outcomes: [JobOutcome]

    /// The failure the batch read answered with, `nil` when the read answered a batch.
    public let readFailure: (any Error)?

    /// Creates the report for one iteration.
    public init(outcomes: [JobOutcome], readFailure: (any Error)?) {
        self.outcomes = outcomes
        self.readFailure = readFailure
    }
}

