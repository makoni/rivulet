import Foundation
import Testing
@testable import RivuletCore

/// A response header name that appears twice on the wire.
///
/// The reference keeps a list per name: `textproto.ReadMIMEHeader` appends the values in the order
/// they arrive, and `Header.Get` answers the first of that list, so the value a hostile response
/// acts on is the first one, and the first `Location` is the hop the reference follows. The port
/// holds one value per name, so which of the two it holds is the rule, and before this suite it
/// held the last value added, which is the divergence these pins close.
///
/// What these pins can fail on, each checked by patching the rule and reverting byte-identically,
/// with each probe named by what it flips: the value read as the last one added, which flipped the
/// repeated-name pin, the case pin and the hop pin; and the name compared with its own case, so one
/// name written two ways became two entries, which flipped the case pin alone.
///
/// What these pins cannot fail on: which of the two spellings the one entry holds, because
/// `header(_:)` reads through either form — the case pin reads that there is one entry, not which
/// spelling it is; both values for one name, which the port does not model — the reference has a
/// list, and `Set-Cookie` is the usual case where that shows; the canonical spelling a key gets
/// upstream, which this port keeps as the wire delivered it; the case rules of the client's
/// decoder, which decides the name before this code sees it; the value of a hop that is not the
/// last one, because `fetch` returns the last response, which is why the hop pin reads the path the
/// stub was asked for rather than the header; and a response whose two values are the same, which
/// no wrong rule can be caught on.
@Suite struct RepeatedResponseHeadersTests {
    @Test func aRepeatedNameKeepsTheFirstValue() async throws {
        try await FetchTestSupport.withServer(behaviors: [
            "/feed": StubFeedServer.Behavior(headerPairs: [("X-Test", "first"), ("X-Test", "second")]),
        ]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options()) { fetcher in
                let response = try await fetcher.fetch(FetchRequest(url: server.url("/feed"), headers: [:]))
                #expect(response.header("X-Test") == "first")
            }
        }
    }

    @Test func theSameNameWrittenTwoWaysIsOneName() async throws {
        try await FetchTestSupport.withServer(behaviors: [
            "/feed": StubFeedServer.Behavior(headerPairs: [("x-test", "first"), ("X-Test", "second")]),
        ]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options()) { fetcher in
                let response = try await fetcher.fetch(FetchRequest(url: server.url("/feed"), headers: [:]))
                // The count is read first, because it is what makes the value deterministic: one
                // name written two ways is one entry, so the lookup below cannot find the second
                // spelling.
                let entries = response.headers.filter { $0.key.lowercased() == "x-test" }
                #expect(entries.count == 1)
                #expect(response.header("X-Test") == "first")
                #expect(response.header("x-test") == "first")
            }
        }
    }

    @Test func theFirstLocationIsTheHopTaken() async throws {
        // The hop is where the difference matters, and it is also the only way to read it: `fetch`
        // returns the response of the last hop, so the `Location` of the redirect response is not
        // available to a test. Which path the stub was asked for is what the first value decided.
        try await FetchTestSupport.withServer(behaviors: [
            "/redirect": StubFeedServer.Behavior(
                status: 302,
                headerPairs: [("Location", "/first"), ("Location", "/second")]
            ),
            "/first": StubFeedServer.Behavior(body: Data("first".utf8)),
            "/second": StubFeedServer.Behavior(body: Data("second".utf8)),
        ]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options()) { fetcher in
                let response = try await fetcher.fetch(FetchRequest(url: server.url("/redirect"), headers: [:]))
                #expect(response.body == Data("first".utf8))
                #expect(response.effectiveURL == server.url("/first"))

                // The second value is not read at all: the path it names was never asked for.
                #expect(server.received(for: "/first").count == 1)
                #expect(server.received(for: "/second").isEmpty)
            }
        }
    }
}
