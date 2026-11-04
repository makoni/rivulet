import Fluent
import FluentSQLiteDriver
import SQLKit
import Testing
@testable import RivuletCore

/// CRUD round-trip for ``CategoryRepository`` against a real SQLite file, and the two orders its
/// reads answer in: position then title, and title alone for the read the Google Reader tag list
/// builds. Both order pins set positions that differ from the title order, so a patch that used one
/// order for both reads fails on the pin that names the other.
@Suite struct CategoryRepositoryTests {
    @Test func createStoresTheFieldsAndDefaultsPositionToZero() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let users = UserRepository(connection)
                let categories = CategoryRepository(connection)
                let user = try await users.create(username: "alice", passwordHash: "hash", isAdmin: false)
                let userID = try #require(user.id)

                let category = try await categories.create(userID: userID, title: "Tech")
                let id = try #require(category.id)

                // Re-read through a fresh fetch: the assertions prove the stored row.
                let stored = try await categories.fetch(id: id)
                #expect(stored?.id == id)
                #expect(stored?.userID == userID)
                #expect(stored?.title == "Tech")
                #expect(stored?.position == 0)
                #expect(stored?.createdAt == stored?.updatedAt)
            }
        }
    }

    @Test func duplicateTitleForTheSameUserIsRejected() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let users = UserRepository(connection)
                let categories = CategoryRepository(connection)
                let alice = try await users.create(username: "alice", passwordHash: "a", isAdmin: false)
                let bob = try await users.create(username: "bob", passwordHash: "b", isAdmin: false)
                let aliceID = try #require(alice.id)
                let bobID = try #require(bob.id)
                _ = try await categories.create(userID: aliceID, title: "Tech")

                do {
                    _ = try await categories.create(userID: aliceID, title: "Tech")
                    Issue.record("expected the duplicate (user, title) pair to be rejected")
                } catch {
                    // UNIQUE(user_id, title) violation; driver error type is not promised.
                }
                // Each user owns the default "All" category plus "Tech".
                #expect(try await categories.list(userID: aliceID).map(\.title) == ["All", "Tech"])

                // The same title is legal for another user.
                _ = try await categories.create(userID: bobID, title: "Tech")
                #expect(try await categories.list(userID: bobID).map(\.title) == ["All", "Tech"])
            }
        }
    }

    @Test func listOrdersByPositionThenTitle() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let users = UserRepository(connection)
                let categories = CategoryRepository(connection)
                let user = try await users.create(username: "alice", passwordHash: "hash", isAdmin: false)
                let userID = try #require(user.id)
                _ = try await categories.create(userID: userID, title: "bravo")
                _ = try await categories.create(userID: userID, title: "alpha")
                _ = try await categories.create(userID: userID, title: "charlie")
                _ = try await categories.create(userID: userID, title: "delta")

                // The repository does not expose position updates (the later API stages
                // do), so pin positions the way FTSSyncTests pins state with raw SQL:
                // delta at 0 makes the sorted order differ from insertion order, and
                // alpha/charlie share position 1 to exercise the title tie-break.
                guard let sql = connection as? any SQLDatabase else {
                    throw StorageError.notSQLDatabase
                }
                try await sql.raw("UPDATE categories SET position = 1 WHERE title = 'alpha'").run()
                try await sql.raw("UPDATE categories SET position = 1 WHERE title = 'charlie'").run()

                let titles = try await categories.list(userID: userID).map(\.title)
                #expect(titles == ["All", "bravo", "delta", "alpha", "charlie"])
            }
        }
    }

    @Test func listByTitleIgnoresPosition() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let users = UserRepository(connection)
                let categories = CategoryRepository(connection)
                let user = try await users.create(username: "alice", passwordHash: "hash", isAdmin: false)
                let userID = try #require(user.id)
                _ = try await categories.create(userID: userID, title: "News")
                _ = try await categories.create(userID: userID, title: "Tech")

                // The Google Reader tag list reads the reference's `Categories` statement, which
                // orders by title alone. Positions are set so a patch that ordered by position
                // answered Tech first here.
                guard let sql = connection as? any SQLDatabase else {
                    throw StorageError.notSQLDatabase
                }
                try await sql.raw("UPDATE categories SET position = 2 WHERE title = 'News'").run()
                try await sql.raw("UPDATE categories SET position = 1 WHERE title = 'Tech'").run()

                #expect(try await categories.listByTitle(userID: userID).map(\.title)
                    == ["All", "News", "Tech"])
            }
        }
    }

    @Test func deletingACategoryRemovesItsFeeds() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let users = UserRepository(connection)
                let categories = CategoryRepository(connection)
                let feeds = FeedRepository(connection)
                let user = try await users.create(username: "alice", passwordHash: "hash", isAdmin: false)
                let userID = try #require(user.id)
                let category = try await categories.create(userID: userID, title: "Tech")
                let categoryID = try #require(category.id)
                let feed = try await feeds.create(
                    userID: userID,
                    categoryID: categoryID,
                    url: "https://example.com/feed.xml"
                )
                let feedID = try #require(feed.id)

                try await categories.delete(id: categoryID)

                #expect(try await categories.fetch(id: categoryID) == nil)
                #expect(try await feeds.fetch(id: feedID) == nil)
            }
        }
    }
}
