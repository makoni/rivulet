import Foundation
import Testing
@testable import RivuletCore

/// Daily cleanup: archives old read and unread entries, keeping tombstones
/// (reference `internal/cli/cleanup_tasks.go` + `ArchiveEntries`).
@Suite struct RetentionTests {
    /// Fixed "now" for deterministic cutoffs; the fixtures backdate `created_at`
    /// relative to it.
    private let now = 1_750_000_000

    @Test func policyDefaultsMatchTheReference() {
        #expect(RetentionPolicy.default.readEntryAgeDays == 60)
        #expect(RetentionPolicy.default.unreadEntryAgeDays == 180)
        #expect(RetentionPolicy.default.batchSize == 10_000)
    }

    @Test func runArchivesOldReadEntriesAndWritesTombstones() async throws {
        try await withMigratedStorage { _, storage in
            let seed = try await storage.withConnection { connection -> (userID: Int, feedID: Int, old: Int, young: Int, oldUnread: Int) in
                let feed = try await seedFeed(connection)
                let old = try await seedEntry(
                    connection, userID: feed.userID, feedID: feed.feedID,
                    hash: "old-read", status: .read
                )
                let young = try await seedEntry(
                    connection, userID: feed.userID, feedID: feed.feedID,
                    hash: "young-read", status: .read
                )
                let oldUnread = try await seedEntry(
                    connection, userID: feed.userID, feedID: feed.feedID,
                    hash: "old-unread"
                )
                for (id, daysAgo) in [(old, 61), (young, 10), (oldUnread, 61)] {
                    try await backdateCreatedAt(connection, id: id, createdAt: now - daysAgo * 86_400)
                }
                return (feed.userID, feed.feedID, old, young, oldUnread)
            }

            let counts = try await Retention().run(on: storage, now: now)

            #expect(counts.read == 1)
            #expect(counts.unread == 0)
            try await storage.withConnection { connection in
                let entries = EntryRepository(connection)
                let archived = try await entries.fetch(id: seed.old)
                let young = try await entries.fetch(id: seed.young)
                let oldUnread = try await entries.fetch(id: seed.oldUnread)
                let tombstones = try await tombstoneCount(connection)
                #expect(archived == nil)
                #expect(young != nil)
                #expect(oldUnread != nil)
                #expect(tombstones == 1)
            }

            // A refresh cannot bring the archived entry back.
            let reimport = try await storage.withTransaction {
                try await EntryRepository($0).upsert(
                    userID: seed.userID,
                    feedID: seed.feedID,
                    input: entryInput(hash: "old-read"),
                    updateExisting: false
                )
            }
            guard case .tombstoned = reimport else {
                Issue.record("expected the archived hash to be refused as tombstoned")
                return
            }
        }
    }

    @Test func runArchivesUnreadEntriesOlderThanOneHundredEightyDays() async throws {
        try await withMigratedStorage { _, storage in
            let seed = try await storage.withConnection { connection -> (oldUnread: Int, midUnread: Int, oldRead: Int) in
                let feed = try await seedFeed(connection)
                let oldUnread = try await seedEntry(
                    connection, userID: feed.userID, feedID: feed.feedID, hash: "old-unread"
                )
                let midUnread = try await seedEntry(
                    connection, userID: feed.userID, feedID: feed.feedID, hash: "mid-unread"
                )
                let oldRead = try await seedEntry(
                    connection, userID: feed.userID, feedID: feed.feedID,
                    hash: "old-read", status: .read
                )
                for (id, daysAgo) in [(oldUnread, 181), (midUnread, 100), (oldRead, 181)] {
                    try await backdateCreatedAt(connection, id: id, createdAt: now - daysAgo * 86_400)
                }
                return (oldUnread, midUnread, oldRead)
            }

            let counts = try await Retention().run(on: storage, now: now)

            #expect(counts.read == 1)
            #expect(counts.unread == 1)
            try await storage.withConnection { connection in
                let entries = EntryRepository(connection)
                let archivedUnread = try await entries.fetch(id: seed.oldUnread)
                let mid = try await entries.fetch(id: seed.midUnread)
                let archivedRead = try await entries.fetch(id: seed.oldRead)
                #expect(archivedUnread == nil)
                #expect(mid != nil)
                #expect(archivedRead == nil)
            }
        }
    }

