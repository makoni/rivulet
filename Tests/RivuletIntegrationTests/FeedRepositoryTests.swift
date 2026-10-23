import Foundation
import Fluent
import FluentSQLiteDriver
import Testing
@testable import RivuletCore

/// CRUD round-trip and fetch-state bookkeeping for ``FeedRepository``.
@Suite struct FeedRepositoryTests {
    /// Creates a user with one category and one feed.
    private func seedFeed(_ connection: any Database) async throws -> (User, Category, Feed) {
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
        return (user, category, feed)
    }

    @Test func createAppliesTheUpstreamDefaults() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let before = nowInSeconds()
                let feed = try await seedFeed(connection).2
                let after = nowInSeconds()
                let id = try #require(feed.id)

                // Re-read through a fresh fetch: the assertions prove the stored defaults.
                let stored = try await FeedRepository(connection).fetch(id: id)
                #expect(stored?.id == id)
                #expect(stored?.url == "https://example.com/feed.xml")
                #expect(stored?.siteURL == "")
                #expect(stored?.title == "")
                #expect(stored?.feedDescription == "")
                #expect(stored?.iconID == nil)
                #expect(stored?.etag == "")
                #expect(stored?.lastModified == "")
                #expect(stored?.checkInterval == 60)
                #expect(stored?.parsingErrorCount == 0)
                #expect(stored?.parsingErrorMessage == "")
                #expect(stored?.userAgent == "")
                #expect(stored?.disabled == false)
                #expect(stored?.fetchedAt == nil)
                #expect(stored?.createdAt == stored?.updatedAt)
                #expect((stored?.nextCheckAt ?? -1) >= before)
                #expect((stored?.nextCheckAt ?? -1) <= after)
            }
        }
    }

    @Test func thePerFeedFetchSettingsRoundTrip() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let feeds = FeedRepository(connection)
                let feed = try await seedFeed(connection).2
                let feedID = try #require(feed.id)

                // Upstream defaults for both flags: false.
                let created = try await feeds.fetch(id: feedID)
                #expect(created?.ignoreHTTPCache == false)
                #expect(created?.fetchViaProxy == false)

                feed.ignoreHTTPCache = true
                feed.fetchViaProxy = true
                try await feed.save(on: connection)

                let stored = try await feeds.fetch(id: feedID)
                #expect(stored?.ignoreHTTPCache == true)
                #expect(stored?.fetchViaProxy == true)
            }
        }
    }

    @Test func duplicateURLForTheSameUserIsRejected() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let feeds = FeedRepository(connection)
                let (user, category, _) = try await seedFeed(connection)
                let userID = try #require(user.id)
                let categoryID = try #require(category.id)

                do {
                    _ = try await feeds.create(userID: userID, categoryID: categoryID, url: "https://example.com/feed.xml")
                    Issue.record("expected the duplicate (user, url) pair to be rejected")
                } catch {
                    // UNIQUE(user_id, url) violation; driver error type is not promised.
                }
                #expect(try await feeds.list(userID: userID).count == 1)

                // The same URL is legal for another user.
                let users = UserRepository(connection)
                let categories = CategoryRepository(connection)
                let bob = try await users.create(username: "bob", passwordHash: "b", isAdmin: false)
                let bobID = try #require(bob.id)
                let bobCategory = try await categories.create(userID: bobID, title: "B")
                let bobCategoryID = try #require(bobCategory.id)
                _ = try await feeds.create(userID: bobID, categoryID: bobCategoryID, url: "https://example.com/feed.xml")
                #expect(try await feeds.list(userID: bobID).count == 1)
            }
        }
    }

    @Test func fetchByIDAndByURLFindTheStoredFeed() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let feeds = FeedRepository(connection)
                let (user, _, feed) = try await seedFeed(connection)
                let userID = try #require(user.id)
                let feedID = try #require(feed.id)

                #expect(try await feeds.fetch(id: feedID)?.url == "https://example.com/feed.xml")
                #expect(try await feeds.fetch(userID: userID, url: feed.url)?.id == feedID)
                #expect(try await feeds.fetch(id: 999) == nil)
                #expect(try await feeds.fetch(userID: userID, url: "https://unknown.example/x") == nil)
            }
        }
    }

    @Test func listReturnsOnlyTheFeedsOfTheUser() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let users = UserRepository(connection)
                let categories = CategoryRepository(connection)
                let feeds = FeedRepository(connection)
                let alice = try await users.create(username: "alice", passwordHash: "a", isAdmin: false)
                let bob = try await users.create(username: "bob", passwordHash: "b", isAdmin: false)
                let aliceID = try #require(alice.id)
                let bobID = try #require(bob.id)
                let aliceCategory = try await categories.create(userID: aliceID, title: "A")
                let bobCategory = try await categories.create(userID: bobID, title: "B")
                let aliceCategoryID = try #require(aliceCategory.id)
                let bobCategoryID = try #require(bobCategory.id)
                _ = try await feeds.create(
                    userID: aliceID,
                    categoryID: aliceCategoryID,
                    url: "https://alice.example/feed.xml"
                )
                _ = try await feeds.create(
                    userID: bobID,
                    categoryID: bobCategoryID,
                    url: "https://bob.example/feed.xml"
                )

                let aliceFeeds = try await feeds.list(userID: aliceID)
                #expect(aliceFeeds.map(\.url) == ["https://alice.example/feed.xml"])
            }
        }
    }

    @Test func recordFetchStoresStateAndResetsTheParsingErrors() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let feeds = FeedRepository(connection)
                let feed = try await seedFeed(connection).2
                let feedID = try #require(feed.id)
                _ = try await feeds.recordParsingError(feedID: feedID, message: "boom one", nextCheckAt: nowInSeconds())
                _ = try await feeds.recordParsingError(feedID: feedID, message: "boom two", nextCheckAt: nowInSeconds())
                let nextCheckAt = nowInSeconds() + 600
                let before = nowInSeconds()
                _ = try await feeds.recordFetch(
                    feedID: feedID,
                    etag: "etag-1",
                    lastModified: "Fri, 01 Jan 2026 00:00:00 GMT",
                    nextCheckAt: nextCheckAt
                )
                let after = nowInSeconds()

                let refreshed = try await feeds.fetch(id: feedID)
                #expect(refreshed?.etag == "etag-1")
                #expect(refreshed?.lastModified == "Fri, 01 Jan 2026 00:00:00 GMT")
                #expect(refreshed?.nextCheckAt == nextCheckAt)
                #expect((refreshed?.fetchedAt ?? -1) >= before)
                #expect((refreshed?.fetchedAt ?? -1) <= after)
                #expect(refreshed?.parsingErrorCount == 0)
                #expect(refreshed?.parsingErrorMessage == "")
            }
        }
    }

    @Test func recordParsingErrorKeepsTheNewestMessageAndIncrementsTheCounter() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let feeds = FeedRepository(connection)
                let feed = try await seedFeed(connection).2
                let feedID = try #require(feed.id)
                let before = nowInSeconds()
                _ = try await feeds.recordParsingError(feedID: feedID, message: "boom one", nextCheckAt: before)
                let secondCheck = nowInSeconds()
                _ = try await feeds.recordParsingError(feedID: feedID, message: "boom two", nextCheckAt: secondCheck)
                let after = nowInSeconds()

                let refreshed = try await feeds.fetch(id: feedID)
                #expect(refreshed?.parsingErrorCount == 2)
                #expect(refreshed?.parsingErrorMessage == "boom two")
                #expect(refreshed?.nextCheckAt == secondCheck)
                #expect((refreshed?.fetchedAt ?? -1) >= before)
                #expect((refreshed?.fetchedAt ?? -1) <= after)
            }
        }
    }

    @Test func bookkeepingForAMissingFeedIsReported() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let feeds = FeedRepository(connection)

                do {
                    _ = try await feeds.recordFetch(
                        feedID: 999,
                        etag: "",
                        lastModified: "",
                        nextCheckAt: 1
                    )
                    Issue.record("expected recordFetch to fail for a missing feed")
                } catch let error as StorageError {
                    #expect(error == .feedNotFound(id: 999))
                }

                do {
                    _ = try await feeds.recordParsingError(feedID: 999, message: "boom", nextCheckAt: 1)
                    Issue.record("expected recordParsingError to fail for a missing feed")
                } catch let error as StorageError {
                    #expect(error == .feedNotFound(id: 999))
                }
            }
        }
    }

    @Test func deleteRemovesTheFeed() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let feeds = FeedRepository(connection)
                let feed = try await seedFeed(connection).2
                let feedID = try #require(feed.id)

                try await feeds.delete(id: feedID)

                #expect(try await feeds.fetch(id: feedID) == nil)
            }
        }
    }
}
