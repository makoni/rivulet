import Foundation
import Fluent
import FluentSQLiteDriver
import Testing
@testable import RivuletCore

/// CRUD round-trip for ``UserRepository`` against a real SQLite file.
@Suite struct UserRepositoryTests {
    @Test func createStoresTheAccountFieldsAndAssignsAnID() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let users = UserRepository(connection)
                let user = try await users.create(username: "alice", passwordHash: "hash", isAdmin: true)
                let id = try #require(user.id)

                // Re-read through a fresh fetch: the assertions prove the stored row,
                // not the in-memory object.
                let stored = try await users.fetch(id: id)
                #expect(stored?.id == id)
                #expect(stored?.username == "alice")
                #expect(stored?.passwordHash == "hash")
                #expect(stored?.isAdmin == true)
                #expect(stored?.googleReaderUsername == nil)
                #expect(stored?.googleReaderPasswordHash == nil)
                #expect(stored?.feverUsername == nil)
                #expect(stored?.feverToken == nil)
                #expect(stored?.createdAt == stored?.updatedAt)
            }
        }
    }

    @Test func createAlsoCreatesTheDefaultAllCategory() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let users = UserRepository(connection)
                let categories = CategoryRepository(connection)
                let user = try await users.create(username: "alice", passwordHash: "hash", isAdmin: false)
                let id = try #require(user.id)

                let titles = try await categories.list(userID: id).map(\.title)
                #expect(titles == ["All"])
            }
        }
    }

    @Test func usernamesAreStoredLowercaseAndLookupsAreCaseInsensitive() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let users = UserRepository(connection)
                let user = try await users.create(username: "Alice", passwordHash: "hash", isAdmin: false)
                let id = try #require(user.id)

                #expect(try await users.fetch(id: id)?.username == "alice")
                #expect(try await users.fetch(username: "ALICE")?.id == id)
                #expect(try await users.fetch(username: "Alice")?.id == id)

                do {
                    _ = try await users.create(username: "ALICE", passwordHash: "b", isAdmin: false)
                    Issue.record("expected the case-insensitive duplicate username to be rejected")
                } catch {
                    // UNIQUE(username) violation after normalization; the driver error
                    // type is not promised.
                }
                #expect(try await users.list().count == 1)
            }
        }
    }

    @Test func fetchByIDAndByUsernameFindTheStoredUser() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let users = UserRepository(connection)
                let alice = try await users.create(username: "alice", passwordHash: "a", isAdmin: false)
                let bob = try await users.create(username: "bob", passwordHash: "b", isAdmin: false)
                let aliceID = try #require(alice.id)
                let bobID = try #require(bob.id)

                let byID = try await users.fetch(id: bobID)
                #expect(byID?.username == "bob")
                #expect(try await users.fetch(id: aliceID)?.passwordHash == "a")
                #expect(try await users.fetch(username: "alice")?.id == aliceID)
                #expect(try await users.fetch(username: "bob")?.id == bobID)
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
