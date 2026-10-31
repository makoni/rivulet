import Fluent
import Foundation
import SQLKit
import Testing
@testable import RivuletCore

/// The refresh pipeline for one feed: the seam where the fetcher, the parser, the sanitizer and the
/// storage layer meet — the caller `docs/plan/stage-2-fetching.md` left open for the fetch result
/// and the error state.  Every expected value is the reference's behavior, read from
/// `internal/reader/handler/handler.go` (`RefreshFeed`), `internal/model/feed.go` (`CheckedNow`,
/// `ScheduleNextCheck`), `internal/reader/processor/processor.go` and
/// `internal/reader/urlcleaner/urlcleaner.go` at commit `c4d54f87`, not this implementation's, so a
/// failure here is a difference in the port and `docs/parity.md` is the only way a difference can
/// stay. The clock is injected, so every stamp a pin reads is the injected instant, which the
/// process clock could not produce.  What these tests can fail on, checked by patching each rule
/// and reverting: the entry processing order, the sanitizer base, the tracking-parameter rule and
/// the hash taken before the cleaner runs, the validator storage on each of the three paths, the
/// error counter on both sides, the conditional-hit rule, the schedule computed before the answer
/// is read, the delay that wins over the interval, the source of the interval, the force-refresh
/// rule, the entry-update branch, the stored feed URL in the outbound rule, the user scope, the
/// date fallback, the stored site URL, and that
/// the failure record is committed rather than rolled back with the entry batch.  What they cannot
/// fail on: the wording of a recorded message, because Rivulet has no locale keys, so a pin
/// compares the error case and the counter, not the text; the single write transaction itself,
/// because nothing here can make one statement inside it fail while the others succeed; the
/// entry-frequency scheduler, which this slice does not read; the two columns the reference gates
/// the entry-update branch on, which the schema does not have; the user rules the reference applies
/// in its processor — filters, rewrite, scraping — which the plan puts in later stages; and the
/// duplicate check, the icon checker and the reading time, which land with those stages. Nothing
/// here sleeps or polls.
@Suite struct RefreshPipelineTests {
    /// The instant every stamp is read from, so a pin can tell the injected clock from the process
    /// one.
    private let now = 1_700_000_000
    private let policy = NextCheckPolicy()

    @Test func entriesLandSanitizedAndIndexedAndWriteNothingWithoutModification() async throws {
        try await withCase(behaviors: ["/feed": answer(rss([
            ("<p>Hello</p><script>alert(1)</script>", "https://example.org/a"),
            ("<p>Second</p>", "https://example.org/b"),
        ]))]) { _, storage, userID, feedID, pipeline in
            let outcome = try await pipeline.refresh(userID: userID, feedID: feedID)

            #expect(outcome.conditionalHit == false)
            #expect(outcome.newEntryHashes.count == 2)
            #expect(outcome.updatedEntryHashes.isEmpty)
            #expect(outcome.nextCheckAt == now + 3600)

            let rows = try await storedRows(storage, feedID: feedID)
            #expect(rows.count == 2)

            // The reference processes the entries oldest first, so the entry the document declared
            // second is the one stored first. Read through the ids, which follow the insert order:
            // the storage clock is not a seam here, so `created_at` cannot show this.
            #expect(rows.map(\.url) == ["https://example.org/b", "https://example.org/a"])

            // The reference sanitizes what each entry carries before the storage layer sees it,
            // and the repository indexes the plain text of the stored HTML. The sanitizer's own
            // corpus pins its output shape; this pins that the pipeline runs it on the content as
            // the reference read it.
            #expect(rows.allSatisfy { !$0.content.contains("script") })
            #expect(rows.map(\.contentText) == ["Second", "Hello"])

            // An entry with no date carries the injected clock, not the process one.
            #expect(rows.map(\.publishedAt) == [now, now])

            // The reference compares the answer with the stored validators: when the ETag matches,
            // the not-modified branch writes no entries, so a second plain refresh writes nothing.
            let second = try await pipeline.refresh(userID: userID, feedID: feedID)
            #expect(second.newEntryHashes.isEmpty)
            #expect(second.updatedEntryHashes.isEmpty)
            #expect(try await entryCount(storage, feedID: feedID) == 2)

            // The reference updates a known entry when the entry-update gate is open. The forced
            // path always opens it, and the two columns the gate otherwise reads (`crawler`,
            // `ignore_entry_updates`) are not in this port's schema, so the gate is open on every
            // path, as `docs/parity.md` records; the forced case is the one that reports the
            // branch.
            let forced = try await pipeline.refresh(userID: userID, feedID: feedID,
                forceRefresh: true)
            #expect(forced.newEntryHashes.isEmpty)
            #expect(forced.updatedEntryHashes.count == 2)
            #expect(try await entryCount(storage, feedID: feedID) == 2)
        }
    }

