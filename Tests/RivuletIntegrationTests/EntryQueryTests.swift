import Foundation
import Testing
@testable import RivuletCore

/// Entry listings: filters, pagination, counts and enclosures.
///
/// The reference builds listings with `EntryQueryBuilder`
/// (`internal/storage/entry_query_builder.go`); these tests pin the behaviours
/// the client APIs rely on: scoping, strict cursors and deterministic
/// pagination. Full-text search has its own suite (``EntrySearchTests``).
@Suite struct EntryQueryTests {
    @Test func aListingIsScopedToTheOwner() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let alice = try await seedFeed(connection, username: "alice")
                let bob = try await seedFeed(connection, username: "bob")
                let aliceEntry = try await seedEntry(
                    connection, userID: alice.userID, feedID: alice.feedID, hash: "alice"
                )
                let bobEntry = try await seedEntry(
                    connection, userID: bob.userID, feedID: bob.feedID, hash: "bob"
                )
                let entries = EntryRepository(connection)

                #expect(try await entries.listIDs(EntryQuery(userID: alice.userID)) == [aliceEntry])
                #expect(try await entries.list(EntryQuery(userID: alice.userID)).compactMap(\.id) == [aliceEntry])
                #expect(try await entries.count(EntryQuery(userID: alice.userID)) == 1)
                #expect(try await entries.listIDs(EntryQuery(userID: bob.userID)) == [bobEntry])
                #expect(
                    try await entries.listIDs(EntryQuery(userID: alice.userID, entryIDs: [bobEntry])).isEmpty
                )
            }
        }
    }

    @Test func aListingReturnsTheStoredFields() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                let id = try await seedEntry(
                    connection,
                    userID: feed.userID,
                    feedID: feed.feedID,
                    hash: "h1",
                    title: "Stored title",
                    url: "https://example.com/stored",
                    author: "Stored author",
                    content: "<p>Stored <b>content</b></p>",
                    publishedAt: 1_600_000_000,
                    status: .read,
                    starred: true
                )
                let entries = EntryRepository(connection)

                let listed = try #require(try await entries.list(EntryQuery(userID: feed.userID)).first)
                #expect(listed.id == id)
                #expect(listed.userID == feed.userID)
                #expect(listed.feedID == feed.feedID)
                #expect(listed.hash == "h1")
                #expect(listed.title == "Stored title")
                #expect(listed.url == "https://example.com/stored")
                #expect(listed.author == "Stored author")
                #expect(listed.content == "<p>Stored <b>content</b></p>")
                #expect(listed.contentText == "Stored content")
                #expect(listed.status == .read)
                #expect(listed.starred)
                #expect(listed.publishedAt == 1_600_000_000)
                #expect(listed.createdAt > 0)
                #expect(listed.updatedAt >= listed.createdAt)
                // The value behaves like a fetched model, so callers may persist it.
                #expect(listed._$idExists)
            }
        }
    }

    @Test func statusAndStarredFiltersSelectTheMatchingEntries() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                let unread = try await seedEntry(
                    connection, userID: feed.userID, feedID: feed.feedID, hash: "unread", publishedAt: 100
                )
                let read = try await seedEntry(
                    connection,
                    userID: feed.userID,
                    feedID: feed.feedID,
                    hash: "read",
                    publishedAt: 200,
                    status: .read
                )
                let starred = try await seedEntry(
                    connection,
                    userID: feed.userID,
                    feedID: feed.feedID,
                    hash: "starred",
                    publishedAt: 300,
                    starred: true
                )
                let entries = EntryRepository(connection)

                #expect(
                    try await entries.listIDs(EntryQuery(userID: feed.userID, statuses: [.unread]))
                        == [unread, starred]
                )
                #expect(
                    try await entries.listIDs(EntryQuery(userID: feed.userID, statuses: [.read]))
                        == [read]
                )
                #expect(
                    try await entries.listIDs(EntryQuery(userID: feed.userID, statuses: [.read, .unread]))
                        == [unread, read, starred]
                )
                #expect(
                    try await entries.listIDs(EntryQuery(userID: feed.userID, starred: true))
                        == [starred]
                )
                #expect(
                    try await entries.listIDs(EntryQuery(userID: feed.userID, starred: false))
                        == [unread, read]
                )
                #expect(
                    try await entries.listIDs(EntryQuery(userID: feed.userID, starred: nil))
                        == [unread, read, starred]
                )
            }
        }
    }

    @Test func feedAndCategoryFiltersScopeTheListing() async throws {
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
                    connection, userID: userID, categoryID: news, url: "https://example.com/3.xml"
                )
                let otherUserID = try await seedUser(connection, username: "bob")
                let otherCategory = try await seedCategory(connection, userID: otherUserID, title: "Tech")
                let otherFeed = try await seedFeed(
                    connection, userID: otherUserID, categoryID: otherCategory, url: "https://example.com/other.xml"
                )
                let first = try await seedEntry(
                    connection, userID: userID, feedID: firstFeed, hash: "1", publishedAt: 100
                )
                let second = try await seedEntry(
                    connection, userID: userID, feedID: secondFeed, hash: "2", publishedAt: 200
                )
                let third = try await seedEntry(
                    connection, userID: userID, feedID: newsFeed, hash: "3", publishedAt: 300
                )
                let other = try await seedEntry(
                    connection, userID: otherUserID, feedID: otherFeed, hash: "4", publishedAt: 400
                )
                let entries = EntryRepository(connection)

                #expect(try await entries.listIDs(EntryQuery(userID: userID, feedID: secondFeed)) == [second])
                #expect(try await entries.listIDs(EntryQuery(userID: userID, categoryID: tech)) == [first, second])
                #expect(try await entries.listIDs(EntryQuery(userID: userID, categoryID: news)) == [third])
                // A category that belongs to another user selects nothing.
                #expect(
                    try await entries.listIDs(EntryQuery(userID: userID, categoryID: otherCategory)).isEmpty
                )
                // An entry of another user never leaks through a feed filter.
                #expect(try await entries.listIDs(EntryQuery(userID: userID, feedID: otherFeed)).isEmpty)
                // A set identifier is applied literally; zero selects nothing.
                #expect(try await entries.listIDs(EntryQuery(userID: userID, feedID: 0)).isEmpty)
                #expect(try await entries.listIDs(EntryQuery(userID: userID, categoryID: 0)).isEmpty)
                #expect(try await entries.listIDs(EntryQuery(userID: otherUserID, feedID: otherFeed)) == [other])
            }
        }
    }

    @Test func entryIDFiltersAndCursorsUseStrictBounds() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                let first = try await seedEntry(
                    connection, userID: feed.userID, feedID: feed.feedID, hash: "first", publishedAt: 100
                )
                let second = try await seedEntry(
                    connection, userID: feed.userID, feedID: feed.feedID, hash: "second", publishedAt: 200
                )
                let third = try await seedEntry(
                    connection, userID: feed.userID, feedID: feed.feedID, hash: "third", publishedAt: 300
                )
                let entries = EntryRepository(connection)

                #expect(
                    try await entries.listIDs(EntryQuery(userID: feed.userID, entryIDs: [third, first]))
                        == [first, third]
                )
                // An empty id selection means "any", as in the reference.
                #expect(
                    try await entries.listIDs(EntryQuery(userID: feed.userID, entryIDs: []))
                        == [first, second, third]
                )
                #expect(
                    try await entries.listIDs(EntryQuery(userID: feed.userID, publishedAfter: 100))
                        == [second, third]
                )
                #expect(
                    try await entries.listIDs(EntryQuery(userID: feed.userID, publishedBefore: 200))
                        == [first]
                )
                #expect(
                    try await entries.listIDs(
                        EntryQuery(userID: feed.userID, publishedAfter: 100, publishedBefore: 300)
                    ) == [second]
                )
                #expect(try await entries.listIDs(EntryQuery(userID: feed.userID, afterID: second)) == [third])
                #expect(try await entries.listIDs(EntryQuery(userID: feed.userID, beforeID: second)) == [first])
                #expect(
                    try await entries.listIDs(EntryQuery(userID: feed.userID, afterID: second, beforeID: third))
                        .isEmpty
                )
            }
        }
    }

    @Test func paginationFollowsTheRequestedOrderWithAnIDTiebreaker() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                let first = try await seedEntry(
                    connection, userID: feed.userID, feedID: feed.feedID, hash: "first", publishedAt: 100
                )
                let second = try await seedEntry(
                    connection, userID: feed.userID, feedID: feed.feedID, hash: "second", publishedAt: 200
                )
                let third = try await seedEntry(
                    connection, userID: feed.userID, feedID: feed.feedID, hash: "third", publishedAt: 200
                )
                let fourth = try await seedEntry(
                    connection, userID: feed.userID, feedID: feed.feedID, hash: "fourth", publishedAt: 300
                )
                let entries = EntryRepository(connection)
                let ascending = EntryQuery(userID: feed.userID)

                // Equal dates fall back to the id, so pages cannot overlap.
                #expect(try await entries.listIDs(ascending) == [first, second, third, fourth])
                let descending = EntryQuery(
                    userID: feed.userID,
                    sort: EntrySort(field: .publishedAt, direction: .descending)
                )
                #expect(try await entries.listIDs(descending) == [fourth, third, second, first])
                #expect(
                    try await entries.listIDs(
                        EntryQuery(userID: feed.userID, sort: EntrySort(field: .id, direction: .descending))
                    ) == [fourth, third, second, first]
                )

                var page = ascending
                page.limit = 2
                #expect(try await entries.listIDs(page) == [first, second])
                page.offset = 2
                #expect(try await entries.listIDs(page) == [third, fourth])
                // The model listing follows the same order as the ids.
                #expect(try await entries.list(page).compactMap(\.id) == [third, fourth])
                // An offset also works without an explicit limit.
                page.limit = nil
                page.offset = 1
                #expect(try await entries.listIDs(page) == [second, third, fourth])
            }
        }
    }

    @Test func countIgnoresPaginationAndCombinesFilters() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                for (index, hash) in ["one", "two", "three"].enumerated() {
                    try await seedEntry(
                        connection,
                        userID: feed.userID,
                        feedID: feed.feedID,
                        hash: hash,
                        publishedAt: 100 + index
                    )
                }
                let read = try await seedEntry(
                    connection,
                    userID: feed.userID,
                    feedID: feed.feedID,
                    hash: "read",
                    publishedAt: 200,
                    status: .read
                )
                let entries = EntryRepository(connection)

                #expect(
                    try await entries.count(
                        EntryQuery(userID: feed.userID, statuses: [.read])
                    ) == 1
                )
                #expect(
                    try await entries.count(
                        EntryQuery(userID: feed.userID, statuses: [.unread], limit: 1, offset: 2)
                    ) == 3
                )
                #expect(
                    try await entries.count(
                        EntryQuery(userID: feed.userID, entryIDs: [read])
                    ) == 1
                )
                // Filters combine: two unread entries after the boundary match the term.
                #expect(
                    try await entries.count(
                        EntryQuery(
                            userID: feed.userID,
                            statuses: [.unread],
                            publishedAfter: 100,
                            search: "hello"
                        )
                    ) == 2
                )
            }
        }
    }

    @Test func anOversizedOrZeroLimitIsClampedToTheMaximum() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                try await seedManyEntries(
                    connection, userID: feed.userID, feedID: feed.feedID, count: 1_001
                )
                let entries = EntryRepository(connection)

                #expect(EntryQuery.maximumLimit == 1_000)
                #expect(
                    try await entries.listIDs(EntryQuery(userID: feed.userID, limit: 5_000)).count
                        == EntryQuery.maximumLimit
                )
                #expect(
                    try await entries.listIDs(EntryQuery(userID: feed.userID, limit: 0)).count
                        == EntryQuery.maximumLimit
                )
                #expect(
                    try await entries.listIDs(EntryQuery(userID: feed.userID, limit: -1)).count
                        == EntryQuery.maximumLimit
                )
                // No limit at all is how the reference lists every id (Fever).
                #expect(try await entries.listIDs(EntryQuery(userID: feed.userID)).count == 1_001)
            }
        }
    }

    @Test func enclosuresCanBeFetchedForManyEntries() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                let first = try await seedEntry(
                    connection, userID: feed.userID, feedID: feed.feedID, hash: "first"
                )
                let second = try await seedEntry(
                    connection, userID: feed.userID, feedID: feed.feedID, hash: "second"
                )
                let entries = EntryRepository(connection)
                try await entries.upsert(
                    userID: feed.userID,
                    feedID: feed.feedID,
                    input: entryInput(
                        hash: "first",
                        enclosures: [
                            .init(url: "https://example.com/a.mp3", mimeType: "audio/mpeg", size: 10),
                            .init(url: "https://example.com/b.mp3", mimeType: "audio/mpeg", size: 20),
                        ]
                    ),
                    updateExisting: true
                )

                let byEntry = try await entries.fetchEnclosures(entryIDs: [first, second])
                #expect(byEntry[first]?.map(\.url) == ["https://example.com/a.mp3", "https://example.com/b.mp3"])
                #expect(byEntry[second] == nil)
                #expect(try await entries.fetchEnclosures(entryIDs: []).isEmpty)
            }
        }
    }
}
