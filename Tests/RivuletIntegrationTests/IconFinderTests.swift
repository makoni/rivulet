import Foundation
import Testing
@testable import RivuletCore

/// The order the icon search tries, read end to end through the fetcher against a stub server.
/// Ported from `internal/reader/icon/finder.go` (`findIcon`, `downloadIcon`,
/// `fetchIconsFromHTMLDocument`, `fetchDefaultIcon`); the upstream file has no test for the
/// order, so these pins are the port's own.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the order is
/// the feed's own icon URL, then the website document, then the root document only when it
/// differs from the website URL, then the default icon joined to the root; the first step that
/// produces an icon stops the search, so a patch that continues past it fails the pin that reads
/// which document's icon answers and counts the requests the later steps never make; a failing
/// step is skipped rather than returned, except the default icon, whose failure is the answer, so
/// a patch that returns an earlier failure fails the pin that names the asymmetry; the feed's icon
/// URL is read as the icon bytes, not scanned as a document, which is pinned by a document-shaped
/// body on that path; a `data:` href is answered without a request; and the default icon path is
/// the joined one, not the root path itself.
///
/// What they cannot fail on: the rules the finder reads through other suites — the charset
/// layer, the tokenizer, the four selector branches, the `data:` shape, the URL resolution and
/// the join cleaning are pinned by their own suites and appear here only as the values the loop
/// passes on; the request headers, which are the fetcher's rules pinned by the fetch suite; the
/// reference's logging, which this port has no layer for; and the reference's
/// `fetchIconsFromHTMLDocument` returning a charset-reader failure, which this port answers
/// with the charset layer returning bytes. Nothing here sleeps or polls.
@Suite struct IconFinderTests {
    @Test func theFeedIconURLIsTriedFirstAndItsAnswerIsTheIcon() async throws {
        // The body on that path is a document with a link, so this pins that the feed's
        // icon URL is read as the icon bytes: a patch that scans it as a document would
        // answer with the linked icon instead.
        let document = Data("<html><link rel=\"icon\" href=\"/linked.png\"></html>".utf8)
        try await FetchTestSupport.withServer(behaviors: [
            "/feed-icon": behavior(contentType: "text/html", body: document),
            "/": behavior(contentType: "text/html", body: document),
        ]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options()) { fetcher in
                let finder = IconFinder(fetcher: fetcher, options: FetchTestSupport.options(),
                    websiteURL: server.url("/").absoluteString,
                    feedIconURL: server.url("/feed-icon").absoluteString)
                let icon = try await finder.find()

                #expect(icon.content == document)
                #expect(icon.mimeType == "text/html")
                #expect(icon.hash ==
                    "55b9301f5e3632d9a0c03b22838ffbf1dd0a24a5b71015ad2a2d8d5704eb3ad5")
                #expect(server.received(for: "/").isEmpty)
            }
        }
    }

    @Test func aFailingFeedIconURLIsSkippedAndTheDocumentWins() async throws {
        let linked = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        try await FetchTestSupport.withServer(behaviors: [
            "/feed-icon": behavior(status: 404, contentType: "text/html", body: Data()),
            "/": behavior(contentType: "text/html",
                body: Data("<html><link rel=\"icon\" href=\"/logo.png\"></html>".utf8)),
            "/logo.png": behavior(contentType: "image/png", body: linked),
        ]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options()) { fetcher in
                let finder = IconFinder(fetcher: fetcher, options: FetchTestSupport.options(),
                    websiteURL: server.url("/").absoluteString,
                    feedIconURL: server.url("/feed-icon").absoluteString)
                let icon = try await finder.find()

                #expect(icon.content == linked)
                #expect(server.received(for: "/feed-icon").count == 1)
            }
        }
    }

    @Test func theRootDocumentIsTriedWhenTheWebsiteURLHasAPath() async throws {
        // The website URL is the subdirectory, which has no link, so the second document
        // is the root.
        let linked = Data([1, 2, 3])
        try await FetchTestSupport.withServer(behaviors: [
            "/subfolder/": behavior(contentType: "text/html", body: Data("<html></html>".utf8)),
            "/": behavior(contentType: "text/html",
                body: Data("<html><link rel=\"icon\" href=\"/logo.png\"></html>".utf8)),
            "/logo.png": behavior(contentType: "image/png", body: linked),
        ]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options()) { fetcher in
                let finder = IconFinder(fetcher: fetcher, options: FetchTestSupport.options(),
                    websiteURL: server.url("/subfolder/").absoluteString)
                let icon = try await finder.find()

                #expect(icon.content == linked)
                #expect(server.received(for: "/subfolder/").count == 1)
                #expect(server.received(for: "/").count == 1)
            }
        }
    }

    @Test func theFirstDocumentThatProducesAnIconStopsTheSearch() async throws {
        // Both documents offer a link, so this is the case that reads the rule "the first step
        // that produces an icon answers": the answer is the first document's icon, and the second
        // document is never requested at all.
        let first = Data([1, 2, 3])
        let second = Data([4, 5, 6])
        try await FetchTestSupport.withServer(behaviors: [
            "/subfolder/": behavior(contentType: "text/html",
                body: Data("<html><link rel=\"icon\" href=\"/a.png\"></html>".utf8)),
            "/": behavior(contentType: "text/html",
                body: Data("<html><link rel=\"icon\" href=\"/b.png\"></html>".utf8)),
            "/a.png": behavior(contentType: "image/png", body: first),
            "/b.png": behavior(contentType: "image/png", body: second),
        ]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options()) { fetcher in
                let finder = IconFinder(fetcher: fetcher, options: FetchTestSupport.options(),
                    websiteURL: server.url("/subfolder/").absoluteString)
                let icon = try await finder.find()

                #expect(icon.content == first)
                #expect(icon.hash ==
                    "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81")
                #expect(server.received(for: "/").isEmpty)
                #expect(server.received(for: "/b.png").isEmpty)
            }
        }
    }

    @Test func theRootDocumentIsNotTriedWhenTheWebsiteURLIsAlreadyTheRoot() async throws {
        // One document request, then the joined default icon. A patch that reads the
        // website URL twice fails the count.
        let favicon = Data([0x00, 0x00, 0x03, 0x00])
        try await FetchTestSupport.withServer(behaviors: [
            "/": behavior(contentType: "text/html", body: Data("<html></html>".utf8)),
            "/favicon.ico": behavior(contentType: "image/x-icon", body: favicon),
        ]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options()) { fetcher in
                let finder = IconFinder(fetcher: fetcher, options: FetchTestSupport.options(),
                    websiteURL: server.url("/").absoluteString)
                let icon = try await finder.find()

                #expect(icon.content == favicon)
                #expect(icon.hash ==
                    "1112da16eb081d8d3dedf4cfb31fb10f96d713988136da3dc00e9f0c8def0e0e")
                #expect(server.received(for: "/").count == 1)
            }
        }
    }

    @Test func theDefaultIconIsJoinedToTheRootURLRatherThanReadAtTheRootPath() async throws {
        // The website URL carries a path, so the joined URL is the root plus
        // `favicon.ico`, and the root document itself answers without a link.
        let favicon = Data([0x00, 0x00, 0x03, 0x00])
        try await FetchTestSupport.withServer(behaviors: [
            "/subfolder/": behavior(contentType: "text/html", body: Data("<html></html>".utf8)),
            "/": behavior(contentType: "text/html", body: Data("<html></html>".utf8)),
            "/favicon.ico": behavior(contentType: "image/x-icon", body: favicon),
        ]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options()) { fetcher in
                let finder = IconFinder(fetcher: fetcher, options: FetchTestSupport.options(),
                    websiteURL: server.url("/subfolder/").absoluteString)
                let icon = try await finder.find()

                #expect(icon.content == favicon)
                #expect(server.received(for: "/subfolder/").count == 1)
                #expect(server.received(for: "/").count == 1)
                #expect(server.received(for: "/favicon.ico").count == 1)
            }
        }
    }

    @Test func aDataHrefIsAnsweredWithoutARequest() async throws {
        // The data URL is the whole answer: no fetch reaches the server for it. The
        // shape and its three encodings are `IconDataURLTests`; this pins that the loop
        // answers with it instead of fetching.
        let svg = "<svg xmlns='http://www.w3.org/2000/svg'></svg>"
        let doc = "<html><link rel=\"icon\" href=\"data:image/svg+xml;utf8,\(svg)\"></html>"
        try await FetchTestSupport.withServer(behaviors: [
            "/": behavior(contentType: "text/html", body: Data(doc.utf8)),
            "/favicon.ico": behavior(contentType: "image/x-icon",
                body: Data([0x00, 0x00, 0x03, 0x00])),
        ]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options()) { fetcher in
                let finder = IconFinder(fetcher: fetcher, options: FetchTestSupport.options(),
                    websiteURL: server.url("/").absoluteString)
                let icon = try await finder.find()

                #expect(icon.mimeType == "image/svg+xml")
                #expect(icon.content == Data(svg.utf8))
                #expect(server.received(for: "/favicon.ico").isEmpty)
            }
        }
    }

    @Test func theDefaultIconFailureIsTheAnswerWhileAnEarlierFailureIsSkipped() async throws {
        // The reference logs a failing document and keeps going, but returns the failure
        // of the last step.
        try await FetchTestSupport.withServer(behaviors: [
            "/": behavior(status: 404, contentType: "text/html", body: Data()),
            "/favicon.ico": behavior(status: 500, contentType: "text/html", body: Data()),
        ]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options()) { fetcher in
                let finder = IconFinder(fetcher: fetcher, options: FetchTestSupport.options(),
                    websiteURL: server.url("/").absoluteString)
                await #expect(throws: FetchError.status(500)) { try await finder.find() }
            }
        }
    }

    private func behavior(status: Int = 200, contentType: String, body: Data)
        -> StubFeedServer.Behavior {
        StubFeedServer.Behavior(status: status, headers: ["Content-Type": contentType], body: body)
    }
}
