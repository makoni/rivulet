import Foundation
import Fluent
import FluentSQLiteDriver
import Testing
@testable import RivuletCore

/// CRUD round-trip and fetch-state bookkeeping for ``FeedRepository``.
@Suite struct FeedRepositoryTests {
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

    /// Creates a user with one category and one feed.
    private func seedFeed(_ connection: any Database) async throws -> (User, Category, Feed) {
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
        return (user, category, feed)
    }

    @Test func createAppliesTheUpstreamDefaults() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let before = nowInSeconds()
                let feed = try await seedFeed(connection).2
                let after = nowInSeconds()

                #expect(feed.id != nil)
                #expect(feed.url == "https://example.com/feed.xml")
                #expect(feed.siteURL == "")
                #expect(feed.title == "")
                #expect(feed.feedDescription == "")
                #expect(feed.iconID == nil)
                #expect(feed.etag == "")
                #expect(feed.lastModified == "")
                #expect(feed.checkInterval == 60)
                #expect(feed.parsingErrorCount == 0)
                #expect(feed.parsingErrorMessage == "")
                #expect(feed.userAgent == "")
                #expect(feed.disabled == false)
                #expect(feed.fetchedAt == nil)
                #expect(feed.createdAt == feed.updatedAt)
                #expect((feed.nextCheckAt ?? -1) >= before)
                #expect((feed.nextCheckAt ?? -1) <= after)
            }
        }
    }

    @Test func duplicateURLForTheSameUserIsRejected() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let (user, category, _) = try await seedFeed(connection)
                let feeds = FeedRepository(connection)

                do {
                    _ = try await feeds.create(
                        userID: user.id!,
                        categoryID: category.id!,
                        url: "https://example.com/feed.xml"
                    )
                    Issue.record("expected the duplicate (user, url) pair to be rejected")
                } catch {
                    // UNIQUE(user_id, url) violation; driver error type is not promised.
                }
                #expect(try await feeds.list(userID: user.id!).count == 1)
            }
        }
    }

    @Test func fetchByIDAndByURLFindTheStoredFeed() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let feeds = FeedRepository(connection)
                let feed = try await seedFeed(connection).2

                #expect(try await feeds.fetch(id: feed.id!)?.url == "https://example.com/feed.xml")
                #expect(try await feeds.fetch(userID: feed.userID, url: feed.url)?.id == feed.id)
                #expect(try await feeds.fetch(id: 999) == nil)
                #expect(try await feeds.fetch(userID: feed.userID, url: "https://unknown.example/x") == nil)
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
                let aliceCategory = try await categories.create(userID: alice.id!, title: "A")
                let bobCategory = try await categories.create(userID: bob.id!, title: "B")
                _ = try await feeds.create(
                    userID: alice.id!,
                    categoryID: aliceCategory.id!,
                    url: "https://alice.example/feed.xml"
                )
                _ = try await feeds.create(
                    userID: bob.id!,
                    categoryID: bobCategory.id!,
                    url: "https://bob.example/feed.xml"
                )

                let aliceFeeds = try await feeds.list(userID: alice.id!)
                #expect(aliceFeeds.map(\.url) == ["https://alice.example/feed.xml"])
            }
        }
    }

    @Test func recordFetchStoresStateAndResetsTheParsingErrors() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let feeds = FeedRepository(connection)
                let feed = try await seedFeed(connection).2
                _ = try await feeds.recordParsingError(feedID: feed.id!, message: "boom one")
                _ = try await feeds.recordParsingError(feedID: feed.id!, message: "boom two")
                let nextCheckAt = nowInSeconds() + 600
                _ = try await feeds.recordFetch(
                    feedID: feed.id!,
                    etag: "etag-1",
                    lastModified: "Fri, 01 Jan 2026 00:00:00 GMT",
                    nextCheckAt: nextCheckAt
                )

                let refreshed = try await feeds.fetch(id: feed.id!)
                #expect(refreshed?.etag == "etag-1")
                #expect(refreshed?.lastModified == "Fri, 01 Jan 2026 00:00:00 GMT")
                #expect(refreshed?.nextCheckAt == nextCheckAt)
                #expect(refreshed?.fetchedAt != nil)
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
                _ = try await feeds.recordParsingError(feedID: feed.id!, message: "boom one")
                _ = try await feeds.recordParsingError(feedID: feed.id!, message: "boom two")

                let refreshed = try await feeds.fetch(id: feed.id!)
                #expect(refreshed?.parsingErrorCount == 2)
                #expect(refreshed?.parsingErrorMessage == "boom two")
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
                    _ = try await feeds.recordParsingError(feedID: 999, message: "boom")
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

                try await feeds.delete(id: feed.id!)

                #expect(try await feeds.fetch(id: feed.id!) == nil)
            }
        }
    }
}

/// Unix seconds, for the "before and after" timestamp assertions.
private func nowInSeconds() -> Int {
    Int(Date.now.timeIntervalSince1970)
}
