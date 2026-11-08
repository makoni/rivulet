import Foundation
import Testing
@testable import RivuletCore

/// The two steps this port has for `subscription/quickadd` discovery, read end to end through the
/// fetcher against a stub server. Ported from `internal/reader/subscription/finder.go`
/// (`FindSubscriptions`) at `c4d54f87`; the upstream file has no test for these steps, so these
/// pins are the port's own.
///
/// What these pins can fail on, each checked by patching the rule and reverting (5 pins, 5
/// probes): the response is read before the body, so a status failure is reported even when the
/// body is empty; the format is decided from the bytes before any token is read, so a patch that
/// scanned first answered the href inside the document; the answer for a document that is already
/// a feed is the URL the response came from, which is a different answer for a hop that was
/// redirected; the base the scan resolves against is the URL this call was given, which the
/// reference changes with its canonical step before the scan — the deviation `docs/parity.md`
/// records — so a patch that resolved against the effective URL fails; and a document with no
/// matching link answers nothing rather than failing the call.
///
/// What these pins cannot show: the steps this port lacks — the well-known paths, the canonical
/// URL, the YouTube, GitHub and RSS-Bridge handlers — which the `minimal_scan` row records; the
/// request headers, which are the fetcher's rules pinned by the fetch suite; the reference's
/// logging, which this port has no layer for; the title and format the reference's subscription
/// value carries, which nothing here uses; and the size cap, which the fetcher owns. The scan's
/// own rules are pinned by `SubscriptionDocumentLinksTests`.
@Suite struct SubscriptionFinderTests {
    @Test func theResponseErrorIsReadBeforeTheBody() async throws {
        // A status failure with an empty body: a patch that read the body first answered the
        // empty-body failure instead, which is a different answer than the one the reference
        // reports here.
        try await FetchTestSupport.withServer(behaviors: ["/gone": StubFeedServer.Behavior(status: 404)]) {
            server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options()) { fetcher in
                let finder = SubscriptionFinder(fetcher: fetcher, options: FetchTestSupport.options())
                await #expect(throws: FetchError.status(404)) {
                    try await finder.findFeedURLs(from: server.url("/gone").absoluteString)
                }
            }
        }
    }

    @Test func theFormatIsDecidedFromTheBytesBeforeAnyTokenIsRead() async throws {
        // The document is a feed, so the step before the scan answers with the URL the response
        // came from, and the href the scan would have read never reaches the answer.
        try await FetchTestSupport.withServer(behaviors: ["/feed": StubFeedServer.Behavior(
            headers: ["Content-Type": "application/rss+xml"],
            body: Data(("<rss version=\"2.0\"><channel><title>Nothing</title>"
                + "<link rel=\"alternate\" type=\"application/rss+xml\" href=\"/inner\"></link>"
                + "</channel></rss>").utf8))]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options()) { fetcher in
                let finder = SubscriptionFinder(fetcher: fetcher, options: FetchTestSupport.options())
                let found = try await finder.findFeedURLs(from: server.url("/feed").absoluteString)
                #expect(found == [server.url("/feed").absoluteString], "the document's own url")
            }
        }
    }

    @Test func theAnswerForAFeedIsTheUrlTheResponseCameFromAndNotTheUrlTheCallWasGiven() async throws {
        try await FetchTestSupport.withServer(behaviors: [
            "/page": StubFeedServer.Behavior(status: 301, headers: ["Location": "/feed"], body: Data()),
            "/feed": StubFeedServer.Behavior(headers: ["Content-Type": "application/rss+xml"],
                body: Data("<rss version=\"2.0\"><channel><title>Nothing</title></channel></rss>".utf8)),
        ]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options()) { fetcher in
                let finder = SubscriptionFinder(fetcher: fetcher, options: FetchTestSupport.options())
                let given = server.url("/page").absoluteString
                let found = try await finder.findFeedURLs(from: given)
                #expect(found == [server.url("/feed").absoluteString],
                    "the two are different answers on this input")
            }
        }
    }

    @Test func theScanResolvesAgainstTheUrlTheFinderWasGiven() async throws {
        // The hop landed on another path, so a patch that resolved against the effective URL
        // answered the href under it. The reference would have answered that too, through its
        // canonical step, which is the deviation `docs/parity.md` records.
        try await FetchTestSupport.withServer(behaviors: [
            "/page/": StubFeedServer.Behavior(status: 301, headers: ["Location": "/other/"], body: Data()),
            "/other/": StubFeedServer.Behavior(headers: ["Content-Type": "text/html"],
                body: Data(("<html><head><link rel=\"alternate\" type=\"application/rss+xml\" "
                    + "href=\"sub/a\"></head></html>").utf8)),
        ]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options()) { fetcher in
                let finder = SubscriptionFinder(fetcher: fetcher, options: FetchTestSupport.options())
                let found = try await finder.findFeedURLs(from: server.url("/page/").absoluteString)
                #expect(found == [server.url("/page/sub/a").absoluteString],
                    "the base the scan was given, not the one the hop landed on")
            }
        }
    }

    @Test func aDocumentWithNoMatchingLinkAnswersNothing() async throws {
        try await FetchTestSupport.withServer(behaviors: ["/page": StubFeedServer.Behavior(
            headers: ["Content-Type": "text/html"],
            body: Data("<html><head><link rel=\"alternate\" type=\"application/rss+xml\">".utf8))]) {
            server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options()) { fetcher in
                let finder = SubscriptionFinder(fetcher: fetcher, options: FetchTestSupport.options())
                let found = try await finder.findFeedURLs(from: server.url("/page").absoluteString)
                #expect(found == [], "the handler answers its zero document for this")
            }
        }
    }
}
