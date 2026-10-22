import AsyncHTTPClient
import Foundation
import Testing
import RivuletCore

/// The fetch matrix against a local stub server: the fetcher is the module boundary, so this is where
/// its statuses, bodies, decompression, limits and timeouts are checked over a real socket. Every test
/// starts its own server on port 0, as `docs/testing.md` requires. The address policy and the proxy hop
/// are in `FetcherSecurityTests.swift`, because they need a resolver seam: the policy tests answer names
/// through a seeded resolver, and the proxy hop is an address host that needs no lookup at all.
@Suite struct FetcherTests {
    @Test func twoHundredReturnsStatusHeadersAndBody() async throws {
        let body = Data("<feed><title>Stub</title></feed>".utf8)
        try await FetchTestSupport.withServer(behaviors: ["/feed": StubFeedServer.Behavior(
            headers: ["Content-Type": "application/xml", "ETag": "\"stub-etag\""],
            body: body
        )]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options()) { fetcher in
                let response = try await fetcher.fetch(FetchRequest(url: server.url("/feed"), headers: [:]))

                #expect(response.status == 200)
                #expect(response.body == body)
                #expect(response.contentType == "application/xml")
                #expect(response.etag == "\"stub-etag\"")
                #expect(response.effectiveURL == server.url("/feed"))
            }
        }
    }

    @Test func conditionalHitHasNoBodyAndTheSecondRequestCarriesTheValidators() async throws {
        try await FetchTestSupport.withServer(behaviors: [
            "/first": StubFeedServer.Behavior(
                headers: ["ETag": "\"abc\"", "Last-Modified": "Mon, 22 Oct 2026 10:00:00 GMT"],
                body: Data("first".utf8)
            ),
            "/second": StubFeedServer.Behavior(status: 304),
        ]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options()) { fetcher in
                let builder = FetchRequestBuilder(options: FetchTestSupport.options())
                let first = try await fetcher.fetch(
                    builder.build(feed: FeedFetchState(feedID: 1, url: server.url("/first")))
                )
                #expect(first.status == 200)

                // The validators the response reports are what the repository stores, and the next
                // request is built from them.
                let second = try await fetcher.fetch(builder.build(feed: FeedFetchState(
                    feedID: 1,
                    url: server.url("/second"),
                    etag: first.etag,
                    lastModified: first.lastModified
                )))
                #expect(second.isConditionalHit)
                #expect(second.body.isEmpty)
                #expect(!second.isModified(against: FeedFetchState(feedID: 1, url: server.url("/second"), etag: first.etag)))

                let sent = try #require(server.received(for: "/second").first)
                #expect(sent.target == "/second")
                #expect(sent.headers["If-None-Match"] == "\"abc\"")
                #expect(sent.headers["If-Modified-Since"] == "Mon, 22 Oct 2026 10:00:00 GMT")
            }
        }
    }

    @Test func gzipBodyIsDecompressed() async throws {
        let body = Data("<feed><title>Gzip</title></feed>".utf8)
        try await FetchTestSupport.withServer(behaviors: [
            "/gzip": StubFeedServer.Behavior(
                headers: ["Content-Encoding": "gzip"],
                body: body,
                gzip: true
            ),
        ]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options()) { fetcher in
                let response = try await fetcher.fetch(FetchRequest(url: server.url("/gzip"), headers: [:]))
                #expect(response.body == body)
            }
        }
    }

    @Test func chunkedBodyIsDecoded() async throws {
        let body = Data("<feed><title>Chunked</title></feed>".utf8)
        try await FetchTestSupport.withServer(behaviors: [
            "/chunked": StubFeedServer.Behavior(
                headers: ["Content-Type": "application/xml"],
                body: body,
                chunked: true
            ),
        ]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options()) { fetcher in
                let response = try await fetcher.fetch(FetchRequest(url: server.url("/chunked"), headers: [:]))
                // The server chose chunked transfer encoding; the assertion that matters is that the
                // body is reassembled, not that the header is echoed back.
                #expect(response.header("Transfer-Encoding") == "chunked")
                #expect(response.body == body)
            }
        }
    }

    @Test func oversizedBodyIsRejectedWithTheCapInItsMessage() async throws {
        let body = Data(repeating: 0x2A, count: 2048)
        try await FetchTestSupport.withServer(behaviors: ["/big": StubFeedServer.Behavior(body: body)]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options(maxBodySize: 1024)) { fetcher in
                do {
                    _ = try await fetcher.fetch(FetchRequest(url: server.url("/big"), headers: [:]))
                    Issue.record("expected the body cap to reject the response")
                } catch let error as FetchError {
                    #expect(error == .bodyTooLarge(1024))
                }
            }
        }
    }

    @Test func slowResponseHitsTheTimeout() async throws {
        try await FetchTestSupport.withServer(behaviors: [
            "/slow": StubFeedServer.Behavior(body: Data("late".utf8), delay: .seconds(2)),
        ]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options(timeout: .seconds(1))) { fetcher in
                do {
                    _ = try await fetcher.fetch(FetchRequest(url: server.url("/slow"), headers: [:]))
                    Issue.record("expected the timeout to stop the request")
                } catch let error as FetchError {
                    #expect(error == .timeout)
                }
            }
        }
    }

    @Test func theDeadlineCoversBodyReadingNotOnlyTheResponseHead() async throws {
        // The head goes out at once and the body after the deadline, so a timeout here can only come
        // from the deadline covering the whole transaction, as the reference's client timeout does. If
        // the deadline bounded only the response head, this response would arrive and the test would
        // fail. The pass condition is a timeout, so the delay is server-side and nothing sleeps.
        try await FetchTestSupport.withServer(behaviors: [
            "/slow-body": StubFeedServer.Behavior(body: Data("late bytes".utf8), bodyDelay: .seconds(2)),
        ]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options(timeout: .seconds(1))) { fetcher in
                do {
                    _ = try await fetcher.fetch(FetchRequest(url: server.url("/slow-body"), headers: [:]))
                    Issue.record("expected the deadline to cut the body")
                } catch let error as FetchError {
                    #expect(error == .timeout)
                }
            }
        }
    }

    @Test func connectionClosedBeforeTheResponseIsAFetchError() async throws {
        try await FetchTestSupport.withServer(behaviors: ["/cut": StubFeedServer.Behavior(cutConnection: true)]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options()) { fetcher in
                do {
                    _ = try await fetcher.fetch(FetchRequest(url: server.url("/cut"), headers: [:]))
                    Issue.record("expected the closed connection to fail the fetch")
                } catch let error as FetchError {
                    #expect(error == .network("connection closed by the peer"))
                }
            }
        }
    }

    @Test func aFailureBeforeAnythingConnectsIsStillAFetchError() async throws {
        // `fetch` promises a FetchError, and the client can fail before a connection: the URL is refused
        // when it is turned into a client request. Nothing is dialled here, so this is a test of the
        // mapping. The host here is an address, so it is classified without a lookup and the resolver is
        // never touched; the policy flag is what admits an address already known to be private.
        try await FetchTestSupport.withServer(behaviors: ["/feed": StubFeedServer.Behavior(body: Data("x".utf8))]) { server in
            try await FetchTestSupport.withFetcher(
                options: FetchTestSupport.options(allowPrivateNetworks: true)
            ) { fetcher in
                let request = FetchRequest(url: URL(string: "ftp://127.0.0.1:\(server.port)/feed")!, headers: [:])
                do {
                    _ = try await fetcher.fetch(request)
                    Issue.record("expected the client to refuse the scheme")
                } catch let error as FetchError {
                    // The wording is the client's, which is what the mapping keeps for an error it does
                    // not classify. The comparison is against the client's own error, so it is not a guess.
                    #expect(error == .network(String(describing: HTTPClientError.unsupportedScheme("ftp"))))
                } catch {
                    Issue.record("expected a FetchError, got \(String(describing: error))")
                }
            }
        }
    }

    @Test func errorStatusIsReportedAsAFetchErrorWithoutThrowing() async throws {
        try await FetchTestSupport.withServer(behaviors: [
            "/missing": StubFeedServer.Behavior(status: 404, body: Data("gone".utf8)),
            "/limited": StubFeedServer.Behavior(status: 429, body: Data("wait".utf8)),
        ]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options()) { fetcher in
                let missing = try await fetcher.fetch(FetchRequest(url: server.url("/missing"), headers: [:]))
                #expect(missing.error() == .status(404))

                let limited = try await fetcher.fetch(FetchRequest(url: server.url("/limited"), headers: [:]))
                #expect(limited.isRateLimited)
                #expect(limited.error() == .status(429))
            }
        }
    }

    @Test func redirectChainEndsAtTheFinalURL() async throws {
        let body = Data("final".utf8)
        try await FetchTestSupport.withServer(behaviors: [
            "/one": StubFeedServer.Behavior(status: 301, headers: ["Location": "/two"]),
            "/two": StubFeedServer.Behavior(status: 302, headers: ["Location": "/three"]),
            "/three": StubFeedServer.Behavior(body: body),
        ]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options()) { fetcher in
                let response = try await fetcher.fetch(FetchRequest(url: server.url("/one"), headers: [:]))
                #expect(response.status == 200)
                #expect(response.body == body)
                #expect(response.effectiveURL == server.url("/three"))
            }
        }
    }

    @Test func onlyTheStatusesTheReferenceFollowsAreFollowed() async throws {
        // Go follows 301, 302, 303, 307 and 308 only. A 300 with a `Location` is an ordinary
        // response; 303 is followed, and the client always uses GET here so the method cannot change.
        try await FetchTestSupport.withServer(behaviors: [
            "/multiple": StubFeedServer.Behavior(status: 300, headers: ["Location": "/final"], body: Data("choice".utf8)),
            "/moved": StubFeedServer.Behavior(status: 303, headers: ["Location": "/final"]),
            "/temporary": StubFeedServer.Behavior(status: 307, headers: ["Location": "/final"]),
            "/permanent": StubFeedServer.Behavior(status: 308, headers: ["Location": "/final"]),
            "/final": StubFeedServer.Behavior(body: Data("final".utf8)),
        ]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options()) { fetcher in
                let choice = try await fetcher.fetch(FetchRequest(url: server.url("/multiple"), headers: [:]))
                #expect(choice.status == 300)
                #expect(choice.body == Data("choice".utf8))

                for path in ["/moved", "/temporary", "/permanent"] {
                    let response = try await fetcher.fetch(FetchRequest(url: server.url(path), headers: [:]))
                    #expect(response.status == 200, Comment("303, 307 and 308 are followed"))
                    #expect(response.effectiveURL == server.url("/final"))
                }
            }
        }
    }

    @Test func aRedirectWithAnEmptyLocationIsTheResponseLikeUpstreamDoes() async throws {
        // Go returns the response when a redirect status carries an empty `Location`; a 3xx without a
        // usable location is not followed. Rivulet must not resolve an empty value against the base and
        // loop on it.
        try await FetchTestSupport.withServer(behaviors: [
            "/empty": StubFeedServer.Behavior(status: 302, headers: ["Location": ""], body: Data("kept".utf8)),
        ]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options()) { fetcher in
                let response = try await fetcher.fetch(FetchRequest(url: server.url("/empty"), headers: [:]))
                #expect(response.status == 302)
                #expect(response.body == Data("kept".utf8))
            }
        }
    }

    @Test func redirectLoopIsCapped() async throws {
        try await FetchTestSupport.withServer(behaviors: [
            "/loop": StubFeedServer.Behavior(status: 302, headers: ["Location": "/loop"]),
        ]) { server in
            try await FetchTestSupport.withFetcher(
                options: FetchTestSupport.options(maxRedirects: 3)
            ) { fetcher in
                do {
                    _ = try await fetcher.fetch(FetchRequest(url: server.url("/loop"), headers: [:]))
                    Issue.record("expected the redirect limit to stop the chain")
                } catch let error as FetchError {
                    #expect(error == .redirectLimit(3))
                }
            }
        }
    }

    @Test func theTimeoutIsOneDeadlineForAllHopsTogetherLikeTheReferencesClientTimeout() async throws {
        // Go computes its deadline once, and it covers connection, redirects and body reading. Here the
        // first hop uses most of it, so the second hop cannot start a fresh timeout of its own: the
        // delay of the second hop is shorter than the configured timeout but longer than what the first
        // hop left, which is the only way this is observable without sleeping. The pass condition is a
        // timeout, and CI overhead only makes it fire earlier.
        try await FetchTestSupport.withServer(behaviors: [
            "/first": StubFeedServer.Behavior(status: 302, headers: ["Location": "/second"], delay: .milliseconds(200)),
            "/second": StubFeedServer.Behavior(body: Data("late".utf8), delay: .milliseconds(900)),
        ]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options(timeout: .seconds(1))) { fetcher in
                do {
                    _ = try await fetcher.fetch(FetchRequest(url: server.url("/first"), headers: [:]))
                    Issue.record("expected the shared deadline to stop the second hop")
                } catch let error as FetchError {
                    #expect(error == .timeout)
                }
            }
        }
    }

    @Test func anUnparseableRedirectLocationIsAFetchErrorWithGoPhraseAndNoParseError() async throws {
        try await FetchTestSupport.withServer(behaviors: [
            "/bad": StubFeedServer.Behavior(status: 302, headers: ["Location": "http://[bad"]),
        ]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options()) { fetcher in
                do {
                    _ = try await fetcher.fetch(FetchRequest(url: server.url("/bad"), headers: [:]))
                    Issue.record("expected the unparseable redirect location to fail")
                } catch let error as FetchError {
                    #expect(error == .redirectTargetUnparseable("http://[bad"))
                    // Go's phrase — `net/http`'s `Client.do` writes it and wraps it in `Get "url":`, which is
                    // what the reference prints. Rivulet has no parse error to print, so the phrase stands
                    // alone, and the wrapper is dropped: that is what is asserted here.
                    #expect(String(describing: error) == "fetcher: failed to parse Location header \"http://[bad\"")
                }
            }
        }
    }
}
