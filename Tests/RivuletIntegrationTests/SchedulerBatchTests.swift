import Foundation
import SQLKit
import Testing
@testable import RivuletCore

/// The due-batch selection the tick reads, from `internal/storage/batch.go` at commit `c4d54f87`.
/// Upstream has no test for this builder, so these pins are the port's own defense.
/// What they can fail on, each checked by patching the rule and reverting: the strict
/// `next_check_at < now()` comparison, the direction of the `ORDER BY next_check_at ASC` — the
/// rows are seeded out of that order so the pin does not pass on insertion order —, the injected
/// instant being the one compared (it is 2065 and the stored schedule 2062, both after the process
/// clock, so a pin can tell the two clocks apart), the error condition appended only for a
/// positive limit and comparing strictly, the disabled gate, the `LIMIT` clause added only for a
/// positive batch size, the host limit off when it is zero, the host filter running only on the
/// rows the `LIMIT` read — a row it skips still uses one of the `LIMIT` slots — rather than on all
/// rows the conditions match, the host taken as the parsed `Host` with its port and without the
/// `www.` strip, two unparseable URLs counted as the two strings as written, which fails when the
/// error branch collapses them into one host or reads the bracketed host instead, the batch not
/// being user-scoped, and the job carrying the stored feed URL rather than the site URL.
/// What they cannot fail on: the `IS false` form of the disabled gate, which the NOT NULL column
/// makes equal to `= 0`; dropping the ordering clause, because the schema's index on
/// `next_check_at` reads the rows in the order the clause asks for; the order of rows sharing one
/// `next_check_at`, which SQL does not define; the PostgreSQL placeholder style the builder
/// writes; and the log lines it emits, because RivuletCore has no logging layer.
/// Nothing sleeps here: the tests read the batch through the repository.
@Suite struct SchedulerBatchTests {
    /// The instant every pin passes. It is after the process clock until 2065, so the stored
    /// schedule read by the pins can only be due relative to this one.
    private let now = 3_000_000_000

