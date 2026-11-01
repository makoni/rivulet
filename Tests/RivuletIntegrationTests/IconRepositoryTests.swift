import Foundation
import Fluent
import FluentSQLiteDriver
import Testing
@testable import RivuletCore

/// Round-trip for ``IconRepository``: dedup by hash, the shape of the `external_id`, the link
/// from the feed row, and the pass that removes icons no feed points at. The reference keeps
/// the mapping in its own `feed_icons` table (`internal/storage/icon.go`, `StoreFeedIcon`);
/// this port stores it as `feeds.icon_id`, which `docs/parity.md` records. The upstream file
/// has no test for the link or the orphan pass, so those pins are the port's own.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the dedupe is
/// by hash — a patch that inserts anyway fails the pins that read the same content stored once,
/// and a patch that returns the value handed in instead of the one already stored fails the pin
/// that names that; `normalizeMimeType` compares the whole value, so a content type carrying a
/// parameter is not one of the known icon types, which is what a patch that strips the
/// parameter before comparing fails on; the link replaces what the feed row had rather than
/// adding a second mapping; and the orphan pass deletes only icons no feed points at, so a
/// patch that deletes the row it just wrote, or one that keeps an icon another feed still
/// points at, fails the pins that name those; and the count the pass returns is the number of rows
/// it deleted.
///
/// What they cannot fail on: the randomness of `external_id`, which the pins read only as the shape
/// Go's `GenerateRandomStringHex(20)` produces; the single transaction the reference wraps the
/// dedupe and the link in, which nothing here can make fail on one statement while the others
/// succeed — the same boundary the pipeline records; the join table itself, which this port does
/// not have; and the mechanism the count is read through, `SELECT changes()`, which cannot show
/// that another statement on the same connection would not be seen — this SQLKit version gives no
/// row count for a raw statement, so the reference's `RowsAffected` has no equivalent here, and
/// `docs/parity.md` records that.
@Suite struct IconRepositoryTests {
    @Test func insertStoresTheIconAndAssignsAnExternalID() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let icons = IconRepository(connection)
                let content = Data([0x89, 0x50, 0x4E, 0x47])
                let icon = try await icons.insert(hash: "hash-a", mimeType: "image/png", content: content)
                let id = try #require(icon.id)

