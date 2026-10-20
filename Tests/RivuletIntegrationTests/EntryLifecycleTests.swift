import Foundation
import Fluent
import FluentSQLiteDriver
import Testing
@testable import RivuletCore

/// Entry user state (status, starred, read-all) and the retention deletion path.
@Suite struct EntryLifecycleTests {
    @Test func statusAndStarredUpdatesAreScopedToTheEntryOwner() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withTransaction { connection in
                let (aliceID, _, aliceFeedID) = try await seedFeed(connection, username: "alice")
                let (bobID, _, bobFeedID) = try await seedFeed(
                    connection,
                    username: "bob",
                    feedURL: "https://bob.example/feed.xml"
                )
                let entries = EntryRepository(connection)
                let aliceEntryID = try #require(
                    try await Self.seedEntries(connection, userID: aliceID, feedID: aliceFeedID, hashes: ["a"]).first
                )
                let bobEntryID = try #require(
                    try await Self.seedEntries(connection, userID: bobID, feedID: bobFeedID, hashes: ["b"]).first
                )
                try await backdateUpdatedAt(connection, id: aliceEntryID, updatedAt: 1)
                try await backdateUpdatedAt(connection, id: bobEntryID, updatedAt: 1)

                // Alice may only change her own entries, even when Bob's id is passed in.
                try await entries.setStatus(userID: aliceID, entryIDs: [aliceEntryID, bobEntryID], status: .read)

                var aliceEntry = try #require(try await entries.fetch(id: aliceEntryID))
                var bobEntry = try #require(try await entries.fetch(id: bobEntryID))
                #expect(aliceEntry.status == .read)
                #expect(aliceEntry.updatedAt > 1)
                #expect(bobEntry.status == .unread)
                #expect(bobEntry.updatedAt == 1)

                // Starring stamps the row as well and stays scoped to the owner.
                try await backdateUpdatedAt(connection, id: aliceEntryID, updatedAt: 1)
                try await entries.setStarred(userID: aliceID, entryIDs: [aliceEntryID, bobEntryID], starred: true)

                aliceEntry = try #require(try await entries.fetch(id: aliceEntryID))
                bobEntry = try #require(try await entries.fetch(id: bobEntryID))
                #expect(aliceEntry.starred)
                #expect(aliceEntry.updatedAt > 1)
                #expect(bobEntry.starred == false)
                #expect(bobEntry.updatedAt == 1)

                // An empty id list is a no-op instead of a syntax error.
                try await entries.setStatus(userID: aliceID, entryIDs: [], status: .unread)
                try await entries.setStarred(userID: aliceID, entryIDs: [], starred: false)
            }
        }
    }

    @Test func toggleStarredFlipsTheFlagAndReportsUnknownEntries() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withTransaction { connection in
                let (userID, _, feedID) = try await seedFeed(connection)
                let entries = EntryRepository(connection)
                let id = try #require(
                    try await Self.seedEntries(connection, userID: userID, feedID: feedID, hashes: ["h1"]).first
                )

                #expect(try await entries.toggleStarred(userID: userID, entryID: id))
                #expect(try await entries.fetch(id: id)?.starred == true)
                #expect(try await entries.toggleStarred(userID: userID, entryID: id) == false)
                #expect(try await entries.fetch(id: id)?.starred == false)

                do {
                    _ = try await entries.toggleStarred(userID: userID, entryID: 999)
                    Issue.record("expected a missing entry to be reported")
                } catch let error as StorageError {
                    #expect(error == .entryNotFound(id: 999))
                }

                // Another user's entry is reported as missing and left untouched.
                let (otherUserID, _, otherFeedID) = try await seedFeed(
                    connection,
                    username: "bob",
                    feedURL: "https://bob.example/feed.xml"
                )
                let otherEntryID = try #require(
                    try await Self.seedEntries(
                        connection, userID: otherUserID, feedID: otherFeedID, hashes: ["b"]
                    ).first
                )
                do {
                    _ = try await entries.toggleStarred(userID: userID, entryID: otherEntryID)
                    Issue.record("expected another user's entry to be reported as missing")
                } catch let error as StorageError {
                    #expect(error == .entryNotFound(id: otherEntryID))
                }
                #expect(try await entries.fetch(id: otherEntryID)?.starred == false)
            }
        }
    }

    @Test func markAllAsReadCoversUnreadEntriesOfTheUser() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withTransaction { connection in
                let (aliceID, _, aliceFeedID) = try await seedFeed(connection, username: "alice")
                let (bobID, _, bobFeedID) = try await seedFeed(
                    connection,
                    username: "bob",
                    feedURL: "https://bob.example/feed.xml"
                )
                let entries = EntryRepository(connection)
                let oldID = try #require(
                    try await Self.seedEntries(
                        connection, userID: aliceID, feedID: aliceFeedID, hashes: ["old"], publishedAt: 1_000
                    ).first
                )
                let newID = try #require(
                    try await Self.seedEntries(
                        connection, userID: aliceID, feedID: aliceFeedID, hashes: ["new"], publishedAt: 3_000
                    ).first
                )
                let alreadyReadID = try #require(
                    try await Self.seedEntries(
                        connection, userID: aliceID, feedID: aliceFeedID, hashes: ["read"], publishedAt: 2_000
                    ).first
                )
                // `before` is exclusive: an entry published exactly at the boundary stays unread.
                let boundaryID = try #require(
                    try await Self.seedEntries(
                        connection, userID: aliceID, feedID: aliceFeedID, hashes: ["boundary"], publishedAt: 2_000
                    ).first
                )
                let bobEntryID = try #require(
                    try await Self.seedEntries(connection, userID: bobID, feedID: bobFeedID, hashes: ["b"]).first
                )
                try await entries.setStatus(userID: aliceID, entryIDs: [alreadyReadID], status: .read)

                try await entries.markAllAsRead(userID: aliceID, before: 2_000)
                #expect(try await entries.fetch(id: oldID)?.status == .read)
                #expect(try await entries.fetch(id: newID)?.status == .unread)
                #expect(try await entries.fetch(id: boundaryID)?.status == .unread)
                #expect(try await entries.fetch(id: bobEntryID)?.status == .unread)

                try await entries.markAllAsRead(userID: aliceID)
                #expect(try await entries.fetch(id: newID)?.status == .read)
                #expect(try await entries.fetch(id: bobEntryID)?.status == .unread)
            }
        }
    }

    @Test func archiveDeletesOldUnstarredEntriesAndWritesTombstones() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withTransaction { connection in
                let (userID, _, feedID) = try await seedFeed(connection)
                let entries = EntryRepository(connection)
                let oldReadID = try #require(
                    try await Self.seedEntries(connection, userID: userID, feedID: feedID, hashes: ["old-read"]).first
                )
                let oldReadStarredID = try #require(
                    try await Self.seedEntries(connection, userID: userID, feedID: feedID, hashes: ["old-starred"]).first
                )
                let oldUnreadID = try #require(
                    try await Self.seedEntries(connection, userID: userID, feedID: feedID, hashes: ["old-unread"]).first
                )
                let newReadID = try #require(
                    try await Self.seedEntries(connection, userID: userID, feedID: feedID, hashes: ["new-read"]).first
                )
                // The cutoff is exclusive: an entry created exactly at it is kept.
                let boundaryReadID = try #require(
                    try await Self.seedEntries(connection, userID: userID, feedID: feedID, hashes: ["boundary"]).first
                )
                try await entries.setStatus(
                    userID: userID,
                    entryIDs: [oldReadID, oldReadStarredID, newReadID, boundaryReadID],
                    status: .read
                )
                try await entries.setStarred(userID: userID, entryIDs: [oldReadStarredID], starred: true)

                let cutoff = nowInSeconds() - 60 * 24 * 3600
                for id in [oldReadID, oldReadStarredID, oldUnreadID] {
                    try await backdateCreatedAt(connection, id: id, createdAt: cutoff - 1)
                }
                try await backdateCreatedAt(connection, id: boundaryReadID, createdAt: cutoff)

                let deleted = try await entries.archive(status: .read, createdBefore: cutoff, limit: 100)

                #expect(deleted == 1)
                #expect(try await entries.fetch(id: oldReadID) == nil)
                #expect(try await entries.fetch(id: oldReadStarredID) != nil)
                #expect(try await entries.fetch(id: oldUnreadID) != nil)
                #expect(try await entries.fetch(id: newReadID) != nil)
                #expect(try await entries.fetch(id: boundaryReadID) != nil)
                #expect(try await tombstoneCount(connection) == 1)

                let outcome = try await entries.upsert(
                    userID: userID,
                    feedID: feedID,
                    input: entryInput(hash: "old-read"),
                    updateExisting: true
                )
                guard case .tombstoned = outcome else {
                    Issue.record("expected the archived entry to stay deleted, got \(outcome)")
                    return
                }
            }
        }
    }

    @Test func archiveRespectsTheLimitAndIgnoresANonPositiveLimit() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withTransaction { connection in
                let (userID, _, feedID) = try await seedFeed(connection)
                let entries = EntryRepository(connection)
                let oldestID = try #require(
                    try await Self.seedEntries(connection, userID: userID, feedID: feedID, hashes: ["oldest"]).first
                )
                let middleID = try #require(
                    try await Self.seedEntries(connection, userID: userID, feedID: feedID, hashes: ["middle"]).first
                )
                let newestID = try #require(
                    try await Self.seedEntries(connection, userID: userID, feedID: feedID, hashes: ["newest"]).first
                )
                try await entries.setStatus(
                    userID: userID,
                    entryIDs: [oldestID, middleID, newestID],
                    status: .read
                )
                let now = nowInSeconds()
                try await backdateCreatedAt(connection, id: oldestID, createdAt: now - 3 * 3600)
                try await backdateCreatedAt(connection, id: middleID, createdAt: now - 2 * 3600)
                try await backdateCreatedAt(connection, id: newestID, createdAt: now - 3600)

                #expect(try await entries.archive(status: .read, createdBefore: now, limit: 0) == 0)
                #expect(try await entries.archive(status: .read, createdBefore: now, limit: 1) == 1)
                #expect(try await entries.fetch(id: oldestID) == nil)
                #expect(try await entries.fetch(id: middleID) != nil)
                #expect(try await entries.fetch(id: newestID) != nil)

                #expect(try await entries.archive(status: .read, createdBefore: now, limit: 10) == 2)
                #expect(try await entryCount(connection) == 0)
                #expect(try await tombstoneCount(connection) == 3)
            }
        }
    }

    @Test func archiveSkipsTombstonesForEmptyHashes() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withTransaction { connection in
                let (userID, _, feedID) = try await seedFeed(connection)
                let entries = EntryRepository(connection)
                _ = try await Self.seedEntries(connection, userID: userID, feedID: feedID, hashes: [""])

                #expect(try await entries.archive(status: .unread, createdBefore: nowInSeconds() + 1, limit: 10) == 1)
                #expect(try await entryCount(connection) == 0)
                #expect(try await tombstoneCount(connection) == 0)
            }
        }
    }

    // MARK: - Helpers

    /// Creates one entry per hash and returns their ids.
    private static func seedEntries(
        _ connection: any Database,
        userID: Int,
        feedID: Int,
        hashes: [String],
        publishedAt: Int = 1_700_000_000
    ) async throws -> [Int] {
        var ids: [Int] = []
        let entries = EntryRepository(connection)
        for hash in hashes {
            let outcome = try await entries.upsert(
                userID: userID,
                feedID: feedID,
                input: entryInput(hash: hash, title: hash, publishedAt: publishedAt),
                updateExisting: true
            )
            guard case .created(let entry) = outcome else {
                Issue.record("could not create entry \(hash): \(outcome)")
                continue
            }
            ids.append(try #require(entry.id))
        }
        return ids
    }
}
