import Foundation
import SQLKit
import Testing
@testable import RivuletCore

/// The entry-frequency mode read through the pipeline, so the count the storage layer
/// value the schedule is built from, not the number a test hands to the policy. The order is the
/// reference's (`RefreshFeed` at commit `c4d54f87`): the count is read at the start of the refresh,
/// before the fetch and before any entry is written, and the schedule is fixed from it before the
/// answer is read. The clock is injected, so every instant this pin reads is the injected one. What
/// this can fail on, checked by patching the rule and reverting: that the count is read at all — an
/// implementation that passes 0 schedules the maximum, 86400, where this pin expects the division,
/// 50400 — and that the read happens before the entries land: the entry this refresh writes is
/// published at the injected instant, so a read after the entry batch sees 13 rows and answers 14,
/// which schedules 43200. What it cannot fail on: that the count is read only for the
/// entry-frequency mode, because in the round-robin mode the count answers nothing — the
/// mode itself is pinned in `NextCheckPolicyTests` — and that the read runs inside the
/// write transaction, which is what no test here can pin. Nothing here sleeps.
/// mode, because in the round-robin mode the count answers nothing — the mode itself is pinned in
/// `NextCheckPolicyTests` — and that the read runs inside the write transaction, which is what no
/// test here can pin. Nothing here sleeps.
@Suite struct EntryFrequencyPipelineTests {
    /// The injected instant: 2065, after the process clock, so a pin can tell the clock it
    /// was given
    /// from the process one.
    private let now = 3_000_000_000

    @Test func theScheduleComesFromTheWeeklyCountThePipelineRead() async throws {
        try await FetchTestSupport.withServer(behaviors: ["/feed": answer(rss([
            ("<p>A</p>", "https://example.org/a"),
        ]))]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options()) { fetcher in
                try await withMigratedStorage { _, storage in
                    let graph = try await seedGraph(storage, username: "alice")
                    let feedURL = server.url("/feed").absoluteString
                    let feedID = try await seedRow(storage, graph, url: feedURL)

                    // Twelve stored entries inside the week, 50400 seconds
                    // apart: the span is 554400,
                    // the average gap 50400, and the rule answers 12, which
                    // the default clamps keep,
                    // so the interval is 604800 / 12 = 50400.
                    for offset in stride(from: 554_400, through: 0, by: -50_400) {
                        try await putEntry(storage, graph, feedID: feedID,
                            publishedAt: now - offset)
                    }

                    let pipeline = RefreshPipeline(storage: storage, fetcher: fetcher,
                        options: FetchTestSupport.options(),
                        nextCheck: NextCheckPolicy(mode: .entryFrequency),
                        clock: FixedClock(now: now))
                    let outcome = try await pipeline.refresh(userID: graph.userID, feedID: feedID)

                    #expect(outcome.newEntryHashes.count == 1)
                    #expect(outcome.nextCheckAt == now + 50400)

                    // The same value is what the row stores, so the schedule is written from the
                    // count read, not only reported by the outcome.
                    #expect(try await storedSchedule(storage, feedID: feedID) == now + 50400)
                }
            }
        }
    }

    // MARK: - Helpers

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

    private func putEntry(_ storage: SQLiteStorage,
        _ graph: (userID: Int, categoryID: Int), feedID: Int, publishedAt: Int) async throws {
        try await storage.withConnection { connection in
            try await seedEntry(connection, userID: graph.userID, feedID: feedID,
                hash: "e\(publishedAt)", publishedAt: publishedAt)
        }
    }

    private func storedSchedule(_ storage: SQLiteStorage, feedID: Int) async throws -> Int {
        try await storage.withConnection { connection in
            let row = try await sqlDatabase(connection).raw("""
                SELECT next_check_at FROM feeds WHERE id = \(bind: feedID)
                """).first()
            return try #require(row).decode(column: "next_check_at", as: Int.self)
        }
    }

    private func rss(_ entries: [(content: String, url: String)]) -> String {
        var document = "<rss version=\"2.0\"><channel><title>T</title>"
        for entry in entries {
            document += "<item><title>E</title><link>\(entry.url)</link>"
                + "<description>\(entry.content)</description></item>"
        }
        return document + "</channel></rss>"
    }

    private func answer(_ body: String) -> StubFeedServer.Behavior {
        StubFeedServer.Behavior(body: Data(body.utf8))
    }
}
