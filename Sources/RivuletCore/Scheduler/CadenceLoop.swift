// Ported from Miniflux internal/cli/scheduler.go `feedScheduler` (Apache-2.0); adapted for
// Swift/SQLite.

import Foundation

/// The cadence loop the reference's `feedScheduler` goroutine is: wait for the interval, run one
/// tick, and go on while the seam answers that the loop runs again.
///
/// The reference reads the batch through the builder on each firing and logs a failure without
/// stopping, so a failing read is reported and the loop runs again — here the report carries the
/// failure, because `RivuletCore` has no logging layer. The two shapes part at the await: the
/// reference pushes the jobs to the pool and goes on to the next firing, so a slow batch can
/// overlap the next tick there, while this loop runs one tick to the end before the next read,
/// which `docs/parity.md` records. The loop reads the clock through the scheduler on each
/// iteration, so the batch it answers is the one the injected clock gives at that read; the
/// reference's due rule compares against SQL `now()` at query time, the divergence the scheduler
/// section of `docs/parity.md` records. The loop is the piece
/// `docs/plan/stage-4-ingestion.md` left out of stage 4 for the same reason: a test drives the
/// cadence through the seam instead of sleeping, so nothing here waits.
public actor CadenceLoop {
    private let scheduler: Scheduler
    private let cadence: any Cadence
    private let interval: Duration

    /// Builds the loop around the tick it runs and the seam it waits through.
    ///
    /// - Parameters:   - scheduler: The tick the loop runs, one per interval.   - cadence: The seam
    /// the loop waits through.   - interval: The cadence the loop hands to the seam on every
    /// iteration, which is     `SchedulerOptions.pollingFrequency`.
    public init(scheduler: Scheduler, cadence: any Cadence, interval: Duration) {
        self.scheduler = scheduler
        self.cadence = cadence
        self.interval = interval
    }

    /// Runs the loop until the seam answers that it stops.
    ///
    /// - Returns: One report per iteration the loop ran, in the order the iterations ran. A report
    /// carries   the failure the read answered with, so a caller reports it; the loop does not stop
    /// on one.
    public func run() async throws -> [CadenceReport] {
        var reports: [CadenceReport] = []

        while await cadence.wait(for: interval) {
            do {
                reports.append(CadenceReport(outcomes: try await scheduler.tick(), readFailure: nil))
            } catch {
                reports.append(CadenceReport(outcomes: [], readFailure: error))
            }
        }

        return reports
    }
}

