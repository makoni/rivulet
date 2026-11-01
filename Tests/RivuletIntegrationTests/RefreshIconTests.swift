import Fluent
import Foundation
import Testing
@testable import RivuletCore

/// The call the refresh path makes for one feed, in the reference's order (`RefreshFeed`,
/// `internal/reader/icon/checker.go` and `internal/reader/handler/handler.go` at commit
/// `c4d54f87`): the entry loop, then the checker for the feed, then the validators.
/// `IconCheckerTests` pins the checker's own half; these pins are the wiring — which branch
/// calls it, which fork the flag selects, and which values the pipeline hands it. The values
/// are read from the stored row, because the reference's checker runs on the row it read, not
/// on a copy of the parse.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the checker
/// runs on the modified branch only, so a patch that does not call it at all fails the pins
/// that read what the modified branch writes, and a patch that calls it on the conditional-hit
/// branch fails the pin that reads a hit against a stored validator; the fork is the forced
/// flag, so a patch that takes the other fork on the forced path fails the pin that reads a
/// feed with an existing mapping being moved, and a patch that applies the guard to the forced
/// path fails the same pin from the other side; the icon URL is the value the parse produced,
/// which a patch that reads the scan's answer instead fails, because the parse's path and the
/// scan's path are given different bytes on the stub server; and the site URL and the user
/// agent are read from the row, which a patch that hands the checker the parse's site URL or
/// nothing at all fails, because the row's site URL is a path the server answers for while the
/// parse's link names a host it does not. The pins read the stored mapping and the row it
/// points at, which is the only place the checker's two decisions can be read.
///
/// What they cannot fail on: the order of the statements inside the transaction, because the pins
/// read what the commit left rather than the order the writes happened in, so the checker running
/// before the error counter is reset and before the validators are written cannot be shown; the
/// reference's logging, which this port has no layer for; the failure path, which
/// `RefreshPipelineTests` pins as writing the error record, so no case here can reach the
/// checker on it; the checker's builder half — cookie, timeout, proxy, TLS and HTTP2 —
/// documented as deferred in `docs/reference-notes.md`; the size cap, the checksum function and
/// the content-type normalization, which the fetch and storage suites pin and these pins read
/// only as the values the checker passes on; the guard read that itself fails, which the
/// checker suite names as unpinnable; the empty-site fallback, which `RefreshPipelineTests`
/// pins as the storage rule; and that the user agent falls back to the default when the row
/// carries none, which is the builder's rule. Nothing here sleeps or polls.
@Suite struct RefreshIconTests {
    private let now = 1_700_000_000
    private let policy = NextCheckPolicy()

    @Test func theModifiedBranchRunsTheCheckerAndTheConditionalHitBranchDoesNot() async throws {
        // The scan path is the one the guard does not stop, so a request on it and a row written
        // through it show that the checker ran. The first case is read on the modified branch; the
        // second, where the answer is a hit against the validator the row holds, is read on the
        // branch the reference does not call the checker on.
        let scanAnswer = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let scanDocument = Data("<html><link rel=\"icon\" href=\"/logo.png\"></html>".utf8)

        try await withCase(behaviors: [
            "/feed": answer(feedDocument),
            "/doc": document(body: scanDocument),
            "/logo.png": document(contentType: "image/png", body: scanAnswer),
        ], sitePath: "/doc") { server, storage, userID, feedID, pipeline, _ in
            _ = try await pipeline.refresh(userID: userID, feedID: feedID)

            #expect(server.received(for: "/doc").count == 1)

            let mapping = try #require(await storedIconID(storage, feedID: feedID))
            let icon = try #require(await storedIcon(storage, iconID: mapping))
            #expect(icon.content == scanAnswer)
        }

        try await withCase(behaviors: [
            "/feed": document(status: 304, contentType: "application/rss+xml", body: Data()),
            "/doc": document(body: scanDocument),
            "/logo.png": document(contentType: "image/png", body: scanAnswer),
        ], sitePath: "/doc", storedValidator: "\"stub-etag\"") { server, storage, userID, feedID,
            pipeline, _ in
            _ = try await pipeline.refresh(userID: userID, feedID: feedID)

            // The scan could have answered here, so the absence of the request and
            // of the row is what shows the branch.
            #expect(server.received(for: "/feed").count == 1)
            #expect(server.received(for: "/doc").isEmpty)

            let rows = try await storedIconCount(storage)
            #expect(rows == 0)
            let mapping = try await storedIconID(storage, feedID: feedID)
            #expect(mapping == nil)
        }
    }

