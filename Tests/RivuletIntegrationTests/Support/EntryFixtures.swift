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
