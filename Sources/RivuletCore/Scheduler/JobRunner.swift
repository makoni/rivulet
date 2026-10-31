import Foundation

/// What the pool runs for one job: the seam a test drives instead of the worker.
///
/// The reference worker calls `feedHandler.RefreshFeed` with `forceRefresh` false
/// (`internal/worker/worker.go`), so the seam's contract is the non-forced path: the stored
/// validators are sent. The scheduler tests drive this seam with a recorder, so they pin what the
/// tick does with the jobs it selected without a server or a database; the pipeline path is pinned
/// through the real pipeline in `SchedulerTickTests`. The pool size itself is not pinned: pinning a
/// cap would mean waiting until a group reaches a size, and `docs/testing.md` forbids sleeping.
public protocol JobRunner: Sendable {
    /// Runs one job as the worker does: the refresh path without the forced flag.
    func run(job: RefreshJob) async throws
}