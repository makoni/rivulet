import FluentKit
import Foundation

/// A corpus of feeds and entries created by ``Seeding``.
public struct SeededCorpus: Sendable, Equatable {
    /// The id of the user that owns every seeded feed.
    public let userID: Int

    /// The number of feeds created.
    public let feeds: Int

    /// The number of entries created.
    public let entries: Int
}

/// Invalid arguments for ``Seeding/seed(on:feeds:entries:)``.
public enum SeedingError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The requested corpus shape is impossible: `feeds` must be positive and
    /// `entries` cannot be negative.
    case invalidCounts(feeds: Int, entries: Int)

    /// Human-readable message used by the CLI error path.
    public var description: String {
        switch self {
        case .invalidCounts(let feeds, let entries):
            return "invalid corpus size: \(feeds) feed(s), \(entries) entry/entries"
        }
    }
}

/// Builds a deterministic corpus of feeds and entries for benchmarks and heavy tests.
///
/// The corpus has one user (whose creation adds the default category), one
/// explicit `Seeded` category, `feeds` feeds and `entries` entries distributed
/// round-robin over the feeds. Titles, URLs, content and timestamps depend only
/// on the feed and entry positions, so two fresh databases seeded with the same
/// parameters hold identical entry data. There is no Miniflux counterpart: the
/// reference benchmarks use its PostgreSQL fixtures.
public enum Seeding {
    /// Entry `n` is published `entries - n + 1` hours before this Unix
    /// timestamp, so the whole corpus — including the newest entry — lies in
    /// the past.
    static let seedEpoch = 1_700_000_000

    /// Creates the corpus in one write transaction.
    ///
    /// - Parameters:
    ///   - storage: A migrated database; the corpus is added to its content.
    ///   - feeds: The number of feeds to create; must be positive.
    ///   - entries: The number of entries to create; may be zero.
    /// - Returns: What was created, including the owning user's id.
    /// - Throws: ``SeedingError/invalidCounts(feeds:entries:)`` when the
    ///   requested shape is impossible.
    public static func seed(
        on storage: SQLiteStorage,
        feeds: Int,
        entries: Int
    ) async throws -> SeededCorpus {
        guard feeds > 0, entries >= 0 else {
            throw SeedingError.invalidCounts(feeds: feeds, entries: entries)
        }

        return try await storage.withTransaction { connection in
            let user = try await UserRepository(connection)
                .create(username: "seeded", passwordHash: "seeded", isAdmin: false)
            let userID = try user.requireID()
            let category = try await CategoryRepository(connection)
                .create(userID: userID, title: "Seeded")
            let categoryID = try category.requireID()
            for index in 0..<feeds {
                _ = try await FeedRepository(connection).create(
                    userID: userID,
                    categoryID: categoryID,
                    url: "https://example.com/feeds/\(index).xml"
                )
            }
            if entries > 0 {
                try await insertEntries(
                    on: connection, userID: userID, feeds: feeds, count: entries
                )
            }
            return SeededCorpus(userID: userID, feeds: feeds, entries: entries)
        }
    }

    /// Inserts all entries with one recursive statement; `feed.position` is the
    /// 1-based position of a feed in creation order, so the corpus does not rely
    /// on consecutive feed ids.
    private static func insertEntries(
        on connection: any Database,
        userID: Int,
        feeds: Int,
        count: Int
    ) async throws {
        try await RawSQL.sql(on: connection).raw("""
            WITH RECURSIVE seq(n) AS (
                SELECT 1
                UNION ALL
                SELECT n + 1 FROM seq WHERE n < \(bind: count)
            )
            INSERT INTO entries (
                user_id, feed_id, hash, title, url, author,
                content, content_text, published_at, created_at, updated_at
            )
            SELECT
                \(bind: userID),
                feed.id,
                'seed-' || n,
                'Seeded title ' || n,
                'https://example.com/posts/' || n,
                '',
                '<p>Seeded entry ' || n || '</p>',
                'seeded entry ' || n,
                \(bind: seedEpoch) - (\(bind: count) - n + 1) * 3600,
                \(bind: seedEpoch) - (\(bind: count) - n + 1) * 3600,
                \(bind: seedEpoch) - (\(bind: count) - n + 1) * 3600
            FROM seq
            JOIN (
                SELECT id, row_number() OVER (ORDER BY id) AS position
                FROM feeds
                WHERE user_id = \(bind: userID)
            ) AS feed ON feed.position = (n - 1) % \(bind: feeds) + 1
            """).run()
    }
}
