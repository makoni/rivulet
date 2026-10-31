import Foundation
import SQLKit
import Testing
@testable import RivuletCore

/// The weekly entry count the entry-frequency mode divides the week by, from
/// `internal/storage/feed.go` (`WeeklyFeedEntryCount`) at commit `c4d54f87`, which upstream has no
/// test for.
/// The rule is the average gap between the entries of one feed inside one week, taken as whole
/// division of the span by `count - 1`, and the week rounded up over that gap, over the rows of
/// one user, with `COALESCE(..., 0)` so an empty feed answers 0 and a single entry answers 0 as
/// well, because the average gap is undefined when `count - 1` is 0. Every expected value is the
/// reference's rule computed by hand, not this implementation's.
/// What these cases can fail on: the rounding up, because 604800 over a gap of 20000 is 30.24, so
/// the rule answers 31 where a plain whole division answers 30; the division that keeps the gap
/// whole, because a span of 15 over two gaps answers 7 and the week over it 86400, where a gap
/// read as 7.5 answers 80640; the week window, because the row exactly on the boundary answers 2
/// with the three rows counted and 7 when the boundary reads as exclusive; the user scope, because
/// the same rows read without it answer 61; and the empty result, because `COALESCE` answers 0
/// where reading the null directly would fail the read.
/// What they cannot fail on: the `NULLIF(count - 1, 0)` guard for a single entry, because without
/// it SQLite divides by zero and answers null, which `COALESCE` turns into the same 0; the SQL
/// `now()` the reference compares the window against, which here is the instant the caller passes
/// — the injected clock the pipeline section already records; the log lines and the error wrapping
/// the storage layer adds, because RivuletCore has neither a logging nor a locale layer; and the
/// transaction the read runs inside, which is what no test here can pin. Nothing sleeps here, and
/// the read goes through the repository on a checked-out connection.
@Suite struct WeeklyEntryCountTests {
    /// The instant the window is read from: 2065, after the process clock, so a pin can tell the
    /// injected clock from the process one.
    private let now = 3_000_000_000

    @Test func aFeedWithNoEntriesAnswersZero() async throws {
        try await withMigratedStorage { _, storage in
            let graph = try await seedGraph(storage, username: "alice")
            let feedID = try await seedRow(storage, graph, url: "http://host.test/feed")
            #expect(try await count(storage, userID: graph.userID, feedID: feedID, now: now) == 0)
        }
    }

    @Test func aSingleEntryAnswersZeroBecauseTheAverageGapIsUndefined() async throws {
        try await withMigratedStorage { _, storage in
            let graph = try await seedGraph(storage, username: "alice")
            let feedID = try await seedRow(storage, graph, url: "http://host.test/feed")
            try await putEntry(storage, graph, feedID: feedID, publishedAt: now)
            // The average gap needs two entries: the reference's `NULLIF(count - 1, 0)` answers no
            // value, `COALESCE` turns that into 0, and the same answer comes from the guard being
            // absent, because SQLite divides by zero and answers null. So this case pins the rule
            // that a single entry answers 0, not the guard that produces it.
            #expect(try await count(storage, userID: graph.userID, feedID: feedID, now: now) == 0)
        }
    }

    @Test func theCountIsTheCeilingOfTheWeekOverTheAverageGap() async throws {
        try await withMigratedStorage { _, storage in
            let graph = try await seedGraph(storage, username: "alice")
            let feedID = try await seedRow(storage, graph, url: "http://host.test/feed")
            // Three entries spanning 40000 seconds: the average gap is 20000, the week over it is
            // 30.24, and the ceiling answers 31. An integer division, or a comparison that
            // truncates, answers 30 here.
            try await putEntry(storage, graph, feedID: feedID, publishedAt: now - 40_000)
            try await putEntry(storage, graph, feedID: feedID, publishedAt: now - 20_000)
            try await putEntry(storage, graph, feedID: feedID, publishedAt: now)
            #expect(try await count(storage, userID: graph.userID, feedID: feedID, now: now) == 31)
        }
    }

    @Test func anEntryExactlyOnTheWeekBoundaryIsCounted() async throws {
        try await withMigratedStorage { _, storage in
            let graph = try await seedGraph(storage, username: "alice")
            let feedID = try await seedRow(storage, graph, url: "http://host.test/feed")
            // The reference compares `published_at >= now() - interval '1 week'`, so
            // the row exactly on the boundary is inside: the span is the whole week,
            // the average gap 302400, and the
            // ceiling answers 2. A boundary read as exclusive leaves two rows 100000 apart, which
            // the rule answers as 7.
            try await putEntry(storage, graph, feedID: feedID, publishedAt: now - 604_800)
            try await putEntry(storage, graph, feedID: feedID, publishedAt: now - 100_000)
            try await putEntry(storage, graph, feedID: feedID, publishedAt: now)
            #expect(try await count(storage, userID: graph.userID, feedID: feedID, now: now) == 2)
        }
    }

    @Test func theCountIsScopedToTheUser() async throws {
        try await withMigratedStorage { _, storage in
            let alice = try await seedGraph(storage, username: "alice")
            let bob = try await seedGraph(storage, username: "bob")
            let feedID = try await seedRow(storage, alice, url: "http://host.test/feed")
            // Alice's two rows are 40000 apart, which the rule answers as 16. Bob's
            // rows on the same feed are inside the window too, so reading the count
            // without the user filter would put
            // five rows 40000 apart and answer 61.
            try await putEntry(storage, alice, feedID: feedID, publishedAt: now - 40_000)
            try await putEntry(storage, alice, feedID: feedID, publishedAt: now)
            try await putEntry(storage, bob, feedID: feedID, publishedAt: now - 30_000)
            try await putEntry(storage, bob, feedID: feedID, publishedAt: now - 20_000)
            try await putEntry(storage, bob, feedID: feedID, publishedAt: now - 10_000)
            #expect(try await count(storage, userID: alice.userID, feedID: feedID, now: now) == 16)
        }
    }

    // MARK: - Helpers

    private func count(_ storage: SQLiteStorage, userID: Int, feedID: Int, now: Int) async throws
        -> Int {
        try await storage.withConnection { connection in
            try await FeedRepository(connection).weeklyEntryCount(userID: userID, feedID: feedID,
                now: now)
        }
    }

    private func seedGraph(_ storage: SQLiteStorage, username: String) async throws
        -> (userID: Int, categoryID: Int) {
        try await storage.withConnection { connection in
            let userID = try await seedUser(connection, username: username)
            let categoryID = try await seedCategory(connection, userID: userID, title: "Tech")
            return (userID, categoryID)
        }
    }

    private func seedRow(_ storage: SQLiteStorage, _ graph: (userID: Int, categoryID: Int),
        url: String) async throws -> Int {
        try await storage.withConnection { connection in
            try await seedFeed(connection, userID: graph.userID, categoryID: graph.categoryID,
                url: url)
        }
    }

    /// One stored entry through the repository, so the read sees the rows the rule counts.
    private func putEntry(_ storage: SQLiteStorage,
        _ graph: (userID: Int, categoryID: Int), feedID: Int, publishedAt: Int) async throws {
        try await storage.withConnection { connection in
            try await seedEntry(connection, userID: graph.userID, feedID: feedID,
                hash: "e\(publishedAt)", publishedAt: publishedAt)
        }
    }
}
