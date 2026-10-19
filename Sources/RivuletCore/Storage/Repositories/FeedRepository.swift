// Ported from Miniflux internal/storage/feed.go (Apache-2.0); adapted for Swift/SQLite.
import Foundation
import FluentKit

/// Creates, lists and deletes feeds, and records their fetch state.
///
/// `recordFetch` and `recordParsingError` mirror the reference refresh path,
/// where the last check time and the next-check schedule are fixed before the
/// fetch and persisted with its outcome: a successful fetch stores the
/// conditional-GET headers and the next check time, stamps the last check
/// time and resets the parsing failure state; a failure increments the
/// failure counter, keeps the latest error message and persists the last
/// check time and the rescheduled check.
///
/// - See: ``SQLiteStorage/withConnection(_:)`` — the repository takes the
///   checked-out connection and lives inside that checkout.
public struct FeedRepository {
    private let database: any Database

    /// Creates the repository around a checked-out connection.
    public init(_ database: any Database) {
        self.database = database
    }

    /// Creates a feed with the reference defaults: empty strings, a 60-minute
    /// polling interval, no parsing errors, enabled, and due for the first
    /// check immediately.
    public func create(userID: Int, categoryID: Int, url: String) async throws -> Feed {
        let now = Int(Date.now.timeIntervalSince1970)
        let feed = Feed()
        feed.userID = userID
        feed.categoryID = categoryID
        feed.url = url
        feed.siteURL = ""
        feed.title = ""
        feed.feedDescription = ""
        feed.iconID = nil
        feed.etag = ""
        feed.lastModified = ""
        feed.nextCheckAt = now
        feed.checkInterval = 60
        feed.parsingErrorCount = 0
        feed.parsingErrorMessage = ""
        feed.userAgent = ""
        feed.disabled = false
        feed.fetchedAt = nil
        feed.createdAt = now
        feed.updatedAt = now
        try await feed.create(on: database)
        return feed
    }

    /// Returns the feed with `id`, or `nil`.
    public func fetch(id: Int) async throws -> Feed? {
        try await Feed.query(on: database).filter(\Feed.$id == id).first()
    }

    /// Returns the feed of `userID` with `url`, or `nil`.
    public func fetch(userID: Int, url: String) async throws -> Feed? {
        try await Feed.query(on: database)
            .filter(\Feed.$userID == userID)
            .filter(\Feed.$url == url)
            .first()
    }

    /// Returns the feeds of `userID`, ordered by id.
    public func list(userID: Int) async throws -> [Feed] {
        try await Feed.query(on: database)
            .filter(\Feed.$userID == userID)
            .sort(\Feed.$id)
            .all()
    }

    /// Deletes the feed; its entries, enclosures and tombstones cascade away.
    public func delete(id: Int) async throws {
        try await Feed.query(on: database).filter(\Feed.$id == id).delete()
    }

    /// Records a successful fetch: stores the conditional-GET headers and the
    /// next check time, stamps `fetched_at`, and resets the parsing failure
    /// state.
    ///
    /// - Throws: ``StorageError/feedNotFound(id:)`` if the feed does not exist.
    public func recordFetch(feedID: Int, etag: String, lastModified: String, nextCheckAt: Int) async throws {
        guard let feed = try await fetch(id: feedID) else {
            throw StorageError.feedNotFound(id: feedID)
        }
        let now = Int(Date.now.timeIntervalSince1970)
        feed.etag = etag
        feed.lastModified = lastModified
        feed.nextCheckAt = nextCheckAt
        feed.fetchedAt = now
        feed.parsingErrorCount = 0
        feed.parsingErrorMessage = ""
        feed.updatedAt = now
        try await feed.update(on: database)
    }

    /// Records a failed refresh (upstream `UpdateFeedError`): increments the
    /// consecutive-failure counter, keeps the latest error message, and
    /// persists the last check time and the rescheduled check computed by the
    /// caller.
    ///
    /// - Throws: ``StorageError/feedNotFound(id:)`` if the feed does not exist.
    public func recordParsingError(feedID: Int, message: String, nextCheckAt: Int) async throws {
        guard let feed = try await fetch(id: feedID) else {
            throw StorageError.feedNotFound(id: feedID)
        }
        let now = Int(Date.now.timeIntervalSince1970)
        feed.parsingErrorCount += 1
        feed.parsingErrorMessage = message
        feed.fetchedAt = now
        feed.nextCheckAt = nextCheckAt
        feed.updatedAt = now
        try await feed.update(on: database)
    }
}