    @Test func theBatchIsStrictlyDueAndOrderedByNextCheckAgainstTheInjectedInstant() async throws {
        try await withMigratedStorage { _, storage in
            let graph = try await seedGraph(storage, username: "alice")
            // Seeded out of the clause order, so an implementation that drops the ordering cannot
            // pass on insertion order.
            let later = try await seedRow(storage, graph, url: "http://host.test/later",
                nextCheckAt: 2_900_000_001)
            let early = try await seedRow(storage, graph, url: "http://host.test/early",
                nextCheckAt: 2_900_000_000)
            // Exactly the injected instant: the strict comparison excludes it; a `<=` would keep
            // it. The other two rows are after the process clock, so only the injected instant can
            // make them due.
            let equal = try await seedRow(storage, graph, url: "http://host.test/equal",
                nextCheckAt: now)

            let jobs = try await batch(storage, now: now, options: .defaults)
            #expect(jobs == [job(early, graph, "http://host.test/early"),
                job(later, graph, "http://host.test/later")])
            #expect(!jobs.contains(where: { $0.feedID == equal }))
        }
    }

    @Test func theErrorConditionIsAppendedOnlyForAPositiveLimitAndComparesStrictly() async throws {
        try await withMigratedStorage { _, storage in
            let graph = try await seedGraph(storage, username: "alice")
            let below = try await seedRow(storage, graph, url: "http://host.test/below",
                nextCheckAt: 2_900_000_000, errorCount: 2)
            let atLimit = try await seedRow(storage, graph, url: "http://host.test/at-limit",
                nextCheckAt: 2_900_000_001, errorCount: 3)

            // Strict `<` at the default limit: a row exactly at the limit is out.
            #expect(try await batch(storage, now: now, options: .defaults) ==
                [job(below, graph, "http://host.test/below")])

            // The condition is appended only when the limit is positive. With 0 the row at the same
            // count is selected: an implementation that reads zero as a value appends `< 0` and
            // selects nothing.
            let noLimit = options(batchSize: 100, workerPoolSize: 16, parsingErrorLimit: 0,
                limitPerHost: 0)
            #expect(try await batch(storage, now: now, options: noLimit) == [
                job(below, graph, "http://host.test/below"),
                job(atLimit, graph, "http://host.test/at-limit"),
            ])
        }
    }

    @Test func disabledFeedsAreExcludedAndEnabledOnesSelected() async throws {
        try await withMigratedStorage { _, storage in
            let graph = try await seedGraph(storage, username: "alice")
            let enabled = try await seedRow(storage, graph, url: "http://host.test/enabled",
                nextCheckAt: 2_900_000_000)
            let disabled = try await seedRow(storage, graph, url: "http://host.test/disabled",
                nextCheckAt: 2_900_000_001, disabled: true)

            let jobs = try await batch(storage, now: now, options: .defaults)
            #expect(jobs == [job(enabled, graph, "http://host.test/enabled")])
            #expect(!jobs.contains(where: { $0.feedID == disabled }))
        }
    }

    @Test func aZeroBatchSizeAddsNoLimitAndAPositiveOneCapsTheRowsRead() async throws {
        try await withMigratedStorage { _, storage in
            let graph = try await seedGraph(storage, username: "alice")
            let first = try await seedRow(storage, graph, url: "http://host.test/first",
                nextCheckAt: 2_900_000_000)
            let second = try await seedRow(storage, graph, url: "http://host.test/second",
                nextCheckAt: 2_900_000_001)
            let third = try await seedRow(storage, graph, url: "http://host.test/third",
                nextCheckAt: 2_900_000_002)

            // Zero is the switch, not a cap: an implementation that reads it as a value writes
            // `LIMIT 0` and answers with nothing.
            let noCap = options(batchSize: 0, workerPoolSize: 16, parsingErrorLimit: 3,
                limitPerHost: 0)
            #expect(try await batch(storage, now: now, options: noCap) == [
                job(first, graph, "http://host.test/first"),
                job(second, graph, "http://host.test/second"),
                job(third, graph, "http://host.test/third"),
            ])

            // A positive size caps the rows read, in the order the clause puts them.
            let capped = options(batchSize: 1, workerPoolSize: 16, parsingErrorLimit: 3,
                limitPerHost: 0)
            #expect(try await batch(storage, now: now, options: capped) ==
                [job(first, graph, "http://host.test/first")])
        }
    }

    @Test func theHostFilterRunsOnlyOnTheRowsTheLimitReadAndNotOnAllRowsMatched() async throws {
        try await withMigratedStorage { _, storage in
            let graph = try await seedGraph(storage, username: "alice")
            let onFirstHost = try await seedRow(storage, graph, url: "http://first.test/a",
                nextCheckAt: 2_900_000_000)
            _ = try await seedRow(storage, graph, url: "http://first.test/b",
                nextCheckAt: 2_900_000_001)
            _ = try await seedRow(storage, graph, url: "http://first.test/c",
                nextCheckAt: 2_900_000_002)
            // The fourth row is past the cap: `LIMIT 3` reads only the three first rows, all on the
            // first host, so the host filter runs on those and skips two. An implementation that
            // filters before the limit would keep this row too.
            let onSecondHost = try await seedRow(storage, graph, url: "http://second.test/d",
                nextCheckAt: 2_900_000_003)

            let capped = options(batchSize: 3, workerPoolSize: 16, parsingErrorLimit: 3,
                limitPerHost: 1)
            let jobs = try await batch(storage, now: now, options: capped)
            #expect(jobs == [job(onFirstHost, graph, "http://first.test/a")])
            #expect(!jobs.contains(where: { $0.feedID == onSecondHost }))
        }
    }

    @Test func thePerHostLimitIsOffWhenItIsZero() async throws {
        try await withMigratedStorage { _, storage in
            let graph = try await seedGraph(storage, username: "alice")
            let first = try await seedRow(storage, graph, url: "http://one.test/a",
                nextCheckAt: 2_900_000_000)
            let second = try await seedRow(storage, graph, url: "http://one.test/b",
                nextCheckAt: 2_900_000_001)

            // The reference applies the filter only when the limit is above zero, so both rows are
            // kept. An implementation that reads zero as a value compares `hosts[h] >= 0` and
            // selects nothing.
            let off = options(batchSize: 100, workerPoolSize: 16, parsingErrorLimit: 3,
                limitPerHost: 0)
            #expect(try await batch(storage, now: now, options: off) == [
                job(first, graph, "http://one.test/a"),
                job(second, graph, "http://one.test/b"),
            ])
        }
    }

    @Test func theHostIsTheParsedHostWithItsPortAndTheWwwPrefixIsNotStripped() async throws {
        try await withMigratedStorage { _, storage in
            let graph = try await seedGraph(storage, username: "alice")
            let www = try await seedRow(storage, graph, url: "http://www.example.org/a",
                nextCheckAt: 2_900_000_000)
            let bare = try await seedRow(storage, graph, url: "http://example.org/b",
                nextCheckAt: 2_900_000_001)
            let withPort = try await seedRow(storage, graph, url: "http://example.org:8080/c",
                nextCheckAt: 2_900_000_002)

            // Three rows, one per host as `urllib.Domain` reads it. Stripping `www.` would make the
            // first equal the second, and reading the port-less `Hostname` would make the second
            // equal the third. With a per-host limit of 1, all three survive only when the three
            // hosts are distinct.
            let capped = options(batchSize: 100, workerPoolSize: 16, parsingErrorLimit: 3,
                limitPerHost: 1)
            #expect(try await batch(storage, now: now, options: capped) == [
                job(www, graph, "http://www.example.org/a"),
                job(bare, graph, "http://example.org/b"),
                job(withPort, graph, "http://example.org:8080/c"),
            ])
        }
    }

    @Test func anUnparseableURLCountsAsTheStringAsWritten() async throws {
        try await withMigratedStorage { _, storage in
            let graph = try await seedGraph(storage, username: "alice")
            // Go's parse fails on the unclosed bracket host, so `Domain` answers with the string as
            // it was written. The two unparseable rows are distinct strings that any parse-then-
            // normalize fallback would collapse to the same host — the bracketed host, or a value
            // that drops the query — and the third row's parsed host is `[::1]`. All three survive
            // the limit of 1 only while the fallback answers with the string as written.
            let unparseable = try await seedRow(storage, graph,
                url: "https://[::1?utm_source=mail", nextCheckAt: 2_900_000_000)
            let unparseableToo = try await seedRow(storage, graph, url: "https://[::1",
                nextCheckAt: 2_900_000_001)
            let bracketed = try await seedRow(storage, graph, url: "https://[::1]/feed",
                nextCheckAt: 2_900_000_002)

            let capped = options(batchSize: 100, workerPoolSize: 16, parsingErrorLimit: 3,
                limitPerHost: 1)
            #expect(try await batch(storage, now: now, options: capped) == [
                job(unparseable, graph, "https://[::1?utm_source=mail"),
                job(unparseableToo, graph, "https://[::1"),
                job(bracketed, graph, "https://[::1]/feed"),
            ])
        }
    }

    @Test func theBatchIsNotScopedToTheUser() async throws {
        try await withMigratedStorage { _, storage in
            let alice = try await seedGraph(storage, username: "alice")
            let bob = try await seedGraph(storage, username: "bob")
            let aliceFeed = try await seedRow(storage, alice, url: "http://host.test/alice",
                nextCheckAt: 2_900_000_000)
            let bobFeed = try await seedRow(storage, bob, url: "http://host.test/bob",
                nextCheckAt: 2_900_000_001)

            // `feedScheduler` calls no `WithUserID`, so each job carries the user of its own row.
            #expect(try await batch(storage, now: now, options: .defaults) == [
                job(aliceFeed, alice, "http://host.test/alice"),
                job(bobFeed, bob, "http://host.test/bob"),
            ])
        }
    }

    @Test func theJobCarriesTheStoredFeedURLAndNotTheSiteURL() async throws {
        try await withMigratedStorage { _, storage in
            let graph = try await seedGraph(storage, username: "alice")
            let feedID = try await seedRow(storage, graph, url: "http://host.test/feed",
                nextCheckAt: 2_900_000_000)

            // The builder selects the `url` column; the site URL the row holds after a parse
            // names a different host, so the expected job can tell the two readings apart.
            try await storage.withConnection { connection in
                try await sqlDatabase(connection).raw("""
                    UPDATE feeds SET site_url = \(bind: "https://site.test")
                    WHERE id = \(bind: feedID)
                    """).run()
            }

            #expect(try await batch(storage, now: now, options: .defaults) ==
                [job(feedID, graph, "http://host.test/feed")])
        }
    }

    // MARK: - Helpers

    private func options(batchSize: Int, workerPoolSize: Int, parsingErrorLimit: Int,
        limitPerHost: Int) -> SchedulerOptions {
        SchedulerOptions(pollingFrequency: .seconds(60), batchSize: batchSize,
            workerPoolSize: workerPoolSize, parsingErrorLimit: parsingErrorLimit,
            limitPerHost: limitPerHost)
    }

    /// The expected job for a row, in the order the batch query scans the reference's `model.Job`.
    private func job(_ feedID: Int, _ graph: (userID: Int, categoryID: Int), _ url: String)
        -> RefreshJob {
        RefreshJob(feedID: feedID, userID: graph.userID, feedURL: url)
    }

    private func seedGraph(_ storage: SQLiteStorage, username: String) async throws
        -> (userID: Int, categoryID: Int) {
        try await storage.withConnection { connection in
            let userID = try await seedUser(connection, username: username)
            let categoryID = try await seedCategory(connection, userID: userID, title: "Tech")
            return (userID, categoryID)
        }
    }

    /// Seeds one feed row with the values the batch reads. The row is created due at the process
    /// clock, so every pin that reads due-ness sets its own schedule through the same checkout.
    private func seedRow(_ storage: SQLiteStorage, _ graph: (userID: Int, categoryID: Int),
        url: String, nextCheckAt: Int, errorCount: Int = 0, disabled: Bool = false) async throws
        -> Int {
        try await storage.withConnection { connection in
            let feedID = try await seedFeed(connection, userID: graph.userID,
                categoryID: graph.categoryID, url: url)
            try await sqlDatabase(connection).raw("""
                UPDATE feeds SET next_check_at = \(bind: nextCheckAt),
                    parsing_error_count = \(bind: errorCount), disabled = \(bind: disabled)
                WHERE id = \(bind: feedID)
                """).run()
            return feedID
        }
    }

    private func batch(_ storage: SQLiteStorage, now: Int, options: SchedulerOptions)
        async throws -> [RefreshJob] {
        try await storage.withConnection { connection in
            try await FeedRepository(connection).dueBatch(now: now, options: options)
        }
    }
}