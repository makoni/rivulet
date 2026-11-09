import Fluent
import Foundation
import Testing
@testable import RivuletCore

/// The checker half of the icon path: `internal/reader/icon/checker.go` at commit `c4d54f87` — the
/// guard, the two storage decisions, the branch the guard does not cover, and the user agent the
/// reference's checker hands to its builder. The upstream file has no test, so these pins are the
/// port's own.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the guard stops
/// the search when the feed already has an icon, so a patch that drops the guard fails the pin that
/// counts the requests the guard never makes; the guard reads the mapping for this feed rather than
/// the icon table, so a patch that answers from any stored row with the same hash fails the pin
/// that runs the search for a feed with no mapping of its own; storing and pointing are two
/// decisions that both run on either branch, so a patch that stores without pointing, and a
/// patch that points only on the branch it inserted on, fail the pins that name those; the
/// guard belongs to the missing path only, so a patch that applies it to the other path fails
/// the pin that writes for a feed that already has an icon; a failing search writes nothing,
/// which a patch that writes anyway fails; and the request carries the feed's user agent, which
/// a patch that hands the builder nothing fails.
///
/// What they cannot fail on: the reference logs each failure and this port has no logging
/// layer, so a swallowed failure reads only as "the call completes and nothing was written";
/// the branch that reads the search answering nothing, because no patch can store a nil answer —
/// a patch that makes the search answer for a rejected image changes the resize rule, which is a
/// different pin; the dedupe, the content-type
/// normalization, the single transaction and the join table are the storage suite's rules,
/// which these pins read only as the values the checker passes on; the request headers are the
/// fetch suite's rules, so the pin here names only that the checker hands the feed's value on,
/// not the fallback to the default; the guard read cannot show that a read which fails answers the
/// same as a read that finds nothing; and the cookie, timeout, proxy, TLS and HTTP2 half of the
/// builder the reference's checker uses is documented as deferred in `docs/reference-notes.md`.
@Suite struct IconCheckerTests {
    @Test func theFoundIconIsStoredAndTheFeedPointsAtIt() async throws {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        try await withChecker(behaviors: [
            "/": behavior(contentType: "text/html",
                body: Data("<html><link rel=\"icon\" href=\"/logo.png\"></html>".utf8)),
            "/logo.png": behavior(contentType: "image/png", body: bytes),
        ]) { checker, connection, feedID, _ in
            await checker.createIfMissing()

            let stored = try await Icon.query(on: connection).first()
            let icon = try #require(stored)
            // The checksum is the download half's rule, read here as the value the checker passes
            // on: it covers the body bytes, not the response as a whole.
            #expect(icon.hash ==
                "4c4b6a3be1314ab86138bef4314dde022e600960d8689a2c8f8631802d20dab6")
            #expect(icon.content == bytes)

            let link = try await feedIconID(connection, feedID)
            #expect(link == icon.id)
        }
    }

    @Test func theGuardStopsTheSearchWhenTheFeedAlreadyHasAnIcon() async throws {
        try await withChecker(behaviors: [
            "/": behavior(contentType: "text/html",
                body: Data("<html><link rel=\"icon\" href=\"/logo.png\"></html>".utf8)),
            "/logo.png": behavior(contentType: "image/png", body: Data([1, 2, 3])),
        ], prepare: { connection, feedID in
            let icons = IconRepository(connection)
            let icon = try await icons.insert(
                hash: "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81",
                mimeType: "image/png", content: Data([1, 2, 3]))
            try await icons.link(feedID: feedID, iconID: try #require(icon.id))
        }) { checker, connection, feedID, server in
            await checker.createIfMissing()

            #expect(server.received(for: "/").isEmpty)
            #expect(server.received(for: "/logo.png").isEmpty)

            let rows = try await Icon.query(on: connection).count()
            #expect(rows == 1)

            let link = try await feedIconID(connection, feedID)
            #expect(link != nil)
        }
    }

    @Test func theGuardReadsTheMappingForThisFeedNotTheIconTable() async throws {
        try await withChecker(behaviors: [
            "/": behavior(contentType: "text/html",
                body: Data("<html><link rel=\"icon\" href=\"/logo.png\"></html>".utf8)),
            "/logo.png": behavior(contentType: "image/png", body: Data([1, 2, 3])),
        ], prepare: { connection, _ in
            // Another feed owns the mapping, so the icon table is not empty while this feed's is.
            let other = try await seedFeed(connection, username: "bob",
                feedURL: "https://example.org/other")
            let icons = IconRepository(connection)
            let icon = try await icons.insert(
                hash: "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81",
                mimeType: "image/png", content: Data([1, 2, 3]))
            try await icons.link(feedID: other.feedID, iconID: try #require(icon.id))
        }) { checker, connection, feedID, server in
            await checker.createIfMissing()

            // The request is what shows the guard did not stop this feed: a patch that reads the
            // guard from the icon table answers for it without searching.
            #expect(server.received(for: "/").count == 1)

            let link = try await feedIconID(connection, feedID)
            #expect(link != nil)
        }
    }

    @Test func theReuseBranchWritesNoSecondRowButStillPointsTheFeedAtTheExistingOne() async throws {
        try await withChecker(behaviors: [
            "/": behavior(contentType: "text/html",
                body: Data("<html><link rel=\"icon\" href=\"/logo.png\"></html>".utf8)),
            "/logo.png": behavior(contentType: "image/png", body: Data([1, 2, 3])),
        ], prepare: { connection, _ in
            // The row is already there under another feed, so the checker takes the branch that
            // finds it by hash instead of the one that inserts.
            let other = try await seedFeed(connection, username: "bob",
                feedURL: "https://example.org/other")
            let icons = IconRepository(connection)
            let icon = try await icons.insert(
                hash: "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81",
                mimeType: "image/png", content: Data([1, 2, 3]))
            try await icons.link(feedID: other.feedID, iconID: try #require(icon.id))
        }) { checker, connection, feedID, _ in
            await checker.createIfMissing()

            let rows = try await Icon.query(on: connection).count()
            #expect(rows == 1)

            let link = try await feedIconID(connection, feedID)
            #expect(link != nil)
        }
    }

    @Test func theUnguardedPathWritesEvenWhenTheFeedAlreadyHasAnIcon() async throws {
        try await withChecker(behaviors: [
            "/": behavior(contentType: "text/html",
                body: Data("<html><link rel=\"icon\" href=\"/logo.png\"></html>".utf8)),
            "/logo.png": behavior(contentType: "image/png", body: Data([4, 5, 6])),
        ], prepare: { connection, feedID in
            let icons = IconRepository(connection)
            let icon = try await icons.insert(
                hash: "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81",
                mimeType: "image/png", content: Data([1, 2, 3]))
            try await icons.link(feedID: feedID, iconID: try #require(icon.id))
        }) { checker, connection, feedID, _ in
            await checker.updateOrCreate()

            let second = try await Icon.query(on: connection)
                .filter(\Icon.$hash ==
                    "787c798e39a5bc1910355bae6d0cd87a36b2e10fd0202a83e3bb6b005da83472")
                .first()
            let icon = try #require(second)

            let rows = try await Icon.query(on: connection).count()
            #expect(rows == 2)

            let link = try await feedIconID(connection, feedID)
            #expect(link == icon.id)
        }
    }

    @Test func aFailingSearchWritesNothing() async throws {
        try await withChecker(behaviors: [
            "/": behavior(status: 500, contentType: "text/html", body: Data()),
        ]) { checker, connection, feedID, _ in
            await checker.createIfMissing()

            let rows = try await Icon.query(on: connection).count()
            #expect(rows == 0)

            let link = try await feedIconID(connection, feedID)
            #expect(link == nil)
        }
    }

    @Test func theCheckerHandsTheFeedUserAgentToTheRequest() async throws {
        try await withChecker(behaviors: [
            "/": behavior(contentType: "text/html",
                body: Data("<html><link rel=\"icon\" href=\"/logo.png\"></html>".utf8)),
            "/logo.png": behavior(contentType: "image/png", body: Data([1, 2, 3])),
        ], userAgent: "NetNewsWire/6") { checker, _, _, server in
            await checker.createIfMissing()

            let request = try #require(server.received(for: "/").first)
            #expect(header(request, "user-agent") == "NetNewsWire/6")
        }
    }

    /// Runs one checker against a server started for this test and a migrated database,
    /// with the feed seeded on this server. `prepare` writes the rows a pin needs before
    /// the checker runs, so a pin can tell what the checker wrote from what the test
    /// seeded.
    private func withChecker(
        behaviors: [String: StubFeedServer.Behavior],
        websitePath: String = "/",
        userAgent: String = "",
        prepare: (@Sendable (any Database, Int) async throws -> Void)? = nil,
        _ body: @escaping @Sendable (IconChecker, any Database, Int, StubFeedServer)
            async throws -> Void
    ) async throws {
        try await FetchTestSupport.withServer(behaviors: behaviors) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options()) { fetcher in
                try await withMigratedStorage { _, storage in
                    try await storage.withConnection { connection in
                        let websiteURL = server.url(websitePath).absoluteString
                        let (_, _, feedID) = try await seedFeed(connection, feedURL: websiteURL)
                        if let prepare { try await prepare(connection, feedID) }

                        let checker = IconChecker(fetcher: fetcher,
                            options: FetchTestSupport.options(), icons: IconRepository(connection),
                            feedID: feedID, websiteURL: websiteURL, userAgent: userAgent)
                        try await body(checker, connection, feedID, server)
                    }
                }
            }
        }
    }

    private func feedIconID(_ connection: any Database, _ feedID: Int) async throws -> Int? {
        try await Feed.query(on: connection).filter(\Feed.$id == feedID).first()?.iconID
    }

    /// Reads one header as the server recorded it, so the pin does not depend on the case
    /// the request arrived with.
    private func header(_ request: StubFeedServer.Received, _ name: String) -> String? {
        request.headers.first { $0.key.lowercased() == name }?.value
    }

    private func behavior(status: Int = 200, contentType: String, body: Data)
        -> StubFeedServer.Behavior {
        StubFeedServer.Behavior(status: status, headers: ["Content-Type": contentType], body: body)
    }
}
