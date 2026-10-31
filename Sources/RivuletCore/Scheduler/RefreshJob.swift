// Ported from Miniflux internal/model/job.go (Apache-2.0); adapted for Swift/SQLite.

/// One unit of work the batch selects: which feed to refresh for which user.
///
/// The fields are the reference's `model.Job`; the order is the order the batch query scans the
/// row in. The URL is the stored feed URL, not the site URL the row may hold after a parse.
public struct RefreshJob: Sendable, Equatable {
    /// The feed to refresh.
    public let feedID: Int

    /// The user the feed belongs to.
    public let userID: Int

    /// The feed URL as the row stores it.
    public let feedURL: String

    /// Creates a job for one row of the batch.
    public init(feedID: Int, userID: Int, feedURL: String) {
        self.feedID = feedID
        self.userID = userID
        self.feedURL = feedURL
    }
}