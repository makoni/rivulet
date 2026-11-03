import Foundation
import Fluent
import FluentSQLiteDriver
import Testing
@testable import RivuletCore

/// CRUD round-trip for ``UserRepository`` against a real SQLite file.
///
/// What these pins can fail on: the lowercase write, the case-insensitive lookup, the uniqueness of
/// the name, the order `list` reads, the default "All" category written with the row, and the
/// existence read finding the stored name whatever case it is given, which a patch that compares
/// the input as read fails. That last pin was checked by patching and reverting for this change;
/// the others were checked the same way when they landed. What they cannot fail on: the single-row
/// limit of that existence read, which a lookup that fetched every matching row answers the same
/// way, so the code states it rather than pinning it; and the transaction the pair of writes would
/// need, which is the caller's and is stated in the repository comment. The integration pins below
/// name the storage rules; `IntegrationCredentialsTests` pins the command that calls them. Each of
/// them was checked by patching the rule and reverting.
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

    @Test func theIntegrationWriteStoresTheValuesAsGiven() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let users = UserRepository(connection)
                let user = try await users.create(username: "alice", passwordHash: "a", isAdmin: false)
                let id = try #require(user.id)

                // Unlike the account name, the integration names are written as they are given,
                // which is what `UpdateIntegration` does upstream: `fever_username=$9`, no `LOWER`.
                try await users.updateIntegration(user, feverUsername: "Fever1",
                    feverToken: "71e9d7c8fd7d2b3dc94c3de389826bd8",
                    googleReaderUsername: "Gr1", googleReaderPasswordHash: "stored-hash")

                // Read back through a fresh fetch, so the pin reports the stored row.
                let stored = try #require(try await users.fetch(id: id))
                #expect(stored.username == "alice", "the account name is not rewritten: \(stored)")
                #expect(stored.feverUsername == "Fever1", "the name as given: \(stored)")
                #expect(stored.googleReaderUsername == "Gr1", "the name as given: \(stored)")
                #expect(stored.feverToken == "71e9d7c8fd7d2b3dc94c3de389826bd8",
                    "the value the caller derived is what is stored: \(stored)")
                #expect(stored.googleReaderPasswordHash == "stored-hash",
                    "the value the caller hashed is what is stored: \(stored)")
            }
        }
    }

    @Test func theDuplicateReadsExcludeTheRowTheyBelongTo() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let users = UserRepository(connection)
                let alice = try await users.create(username: "alice", passwordHash: "a", isAdmin: false)
                let bob = try await users.create(username: "bob", passwordHash: "b", isAdmin: false)
                let aliceID = try #require(alice.id)
                let bobID = try #require(bob.id)

                try await users.updateIntegration(alice, feverUsername: "Fever1",
                    feverToken: "t1", googleReaderUsername: "Gr1",
                    googleReaderPasswordHash: "h1")

                // Upstream reads `user_id != $1`, so a value the user's own row holds is not a
                // duplicate: a patch that dropped the exclusion answers true on this line.
                #expect(!(try await users.hasDuplicateFeverUsername(userID: aliceID,
                    feverUsername: "Fever1")), "the row the value is on belongs to this user")
                #expect(try await users.hasDuplicateFeverUsername(userID: bobID,
                    feverUsername: "Fever1"), "the same value on another row is a duplicate")
                #expect(!(try await users.hasDuplicateGoogleReaderUsername(userID: aliceID,
                    googleReaderUsername: "Gr1")), "the same rule on the other read")
                #expect(try await users.hasDuplicateGoogleReaderUsername(userID: bobID,
                    googleReaderUsername: "Gr1"), "the control for the other read")
            }
        }
    }

    @Test func theDuplicateReadsCompareTheValueAsReadAndReadTheirOwnColumn() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let users = UserRepository(connection)
                let alice = try await users.create(username: "alice", passwordHash: "a", isAdmin: false)
                let bob = try await users.create(username: "bob", passwordHash: "b", isAdmin: false)
                let bobID = try #require(bob.id)

                // The two columns hold different values, so each read can be named by what it answers.
                try await users.updateIntegration(alice, feverUsername: "FName",
                    feverToken: "t", googleReaderUsername: "GName",
                    googleReaderPasswordHash: "h")

                // No `LOWER` in either check, unlike the account lookup: a patch that lowercased the
                // input before comparing fails these two lines.
                #expect(try await users.hasDuplicateFeverUsername(userID: bobID,
                    feverUsername: "FName"), "the value as read")
                #expect(!(try await users.hasDuplicateFeverUsername(userID: bobID,
                    feverUsername: "fname")), "the input is not lowercased first")
                #expect(try await users.hasDuplicateGoogleReaderUsername(userID: bobID,
                    googleReaderUsername: "GName"), "the value as read")
                #expect(!(try await users.hasDuplicateGoogleReaderUsername(userID: bobID,
                    googleReaderUsername: "gname")), "the input is not lowercased first")

                // Which column each check reads: a patch that read the other column for this rule
                // would answer true here, where only the Fever column holds `GName` and only the
                // Google Reader column holds `FName`.
                #expect(!(try await users.hasDuplicateFeverUsername(userID: bobID,
                    feverUsername: "GName")), "the Fever check reads the Fever column")
                #expect(!(try await users.hasDuplicateGoogleReaderUsername(userID: bobID,
                    googleReaderUsername: "FName")), "the Google Reader check reads its own column")
            }
        }
    }
}
