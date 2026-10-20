import Foundation
import Fluent
import FluentSQLiteDriver
import Testing
@testable import RivuletCore

/// The entry write path: insert, refresh, enclosures and tombstone refusal.
@Suite struct EntryRepositoryTests {
    @Test func upsertInsertsANewEntryWithTheUpstreamDefaults() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withTransaction { connection in
                let (userID, _, feedID) = try await seedFeed(connection)
                let entries = EntryRepository(connection)
                let before = nowInSeconds()

                let outcome = try await entries.upsert(
                    userID: userID,
                    feedID: feedID,
                    input: entryInput(),
                    updateExisting: true
                )

                guard case .created(let created) = outcome else {
                    Issue.record("expected a new entry, got \(outcome)")
                    return
                }
                let id = try #require(created.id)
                // The returned value feeds the ingestion pipeline; it must match the row.
                #expect(created.contentText == "Hello world")
                #expect(created.status == .unread)
                #expect(created.starred == false)
                #expect(created.createdAt == created.updatedAt)
                // The value behaves like a fetched model, so callers may persist it.
                #expect(created._$idExists)
                let stored = try #require(try await entries.fetch(id: id))
                #expect(created.createdAt == stored.createdAt)
                #expect(stored.userID == userID)
                #expect(stored.feedID == feedID)
                #expect(stored.hash == "h1")
                #expect(stored.title == "Title")
                #expect(stored.url == "https://example.com/1")
                #expect(stored.author == "Author")
                #expect(stored.content == "<p>Hello <b>world</b></p>")
                #expect(stored.contentText == "Hello world")
                #expect(stored.status == .unread)
                #expect(stored.starred == false)
                #expect(stored.publishedAt == 1_700_000_000)
                #expect(stored.createdAt >= before)
                #expect(stored.updatedAt == stored.createdAt)
                #expect(try await entries.fetchEnclosures(entryID: id).isEmpty)
            }
        }
    }

    @Test func aRefreshUpdatesTheFeedFieldsAndPreservesTheUserState() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withTransaction { connection in
                let (userID, _, feedID) = try await seedFeed(connection)
                let entries = EntryRepository(connection)
                guard case .created(let created) = try await entries.upsert(
                    userID: userID,
                    feedID: feedID,
                    input: entryInput(),
                    updateExisting: true
                ) else {
                    Issue.record("expected a new entry")
                    return
                }
                let id = try #require(created.id)
                try await entries.setStatus(userID: userID, entryIDs: [id], status: .read)
                try await entries.setStarred(userID: userID, entryIDs: [id], starred: true)
                let withUserState = try #require(try await entries.fetch(id: id))
                // A refresh must not restamp the row: only user-state changes do.
                try await backdateUpdatedAt(connection, id: id, updatedAt: 1_500_000_000)

                let outcome = try await entries.upsert(
                    userID: userID,
                    feedID: feedID,
                    input: entryInput(
                        title: "New title",
                        url: "https://example.com/2",
                        author: "New author",
                        content: "<p>Replaced</p>",
                        publishedAt: 1_600_000_000
                    ),
                    updateExisting: true
                )

                guard case .updated = outcome else {
                    Issue.record("expected the stored entry to be updated, got \(outcome)")
                    return
                }
                let stored = try #require(try await entries.fetch(id: id))
                #expect(stored.title == "New title")
                #expect(stored.url == "https://example.com/2")
                #expect(stored.author == "New author")
                #expect(stored.content == "<p>Replaced</p>")
                #expect(stored.contentText == "Replaced")
                #expect(stored.status == .read)
                #expect(stored.starred)
                #expect(stored.publishedAt == 1_700_000_000)
                #expect(stored.createdAt == withUserState.createdAt)
                #expect(stored.updatedAt == 1_500_000_000)
                #expect(try await entryCount(connection) == 1)
            }
        }
    }

    @Test func anEntryWithTheSameHashInAnotherFeedIsADifferentEntry() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withTransaction { connection in
                let (userID, categoryID, firstFeedID) = try await seedFeed(connection)
                let secondFeed = try await FeedRepository(connection).create(
                    userID: userID,
                    categoryID: categoryID,
                    url: "https://example.com/other.xml"
                )
                let secondFeedID = try #require(secondFeed.id)
                let entries = EntryRepository(connection)

                for feedID in [firstFeedID, secondFeedID] {
                    let outcome = try await entries.upsert(
                        userID: userID,
                        feedID: feedID,
                        input: entryInput(),
                        updateExisting: true
                    )
                    guard case .created = outcome else {
                        Issue.record("expected a new entry in feed #\(feedID), got \(outcome)")
                        return
                    }
                }
                #expect(try await entryCount(connection) == 2)
            }
        }
    }

    @Test func upsertWithoutUpdateExistingLeavesTheStoredEntryUntouched() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withTransaction { connection in
                let (userID, _, feedID) = try await seedFeed(connection)
                let entries = EntryRepository(connection)
                guard case .created(let created) = try await entries.upsert(
                    userID: userID,
                    feedID: feedID,
                    input: entryInput(title: "Original"),
                    updateExisting: true
                ) else {
                    Issue.record("expected a new entry")
                    return
                }
                let id = try #require(created.id)

                let outcome = try await entries.upsert(
                    userID: userID,
                    feedID: feedID,
                    input: entryInput(title: "Ignored", content: "<p>Ignored</p>"),
                    updateExisting: false
                )
                guard case .existing = outcome else {
                    Issue.record("expected the stored entry to be reused, got \(outcome)")
                    return
                }
                let stored = try #require(try await entries.fetch(id: id))
                #expect(stored.title == "Original")
                #expect(stored.contentText == "Hello world")
                #expect(try await entryCount(connection) == 1)
            }
        }
    }

    @Test func aTombstonedEntryIsNeverReinserted() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withTransaction { connection in
                let (userID, _, feedID) = try await seedFeed(connection)
                let entries = EntryRepository(connection)
                guard case .created(let created) = try await entries.upsert(
                    userID: userID,
                    feedID: feedID,
                    input: entryInput(),
                    updateExisting: true
                ) else {
                    Issue.record("expected a new entry")
                    return
                }
                let id = try #require(created.id)
                let stored = try #require(try await entries.fetch(id: id))
                try await entries.setStatus(userID: userID, entryIDs: [id], status: .read)

                let deleted = try await entries.archive(
                    status: .read,
                    createdBefore: stored.createdAt + 1,
                    limit: 10
                )
                #expect(deleted == 1)
                #expect(try await entries.fetch(id: id) == nil)
                #expect(try await entryCount(connection) == 0)
                #expect(try await tombstoneCount(connection) == 1)

                let outcome = try await entries.upsert(
                    userID: userID,
                    feedID: feedID,
                    input: entryInput(title: "Resurrected"),
                    updateExisting: true
                )
                guard case .tombstoned = outcome else {
                    Issue.record("expected the tombstoned entry to be refused, got \(outcome)")
                    return
                }
                #expect(try await entryCount(connection) == 0)
                #expect(try await entries.isNewEntry(feedID: feedID, hash: "h1") == false)
            }
        }
    }

    @Test func isNewEntryTracksStoredAndTombstonedHashes() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withTransaction { connection in
                let (userID, _, feedID) = try await seedFeed(connection)
                let entries = EntryRepository(connection)
                #expect(try await entries.isNewEntry(feedID: feedID, hash: "h1"))
                #expect(try await entries.isNewEntry(feedID: feedID, hash: "unknown"))

                guard case .created(let created) = try await entries.upsert(
                    userID: userID,
                    feedID: feedID,
                    input: entryInput(),
                    updateExisting: true
                ) else {
                    Issue.record("expected a new entry")
                    return
                }
                let id = try #require(created.id)
                #expect(try await entries.isNewEntry(feedID: feedID, hash: "h1") == false)

                let stored = try #require(try await entries.fetch(id: id))
                try await entries.setStatus(userID: userID, entryIDs: [id], status: .read)
                _ = try await entries.archive(status: .read, createdBefore: stored.createdAt + 1, limit: 10)

                // Tombstoned entries stay known, so a refresh cannot resurrect them.
                #expect(try await entries.isNewEntry(feedID: feedID, hash: "h1") == false)

                // Identity is per feed: the same hash is new in another feed.
                let (_, _, otherFeedID) = try await seedFeed(
                    connection,
                    username: "bob",
                    feedURL: "https://bob.example/feed.xml"
                )
                #expect(try await entries.isNewEntry(feedID: otherFeedID, hash: "h1"))
            }
        }
    }

    @Test func enclosuresAreTrimmedDeduplicatedAndReplacedOnRefresh() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withTransaction { connection in
                let (userID, _, feedID) = try await seedFeed(connection)
                let entries = EntryRepository(connection)
                let input = entryInput(enclosures: [
                    .init(url: " https://cdn.example/a.mp3 ", mimeType: "audio/mpeg", size: 10),
                    .init(url: "https://cdn.example/a.mp3", mimeType: "audio/mpeg", size: 10),
                    .init(url: "   ", mimeType: "", size: 0),
                    .init(url: "https://cdn.example/b.jpg", mimeType: "image/jpeg", size: 20),
                ])

                guard case .created(let created) = try await entries.upsert(
                    userID: userID,
                    feedID: feedID,
                    input: input,
                    updateExisting: true
                ) else {
                    Issue.record("expected a new entry")
                    return
                }
                let id = try #require(created.id)

                let stored = try await entries.fetchEnclosures(entryID: id)
                #expect(stored.map(\.url) == ["https://cdn.example/a.mp3", "https://cdn.example/b.jpg"])
                #expect(stored.map(\.mimeType) == ["audio/mpeg", "image/jpeg"])
                #expect(stored.map(\.size) == [10, 20])
                let storedAID = try #require(stored.first?.id)

                // A URL that is still declared keeps its row and stored metadata; new URLs
                // are inserted and disappeared ones are deleted (upstream `updateEnclosures`).
                _ = try await entries.upsert(
                    userID: userID,
                    feedID: feedID,
                    input: entryInput(enclosures: [
                        .init(url: "https://cdn.example/a.mp3", mimeType: "audio/ogg", size: 99),
                        .init(url: "https://cdn.example/c.mp3", mimeType: "audio/mpeg", size: 30),
                    ]),
                    updateExisting: true
                )
                let refreshed = try await entries.fetchEnclosures(entryID: id)
                #expect(refreshed.map(\.url) == ["https://cdn.example/a.mp3", "https://cdn.example/c.mp3"])
                #expect(refreshed.map(\.mimeType) == ["audio/mpeg", "audio/mpeg"])
                #expect(refreshed.map(\.size) == [10, 30])
                #expect(refreshed.first?.id == storedAID)

                // A refreshed entry without enclosures must not keep stale rows.
                _ = try await entries.upsert(
                    userID: userID,
                    feedID: feedID,
                    input: entryInput(),
                    updateExisting: true
                )
                #expect(try await entries.fetchEnclosures(entryID: id).isEmpty)
            }
        }
    }

    @Test func theSearchIndexFollowsRepositoryWrites() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withTransaction { connection in
                let (userID, _, feedID) = try await seedFeed(connection)
                let entries = EntryRepository(connection)

                guard case .created(let created) = try await entries.upsert(
                    userID: userID,
                    feedID: feedID,
                    input: entryInput(content: "<p>Swift concurrency</p>"),
                    updateExisting: true
                ) else {
                    Issue.record("expected a new entry")
                    return
                }
                let id = try #require(created.id)
                // content_text is written by the repository and indexed by the triggers.
                #expect(try await searchCount(connection, term: "concurrency") == 1)
                #expect(try await searchCount(connection, term: "swift") == 1)

                _ = try await entries.upsert(
                    userID: userID,
                    feedID: feedID,
                    input: entryInput(content: "<p>Kotlin coroutines</p>"),
                    updateExisting: true
                )
                #expect(try await searchCount(connection, term: "concurrency") == 0)
                #expect(try await searchCount(connection, term: "coroutines") == 1)

                // The delete trigger keeps the index in sync with the retention path.
                let stored = try #require(try await entries.fetch(id: id))
                try await entries.setStatus(userID: userID, entryIDs: [id], status: .read)
                _ = try await entries.archive(
                    status: .read,
                    createdBefore: stored.createdAt + 1,
                    limit: 10
                )
                #expect(try await searchCount(connection, term: "coroutines") == 0)
            }
        }
    }
}
