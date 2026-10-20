import Foundation
import Fluent
import SQLKit
import Testing
@testable import RivuletCore

/// Seeds the minimum graph an entry needs: a user, one category and one feed.
func seedFeed(
    _ connection: any Database,
    username: String = "alice",
    feedURL: String = "https://example.com/feed.xml"
) async throws -> (userID: Int, categoryID: Int, feedID: Int) {
    let user = try await UserRepository(connection)
        .create(username: username, passwordHash: "hash", isAdmin: false)
    let userID = try #require(user.id)
    let category = try await CategoryRepository(connection).create(userID: userID, title: "Tech")
    let categoryID = try #require(category.id)
    let feed = try await FeedRepository(connection)
        .create(userID: userID, categoryID: categoryID, url: feedURL)
    return (userID, categoryID, try #require(feed.id))
}

/// Seeds a user and returns its id.
func seedUser(_ connection: any Database, username: String = "alice") async throws -> Int {
    let user = try await UserRepository(connection)
        .create(username: username, passwordHash: "hash", isAdmin: false)
    return try #require(user.id)
}

/// Seeds a category of `userID` and returns its id.
func seedCategory(_ connection: any Database, userID: Int, title: String) async throws -> Int {
    let category = try await CategoryRepository(connection).create(userID: userID, title: title)
    return try #require(category.id)
}

/// Seeds a feed in `categoryID` and returns its id.
func seedFeed(
    _ connection: any Database,
    userID: Int,
    categoryID: Int,
    url: String
) async throws -> Int {
    let feed = try await FeedRepository(connection)
        .create(userID: userID, categoryID: categoryID, url: url)
    return try #require(feed.id)
}

/// Inserts an entry through the repository, applies the user state and returns its id.
@discardableResult
func seedEntry(
    _ connection: any Database,
    userID: Int,
    feedID: Int,
    hash: String,
    title: String = "Title",
    url: String = "https://example.com/entry",
    author: String = "Author",
    content: String = "<p>Hello world</p>",
    publishedAt: Int = 1_700_000_000,
    status: EntryStatus = .unread,
    starred: Bool = false
) async throws -> Int {
    let entries = EntryRepository(connection)
    let outcome = try await entries.upsert(
        userID: userID,
        feedID: feedID,
        input: entryInput(
            hash: hash,
            title: title,
            url: url,
            author: author,
            content: content,
            publishedAt: publishedAt
        ),
        updateExisting: false
    )
    guard case .created(let entry) = outcome, let id = entry.id else {
        throw EntryFixtureError.entryNotCreated
    }
    if status != .unread {
        try await entries.setStatus(userID: userID, entryIDs: [id], status: status)
    }
    if starred {
        try await entries.setStarred(userID: userID, entryIDs: [id], starred: true)
    }
    return id
}

/// Bulk-seeds `count` unread entries with distinct publication times and hashes.
func seedManyEntries(
    _ connection: any Database,
    userID: Int,
    feedID: Int,
    count: Int,
    firstPublishedAt: Int = 1_700_000_000
) async throws {
    try await sqlDatabase(connection).raw("""
        WITH RECURSIVE seq(n) AS (
            SELECT 1
            UNION ALL
            SELECT n + 1 FROM seq WHERE n < \(bind: count)
        )
        INSERT INTO entries (
            user_id, feed_id, hash, title, url, author,
            content, content_text, published_at, created_at, updated_at
        )
        SELECT
            \(bind: userID), \(bind: feedID), 'bulk-' || n, 'Bulk ' || n, '', '',
            '', '', \(bind: firstPublishedAt) + n, 0, 0
        FROM seq
        """).run()
}

/// Setup failures that the fixtures themselves cannot express.
private enum EntryFixtureError: Error {
    case entryNotCreated
}

/// Builds an entry input with recognizable defaults.
func entryInput(
    hash: String = "h1",
    title: String = "Title",
    url: String = "https://example.com/1",
    author: String = "Author",
    content: String = "<p>Hello <b>world</b></p>",
    publishedAt: Int = 1_700_000_000,
    enclosures: [EntryInput.Enclosure] = []
) -> EntryInput {
    EntryInput(
        hash: hash,
        title: title,
        url: url,
        author: author,
        content: content,
        publishedAt: publishedAt,
        enclosures: enclosures
    )
}

/// Unix seconds, for "before and after" timestamp assertions.
func nowInSeconds() -> Int {
    Int(Date.now.timeIntervalSince1970)
}

/// The checked-out connection as a SQL database.
func sqlDatabase(_ connection: any Database) throws -> any SQLDatabase {
    guard let sql = connection as? any SQLDatabase else {
        throw StorageError.notSQLDatabase
    }
    return sql
}

/// Number of stored entries; the repository has no listing API yet.
func entryCount(_ connection: any Database) async throws -> Int {
    try await count("entries", on: connection)
}

/// Number of recorded tombstones.
func tombstoneCount(_ connection: any Database) async throws -> Int {
    try await count("entry_tombstones", on: connection)
}

/// Number of FTS5 matches for `term`; the write path must keep `entries_fts` in sync.
func searchCount(_ connection: any Database, term: String) async throws -> Int {
    let row = try await sqlDatabase(connection)
        .raw("SELECT COUNT(*) AS count FROM entries_fts WHERE entries_fts MATCH \(bind: term)")
        .first()
    return try row?.decode(column: "count", as: Int.self) ?? -1
}

/// Moves `created_at` into the past; the retention cutoff reads this column.
func backdateCreatedAt(_ connection: any Database, id: Int, createdAt: Int) async throws {
    try await sqlDatabase(connection)
        .raw("UPDATE entries SET created_at = \(bind: createdAt) WHERE id = \(bind: id)")
        .run()
}

/// Moves `updated_at` into the past, to observe whether a mutation stamps it.
func backdateUpdatedAt(_ connection: any Database, id: Int, updatedAt: Int) async throws {
    try await sqlDatabase(connection)
        .raw("UPDATE entries SET updated_at = \(bind: updatedAt) WHERE id = \(bind: id)")
        .run()
}

private func count(_ table: String, on connection: any Database) async throws -> Int {
    let row = try await sqlDatabase(connection).raw("SELECT COUNT(*) AS count FROM \(ident: table)").first()
    return try row?.decode(column: "count", as: Int.self) ?? -1
}