    @Test func theSanitizerResolvesARelativeLinkAgainstTheEntryURLNotTheFeedURL() async throws {
        try await withCase(behaviors: ["/feed": answer(rss([
            ("<p><a href=\"/post/1\">link</a></p>", "https://posts.example.org/a"),
        ]))]) { _, storage, userID, feedID, pipeline in
            _ = try await pipeline.refresh(userID: userID, feedID: feedID)

            // The reference sanitizes each entry with the entry URL as the base, so the link
            // resolves against the entry host rather than the host the feed declares.
            let row = try #require(await storedRows(storage, feedID: feedID).first)
            #expect(row.content.contains("https://posts.example.org/post/1"))
        }
    }

    @Test func trackingParametersAreRemovedAndAnUnparseableURLIsStoredAsWritten() async throws {
        try await withCase(behaviors: ["/feed": answer(rss([
            ("<p>A</p>", "https://example.org/a?utm_source=mail&id=7"),
            ("<p>B</p>", "https://[::1?utm_source=mail"),
        ]))]) { _, storage, userID, feedID, pipeline in
            _ = try await pipeline.refresh(userID: userID, feedID: feedID)

            // Go's parse fails on an unclosed bracket host, so the cleaner returns an error and
            // the reference keeps the URL as the feed wrote it. The rows read through the ids come
            // in the order the reversed entry loop wrote them, the same order the hash pin below
            // reads.
            let rows = try await storedRows(storage, feedID: feedID)
            #expect(rows.map(\.url) == [
                "https://[::1?utm_source=mail",
                "https://example.org/a?id=7",
            ])

