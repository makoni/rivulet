import Fluent
import FluentSQLiteDriver
import SQLKit
import Testing
@testable import RivuletCore

/// CRUD round-trip for `CategoryRepository` against a real SQLite file, and the two orders its
/// reads answer in: position then title, and title alone for the read the Google Reader tag list
/// builds. Both order pins set positions that differ from the title order, so a patch that used one
/// order for both reads fails on the pin that names the other. The reads the tag write path is
/// built on are pinned too: the title read compares the title as read while the duplicate read
/// lowercases both sides and excludes the row it is checking, the rename writes what the request
/// carries, and the named delete keeps at least one category — its guard runs before any write —
/// moves the feeds of the deleted rows to the first remaining title, per user on both the read that
/// counts and the statement that deletes.
///
/// What this suite cannot show is named here: the row order the delete's read answers its rows in,
/// which the statement does not order, so a patch that took any remaining row in that order
/// answered the same as the pick; the transaction boundary, which is the caller's, because no pin
/// can make a statement fail in the middle of one; and the order of the guard, the reassignment and
/// the delete, which is the same for every input that reaches them.
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

                // The repository does not expose position updates (the later API stages do), so pin
                // positions the way FTSSyncTests pins state with raw SQL: delta at 0 makes the
                // sorted order differ from insertion order, and alpha/charlie share position 1 to
                // exercise the title tie-break.
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

    @Test func theTitleReadComparesTheTitleAsRead() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let categories = CategoryRepository(connection)
                let userID = try await seedUser(connection, username: "alice")
                _ = try await seedCategory(connection, userID: userID, title: "Tech")

                #expect(try await categories.byTitle(userID: userID, title: "Tech") != nil,
                    "the title is compared as it is given")
                #expect(try await categories.byTitle(userID: userID, title: "tech") == nil,
                    "a different case is a different title for this read")
            }
        }
    }

    @Test func theDuplicateReadLowercasesBothSidesAndExcludesTheRowItIsChecking() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let categories = CategoryRepository(connection)
                let userID = try await seedUser(connection, username: "alice")
                let newsID = try await seedCategory(connection, userID: userID, title: "News")
                let techID = try await seedCategory(connection, userID: userID, title: "Tech")
                let other = try await seedUser(connection, username: "bob")
                let bobOtherID = try await seedCategory(connection, userID: other, title: "Other")

                #expect(try await categories.anotherTitleExists(userID: userID, categoryID: newsID,
                    title: "tech") == true, "the other row is found through the lowercased form")
                #expect(try await categories.anotherTitleExists(userID: userID, categoryID: techID,
                    title: "Tech") == false, "the row being checked is not a duplicate of itself")
                #expect(try await categories.anotherTitleExists(userID: userID, categoryID: newsID,
                    title: "Other") == false, "no row of this user carries that title")

                // Only the other user has that title, so a patch that read the uniqueness across
                // the whole table instead of per user would answer true here.
                #expect(try await categories.anotherTitleExists(userID: other, categoryID: bobOtherID,
                    title: "tech") == false, "another user's row is not a duplicate for this user")
            }
        }
    }

    @Test func theRenameWritesTheTitleTheRequestCarries() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let categories = CategoryRepository(connection)
                let userID = try await seedUser(connection, username: "alice")
                let categoryID = try await seedCategory(connection, userID: userID, title: "Tech")

                try await categories.setTitle(userID: userID, categoryID: categoryID, title: "News")
                let stored = try #require(try await categories.fetch(id: categoryID))
                #expect(stored.title == "News", "the title is what the read answered")
            }
        }
    }

    @Test func theNamedDeleteKeepsAtLeastOneCategoryAndReassignsFeedsToTheFirstRemainingTitle()
        async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let categories = CategoryRepository(connection)
                let feeds = FeedRepository(connection)
                let userID = try await seedUser(connection, username: "alice")
                // `seedUser` creates the default "All" category, so the rows below are the ones
                // this read has to pick between, and the input names only two of them, which leaves
                // two rows for the pick: it answers the smallest of the titles left, which is what
                // a patch that reversed the comparison fails on. The row order the read answers its
                // rows in is not pinned, because the statement has no `ORDER BY`.
                let allRow = try #require(try await categories.byTitle(userID: userID, title: "All"))
                let allID = try #require(allRow.id)
                let zetaID = try await seedCategory(connection, userID: userID, title: "Zeta")
                let amyID = try await seedCategory(connection, userID: userID, title: "Amy")
                let techID = try await seedCategory(connection, userID: userID, title: "Tech")
                let other = try await seedUser(connection, username: "bob")
                let bobTechID = try await seedCategory(connection, userID: other, title: "Tech")
                let bobZetaID = try await seedCategory(connection, userID: other, title: "Zeta")
                let zetaFeedID = try #require(try await feeds.create(userID: userID, categoryID: zetaID,
                    url: "https://example.com/1").id)
                let techFeedID = try #require(try await feeds.create(userID: userID, categoryID: techID,
                    url: "https://example.com/2").id)

                try await categories.removeAndReplaceNamed(userID: userID, titles: ["All", "Tech"])

                #expect(try await categories.fetch(id: techID) == nil, "the named row is deleted")
                #expect(try await categories.fetch(id: allID) == nil, "the other named row is deleted")
                #expect(try await categories.fetch(id: zetaID) != nil, "a row that is not named stays")
                #expect(try await feeds.fetch(id: techFeedID)?.categoryID == amyID,
                    "its feed goes to the first remaining title")
                #expect(try await feeds.fetch(id: zetaFeedID)?.categoryID == zetaID,
                    "a feed in a row that is not named is not moved")
                #expect(try await categories.fetch(id: bobTechID) != nil,
                    "another user's row with the same title is not named by this read")
                #expect(try await categories.fetch(id: bobZetaID) != nil,
                    "and not deleted by it, which is what the delete statement is pinned on")

                // The titles are compared as read, so the mixed-case form names nothing: the list
                // is empty, nothing is written, and the rows that are not named stay where they
                // are.
                try await categories.removeAndReplaceNamed(userID: userID, titles: ["zeta"])
                #expect(try await feeds.fetch(id: techFeedID)?.categoryID == amyID,
                    "the empty list names nothing")
                #expect(try await categories.fetch(id: bobZetaID) != nil,
                    "the mixed-case form names another user's row, which this read does not name")

                // The guard runs before any write: the input that would leave nothing answers the
                // error and leaves the rows where they are.
                do {
                    try await categories.removeAndReplaceNamed(userID: userID,
                        titles: ["Zeta", "Amy"])
                    Issue.record("the guard should have reported before any write")
                } catch {
                    #expect(String(describing: error) ==
                        "store: at least 1 category must remain after deletion",
                        "the wording the reference reports for this rule")
                }
                #expect(try await categories.fetch(id: zetaID) != nil, "nothing was deleted")
                #expect(try await feeds.fetch(id: techFeedID)?.categoryID == amyID,
                    "and nothing was reassigned")
            }
        }
    }
}
