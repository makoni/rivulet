// Ported from Miniflux internal/reader/handler/handler.go `RefreshFeed` (Apache-2.0); adapted for
// Swift/SQLite.

/// The half the refresh path runs through: the fetch, the parse and the writes one feed needs.
///
/// The reference calls this half directly from its handler, so the handler has no seam to stand in for
/// it and its pins cannot show that the pair read runs before the fetch — the fetch is the network half.
/// This port names the half as a seam so the route pin can read the order without a socket: the seam is
/// the reason it exists, and ``RefreshPipeline`` is the one production caller that conforms to it.
public protocol FeedRefreshRunner: Sendable {
    /// Runs the half for one feed of one user.
    ///
    /// - Parameters:
    ///   - userID: The account the feed belongs to.
    ///   - feedID: The feed the half runs for.
    /// - Returns: What the refresh produced, as ``RefreshOutcome``.
    func run(userID: Int, feedID: Int) async throws -> RefreshOutcome
}

extension RefreshPipeline: FeedRefreshRunner {
    /// Runs the half with the flag the reference's API path passes, which is the unforced one.
    public func run(userID: Int, feedID: Int) async throws -> RefreshOutcome {
        try await refresh(userID: userID, feedID: feedID, forceRefresh: false)
    }
}
