import Foundation

/// The part of a feed row a fetch needs.
///
/// It keeps the fetcher independent of the Fluent model: the repository reads the row, this
/// value carries the state the request is built from, and the fetch result is written back
/// through ``FeedRepository``.
public struct FeedFetchState: Sendable, Equatable {
    /// Feed id, used to persist the fetch result.
    public let feedID: Int

    /// Feed URL. Only `http` and `https` are fetched.
    public let url: URL

    /// Validator stored from the previous response.
    public let etag: String

    /// Validator stored from the previous response.
    public let lastModified: String

    /// Per-feed user agent; the configured one applies when it is empty.
    public let userAgent: String

    /// Per-feed "ignore HTTP cache"; the configured default applies when it is false.
    public let ignoreHTTPCache: Bool

    /// Creates the state from stored feed values.
    public init(
        feedID: Int,
        url: URL,
        etag: String = "",
        lastModified: String = "",
        userAgent: String = "",
        ignoreHTTPCache: Bool = false
    ) {
        self.feedID = feedID
        self.url = url
        self.etag = etag
        self.lastModified = lastModified
        self.userAgent = userAgent
        self.ignoreHTTPCache = ignoreHTTPCache
    }
}