                let stored = try await icons.fetch(id: id)
                #expect(stored?.hash == "hash-a")
                #expect(stored?.mimeType == "image/png")
                #expect(stored?.content == content)
                let externalID = try #require(stored?.externalID)
                #expect(externalID.count == 40)
                #expect(externalID.allSatisfy { $0.isHexDigit })
                #expect(try await icons.fetch(externalID: externalID)?.id == id)
            }
        }
    }

    @Test func mimeTypeIsNormalizedLikeTheReference() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let icons = IconRepository(connection)
                let upper = try await normalize(icons, hash: "hash-a", mimeType: "IMAGE/PNG")
                #expect(upper == "image/png")

                let other = try await normalize(icons, hash: "hash-b", mimeType: "text/plain")
                #expect(other == "image/x-icon")

                let gif = try await normalize(icons, hash: "hash-c", mimeType: "image/GIF")
                #expect(gif == "image/gif")
            }
        }
    }

    @Test func insertWithTheSameHashReturnsTheExistingIcon() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let icons = IconRepository(connection)
                let first = try await icons.insert(hash: "hash-a", mimeType: "image/png",
                    content: Data([1]))
                let second = try await icons.insert(hash: "hash-a", mimeType: "image/png",
                    content: Data([2]))

                #expect(second.id == first.id)
                #expect(second.externalID == first.externalID)
                #expect(second.content == Data([1]))
                #expect(try await icons.fetch(hash: "hash-a")?.id == first.id)
            }
        }
    }

    @Test func fetchByIDAndHashFindTheStoredIcon() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let icons = IconRepository(connection)
                let icon = try await icons.insert(hash: "hash-a", mimeType: "image/png",
                    content: Data([1]))
                let id = try #require(icon.id)

                #expect(try await icons.fetch(id: id)?.hash == "hash-a")
                #expect(try await icons.fetch(id: 999) == nil)
                #expect(try await icons.fetch(hash: "hash-b") == nil)
                #expect(try await icons.fetch(externalID: "nope") == nil)
            }
        }
    }

    @Test func linkWritesTheFeedRowAndReplacesTheIconItHad() async throws {
        // Ported from `internal/storage/icon.go` (`StoreFeedIcon`), which deletes the
        // feed's mapping and inserts the new one in the same transaction. This port has
        // no join table — the feed row carries `icon_id`, recorded in `docs/parity.md` —
        // so the replace is the rule the pins read.
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let userID = try await seedUser(connection)
                let categoryID = try await seedCategory(connection, userID: userID, title: "News")
                let feedID = try await seedFeed(connection, userID: userID, categoryID: categoryID,
                    url: "https://example.org/feed")
                let icons = IconRepository(connection)
                let first = try await icons.insert(hash: "hash-a", mimeType: "image/png",
                    content: Data([1]))
                let second = try await icons.insert(hash: "hash-b", mimeType: "image/png",
                    content: Data([2]))

                try await icons.link(feedID: feedID, iconID: try #require(first.id))
                #expect(try await feedIconID(connection, feedID) == first.id)

                try await icons.link(feedID: feedID, iconID: try #require(second.id))
                #expect(try await feedIconID(connection, feedID) == second.id)

                // The icon the feed no longer points at is an orphan, and the
                // reference's cleanup is the same rule the pins below read.
                #expect(try await icons.cleanupOrphans() == 1)
                #expect(try await icons.fetch(hash: "hash-b") != nil)
                #expect(try await icons.fetch(hash: "hash-a") == nil)
            }
        }
    }

    @Test func anIconTwoFeedsShareSurvivesCleanupBecauseTheOtherFeedStillPointsAtIt() async throws {
        // Dedupe means one row for the same content, so the orphan rule is about the
        // mapping, not about the icon the store just wrote: a patch that deletes the row
        // it inserted fails this pin.
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let userID = try await seedUser(connection)
                let categoryID = try await seedCategory(connection, userID: userID, title: "News")
                let firstFeed = try await seedFeed(connection, userID: userID,
                    categoryID: categoryID,
                    url: "https://example.org/a")
                let secondFeed = try await seedFeed(connection, userID: userID,
                    categoryID: categoryID,
                    url: "https://example.org/b")
                let icons = IconRepository(connection)
                let icon = try await icons.insert(hash: "hash-a", mimeType: "image/png",
                    content: Data([1]))
                let id = try #require(icon.id)

                try await icons.link(feedID: firstFeed, iconID: id)
                try await icons.link(feedID: secondFeed, iconID: id)

                try await Feed.query(on: connection).filter(\Feed.$id == firstFeed).delete()
                #expect(try await icons.cleanupOrphans() == 0)
                #expect(try await icons.fetch(id: id) != nil)
                #expect(try await feedIconID(connection, secondFeed) == id)
            }
        }
    }

    @Test func deletingTheFeedLeavesTheIconUntilTheOrphanPassRuns() async throws {
        // The reference's cascade removes the mapping and leaves the deduplicated row,
        // which is why the orphan pass exists. This port's `ON DELETE SET NULL` leaves
        // the same row, so the pin reads the count the pass returns: one row deleted,
        // and nothing left for a second pass.
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let userID = try await seedUser(connection)
                let categoryID = try await seedCategory(connection, userID: userID, title: "News")
                let feedID = try await seedFeed(connection, userID: userID, categoryID: categoryID,
                    url: "https://example.org/feed")
                let icons = IconRepository(connection)
                let icon = try await icons.insert(hash: "hash-a", mimeType: "image/png",
                    content: Data([1]))
                try await icons.link(feedID: feedID, iconID: try #require(icon.id))

                try await Feed.query(on: connection).filter(\Feed.$id == feedID).delete()
                #expect(try await icons.fetch(hash: "hash-a") != nil)
                #expect(try await icons.cleanupOrphans() == 1)
                #expect(try await icons.fetch(hash: "hash-a") == nil)
                #expect(try await icons.cleanupOrphans() == 0)
            }
        }
    }

    @Test func contentTypeWithAParameterIsStoredAsTheDefaultIconType() async throws {
        // The download half hands the content type on as the header gave it, and
        // `normalizeMimeType` compares the whole value, so a parameter makes it not one
        // of the known icon types.
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let icons = IconRepository(connection)
                let stored = try await icons.insert(hash: "hash-a",
                    mimeType: "image/png; charset=utf-8", content: Data([1]))
                #expect(stored.mimeType == "image/x-icon")
            }
        }
    }

    /// Reads the feed row's icon link, which is the whole mapping this port has.
    private func feedIconID(_ connection: any Database, _ feedID: Int) async throws -> Int? {
        try await Feed.query(on: connection).filter(\Feed.$id == feedID).first()?.iconID
    }

    /// Stores an icon and reads back the content type the storage layer wrote, from the
    /// stored row rather than from the value handed in, so the pin reads what the database
    /// holds.
    private func normalize(_ icons: IconRepository, hash: String, mimeType: String)
        async throws -> String {
        _ = try await icons.insert(hash: hash, mimeType: mimeType, content: Data([1]))
        let stored = try await icons.fetch(hash: hash)
        return try #require(stored?.mimeType)
    }
}
