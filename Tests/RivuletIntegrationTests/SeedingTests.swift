import Fluent
import Foundation
import Testing
@testable import RivuletCore

/// The deterministic corpus builder used for benchmarks and heavy tests.
@Suite struct SeedingTests {
    @Test func seedCreatesTheRequestedCorpus() async throws {
        try await withMigratedStorage { _, storage in
            let corpus = try await Seeding.seed(on: storage, feeds: 3, entries: 37)

            #expect(corpus.feeds == 3)
            #expect(corpus.entries == 37)
            try await storage.withConnection { connection in
                let users = try await Self.count("users", on: connection)
                // The user's default "All" category plus the seeded one.
                let categories = try await Self.count("categories", on: connection)
                let feeds = try await Self.count("feeds", on: connection)
                let entries = try await Self.count("entries", on: connection)
                #expect(users == 1)
                #expect(categories == 2)
                #expect(feeds == 3)
                #expect(entries == 37)

                // Round-robin: 37 entries over 3 feeds is 13, 12, 12.
                let distribution = try await Self.entriesPerFeed(on: connection)
                #expect(distribution == [13, 12, 12])

                let unread = try await EntryRepository(connection)
                    .count(EntryQuery(userID: corpus.userID))
                #expect(unread == 37)

                // The corpus is dated in the past, hourly back from the seed epoch.
                let newest = try await RawSQL.first(
                    "SELECT max(published_at) AS newest FROM entries", on: connection
                )
                let newestValue = try newest?.decode(column: "newest", as: Int.self) ?? 0
                #expect(newestValue <= Seeding.seedEpoch)
            }
        }
    }

    @Test func seedRejectsInvalidCounts() async throws {
        try await withMigratedStorage { _, storage in
            do {
                _ = try await Seeding.seed(on: storage, feeds: 0, entries: 10)
                Issue.record("expected feeds: 0 to be rejected")
            } catch {
                #expect(error as? StorageError == .invalidSeeding(feeds: 0, entries: 10))
            }
            do {
                _ = try await Seeding.seed(on: storage, feeds: 1, entries: -1)
                Issue.record("expected entries: -1 to be rejected")
            } catch {
                #expect(error as? StorageError == .invalidSeeding(feeds: 1, entries: -1))
            }
        }
    }

    @Test func seedAcceptsAnEmptyCorpus() async throws {
        try await withMigratedStorage { _, storage in
            let corpus = try await Seeding.seed(on: storage, feeds: 2, entries: 0)
            #expect(corpus.feeds == 2)
            #expect(corpus.entries == 0)
            try await storage.withConnection { connection in
                let feeds = try await Self.count("feeds", on: connection)
                let entries = try await Self.count("entries", on: connection)
                #expect(feeds == 2)
                #expect(entries == 0)
            }
        }
    }

    @Test func seedIsDeterministicAcrossDatabases() async throws {
        var first: [String] = []
        try await withMigratedStorage { _, storage in
            _ = try await Seeding.seed(on: storage, feeds: 4, entries: 25)
            first = try await Self.digests(on: storage)
        }
        var second: [String] = []
        try await withMigratedStorage { _, storage in
            _ = try await Seeding.seed(on: storage, feeds: 4, entries: 25)
            second = try await Self.digests(on: storage)
        }
        #expect(first.count == 25)
        #expect(first == second)
    }

    /// Row count of `table`; the name is a literal from this file only.
    private static func count(_ table: String, on connection: any Database) async throws -> Int {
        let row = try await RawSQL.first("SELECT count(*) AS n FROM \(table)", on: connection)
        return try row?.decode(column: "n", as: Int.self) ?? 0
    }

    private static func entriesPerFeed(on connection: any Database) async throws -> [Int] {
        let rows = try await RawSQL.sql(on: connection)
            .raw("SELECT count(*) AS n FROM entries GROUP BY feed_id ORDER BY feed_id")
            .all()
        return try rows.map { try $0.decode(column: "n", as: Int.self) }
    }

    /// One line per entry: everything a benchmark corpus must reproduce exactly.
    private static func digests(on storage: SQLiteStorage) async throws -> [String] {
        try await storage.withConnection { connection in
            let rows = try await RawSQL.sql(on: connection).raw("""
                SELECT feed.url || '|' || entries.hash || '|' || entries.title
                       || '|' || entries.content || '|' || entries.content_text
                       || '|' || CAST(entries.published_at AS TEXT) AS digest
                FROM entries
                JOIN feeds AS feed ON feed.id = entries.feed_id
                ORDER BY entries.id
                """).all()
            return try rows.map { try $0.decode(column: "digest", as: String.self) }
        }
    }
}
