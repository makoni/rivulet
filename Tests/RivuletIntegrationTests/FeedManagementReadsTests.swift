import Fluent
import Foundation
import SQLKit
import Testing
@testable import RivuletCore

/// The storage reads the feed management commands are built on: the duplicate read and the category
/// read the rule consults, the delete the `remove` command runs, and the listing order `list`
/// prints. The rule itself is pinned as pure logic by `FeedValidationTests`, and the commands by
/// `FeedCommandTests`.
///
/// What these pins can fail on, each checked by patching the rule and reverting: that the duplicate
/// read answers only for the rows of the account it is given, which a patch that dropped the
/// account condition fails on the input where another account has the url; that the category read
/// answers for the pair it is given, which a patch that dropped the account condition fails on the
/// input where the id belongs to another account; that the delete applies the account it is given,
/// which a patch that deleted by id alone fails on; that the rows below the feed — the entries, the
/// attachments, the tombstones and the search rows — go with it; and that the listing order is the
/// error count first and the lowercased title after, which a patch that ordered by the title alone,
/// or that read the title case-sensitively, fails on the rows seeded where the two orders differ.
///
/// What these pins cannot fail on: the single-row limit of the duplicate read, because the schema's
/// `UNIQUE (user_id, url)` means that read can never have two rows to choose between; the same
/// limit of the category read, because one account cannot have two rows with the same id; the
/// `LOWER` reading being ASCII-only, which no ASCII title can tell apart from the reference's
/// `lower()` on PostgreSQL; and the wording the commands build from these reads, which
/// `FeedCommandTests` read as the rule names.
@Suite struct FeedManagementReadsTests {
    @Test func theDuplicateReadAnswersOnlyForTheRowsOfTheUserItIsGiven() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let feeds = FeedRepository(connection)
                let aliceID = try await seedUser(connection, username: "alice")
                let bobID = try await seedUser(connection, username: "bob")
                let aliceCategory = try await seedCategory(connection, userID: aliceID, title: "A")
                let bobCategory = try await seedCategory(connection, userID: bobID, title: "B")
                _ = try await seedFeed(connection, userID: aliceID, categoryID: aliceCategory,
                    url: "https://alice.example/feed")
                _ = try await seedFeed(connection, userID: bobID, categoryID: bobCategory,
                    url: "https://bob.example/feed")

