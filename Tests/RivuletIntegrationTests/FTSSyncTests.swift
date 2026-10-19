import Fluent
import FluentSQLiteDriver
import SQLKit
import Testing
@testable import RivuletCore

/// Exercises the FTS5 external-content triggers against real rows: search must follow
/// inserts, updates and deletes (including cascades from feed deletion).
@Suite struct FTSSyncTests {
    @Test func ftsFollowsInsertsUpdatesAndDeletes() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let sql = try Self.sqlDatabase(from: connection)
                try await Self.seedFeed(sql)
                try await Self.seedEntry(
                    sql,
                    hash: "h1",
                    title: "Swift concurrency",
                    text: "structured concurrency and tasks"
                )

                try await Self.assertSearchCount(sql, term: "swift", is: 1)
                try await Self.assertSearchCount(sql, term: "structured", is: 1)
                try await Self.assertSearchCount(sql, term: "kotlin", is: 0)

                try await sql.raw(
                    "UPDATE entries SET title = 'Kotlin coroutines', content_text = 'cold flows' WHERE hash = 'h1'"
                ).run()

                try await Self.assertSearchCount(sql, term: "swift", is: 0, "old terms must leave the index")
                try await Self.assertSearchCount(sql, term: "structured", is: 0)
                try await Self.assertSearchCount(sql, term: "kotlin", is: 1)

                // Updates to non-indexed columns must not disturb the index.
                try await sql.raw("UPDATE entries SET status = 'read', starred = 1 WHERE hash = 'h1'").run()
                try await Self.assertSearchCount(sql, term: "kotlin", is: 1)
                try await Self.assertSearchCount(sql, term: "swift", is: 0)

                try await sql.raw("DELETE FROM entries WHERE hash = 'h1'").run()
                try await Self.assertSearchCount(sql, term: "kotlin", is: 0)
            }
        }
    }

    @Test func deletingAFeedCascadesToEntriesAndSearchRows() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let sql = try Self.sqlDatabase(from: connection)
                try await Self.seedFeed(sql)
                try await Self.seedEntry(sql, hash: "h1", title: "alpha", text: "first entry")
                try await Self.seedEntry(sql, hash: "h2", title: "beta", text: "second entry")

                try await Self.assertSearchCount(sql, term: "alpha", is: 1)
                try await Self.assertSearchCount(sql, term: "beta", is: 1)

                // Requires `PRAGMA foreign_keys = ON` from the storage wrapper.
                try await sql.raw("DELETE FROM feeds WHERE id = 1").run()

                let count = try await sql.raw("SELECT COUNT(*) AS count FROM entries").first()
                let entryCount = try count?.decode(column: "count", as: Int.self)
                #expect(entryCount == 0)
                try await Self.assertSearchCount(sql, term: "alpha", is: 0)
                try await Self.assertSearchCount(sql, term: "beta", is: 0)
            }
        }
    }

    // MARK: - Helpers

    private static func sqlDatabase(from connection: any Database) throws -> any SQLDatabase {
        guard let sql = connection as? any SQLDatabase else {
            throw StorageError.notSQLDatabase
        }
        return sql
    }

    private static func seedFeed(_ sql: any SQLDatabase) async throws {
        try await sql.raw(
            "INSERT INTO users (id, username, password_hash, created_at, updated_at) VALUES (1, 'u', 'h', 1, 1)"
        ).run()
        try await sql.raw(
            "INSERT INTO categories (id, user_id, title, position, created_at, updated_at) VALUES (1, 1, 'c', 0, 1, 1)"
        ).run()
        try await sql.raw(
            "INSERT INTO feeds (id, user_id, category_id, url, created_at, updated_at) VALUES (1, 1, 1, 'https://example.com/feed.xml', 1, 1)"
        ).run()
    }

    private static func seedEntry(
        _ sql: any SQLDatabase,
        hash: String,
        title: String,
        text: String
    ) async throws {
        try await sql.raw(
            """
            INSERT INTO entries (user_id, feed_id, hash, title, content_text, published_at, created_at, updated_at)
            VALUES (1, 1, '\(unsafeRaw: hash)', '\(unsafeRaw: title)', '\(unsafeRaw: text)', 1, 1, 1)
            """
        ).run()
    }

    private static func assertSearchCount(
        _ sql: any SQLDatabase,
        term: String,
        is expected: Int,
        _ comment: String = "",
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let count = try await searchCount(sql, term: term)
        #expect(count == expected, "MATCH '\(term)' \(comment)", sourceLocation: sourceLocation)
    }

    private static func searchCount(_ sql: any SQLDatabase, term: String) async throws -> Int {
        let row = try await sql
            .raw("SELECT COUNT(*) AS count FROM entries_fts WHERE entries_fts MATCH '\(unsafeRaw: term)'")
            .first()
        return try row?.decode(column: "count", as: Int.self) ?? -1
    }
}
