import Foundation
import Fluent
import FluentSQLiteDriver
import Testing
@testable import RivuletCore

/// CRUD round-trip for ``UserRepository`` against a real SQLite file.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the lowercase
/// write, the case-insensitive lookup, the uniqueness of the name, the order `list` reads, the
/// default "All" category written with the row, and the existence read finding the stored name
/// whatever case it is given, which a patch that compares the input as read fails. What they cannot
/// fail on: the single-row limit of that existence read, which a lookup that fetched every matching
/// row answers the same way, so the code states it rather than pinning it; and the transaction the
/// pair of writes would need, which is the caller's and is stated in the repository comment.
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

    @Test func userExistsReadsTheStoredNameWhateverCaseItIsGiven() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let users = UserRepository(connection)
                #expect(!(try await users.userExists(username: "carol")), "no row yet")

                _ = try await users.create(username: "Alice", passwordHash: "hash", isAdmin: false)
                #expect(try await users.userExists(username: "alice"))
                // The reference reads the name through `LOWER($1)`, so a patch that compares the
                // input as given fails this line. What the pin cannot fail on is the single-row
                // read: a lookup that fetched every matching row answers the same value, so
                // `LIMIT 1` is stated in the code rather than pinned.
                #expect(try await users.userExists(username: "ALICE"), "the case-insensitive read")
            }
        }
    }

    @Test func listReturnsEveryUserOrderedByUsername() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let users = UserRepository(connection)
                _ = try await users.create(username: "carol", passwordHash: "c", isAdmin: false)
                _ = try await users.create(username: "alice", passwordHash: "a", isAdmin: false)
                _ = try await users.create(username: "bob", passwordHash: "b", isAdmin: false)

                let all = try await users.list()
                #expect(all.map(\.username) == ["alice", "bob", "carol"])
            }
        }
    }
}