                // The control: the read answers for the row the user has.
                #expect(try await feeds.feedURLExists(userID: aliceID,
                    url: "https://alice.example/feed"), "the row this user has")

                // Bob's row is the one the pin reads: a patch that dropped the account condition
                // would answer the same for both accounts, so the control would not tell it apart.
                #expect(!(try await feeds.feedURLExists(userID: aliceID,
                    url: "https://bob.example/feed")),
                    "another user's row is not this user's duplicate")
                #expect(try await feeds.feedURLExists(userID: bobID,
                    url: "https://bob.example/feed"), "and is that user's")
            }
        }
    }

    @Test func theCategoryReadAnswersForThePairItIsGiven() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let categories = CategoryRepository(connection)
                let aliceID = try await seedUser(connection, username: "alice")
                let bobID = try await seedUser(connection, username: "bob")
                let aliceCategory = try await seedCategory(connection, userID: aliceID, title: "A")
                let bobCategory = try await seedCategory(connection, userID: bobID, title: "B")

                // The control: the pair that belongs to the user answers.
                #expect(try await categories.categoryExists(userID: aliceID, categoryID: aliceCategory),
                    "the category of the user it is given")

                // The id is unique across the table, so the only pair that does not belong to this
                // user is the pair with another user's category.
                #expect(!(try await categories.categoryExists(userID: aliceID, categoryID: bobCategory)),
                    "another user's row is not this user's category")
                #expect(try await categories.categoryExists(userID: bobID, categoryID: bobCategory),
                    "and is that user's")
            }
        }
    }

    @Test func theDeleteAppliesTheUserItIsGiven() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let feeds = FeedRepository(connection)
                let sql = try sqlDatabase(connection)
                let aliceID = try await seedUser(connection, username: "alice")
                let bobID = try await seedUser(connection, username: "bob")
                let bobCategory = try await seedCategory(connection, userID: bobID, title: "B")
                let feedID = try await seedFeed(connection, userID: bobID, categoryID: bobCategory,
                    url: "https://bob.example/feed")

                // The row is read back without the account condition, so what the pin sees is
                // whether the delete applied the account it was given, not which row a read
                // answered.
                #expect(try await Self.rowExists(sql, table: "feeds", id: feedID), "the row before")
                try await feeds.delete(id: feedID, userID: aliceID)
                #expect(try await Self.rowExists(sql, table: "feeds", id: feedID),
                    "the row of another user is not deleted")

                try await feeds.delete(id: feedID, userID: bobID)
                #expect(!(try await Self.rowExists(sql, table: "feeds", id: feedID)),
                    "the row of the user it is given is")
            }
        }
    }

    @Test func theRowsBelowTheFeedGoWithIt() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let feeds = FeedRepository(connection)
                let sql = try sqlDatabase(connection)
                let userID = try await seedUser(connection, username: "alice")
                let categoryID = try await seedCategory(connection, userID: userID, title: "Tech")
                let feedID = try await seedFeed(connection, userID: userID, categoryID: categoryID,
                    url: "https://example.com/feed")
                let entryID = try await seedEntry(connection, userID: userID, feedID: feedID,
                    hash: "h1", content: "<p>Searchable content</p>")

                // A tombstone and an attachment, each on its own row, so the pin sees which of the
                // rows the cascade takes away and which it leaves.
                try await sql.raw("""
                    INSERT INTO entry_tombstones (feed_id, hash, deleted_at)
                    VALUES (\(bind: feedID), \(bind: "h1"), \(bind: 1_700_000_000))
                    """).run()
                try await sql.raw("""
                    INSERT INTO enclosures (entry_id, url, mime_type)
                    VALUES (\(bind: entryID), \(bind: "https://example.com/a.mp3"),
                        \(bind: "audio/mpeg"))
                    """).run()
                #expect(try await Self.rowExists(sql, table: "entries_fts", match: "Searchable"),
                    "the search row before the delete")

                try await feeds.delete(id: feedID, userID: userID)
                #expect(!(try await Self.rowExists(sql, table: "feeds", id: feedID)),
                    "the feed row")
                #expect(!(try await Self.rowExists(sql, table: "entries", id: entryID)),
                    "the entry row")
                #expect(try await Self.count(sql, table: "entry_tombstones", column: "feed_id",
                    value: feedID) == 0, "the tombstone")
                #expect(try await Self.count(sql, table: "enclosures", column: "entry_id",
                    value: entryID) == 0, "the attachment")
                #expect(!(try await Self.rowExists(sql, table: "entries_fts", match: "Searchable")),
                    "and the search row, which the schema's triggers remove with the entry")
            }
        }
    }

    @Test func theListingOrderIsTheErrorCountFirstThenTheLowercasedTitle() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let feeds = FeedRepository(connection)
                let aliceID = try await seedUser(connection, username: "alice")
                let bobID = try await seedUser(connection, username: "bob")
                let aliceCategory = try await seedCategory(connection, userID: aliceID, title: "A")
                let bobCategory = try await seedCategory(connection, userID: bobID, title: "B")

                // The two orders the pins read are different here: the error count puts Zeta first,
                // while the title order puts Alpha first, so a patch that ordered by the title
                // alone answers the other sequence.
                let first = try await seedFeed(connection, userID: aliceID,
                    categoryID: aliceCategory, url: "https://alpha.example/feed")
                let second = try await seedFeed(connection, userID: aliceID,
                    categoryID: aliceCategory, url: "https://zeta.example/feed")
                try await Self.setErrorCount(connection, feedID: first, count: 1, title: "Alpha")
                try await Self.setErrorCount(connection, feedID: second, count: 2, title: "Zeta")

                // Equal counts, where the lowercased reading and the case-sensitive one differ:
                // `alpha` before `Beta` is the lowercased order, `Beta` before `alpha` is the
                // other.
                let lower = try await seedFeed(connection, userID: aliceID,
                    categoryID: aliceCategory, url: "https://lower.example/feed")
                let upper = try await seedFeed(connection, userID: aliceID,
                    categoryID: aliceCategory, url: "https://upper.example/feed")
                try await Self.setErrorCount(connection, feedID: lower, count: 2, title: "alpha")
                try await Self.setErrorCount(connection, feedID: upper, count: 2, title: "Beta")

                let ordered = try await feeds.listSortedByErrorCountThenTitle(userID: aliceID)
                #expect(ordered.map(\.id) == [lower, upper, second, first],
                    "the error count first, then the lowercased title inside the equal counts")

                // Bob's row has the largest count, so a patch that read the order without the
                // account condition would answer the sequence this pin expects not to hold.
                let bobFeed = try await seedFeed(connection, userID: bobID, categoryID: bobCategory,
                    url: "https://bob.example/feed")
                try await Self.setErrorCount(connection, feedID: bobFeed, count: 9, title: "Bob")
                let aliceOnly = try await feeds.listSortedByErrorCountThenTitle(userID: aliceID)
                #expect(aliceOnly.map(\.id) == [lower, upper, second, first],
                    "only the rows of the user the listing is given")
            }
        }
    }

    // MARK: - Helpers

    private static func rowExists(_ sql: any SQLDatabase, table: String,
        id: Int) async throws -> Bool {
        let row = try await sql.raw("SELECT 1 AS one FROM \(ident: table) WHERE id = \(bind: id) LIMIT 1")
            .first()
        return row != nil
    }

    private static func rowExists(_ sql: any SQLDatabase, table: String,
        match: String) async throws -> Bool {
        let row = try await sql.raw(
            "SELECT 1 AS one FROM \(ident: table) WHERE \(ident: table) MATCH \(bind: match) LIMIT 1")
            .first()
        return row != nil
    }

    private static func count(_ sql: any SQLDatabase, table: String, column: String,
        value: Int) async throws -> Int {
        let row = try await sql.raw(
            "SELECT COUNT(*) AS count FROM \(ident: table) WHERE \(ident: column) = \(bind: value)")
            .first()
        return try #require(try row?.decode(column: "count", as: Int.self))
    }

    private static func setErrorCount(_ connection: any Database, feedID: Int, count: Int,
        title: String) async throws {
        try await sqlDatabase(connection).raw("""
            UPDATE feeds SET parsing_error_count = \(bind: count), title = \(bind: title)
            WHERE id = \(bind: feedID)
            """).run()
    }
}
