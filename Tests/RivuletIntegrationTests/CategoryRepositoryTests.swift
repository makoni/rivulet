import Fluent
import FluentSQLiteDriver
import Testing
@testable import RivuletCore

/// CRUD round-trip for ``CategoryRepository`` against a real SQLite file.
@Suite struct CategoryRepositoryTests {
    /// Creates a database with the schema migrated and runs `body` against it.
    private func withMigratedStorage(
        _ body: (TestDatabase, SQLiteStorage) async throws -> Void
    ) async throws {
        let database = try await TestDatabase.make()
        do {
            let storage = SQLiteStorage(database: database.app.db(.sqlite), path: database.path)
            try await storage.prepare()
            try await database.app.autoMigrate()
            try await body(database, storage)
        } catch {
            await database.shutdown()
            throw error
        }
        await database.shutdown()
    }

    @Test func createStoresTheFieldsAndDefaultsPositionToZero() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let users = UserRepository(connection)
                let categories = CategoryRepository(connection)
                let user = try await users.create(username: "alice", passwordHash: "hash", isAdmin: false)

                let category = try await categories.create(userID: user.id!, title: "Tech")

                #expect(category.id != nil)
                #expect(category.userID == user.id!)
                #expect(category.title == "Tech")
                #expect(category.position == 0)
                #expect(category.createdAt == category.updatedAt)
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
                _ = try await categories.create(userID: alice.id!, title: "Tech")

                do {
                    _ = try await categories.create(userID: alice.id!, title: "Tech")
                    Issue.record("expected the duplicate (user, title) pair to be rejected")
                } catch {
                    // UNIQUE(user_id, title) violation; driver error type is not promised.
                }

                // The same title is legal for another user.
                _ = try await categories.create(userID: bob.id!, title: "Tech")
                #expect(try await categories.list(userID: bob.id!).count == 1)
            }
        }
    }

    @Test func listOrdersByPositionThenTitle() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let users = UserRepository(connection)
                let categories = CategoryRepository(connection)
                let user = try await users.create(username: "alice", passwordHash: "hash", isAdmin: false)
                _ = try await categories.create(userID: user.id!, title: "bravo")
                _ = try await categories.create(userID: user.id!, title: "alpha")
                _ = try await categories.create(userID: user.id!, title: "charlie")

                let titles = try await categories.list(userID: user.id!).map(\.title)
                #expect(titles == ["alpha", "bravo", "charlie"])
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
                let category = try await categories.create(userID: user.id!, title: "Tech")
                let feed = try await feeds.create(
                    userID: user.id!,
                    categoryID: category.id!,
                    url: "https://example.com/feed.xml"
                )

                try await categories.delete(id: category.id!)

                #expect(try await categories.fetch(id: category.id!) == nil)
                #expect(try await feeds.fetch(id: feed.id!) == nil)
            }
        }
    }
}