    @Test func theIconURLIsTheValueTheParseProducedNotTheOneTheScanFinds() async throws {
        // The channel image names one path and the document scan answers from another, so the bytes
        // the row holds name which value the checker was given. Both paths are answered, so a patch
        // that reads the scan's answer changes the stored bytes and adds the request the
        // pin says is not made.
        let parseAnswer = Data([1, 2, 3])
        let scanAnswer = Data([4, 5, 6])
        let scanDocument = Data("<html><link rel=\"icon\" href=\"/from-scan.png\"></html>".utf8)

        try await withCase(behaviors: [
            "/feed": answer("""
                <rss version="2.0"><channel><title>Parsed Title</title><link></link>
                <image><url>/from-parse.png</url></image>
                <item><title>Entry</title><link>https://example.org/a</link>
                <description>Entry text</description></item></channel></rss>
                """),
            "/doc": document(body: scanDocument),
            "/from-parse.png": document(contentType: "image/png", body: parseAnswer),
            "/from-scan.png": document(contentType: "image/png", body: scanAnswer),
        ], sitePath: "/doc") { server, storage, userID, feedID, pipeline, _ in
            _ = try await pipeline.refresh(userID: userID, feedID: feedID)

            #expect(server.received(for: "/from-scan.png").isEmpty)

            let mapping = try #require(await storedIconID(storage, feedID: feedID))
            let icon = try #require(await storedIcon(storage, iconID: mapping))
            #expect(icon.content == parseAnswer)
        }
    }

    @Test func theGuardRunsOnTheNonForcedBranchAndTheForcedBranchMovesTheMapping() async throws {
        let existing = Data([1, 2, 3])
        let scanAnswer = Data([4, 5, 6])
        let scanDocument = Data("<html><link rel=\"icon\" href=\"/logo.png\"></html>".utf8)

        try await withCase(behaviors: [
            "/feed": answer(feedDocument),
            "/doc": document(body: scanDocument),
            "/logo.png": document(contentType: "image/png", body: scanAnswer),
        ], sitePath: "/doc",
            prepare: { connection, feedID in
                return try await seedStoredIcon(connection, feedID: feedID, content: existing)
            }) { server, storage, userID, feedID, pipeline, preparedIconID in
            _ = try await pipeline.refresh(userID: userID, feedID: feedID)

            // The guard reads the mapping, so the feed already pointing at an icon is not searched
            // and the mapping it holds is not moved.
            #expect(server.received(for: "/doc").isEmpty)
            let mapping = try #require(await storedIconID(storage, feedID: feedID))
            #expect(mapping == preparedIconID)
        }

        try await withCase(behaviors: [
            "/feed": answer(feedDocument),
            "/doc": document(body: scanDocument),
            "/logo.png": document(contentType: "image/png", body: scanAnswer),
        ], sitePath: "/doc",
            prepare: { connection, feedID in
                return try await seedStoredIcon(connection, feedID: feedID, content: existing)
            }) { server, storage, userID, feedID, pipeline, preparedIconID in
            _ = try await pipeline.refresh(userID: userID, feedID: feedID, forceRefresh: true)

            // The fork the flag selects has no guard, so the same feed is searched
            // and the mapping it already held is moved to the row the search
            // answered with.
            #expect(server.received(for: "/doc").count == 1)

            let mapping = try #require(await storedIconID(storage, feedID: feedID))
            #expect(mapping != preparedIconID)
            let icon = try #require(await storedIcon(storage, iconID: mapping))
            #expect(icon.content == scanAnswer)
        }
    }

    @Test func theCheckerReadsTheSiteURLAndTheUserAgentFromTheRow() async throws {
        // The row's site URL is a path this server answers, and the channel link the parse produces
        // names a host it does not, so the request shows which value the checker was given. The
        // header is the only place the user agent can be read.
        let scanDocument = Data("<html><link rel=\"icon\" href=\"/logo.png\"></html>".utf8)
        try await withCase(behaviors: [
            "/feed": answer("""
                <rss version="2.0"><channel><title>Parsed Title</title>
                <link>https://parsed.example/</link>
                <item><title>Entry</title><link>https://example.org/a</link>
                <description>Entry text</description></item></channel></rss>
                """),
            "/doc": document(body: scanDocument),
            "/logo.png": document(contentType: "image/png", body: Data([1, 2, 3])),
        ], sitePath: "/doc", userAgent: "rivulet-refresh-pin") { server, storage, userID, feedID,
            pipeline, _ in
            _ = try await pipeline.refresh(userID: userID, feedID: feedID)

            let sent = try #require(server.received(for: "/doc").first)
            #expect(sent.headers["User-Agent"] == "rivulet-refresh-pin")

            let mapping = try #require(await storedIconID(storage, feedID: feedID))
            let icon = try #require(await storedIcon(storage, iconID: mapping))
            #expect(icon.content == Data([1, 2, 3]))
        }
    }

