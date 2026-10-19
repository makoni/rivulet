import Fluent
import FluentSQLiteDriver
import Testing
@testable import RivuletCore

/// CRUD round-trip for ``UserRepository`` against a real SQLite file.
@Suite struct UserRepositoryTests {
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

    @Test func createStoresTheAccountFieldsAndAssignsAnID() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let users = UserRepository(connection)
                let user = try await users.create(username: "alice", passwordHash: "hash", isAdmin: true)

                #expect(user.id != nil)
                #expect(user.username == "alice")
                #expect(user.passwordHash == "hash")
                #expect(user.isAdmin)
                #expect(user.googleReaderUsername == nil)
                #expect(user.googleReaderPasswordHash == nil)
                #expect(user.feverUsername == nil)
                #expect(user.feverToken == nil)
                #expect(user.createdAt == user.updatedAt)
            }
        }
    }

    @Test func fetchByIDAndByUsernameFindTheStoredUser() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let users = UserRepository(connection)
                let alice = try await users.create(username: "alice", passwordHash: "a", isAdmin: false)
                let bob = try await users.create(username: "bob", passwordHash: "b", isAdmin: false)

                let byID = try await users.fetch(id: bob.id!)
                #expect(byID?.username == "bob")
                #expect(try await users.fetch(id: alice.id!)?.passwordHash == "a")
                #expect(try await users.fetch(username: "alice")?.id == alice.id)
                #expect(try await users.fetch(username: "bob")?.id == bob.id)
                #expect(try await users.fetch(id: 999) == nil)
                #expect(try await users.fetch(username: "carol") == nil)
            }
        }
    }

    @Test func duplicateUsernameIsRejected() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let users = UserRepository(connection)
                _ = try await users.create(username: "alice", passwordHash: "a", isAdmin: false)
                do {
                    _ = try await users.create(username: "alice", passwordHash: "b", isAdmin: true)
                    Issue.record("expected the duplicate username to be rejected")
                } catch {
                    // The driver reports the UNIQUE(username) violation; its concrete
                    // type is a driver detail the storage layer does not promise.
                }
                #expect(try await users.list().count == 1)
            }
        }
    }

    @Test func listReturnsEveryUserOrderedByID() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let users = UserRepository(connection)
                _ = try await users.create(username: "carol", passwordHash: "c", isAdmin: false)
                _ = try await users.create(username: "alice", passwordHash: "a", isAdmin: false)
                _ = try await users.create(username: "bob", passwordHash: "b", isAdmin: false)

                let all = try await users.list()
                #expect(all.map(\.username) == ["carol", "alice", "bob"])
            }
        }
    }
}
