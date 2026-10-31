// Ported from Miniflux internal/worker/worker.go (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// What one job produced, so a test can read the outcome of a tick.
///
/// The reference logs the outcome and reports it to the metrics collector (`internal/worker/
/// worker.go`); RivuletCore has no logging layer, so the port answers with a value. The failure is
/// the typed error the run answered with, which is what a pin compares: the reference's wording is
/// not something this port can pin. The completion order is what the pool produced, which
/// concurrency does not fix, so the pins read the outcomes by job.
public enum JobOutcome: Sendable {
    /// The job ran without a failure.
    case refreshed(RefreshJob)

    /// The job ran and answered with the typed failure the run threw.
    case failed(RefreshJob, any Error)
}