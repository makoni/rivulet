// Ported from Miniflux internal/worker/worker.go (Apache-2.0); adapted for Swift/SQLite.

extension RefreshPipeline: JobRunner {
    /// The pool's unit of work is the pipeline on the non-forced path: the worker calls
    /// `RefreshFeed` with `forceRefresh` false, so the stored validators are sent.
    public func run(job: RefreshJob) async throws {
        _ = try await refresh(userID: job.userID, feedID: job.feedID)
    }
}