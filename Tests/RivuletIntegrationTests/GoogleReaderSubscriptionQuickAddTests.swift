import Foundation
import Testing
import RivuletApp
@testable import RivuletCore

/// `quickAddHandler` of `internal/googlereader/handler.go` at `c4d54f87`, over a real socket
/// and the stub server, with the fetcher the application was built with. The goldens are the
/// reference's own answer for these inputs at the toolchain `go.mod` pins. The scan rules are
/// pinned as pure logic by `SubscriptionDocumentLinksTests`, the response read and the two
/// steps this port has by `SubscriptionFinderTests`, and the document shapes by
/// `GoogleReaderShapeTests`.  What these pins can fail on, each checked by patching the rule
/// and reverting (4 pins, 4 probes): that the name is read from the merged form, so the query
/// half answers on its own; the absolute guard that runs before the fetch, which no value the
/// guard refuses can reach; the zero answer when the scan finds nothing, with the field written
/// without `omitempty` and the three that have it not written; the pick, which is the first
/// value the scan answered; and the status a failing fetch maps to here, which this endpoint
/// decides on its own, because the reference answers 500 for the discovery failure as well.  What
/// these pins cannot show: the discovery steps this port does not have — the `<base href>` read,
/// the canonical URL, the YouTube, GitHub and RSS-Bridge handlers, the well-known paths, which the
/// `minimal_scan` row of `docs/parity.md` records; that the reference parses the discovered feed
/// inside this branch, so its `streamName` is the parsed title while this port writes the row with
/// the create defaults and the title comes on the next pass; no pin here can fail on that, and the
/// parity run reads it only as the key set the answer carries, which is the `parsed_title` row.
/// The wordings of the fetch failure, which are the fetcher's own and the reference's localized
/// strings; and the storage failure this suite cannot trigger.
@Suite struct GoogleReaderSubscriptionQuickAddTests {
    private let routes = "/reader/api/0/subscription/"

    @Test func quickaddReadsItsNameFromTheMergedForm() async throws {
        try await withServedApp(environment: ["FETCHER_ALLOW_PRIVATE_NETWORKS": "1"]) {
            storage, app, base in
            let socket = try await SubscriptionSocket.session(requests: GoogleReaderRequests(app, base),
                storage: storage, routes: routes)

            try await FetchTestSupport.withServer(behaviors: ["/page": page(
                "<link rel=\"alternate\" type=\"application/rss+xml\" href=\"/feed.xml\">")]) { server in
                // The name is only in the query half, so a patch that read the body side answered
                // the guard's wording with the empty value.
                let query = "quickadd?T=\(socket.token)&quickadd=http://127.0.0.1:\(server.port)/page"
                let answer = try await socket.answer(query, pairs: [])
                #expect(answer == "{\"numResults\":1,\"query\":\"http://127.0.0.1:\(server.port)/feed.xml\","
                    + "\"streamId\":\"feed/1\"}", "the query half answers on its own")

                // The account here has one category, so this half cannot tell which read answered
                // it; the title order that read has is falsifiable in the edit suite, where the
                // account has two.
                let row = try #require(try await socket.feed("http://127.0.0.1:\(server.port)/feed.xml"))
                #expect(try await socket.categoryTitle(try #require(row.id)) == "All",
                    "in the category the read answered, because the form carried no tag")
            }
        }
    }

    @Test func quickaddRunsTheAbsoluteGuardBeforeTheScan() async throws {
        try await withServedApp(environment: ["FETCHER_ALLOW_PRIVATE_NETWORKS": "1"]) {
            storage, app, base in
            let socket = try await SubscriptionSocket.session(requests: GoogleReaderRequests(app, base),
                storage: storage, routes: routes)
            // A value the guard refuses never reaches the fetch, so the pin reads which of the two
            // runs first, and the wording names the value as the form read it.
            #expect(try await socket.answer("quickadd", pairs: ["quickadd=/only-a-path"]) ==
                "{\"error_message\":\"googlereader: invalid URL: /only-a-path\"}")
            #expect(try await socket.answer("quickadd", pairs: ["quickadd=example.org/page"]) ==
                "{\"error_message\":\"googlereader: invalid URL: example.org/page\"}",
                "a value with no scheme is refused by the same guard")
        }
    }

    @Test func quickaddAnswersZeroWhenTheScanFindsNothingAndTakesTheFirstValueItRead() async throws {
        try await withServedApp(environment: ["FETCHER_ALLOW_PRIVATE_NETWORKS": "1"]) {
            storage, app, base in
            let socket = try await SubscriptionSocket.session(requests: GoogleReaderRequests(app, base),
                storage: storage, routes: routes)

            try await FetchTestSupport.withServer(behaviors: [
                "/none": page("<link rel=\"stylesheet\" href=\"/style.css\">"),
                "/two": page("<link rel=\"alternate\" type=\"application/rss+xml\" href=\"/first.xml\">"
                    + "<link rel=\"alternate\" type=\"application/atom+xml\" href=\"/second.xml\">"),
            ]) { server in
                // The field without `omitempty` is written when it is 0, and the three that have it
                // are not written — which is also the answer for the title this port has no value
                // for.
                let none = try await socket.answer("quickadd",
                    pairs: ["quickadd=http://127.0.0.1:\(server.port)/none"])
                #expect(none == "{\"numResults\":0}", "the zero answer")

                let pick = try await socket.answer("quickadd",
                    pairs: ["quickadd=http://127.0.0.1:\(server.port)/two"])
                #expect(pick == "{\"numResults\":1,"
                    + "\"query\":\"http://127.0.0.1:\(server.port)/first.xml\",\"streamId\":\"feed/1\"}",
                    "the first value the scan read")
            }
        }
    }

    @Test func quickaddMapsAFailingFetchToTheServerError() async throws {
        try await withServedApp(environment: ["FETCHER_ALLOW_PRIVATE_NETWORKS": "1"]) {
            storage, app, base in
            let socket = try await SubscriptionSocket.session(requests: GoogleReaderRequests(app, base),
                storage: storage, routes: routes)
            // The reference reports the failure as its localized error and answers 500; this port
            // has no locale layer, so the pin reads the status this handler maps the failure to.
            try await FetchTestSupport.withServer(behaviors: ["/gone": StubFeedServer.Behavior(
                status: 404, headers: ["Content-Type": "text/html"], body: Data("nope".utf8))]) { server in
                let failure = try await socket.status("quickadd",
                    pairs: ["quickadd=http://127.0.0.1:\(server.port)/gone"])
                #expect(failure == .internalServerError, "the status the failure maps to")
            }
        }
    }

    /// The document the stub answers with: the head is the part the scan reads, so a pin writes the
    /// attribute the reference's selector matches on.
    private func page(_ head: String) -> StubFeedServer.Behavior {
        StubFeedServer.Behavior(headers: ["Content-Type": "text/html"],
            body: Data(("<html><head>" + head + "</head><body></body></html>").utf8))
    }
}
