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

/// Builds a deterministic corpus of feeds and entries for benchmarks and heavy tests.
///
/// The corpus has one user, one category, `feeds` feeds and `entries` entries
/// distributed round-robin over the feeds. Titles, URLs, content and timestamps
/// depend only on the feed and entry positions, so two fresh databases seeded
/// with the same parameters hold identical entry data. There is no Miniflux
/// counterpart: the reference benchmarks use its PostgreSQL fixtures.
public enum Seeding {
    /// Entry `n` is published `n` hours after this Unix timestamp, in the past.
    static let firstPublishedAt = 1_700_000_000

    /// Creates the corpus in one write transaction.
    ///
    /// - Parameters:
    ///   - storage: A migrated database; the corpus is added to its content.
    ///   - feeds: The number of feeds to create; must be positive.
    ///   - entries: The number of entries to create; may be zero.
    /// - Returns: What was created, including the owning user's id.
    public static func seed(
        on storage: SQLiteStorage,
        feeds: Int,
        entries: Int
    ) async throws -> SeededCorpus {
        precondition(feeds > 0, "a benchmark corpus needs at least one feed")
        precondition(entries >= 0, "the entry count cannot be negative")

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
                \(bind: firstPublishedAt) + n * 3600,
                \(bind: firstPublishedAt) + n * 3600,
                \(bind: firstPublishedAt) + n * 3600
            FROM seq
            JOIN (
                SELECT id, row_number() OVER (ORDER BY id) AS position
                FROM feeds
                WHERE user_id = \(bind: userID)
            ) AS feed ON feed.position = (n - 1) % \(bind: feeds) + 1
            """).run()
    }
}