    // MARK: - Helpers

    /// One case: the server answers each path, the feed row holds the site URL, the user
    /// agent and the validator the test names, and the test reads what the refresh stored.
    /// Both the server and the database are started for this test only, as
    /// `docs/testing.md` requires, and the connection is not held across `refresh`: the
    /// pipeline opens its single write transaction, which the single pooled connection
    /// cannot serve from inside a checkout of its own.
    private func withCase(
        behaviors: [String: StubFeedServer.Behavior],
        sitePath: String = "",
        userAgent: String = "",
        storedValidator: String = "",
        prepare: (@Sendable (any Database, Int) async throws -> Int?)? = nil,
        _ body: @escaping @Sendable (StubFeedServer, SQLiteStorage, Int, Int, RefreshPipeline, Int)
            async throws -> Void
    ) async throws {
        let options = FetchTestSupport.options()
        try await withMigratedStorage { _, storage in
            try await FetchTestSupport.withServer(behaviors: behaviors) { server in
                try await FetchTestSupport.withFetcher(options: options) { fetcher in
                    // One checkout for the setup, released before `refresh` opens the single write
                    // transaction, which the pooled connection cannot serve
                    // from inside a checkout of its own.
                    let seeded = try await storage.withConnection { connection in
                        let userID = try await seedUser(connection)
                        let categoryID = try await seedCategory(connection, userID: userID,
                            title: "Tech")
                        let feedID = try await seedFeed(connection, userID: userID,
                            categoryID: categoryID, url: server.url("/feed").absoluteString)

                        let feed = try #require(await FeedRepository(connection).fetch(id: feedID))
                        if !sitePath.isEmpty { feed.siteURL = server.url(sitePath).absoluteString }
                        if !userAgent.isEmpty { feed.userAgent = userAgent }

                        // The validator a previous refresh left on the
                        // row, so the case that needs a conditional hit
                        // has something to compare against.
                        if !storedValidator.isEmpty { feed.etag = storedValidator }
                        try await feed.update(on: connection)

                        let prepared = try await prepare?(connection, feedID) ?? 0
                        return (userID, feedID, prepared)
                    }

                    let pipeline = RefreshPipeline(storage: storage, fetcher: fetcher,
                        options: options, nextCheck: policy, clock: FixedClock(now: now))
                    try await body(server, storage, seeded.0, seeded.1, pipeline, seeded.2)
                }
            }
        }
    }

    /// Points the feed at a stored row for the case that needs the guard to have something to read,
    /// and returns the id the mapping holds before the refresh runs.
    private func seedStoredIcon(_ connection: any Database, feedID: Int, content: Data)
        async throws -> Int {
        let icons = IconRepository(connection)
        let icon = try await icons.insert(hash: Hashes.sha256(content), mimeType: "image/png",
            content: content)
        let iconID = try #require(icon.id)
        try await icons.link(feedID: feedID, iconID: iconID)
        return iconID
    }

    /// The RSS document every case uses, with no channel image, so the scan branch is the one that
    /// can answer.
    private var feedDocument: String {
        "<rss version=\"2.0\"><channel><title>Parsed Title</title><link></link>"
            + "<item><title>Entry</title><link>https://example.org/a</link>"
            + "<description>Entry text</description></item></channel></rss>"
    }

    private func answer(_ body: String, headers: [String: String] = ["ETag": "\"stub-etag\""])
        -> StubFeedServer.Behavior {
        StubFeedServer.Behavior(headers: headers, body: Data(body.utf8))
    }

    private func document(status: Int = 200, contentType: String = "text/html", body: Data)
        -> StubFeedServer.Behavior {
        StubFeedServer.Behavior(status: status, headers: ["Content-Type": contentType], body: body)
    }

    /// The stored row with `iconID`, which is where the mapping the checker writes can be read.
    private func storedIcon(_ storage: SQLiteStorage, iconID: Int) async throws -> Icon? {
        try await storage.withConnection { connection in
            try await IconRepository(connection).fetch(id: iconID)
        }
    }

    private func storedIconCount(_ storage: SQLiteStorage) async throws -> Int {
        try await storage.withConnection { connection in
            try await Icon.query(on: connection).count()
        }
    }

    private func storedIconID(_ storage: SQLiteStorage, feedID: Int) async throws -> Int? {
        try await storage.withConnection { connection in
            try await FeedRepository(connection).fetch(id: feedID)?.iconID
        }
    }
}