    @Test func runKeepsStarredEntries() async throws {
        try await withMigratedStorage { _, storage in
            let seed = try await storage.withConnection { connection -> (starredRead: Int, starredUnread: Int) in
                let feed = try await seedFeed(connection)
                let starredRead = try await seedEntry(
                    connection, userID: feed.userID, feedID: feed.feedID,
                    hash: "starred-read", status: .read, starred: true
                )
                let starredUnread = try await seedEntry(
                    connection, userID: feed.userID, feedID: feed.feedID,
                    hash: "starred-unread", starred: true
                )
                for (id, daysAgo) in [(starredRead, 100), (starredUnread, 200)] {
                    try await backdateCreatedAt(connection, id: id, createdAt: now - daysAgo * 86_400)
                }
                return (starredRead, starredUnread)
            }

            let counts = try await Retention().run(on: storage, now: now)

            #expect(counts.read == 0)
            #expect(counts.unread == 0)
            try await storage.withConnection { connection in
                let entries = EntryRepository(connection)
                let starredRead = try await entries.fetch(id: seed.starredRead)
                let starredUnread = try await entries.fetch(id: seed.starredUnread)
                #expect(starredRead?.starred == true)
                #expect(starredUnread?.starred == true)
            }
        }
    }

    @Test func runArchivesOldestFirstUpToTheBatchSize() async throws {
        try await withMigratedStorage { _, storage in
            let ids: [Int] = try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                var ids: [Int] = []
                for index in 0..<25 {
                    let id = try await seedEntry(
                        connection, userID: feed.userID, feedID: feed.feedID,
                        hash: "read-\(index)", status: .read
                    )
                    // 60…84 days old; the strict cutoff keeps the 60-day-old one.
                    try await backdateCreatedAt(
                        connection, id: id, createdAt: now - (60 + index) * 86_400
                    )
                    ids.append(id)
                }
                return ids
            }

            let policy = RetentionPolicy(readEntryAgeDays: 60, unreadEntryAgeDays: 180, batchSize: 10)
            let counts = try await Retention(policy: policy).run(on: storage, now: now)

            #expect(counts.read == 10)
            try await storage.withConnection { connection in
                let entries = EntryRepository(connection)
                // The fifteen youngest survive; the ten oldest are gone.
                var kept: [Entry?] = []
                var archived: [Entry?] = []
                for index in ids.indices {
                    let entry = try await entries.fetch(id: ids[index])
                    if index < 15 {
                        kept.append(entry)
                    } else {
                        archived.append(entry)
                    }
                }
                #expect(kept.allSatisfy { $0 != nil })
                #expect(archived.allSatisfy { $0 == nil })
                let tombstones = try await tombstoneCount(connection)
                #expect(tombstones == 10)
            }
        }
    }

    @Test func runArchivesEntriesOfEveryUser() async throws {
        try await withMigratedStorage { _, storage in
            let ids = try await storage.withConnection { connection -> [Int] in
                var ids: [Int] = []
                for username in ["alice", "bob"] {
                    let feed = try await seedFeed(connection, username: username)
                    let id = try await seedEntry(
                        connection, userID: feed.userID, feedID: feed.feedID,
                        hash: "old-\(username)", status: .read
                    )
                    try await backdateCreatedAt(connection, id: id, createdAt: now - 61 * 86_400)
                    ids.append(id)
                }
                return ids
            }

            // Retention is global, like the reference: it is not scoped to one user.
            let counts = try await Retention().run(on: storage, now: now)
            #expect(counts.read == 2)

            try await storage.withConnection { connection in
                let entries = EntryRepository(connection)
                for id in ids {
                    let entry = try await entries.fetch(id: id)
                    #expect(entry == nil)
                }
                let tombstones = try await tombstoneCount(connection)
                #expect(tombstones == 2)
            }
        }
    }

    @Test func runCutoffIsStrictAndKeysOffCreatedAt() async throws {
        try await withMigratedStorage { _, storage in
            let seed = try await storage.withConnection { connection -> (atCutoff: Int, oldPublication: Int, oldUnread: Int) in
                let feed = try await seedFeed(connection)
                // Exactly at the cutoff (60 days): the strict `<` keeps it.
                let atCutoff = try await seedEntry(
                    connection, userID: feed.userID, feedID: feed.feedID,
                    hash: "at-cutoff", status: .read
                )
                try await backdateCreatedAt(connection, id: atCutoff, createdAt: now - 60 * 86_400)
                // Old `published_at` but young `created_at`: retention keys off creation.
                let oldPublication = try await seedEntry(
                    connection,
                    userID: feed.userID,
                    feedID: feed.feedID,
                    hash: "old-publication",
                    publishedAt: 1_000_000_000,
                    status: .read
                )
                try await backdateCreatedAt(connection, id: oldPublication, createdAt: now - 10 * 86_400)
                let oldUnread = try await seedEntry(
                    connection, userID: feed.userID, feedID: feed.feedID, hash: "old-unread"
                )
                try await backdateCreatedAt(
                    connection, id: oldUnread, createdAt: now - (180 * 86_400 + 1)
                )
                return (atCutoff, oldPublication, oldUnread)
            }

            let counts = try await Retention().run(on: storage, now: now)

            #expect(counts.read == 0)
            #expect(counts.unread == 1)
            try await storage.withConnection { connection in
                let entries = EntryRepository(connection)
                let atCutoff = try await entries.fetch(id: seed.atCutoff)
                let oldPublication = try await entries.fetch(id: seed.oldPublication)
                let archived = try await entries.fetch(id: seed.oldUnread)
                #expect(atCutoff != nil)
                #expect(oldPublication != nil)
                #expect(archived == nil)
            }
        }
    }

    @Test func runDoesNothingWithoutABatchSize() async throws {
        try await withMigratedStorage { _, storage in
            let id = try await storage.withConnection { connection -> Int in
                let feed = try await seedFeed(connection)
                let id = try await seedEntry(
                    connection, userID: feed.userID, feedID: feed.feedID, hash: "old", status: .read
                )
                try await backdateCreatedAt(connection, id: id, createdAt: now - 61 * 86_400)
                return id
            }

            let policy = RetentionPolicy(readEntryAgeDays: 60, unreadEntryAgeDays: 180, batchSize: 0)
            let counts = try await Retention(policy: policy).run(on: storage, now: now)

            #expect(counts.read == 0)
            #expect(counts.unread == 0)
            try await storage.withConnection { connection in
                let kept = try await EntryRepository(connection).fetch(id: id)
                #expect(kept != nil)
            }
        }
    }

    @Test func runSkipsANegativeAge() async throws {
        try await withMigratedStorage { _, storage in
            let seed = try await storage.withConnection { connection -> (oldRead: Int, oldUnread: Int) in
                let feed = try await seedFeed(connection)
                let oldRead = try await seedEntry(
                    connection, userID: feed.userID, feedID: feed.feedID, hash: "old-read", status: .read
                )
                let oldUnread = try await seedEntry(
                    connection, userID: feed.userID, feedID: feed.feedID, hash: "old-unread"
                )
                for id in [oldRead, oldUnread] {
                    try await backdateCreatedAt(connection, id: id, createdAt: now - 200 * 86_400)
                }
                return (oldRead, oldUnread)
            }

            let policy = RetentionPolicy(readEntryAgeDays: -1, unreadEntryAgeDays: 180, batchSize: 10_000)
            let counts = try await Retention(policy: policy).run(on: storage, now: now)

            #expect(counts.read == 0)
            #expect(counts.unread == 1)
            try await storage.withConnection { connection in
                let entries = EntryRepository(connection)
                let kept = try await entries.fetch(id: seed.oldRead)
                let archived = try await entries.fetch(id: seed.oldUnread)
                #expect(kept != nil)
                #expect(archived == nil)
            }
        }
    }

    @Test func runClampsZeroAgeToOneDay() async throws {
        try await withMigratedStorage { _, storage in
            let seed = try await storage.withConnection { connection -> (old: Int, fresh: Int) in
                let feed = try await seedFeed(connection)
                let old = try await seedEntry(
                    connection, userID: feed.userID, feedID: feed.feedID, hash: "old", status: .read
                )
                let fresh = try await seedEntry(
                    connection, userID: feed.userID, feedID: feed.feedID, hash: "fresh", status: .read
                )
                try await backdateCreatedAt(connection, id: old, createdAt: now - 2 * 86_400)
                try await backdateCreatedAt(connection, id: fresh, createdAt: now - 10 * 3_600)
                return (old, fresh)
            }

            let policy = RetentionPolicy(readEntryAgeDays: 0, unreadEntryAgeDays: 180, batchSize: 10_000)
            let counts = try await Retention(policy: policy).run(on: storage, now: now)

            #expect(counts.read == 1)
            try await storage.withConnection { connection in
                let entries = EntryRepository(connection)
                let archived = try await entries.fetch(id: seed.old)
                let fresh = try await entries.fetch(id: seed.fresh)
                #expect(archived == nil)
                #expect(fresh != nil)
            }
        }
    }

    @Test func archiveRollsBackWhenTheTombstoneInsertFails() async throws {
        try await withMigratedStorage { _, storage in
            let id = try await storage.withConnection { connection -> Int in
                let feed = try await seedFeed(connection)
                let id = try await seedEntry(
                    connection, userID: feed.userID, feedID: feed.feedID,
                    hash: "atomic", status: .read
                )
                try await backdateCreatedAt(connection, id: id, createdAt: now - 61 * 86_400)
                // The delete and the tombstone insert share the retention
                // transaction: without the table the delete must roll back.
                try await RawSQL.run("DROP TABLE entry_tombstones", on: connection)
                return id
            }

            do {
                _ = try await Retention().run(on: storage, now: now)
                Issue.record("expected the archive to fail without the tombstone table")
            } catch {
                // The failing statement must be the tombstone insert, not a
                // coincidental error: the delete rolls back with it.
                #expect(String(describing: error).contains("entry_tombstones"))
            }

            try await storage.withConnection { connection in
                let kept = try await EntryRepository(connection).fetch(id: id)
                #expect(kept != nil)
            }
        }
    }
}
