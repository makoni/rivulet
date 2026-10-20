import Foundation
import Testing
@testable import RivuletCore

/// Bulk user-state updates scoped to a feed or a category.
///
/// Mirrors `MarkFeedAsRead` and `MarkCategoryAsRead` in the reference: only the
/// caller's unread entries published strictly before the cutoff are marked,
/// and every marked row is stamped with a new `updated_at`.
@Suite struct EntryScopedMarkAsReadTests {
    @Test func markingAFeedAsReadMarksOnlyItsUnreadEntriesBeforeTheCutoff() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let userID = try await seedUser(connection)
                let category = try await seedCategory(connection, userID: userID, title: "Tech")
                let feed = try await seedFeed(
                    connection, userID: userID, categoryID: category, url: "https://example.com/feed.xml"
                )
                let otherFeed = try await seedFeed(
                    connection, userID: userID, categoryID: category, url: "https://example.com/other.xml"
                )
                let otherUserID = try await seedUser(connection, username: "bob")
                let otherCategory = try await seedCategory(connection, userID: otherUserID, title: "Tech")
                let otherUserFeed = try await seedFeed(
                    connection,
                    userID: otherUserID,
                    categoryID: otherCategory,
                    url: "https://example.com/bob.xml"
                )
                let before = try await seedEntry(
                    connection, userID: userID, feedID: feed, hash: "before", publishedAt: 100
                )
                let atCutoff = try await seedEntry(
                    connection, userID: userID, feedID: feed, hash: "cutoff", publishedAt: 200
                )
                let after = try await seedEntry(
                    connection, userID: userID, feedID: feed, hash: "after", publishedAt: 300
                )
                let alreadyRead = try await seedEntry(
                    connection,
                    userID: userID,
                    feedID: feed,
                    hash: "read",
                    publishedAt: 100,
                    status: .read
                )
                let starred = try await seedEntry(
                    connection,
                    userID: userID,
                    feedID: feed,
                    hash: "starred",
                    publishedAt: 100,
                    starred: true
                )
                let otherFeedEntry = try await seedEntry(
                    connection, userID: userID, feedID: otherFeed, hash: "other-feed", publishedAt: 100
                )
                let otherUserEntry = try await seedEntry(
                    connection, userID: otherUserID, feedID: otherUserFeed, hash: "other-user", publishedAt: 100
                )
                for id in [before, atCutoff, after, alreadyRead, starred, otherFeedEntry, otherUserEntry] {
                    try await backdateUpdatedAt(connection, id: id, updatedAt: 1_000)
                }
                let entries = EntryRepository(connection)

                try await entries.markFeedAsRead(userID: userID, feedID: feed, before: 200)

                let marked = try #require(try await entries.fetch(id: before))
                #expect(marked.status == .read)
                #expect(marked.updatedAt > 1_000)
                let justAtCutoff = try #require(try await entries.fetch(id: atCutoff))
                #expect(justAtCutoff.status == .unread)
                #expect(justAtCutoff.updatedAt == 1_000)
                let justAfter = try #require(try await entries.fetch(id: after))
                #expect(justAfter.status == .unread)
                #expect(justAfter.updatedAt == 1_000)
                let readEntry = try #require(try await entries.fetch(id: alreadyRead))
                #expect(readEntry.status == .read)
                #expect(readEntry.updatedAt == 1_000)
                // Starred unread entries are marked like any other; the flag stays.
                let starredEntry = try #require(try await entries.fetch(id: starred))
                #expect(starredEntry.status == .read)
                #expect(starredEntry.starred)
                #expect(starredEntry.updatedAt > 1_000)
                let untouchedFeed = try #require(try await entries.fetch(id: otherFeedEntry))
                #expect(untouchedFeed.status == .unread)
                #expect(untouchedFeed.updatedAt == 1_000)
                let untouchedUser = try #require(try await entries.fetch(id: otherUserEntry))
                #expect(untouchedUser.status == .unread)
                #expect(untouchedUser.updatedAt == 1_000)
            }
        }
    }

    @Test func markingACategoryAsReadMarksOnlyItsFeedsForTheOwner() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let userID = try await seedUser(connection)
                let tech = try await seedCategory(connection, userID: userID, title: "Tech")
                let news = try await seedCategory(connection, userID: userID, title: "News")
                let firstFeed = try await seedFeed(
                    connection, userID: userID, categoryID: tech, url: "https://example.com/1.xml"
                )
                let secondFeed = try await seedFeed(
                    connection, userID: userID, categoryID: tech, url: "https://example.com/2.xml"
                )
                let newsFeed = try await seedFeed(
                    connection, userID: userID, categoryID: news, url: "https://example.com/news.xml"
                )
                let otherUserID = try await seedUser(connection, username: "bob")
                let otherCategory = try await seedCategory(connection, userID: otherUserID, title: "Tech")
                let otherFeed = try await seedFeed(
                    connection,
                    userID: otherUserID,
                    categoryID: otherCategory,
                    url: "https://example.com/other.xml"
                )
                let first = try await seedEntry(
                    connection, userID: userID, feedID: firstFeed, hash: "first", publishedAt: 100
                )
                let second = try await seedEntry(
                    connection, userID: userID, feedID: secondFeed, hash: "second", publishedAt: 150
                )
                let atCutoff = try await seedEntry(
                    connection, userID: userID, feedID: firstFeed, hash: "cutoff", publishedAt: 200
                )
                let newsEntry = try await seedEntry(
                    connection, userID: userID, feedID: newsFeed, hash: "news", publishedAt: 100
                )
                let otherEntry = try await seedEntry(
                    connection, userID: otherUserID, feedID: otherFeed, hash: "other", publishedAt: 100
                )
                for id in [first, second, atCutoff, newsEntry, otherEntry] {
                    try await backdateUpdatedAt(connection, id: id, updatedAt: 1_000)
                }
                let entries = EntryRepository(connection)

                try await entries.markCategoryAsRead(userID: userID, categoryID: tech, before: 200)

                let markedFirst = try #require(try await entries.fetch(id: first))
                #expect(markedFirst.status == .read)
                #expect(markedFirst.updatedAt > 1_000)
                let markedSecond = try #require(try await entries.fetch(id: second))
                #expect(markedSecond.status == .read)
                #expect(markedSecond.updatedAt > 1_000)
                let justAtCutoff = try #require(try await entries.fetch(id: atCutoff))
                #expect(justAtCutoff.status == .unread)
                #expect(justAtCutoff.updatedAt == 1_000)
                let otherCategoryEntry = try #require(try await entries.fetch(id: newsEntry))
                #expect(otherCategoryEntry.status == .unread)
                #expect(otherCategoryEntry.updatedAt == 1_000)
                let otherUserEntry = try #require(try await entries.fetch(id: otherEntry))
                #expect(otherUserEntry.status == .unread)
                #expect(otherUserEntry.updatedAt == 1_000)
            }
        }
    }
}
