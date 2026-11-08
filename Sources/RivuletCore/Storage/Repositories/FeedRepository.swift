// Ported from Miniflux internal/storage/feed.go (Apache-2.0); adapted for Swift/SQLite.
import Foundation
import FluentKit

/// Creates, lists and deletes feeds, and records their fetch state.  `recordFetch` and
/// `recordParsingError` mirror the reference refresh path, where the last check time and the next-
/// check schedule are fixed before the fetch and persisted with its outcome: a successful fetch
/// stores the conditional-GET headers and the next check time, stamps the last check time and
/// resets the parsing failure state; a failure increments the failure counter, keeps the latest
/// error message and persists the last check time and the rescheduled check.  - See:
/// ``SQLiteStorage/withConnection(_:)`` — the repository takes the checked-out connection and lives
/// inside that checkout.
public struct FeedRepository {
    // Internal, not private: the batch extension lives in its own file, as the entry query
    // extension does.
    let database: any Database

    /// Creates the repository around a checked-out connection.
    public init(_ database: any Database) {
        self.database = database
    }

    /// Creates a feed with the reference defaults: empty strings, a 60-minute polling interval, no
    /// parsing errors, enabled, and due for the first check immediately.
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
        feed.ignoreHTTPCache = false
        feed.fetchViaProxy = false
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

    /// Returns the feed of `userID` with `id`, or `nil` (upstream `FeedByID`).  The refresh path
    /// reads the row through this scope, so a feed of another user is not found and nothing is
    /// written for it.
    public func fetch(userID: Int, id: Int) async throws -> Feed? {
        try await Feed.query(on: database)
            .filter(\Feed.$userID == userID)
            .filter(\Feed.$id == id)
            .first()
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

    /// The duplicate answer `FeedValidation` reads: whether this user already has a row with `url`.
    ///
    /// The reference reads one row (`internal/storage/feed.go` at commit `c4d54f87`), and the
    /// `LIMIT 1` is recorded as unpinnable in `FeedManagementReadsTests` because the schema's
    /// `UNIQUE (user_id, url)` means this read can never have two rows to choose between. What the
    /// pin shows is the user condition: the read answers for this user's row, not for another
    /// user's row with the same url.
    ///
    /// - Parameters:
    ///   - userID: The account the answer is read for.
    ///   - url: The url as it was read.
    /// - Returns: Whether this user has a row with `url`.
    public func feedURLExists(userID: Int, url: String) async throws -> Bool {
        let sql = try RawSQL.sql(on: database)
        let row = try await sql.raw("""
            SELECT 1 AS one FROM feeds WHERE user_id = \(bind: userID) AND url = \(bind: url) LIMIT 1
            """).first()
        return row != nil
    }

    /// Deletes the feed of `userID`; its entries, enclosures and tombstones cascade away.
    ///
    /// The account is part of the statement, as `RemoveFeed` has it in the reference: a row another
    /// account has with the same id is not this account's row. `FeedManagementReadsTests` pins both
    /// the account condition and the cascade.
    ///
    /// - Parameters:
    ///   - id: Row id of the feed.
    ///   - userID: The account the row must belong to.
    public func delete(id: Int, userID: Int) async throws {
        try await Feed.query(on: database)
            .filter(\Feed.$id == id)
            .filter(\Feed.$userID == userID)
            .delete()
    }

    /// `UpdateFeed` for the two columns the subscription handlers modify: the title the rename
    /// writes and the category the move writes. A column the caller does not name is left as the
    /// row held it, which is what the reference's modification request does with a field it does
    /// not carry. The stamp is this port's own: the reference's write names no `updated_at` at all,
    /// so the value here is the time the write runs at, and no pin reads it.
    public func update(feed: Feed, title: String?, categoryID: Int?) async throws {
        if let title { feed.title = title }
        if let categoryID { feed.categoryID = categoryID }
        feed.updatedAt = Int(Date.now.timeIntervalSince1970)
        try await feed.update(on: database)
    }

    /// Records a successful fetch (upstream `UpdateFeed`): stores the conditional-GET headers, the
    /// site URL the caller resolved, the next check time and the check time the caller read from
    /// its clock, and resets the parsing failure state. The title stays as the row held it, as the
    /// reference leaves it on this path.  - Throws: ``StorageError/feedNotFound(id:)`` if the feed
    /// does not exist.
    public func recordFetch(feedID: Int, etag: String, lastModified: String, nextCheckAt: Int,
        checkedAt: Int, siteURL: String) async throws {
        guard let feed = try await fetch(id: feedID) else {
            throw StorageError.feedNotFound(id: feedID)
        }
        feed.etag = etag
        feed.lastModified = lastModified
        feed.nextCheckAt = nextCheckAt
        feed.siteURL = siteURL
        feed.fetchedAt = checkedAt
        feed.parsingErrorCount = 0
        feed.parsingErrorMessage = ""
        feed.updatedAt = checkedAt
        try await feed.update(on: database)
    }

    /// Records a failed refresh (upstream `UpdateFeedError`): increments the consecutive-failure
    /// counter, keeps the latest error message, and persists the check time and the rescheduled
    /// check the caller computed. The conditional-GET headers are not touched, as the reference
    /// writes only these columns on the failure path.  - Throws: ``StorageError/feedNotFound(id:)``
    /// if the feed does not exist.
    public func recordParsingError(feedID: Int, message: String, nextCheckAt: Int, checkedAt: Int)
        async throws {
        guard let feed = try await fetch(id: feedID) else {
            throw StorageError.feedNotFound(id: feedID)
        }
        feed.parsingErrorCount += 1
        feed.parsingErrorMessage = message
        feed.fetchedAt = checkedAt
        feed.nextCheckAt = nextCheckAt
        feed.updatedAt = checkedAt
        try await feed.update(on: database)
    }
}