            // The hash is the adapter's, taken from the URL as the feed wrote it: the reference
            // hashes the entry before the cleaner runs, so cleaning cannot change the identity.
            #expect(rows.map(\.hash) == [
                Hashes.sha256("https://[::1?utm_source=mail"),
                Hashes.sha256("https://example.org/a?utm_source=mail&id=7"),
            ])
        }
    }

    @Test func theOutboundRuleComparesAgainstTheStoredFeedURLNotTheParsedOne() async throws {
        try await withCase(behaviors: ["/feed": answer(rss(
            [("<p>A</p>", "https://example.org/a?ref=127.0.0.1&x=1")],
            selfLink: "https://self.example/feed.xml"
        ))]) { _, storage, userID, feedID, pipeline in
            // The channel `atom:link` with `rel="self"` makes the parse report a feed URL on one
            // host, the stored row holds another, and the stored site URL is a third. The
            // reference compares the entry query against the host of the stored feed URL, so the
            // `ref` pair is dropped, and an implementation that read the parse's feed URL would
            // keep it. The host is the stub server's, so the value can only match the row.
            try await setSiteURL(storage, feedID: feedID, value: "https://site.example")
            _ = try await pipeline.refresh(userID: userID, feedID: feedID)

            let row = try #require(await storedRows(storage, feedID: feedID).first)
            #expect(row.url == "https://example.org/a?x=1")
        }
    }

    @Test func theStoredTitleSurvivesARefreshAndAnEmptySiteURLFallsBackToTheFeedURL() async throws {
        try await withCase(behaviors: ["/feed": answer(rss(
            [("<p>A</p>", "https://example.org/a")], link: "https://parsed.example/"
        ))]) { server, storage, userID, feedID, pipeline in
            _ = try await pipeline.refresh(userID: userID, feedID: feedID)

            // `RefreshFeed` writes the title the row already held, not the one the parse produced,
            // and `CheckedNow` puts the feed URL in place of the empty site URL the row holds. The
            // channel link here is not empty, so the fallback answer can be told from the parsed
            // one: an implementation that stored the parse's site URL would answer
            // `https://parsed.example/`.
            let stored = try #require(await storedFeed(storage, feedID: feedID))
            #expect(stored.title == "")
            #expect(stored.siteURL == server.url("/feed").absoluteString)
        }
    }

    @Test func aFetchFailureRecordsTheErrorAndStoresNoneOfTheValidators() async throws {
        try await withCase(behaviors: ["/feed": StubFeedServer.Behavior(
            status: 500,
            headers: ["ETag": "\"response-etag\"", "Last-Modified": "Mon, 22 Oct 2026 10:00:00 GMT"]
        )]) { _, storage, userID, feedID, pipeline in
            try await storeValidators(storage, feedID: feedID, etag: "\"stored-etag\"",
                lastModified: "Fri, 16 Oct 2026 09:00:00 GMT")

            await #expect(throws: FetchError.status(500)) {
                try await pipeline.refresh(userID: userID, feedID: feedID)
            }

            // The failure path returns before the validators are stored, and the check time and
            // the schedule computed before the request are what the failure statement keeps.
            let stored = try #require(await storedFeed(storage, feedID: feedID))
            #expect(stored.etag == "\"stored-etag\"")
            #expect(stored.lastModified == "Fri, 16 Oct 2026 09:00:00 GMT")
            #expect(stored.parsingErrorCount == 1)
            #expect(stored.fetchedAt == now)
            #expect(stored.nextCheckAt == now + 3600)
            #expect(try await entryCount(storage, feedID: feedID) == 0)
        }
    }

    @Test func aConditionalHitStoresOnlyLastModifiedAndResetsTheErrorState() async throws {
        try await withCase(behaviors: ["/feed": StubFeedServer.Behavior(
            status: 304,
            headers: ["ETag": "\"response-etag\"", "Last-Modified": "Mon, 22 Oct 2026 10:00:00 GMT"]
        )]) { _, storage, userID, feedID, pipeline in
            try await storeValidators(storage, feedID: feedID, etag: "\"stored-etag\"",
                lastModified: "Fri, 16 Oct 2026 09:00:00 GMT", errorCount: 2)

            // RFC9111 as the reference reads it: on a conditional hit the Last-Modified header can
            // be stored while the ETag stays as the row holds it, and the body is never read.
            let outcome = try await pipeline.refresh(userID: userID, feedID: feedID)
            #expect(outcome.conditionalHit)
            #expect(outcome.newEntryHashes.isEmpty)
            #expect(outcome.nextCheckAt == now + 3600)

            let stored = try #require(await storedFeed(storage, feedID: feedID))
            #expect(stored.etag == "\"stored-etag\"")
            #expect(stored.lastModified == "Mon, 22 Oct 2026 10:00:00 GMT")
            #expect(stored.parsingErrorCount == 0)
        }
    }

    @Test func aParseFailureKeepsTheScheduleComputedBeforeTheRequest() async throws {
        try await withCase(behaviors: ["/feed": answer("not a feed", headers: [
            "ETag": "\"stub-etag\"", "Cache-Control": "max-age=7200",
        ])]) { _, storage, userID, feedID, pipeline in
            try await storeValidators(storage, feedID: feedID, etag: "\"stored-etag\"",
                lastModified: "Fri, 16 Oct 2026 09:00:00 GMT")

            await #expect(throws: ParserError.feedFormatNotDetected) {
                try await pipeline.refresh(userID: userID, feedID: feedID)
            }

            // The delay the answer carries is read only after the parse succeeds, so the schedule
            // stands as it was computed before the request, and the failure record is committed
            // although the transaction that would have written the entries wrote none.
            let stored = try #require(await storedFeed(storage, feedID: feedID))
            #expect(stored.parsingErrorCount == 1)
            #expect(stored.etag == "\"stored-etag\"")
            #expect(stored.nextCheckAt == now + 3600)
        }
    }

    @Test func theRetryDelayWinsWhenAboveTheIntervalAndOtherwiseTheIntervalWins() async throws {
        try await withCase(behaviors: [
            "/above": StubFeedServer.Behavior(status: 429, headers: ["Retry-After": "7200"]),
            "/below": StubFeedServer.Behavior(status: 429, headers: ["Retry-After": "600"]),
        ]) { server, storage, userID, _, pipeline in
            // `categories` is unique per user and title, so the category is seeded once per test.
            let categoryID = try await existingCategory(storage, userID: userID, title: "Tech")
            for (path, minutes) in [("/above", 120), ("/below", 60)] {
                let feedID = try await seedFeedOn(storage, server.url(path).absoluteString,
                    userID: userID, categoryID: categoryID)

                await #expect(throws: FetchError.status(429)) {
                    try await pipeline.refresh(userID: userID, feedID: feedID)
                }

                let stored = try #require(await storedFeed(storage, feedID: feedID))
                #expect(stored.nextCheckAt == now + minutes * 60, "\(path)")
                #expect(stored.parsingErrorCount == 1, "\(path)")
            }
        }
    }

    @Test func theIntervalComesFromThePolicyAndNotFromTheStoredCheckInterval() async throws {
        try await withCase(behaviors: ["/feed": answer(rss([
            ("<p>A</p>", "https://example.org/a"),
        ]))]) { _, storage, userID, feedID, pipeline in
            // Rivulet stores a per-feed interval the reference model does not have, recorded in
            // `docs/parity.md`, and the reference starts from the configured minimum every time,
            // so a stored value that disagrees with the policy must not decide the schedule here.
            try await setCheckInterval(storage, feedID: feedID, value: 240)

            let outcome = try await pipeline.refresh(userID: userID, feedID: feedID)
            #expect(outcome.nextCheckAt == now + 3600)
        }
    }

    @Test func forceRefreshSendsNoStoredValidatorsAndResetsTheErrorCounter() async throws {
        try await withCase(behaviors: ["/feed": answer(rss([
            ("<p>A</p>", "https://example.org/a"),
        ]))]) { server, storage, userID, feedID, pipeline in
            try await storeValidators(storage, feedID: feedID, etag: "\"stored-etag\"",
                lastModified: "Fri, 16 Oct 2026 09:00:00 GMT", errorCount: 3)
            _ = try await pipeline.refresh(userID: userID, feedID: feedID, forceRefresh: true)

            // The forced path is the one `rivulet refresh` takes: it sends no stored validators,
            // so the answer cannot be a conditional hit, and its end resets the error counter.
            let sent = try #require(server.received(for: "/feed").first)
            #expect(sent.headers["If-None-Match"] == nil)
            #expect(sent.headers["If-Modified-Since"] == nil)

            let stored = try #require(await storedFeed(storage, feedID: feedID))
            #expect(stored.parsingErrorCount == 0)
        }
    }

    @Test func aRefreshOfAnotherUsersFeedIsTheTypedErrorAndWritesNothing() async throws {
        try await withCase(behaviors: ["/feed": answer(rss([
            ("<p>A</p>", "https://example.org/a"),
        ]))]) { server, storage, userID, feedID, pipeline in
            // The feed belongs to the seeded user, and the pipeline is called as another one.
            let otherUser = try await seedUserOn(storage, username: "bob")
            await #expect(throws: StorageError.feedNotFound(id: feedID)) {
                try await pipeline.refresh(userID: otherUser, feedID: feedID)
            }

            // `RefreshFeed` reads the row through `FeedByID`, which is scoped to the user, and the
            // not-found case returns before the counter is touched, so nothing is fetched or
            // written.
            #expect(server.received(for: "/feed").isEmpty)
            let stored = try #require(await storedFeed(storage, feedID: feedID))
            #expect(stored.parsingErrorCount == 0)
            #expect(stored.fetchedAt == nil)
        }
    }

    @Test func theFeedTTLWinsOverTheIntervalAndCacheControlWinsOverTheTTL() async throws {
        try await withCase(behaviors: [
            "/ttl": answer(rss([("<p>A</p>", "https://example.org/a")], ttl: 90)),
            "/short": answer(rss([("<p>A</p>", "https://example.org/a")], ttl: 30),
                headers: ["ETag": "\"stub-etag\""]),
            "/maxage": answer(rss([("<p>A</p>", "https://example.org/a")], ttl: 30),
                headers: ["ETag": "\"stub-etag\"", "Cache-Control": "max-age=7200"]),
            "/expires": answer(rss([("<p>A</p>", "https://example.org/a")], ttl: 30),
                headers: ["ETag": "\"stub-etag\"", "Expires": "Tue, 14 Nov 2023 23:43:20 GMT"]),
        ]) { server, storage, userID, _, pipeline in
            // The delay is the largest of the sources, and the interval wins when it is larger:
            // the reference takes `max(ttl, max-age, expires)` and then `max(interval, delay)`.
            // The four paths answer four different numbers, so the outcome cannot be right on all
            // four unless each source is read and the interval can win. The `Expires` header is the
            // injected instant plus ninety minutes, and the reference adds the current minute to
            // `Until(now).Truncate(minute)`, which is how `FetchResponse.expires` reads it.
            let categoryID = try await existingCategory(storage, userID: userID, title: "Tech")
            for (path, minutes) in [("/ttl", 90), ("/short", 60), ("/maxage", 120),
                ("/expires", 91)] {
                let feedID = try await seedFeedOn(storage, server.url(path).absoluteString,
                    userID: userID, categoryID: categoryID)
                let outcome = try await pipeline.refresh(userID: userID, feedID: feedID)
                #expect(outcome.nextCheckAt == now + minutes * 60, "\(path)")
            }
        }
    }

    // MARK: - Helpers

    /// One case: the server answers each path, the feed row points at `/feed`, and the test reads
    /// what the pipeline stored. Both the server and the database are started for this test only,
    /// as `docs/testing.md` requires. The connection is not held across `refresh`: the pipeline
    /// opens the single write transaction its own, so a test that held a checkout would nest a
    /// second one, which the single pooled connection cannot serve.
    private func withCase(
        behaviors: [String: StubFeedServer.Behavior],
        _ body: (StubFeedServer, SQLiteStorage, Int, Int, RefreshPipeline) async throws -> Void
    ) async throws {
        let options = FetchTestSupport.options()
        try await withMigratedStorage { _, storage in
            try await FetchTestSupport.withServer(behaviors: behaviors) { server in
                try await FetchTestSupport.withFetcher(options: options) { fetcher in
                    let (userID, _, feedID) = try await storage.withConnection { connection in
                        try await seedFeed(connection, feedURL: server.url("/feed").absoluteString)
                    }
                    let pipeline = RefreshPipeline(storage: storage, fetcher: fetcher,
                        options: options, nextCheck: policy, clock: FixedClock(now: now))
                    try await body(server, storage, userID, feedID, pipeline)
                }
            }
        }
    }

    /// One RSS document with the entries as the test names them, in the order the document declares
    /// them. The entry text is written as escaped text, which is what the reference's reader
    /// reports as content. A `selfLink` writes the `atom:link` with `rel="self"`, which the RSS
    /// adapter reads for the feed URL itself.
    private func rss(_ entries: [(content: String, url: String)],
        link: String = "https://example.org/", ttl: Int = 0, selfLink: String = "") -> String {
        var document = "<rss version=\"2.0\" xmlns:atom=\"http://www.w3.org/2005/Atom\">"
        document += "<channel><title>Parsed Title</title><link>\(link)</link>"
        if ttl > 0 { document += "<ttl>\(ttl)</ttl>" }
        if !selfLink.isEmpty {
            document += "<atom:link rel=\"self\" href=\"\(selfLink)\"></atom:link>"
        }
        if ttl > 0 { document += "<ttl>\(ttl)</ttl>" }
        for entry in entries {
            let text = entry.content.replacing("<", with: "&lt;").replacing(">", with: "&gt;")
            document += "<item><title>Entry</title><link>\(entry.url)</link>"
                + "<description>\(text)</description></item>"
        }
        return document + "</channel></rss>"
    }

    private func answer(_ body: String, headers: [String: String] = ["ETag": "\"stub-etag\""])
        -> StubFeedServer.Behavior {
        StubFeedServer.Behavior(headers: headers, body: Data(body.utf8))
    }

    /// The id of the category the helper seeded for the user, read rather than created: the table
    /// is unique per user and title, so the loop tests reuse it for each of their feeds.
    private func existingCategory(_ storage: SQLiteStorage, userID: Int, title: String)
        async throws -> Int {
        try await storage.withConnection { connection in
            let categories = try await CategoryRepository(connection).list(userID: userID)
            return try #require(categories.first { $0.title == title }?.id)
        }
    }

    /// Seeds a user on its own checkout, for the test that calls the pipeline as another user.
    private func seedUserOn(_ storage: SQLiteStorage, username: String) async throws -> Int {
        try await storage.withConnection { connection in
            try await seedUser(connection, username: username)
        }
    }

    /// Seeds a feed that points at `feedURL`, for the cases that need one per path.
    private func seedFeedOn(_ storage: SQLiteStorage, _ feedURL: String, userID: Int,
        categoryID: Int) async throws -> Int {
        try await storage.withConnection { connection in
            try await seedFeed(connection, userID: userID, categoryID: categoryID, url: feedURL)
        }
    }

    /// The validators and the error state as a previous refresh left them.
    private func storeValidators(_ storage: SQLiteStorage, feedID: Int, etag: String,
        lastModified: String, errorCount: Int = 0) async throws {
        try await storage.withConnection { connection in
            let feed = try #require(await FeedRepository(connection).fetch(id: feedID))
            feed.etag = etag
            feed.lastModified = lastModified
            feed.parsingErrorCount = errorCount
            try await feed.update(on: connection)
        }
    }

    /// Writes a stored site URL on a host the feed URL does not have, for the case that needs the
    /// two halves of the outbound rule to name different hosts.
    private func setSiteURL(_ storage: SQLiteStorage, feedID: Int, value: String) async throws {
        try await storage.withConnection { connection in
            let feed = try #require(await FeedRepository(connection).fetch(id: feedID))
            feed.siteURL = value
            try await feed.update(on: connection)
        }
    }

    /// Writes a stored per-feed interval that disagrees with the policy, the way the reference
    /// stores one it never reads on this path.
    private func setCheckInterval(_ storage: SQLiteStorage, feedID: Int, value: Int) async throws {
        try await storage.withConnection { connection in
            let feed = try #require(await FeedRepository(connection).fetch(id: feedID))
            feed.checkInterval = value
            try await feed.update(on: connection)
        }
    }

    private func storedFeed(_ storage: SQLiteStorage, feedID: Int) async throws -> Feed? {
        try await storage.withConnection { connection in
            try await FeedRepository(connection).fetch(id: feedID)
        }
    }

    private struct StoredRow {
        let id: Int
        let hash: String
        let url: String
        let content: String
        let contentText: String
        let publishedAt: Int
    }

    private func storedRows(_ storage: SQLiteStorage, feedID: Int) async throws -> [StoredRow] {
        try await storage.withConnection { connection in
            let rows = try await RawSQL.sql(on: connection).raw("""
                SELECT id, hash, url, content, content_text, published_at FROM entries
                WHERE feed_id = \(bind: feedID) ORDER BY id
                """).all()
            return try rows.map { row in
                StoredRow(
                    id: try row.decode(column: "id", as: Int.self),
                    hash: try row.decode(column: "hash", as: String.self),
                    url: try row.decode(column: "url", as: String.self),
                    content: try row.decode(column: "content", as: String.self),
                    contentText: try row.decode(column: "content_text", as: String.self),
                    publishedAt: try row.decode(column: "published_at", as: Int.self)
                )
            }
        }
    }

    private func entryCount(_ storage: SQLiteStorage, feedID: Int) async throws -> Int {
        try await storage.withConnection { connection in
            let row = try await RawSQL.sql(on: connection).raw("""
                SELECT COUNT(*) AS n FROM entries WHERE feed_id = \(bind: feedID)
                """).first()
            return try row?.decode(column: "n", as: Int.self) ?? 0
        }
    }
}
