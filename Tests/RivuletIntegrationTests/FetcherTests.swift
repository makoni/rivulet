import Foundation
import Testing
import RivuletCore

/// Fetch matrix against a local stub server. The fetcher is the module boundary, so this is where
/// its limits, decompression, redirects, timeouts and the address policy are checked over a real
/// socket. Every test starts its own server on port 0, as `docs/testing.md` requires.
@Suite struct FetcherTests {
    private func options(
        maxBodySize: Int = 1024,
        maxRedirects: Int = 10,
        timeout: Duration = .seconds(5),
        decompression: Bool = true,
        proxyURL: String? = nil,
        allowPrivateNetworks: Bool = true
    ) -> FetcherOptions {
        FetcherOptions(
            timeout: timeout,
            userAgent: FetcherOptions.defaultUserAgent,
            acceptHeader: FetcherOptions.defaultAcceptHeader,
            maxBodySize: maxBodySize,
            maxRedirects: maxRedirects,
            decompression: decompression,
            ignoreHTTPCache: false,
            proxyURL: proxyURL,
            allowPrivateNetworks: allowPrivateNetworks
        )
    }

    /// Runs `body` against a server started for this test and stops it on both paths.
    private func withServer(
        behaviors: [String: StubFeedServer.Behavior],
        _ body: (StubFeedServer) async throws -> Void
    ) async throws {
        let server = try await StubFeedServer.start(behaviors: behaviors)
        do {
            try await body(server)
        } catch {
            try await server.stop()
            throw error
        }
        try await server.stop()
    }

    /// Runs `body` with a proxy started for this test and stops it on both paths.
    private func withProxy(response: Data, _ body: (StubProxy) async throws -> Void) async throws {
        let proxy = try await StubProxy.start(response: response)
        do {
            try await body(proxy)
        } catch {
            try await proxy.stop()
            throw error
        }
        try await proxy.stop()
    }

    /// Runs `body` with a fetcher and closes the clients it created.
    private func withFetcher(
        options: FetcherOptions,
        resolver: any AddressResolver = SystemAddressResolver(),
        _ body: (Fetcher) async throws -> Void
    ) async throws {
        let fetcher = Fetcher(options: options, resolver: resolver)
        do {
            try await body(fetcher)
        } catch {
            try? await fetcher.shutdown()
            throw error
        }
        try await fetcher.shutdown()
    }

    /// Answers every lookup with one address and counts the calls.
    actor CountingResolver: AddressResolver {
        private let answer: [NetworkAddress]
        private(set) var calls = 0

        init(answer: NetworkAddress) {
            self.answer = [answer]
        }

        func resolve(host: String) async throws -> [NetworkAddress] {
            calls += 1
            return answer
        }
    }

    @Test func twoHundredReturnsStatusHeadersAndBody() async throws {
        let body = Data("<feed><title>Stub</title></feed>".utf8)
        try await withServer(behaviors: ["/feed": StubFeedServer.Behavior(
            headers: ["Content-Type": "application/xml", "ETag": "\"stub-etag\""],
            body: body
        )]) { server in
            try await withFetcher(options: options()) { fetcher in
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
        try await withServer(behaviors: [
            "/first": StubFeedServer.Behavior(
                headers: ["ETag": "\"abc\"", "Last-Modified": "Mon, 22 Oct 2026 10:00:00 GMT"],
                body: Data("first".utf8)
            ),
            "/second": StubFeedServer.Behavior(status: 304),
        ]) { server in
            try await withFetcher(options: options()) { fetcher in
                let builder = FetchRequestBuilder(options: options())
                let first = try await fetcher.fetch(builder.build(feed: FeedFetchState(feedID: 1, url: server.url("/first"))))
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
                #expect(sent.headers["If-None-Match"] == "\"abc\"")
                #expect(sent.headers["If-Modified-Since"] == "Mon, 22 Oct 2026 10:00:00 GMT")
            }
        }
    }

    @Test func redirectChainEndsAtTheFinalURL() async throws {
        let body = Data("final".utf8)
        try await withServer(behaviors: [
            "/one": StubFeedServer.Behavior(status: 301, headers: ["Location": "/two"]),
            "/two": StubFeedServer.Behavior(status: 302, headers: ["Location": "/three"]),
            "/three": StubFeedServer.Behavior(body: body),
        ]) { server in
            try await withFetcher(options: options()) { fetcher in
                let response = try await fetcher.fetch(FetchRequest(url: server.url("/one"), headers: [:]))
                #expect(response.status == 200)
                #expect(response.body == body)
                #expect(response.effectiveURL == server.url("/three"))
            }
        }
    }

    @Test func redirectLoopIsCapped() async throws {
        try await withServer(behaviors: [
            "/loop": StubFeedServer.Behavior(status: 302, headers: ["Location": "/loop"]),
        ]) { server in
            try await withFetcher(options: options(maxRedirects: 3)) { fetcher in
                do {
                    _ = try await fetcher.fetch(FetchRequest(url: server.url("/loop"), headers: [:]))
                    Issue.record("expected the redirect limit to stop the chain")
                } catch let error as FetchError {
                    #expect(error == .redirectLimit(3))
                }
            }
        }
    }

    @Test func gzipBodyIsDecompressed() async throws {
        let body = Data("<feed><title>Gzip</title></feed>".utf8)
        try await withServer(behaviors: [
            "/gzip": StubFeedServer.Behavior(
                headers: ["Content-Encoding": "gzip"],
                body: body,
                gzip: true
            ),
        ]) { server in
            try await withFetcher(options: options()) { fetcher in
                let response = try await fetcher.fetch(FetchRequest(url: server.url("/gzip"), headers: [:]))
                #expect(response.body == body)
            }
        }
    }

    @Test func chunkedBodyIsDecoded() async throws {
        let body = Data("<feed><title>Chunked</title></feed>".utf8)
        try await withServer(behaviors: [
            "/chunked": StubFeedServer.Behavior(
                headers: ["Content-Type": "application/xml"],
                body: body,
                chunked: true
            ),
        ]) { server in
            try await withFetcher(options: options()) { fetcher in
                let response = try await fetcher.fetch(FetchRequest(url: server.url("/chunked"), headers: [:]))
                #expect(response.header("Transfer-Encoding") == "chunked")
                #expect(response.body == body)
            }
        }
    }

    @Test func oversizedBodyIsRejectedWithTheCapInItsMessage() async throws {
        let body = Data(repeating: 0x2A, count: 2048)
        try await withServer(behaviors: ["/big": StubFeedServer.Behavior(body: body)]) { server in
            try await withFetcher(options: options(maxBodySize: 1024)) { fetcher in
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
        try await withServer(behaviors: [
            "/slow": StubFeedServer.Behavior(body: Data("late".utf8), delay: .seconds(2)),
        ]) { server in
            try await withFetcher(options: options(timeout: .seconds(1))) { fetcher in
                do {
                    _ = try await fetcher.fetch(FetchRequest(url: server.url("/slow"), headers: [:]))
                    Issue.record("expected the timeout to stop the request")
                } catch let error as FetchError {
                    #expect(error == .timeout)
                }
            }
        }
    }

    @Test func connectionClosedBeforeTheResponseIsAFetchError() async throws {
        try await withServer(behaviors: ["/cut": StubFeedServer.Behavior(cutConnection: true)]) { server in
            try await withFetcher(options: options()) { fetcher in
                do {
                    _ = try await fetcher.fetch(FetchRequest(url: server.url("/cut"), headers: [:]))
                    Issue.record("expected the closed connection to fail the fetch")
                } catch let error as FetchError {
                    #expect(error == .network("connection closed by the peer"))
                }
            }
        }
    }

    @Test func errorStatusIsReportedAsAFetchErrorWithoutThrowing() async throws {
        try await withServer(behaviors: [
            "/missing": StubFeedServer.Behavior(status: 404, body: Data("gone".utf8)),
            "/limited": StubFeedServer.Behavior(status: 429, body: Data("wait".utf8)),
        ]) { server in
            try await withFetcher(options: options()) { fetcher in
                let missing = try await fetcher.fetch(FetchRequest(url: server.url("/missing"), headers: [:]))
                #expect(missing.error() == .status(404))

                let limited = try await fetcher.fetch(FetchRequest(url: server.url("/limited"), headers: [:]))
                #expect(limited.isRateLimited)
                #expect(limited.error() == .status(429))
            }
        }
    }

    @Test func privateTargetsAreRefusedUnlessTheEscapeHatchIsOn() async throws {
        try await withServer(behaviors: ["/feed": StubFeedServer.Behavior(body: Data("x".utf8))]) { server in
            try await withFetcher(options: options(allowPrivateNetworks: false)) { fetcher in
                do {
                    _ = try await fetcher.fetch(FetchRequest(url: server.url("/feed"), headers: [:]))
                    Issue.record("expected the loopback target to be refused")
                } catch let error as FetchError {
                    #expect(error == .privateNetworkHost("127.0.0.1"))
                }
            }
        }
    }

    @Test func thePinnedAddressIsUsedWithoutResolvingTheHostAgain() async throws {
        let resolver = CountingResolver(answer: NetworkAddress.parse("127.0.0.1")!)
        try await withServer(behaviors: ["/feed": StubFeedServer.Behavior(body: Data("pinned".utf8))]) { server in
            try await withFetcher(options: options(), resolver: resolver) { fetcher in
                // The name is resolved once; the client is pointed at that validated address, so the
                // connection the server sees is the pinned one.
                let url = URL(string: "http://localhost:\(server.port)/feed")!
                let response = try await fetcher.fetch(FetchRequest(url: url, headers: [:]))
                #expect(response.body == Data("pinned".utf8))

                let calls = await resolver.calls
                #expect(calls == 1)
            }
        }
    }

    @Test func proxiedRequestIsRoutedToTheProxyAndThePrivateCheckIsSkippedForThatHop() async throws {
        // Upstream treats an explicitly configured proxy as a trusted hop: the private-network check
        // applies to direct connections, and a proxied target is resolved by the proxy, so there is
        // nothing for Rivulet to pin. AsyncHTTPClient tunnels with CONNECT, which is how the stub
        // proxy sees the request.
        let canned = Data("proxied".utf8)
        let target = URL(string: "http://10.0.0.1/feed")!

        try await withProxy(response: Data("HTTP/1.1 200 OK\r\nContent-Length: 7\r\n\r\nproxied".utf8)) { proxy in
            let options = options(proxyURL: proxy.base.absoluteString, allowPrivateNetworks: false)
            let builder = FetchRequestBuilder(options: options)

            try await withFetcher(options: options) { fetcher in
                let proxied = try builder.build(feed: FeedFetchState(feedID: 1, url: target, fetchViaProxy: true))
                #expect(proxied.proxyURL == proxy.base)

                let response = try await fetcher.fetch(proxied)
                #expect(response.status == 200)
                #expect(response.body == canned)
                #expect(response.effectiveURL == target)

                // The proxy is the hop the client connected to, and the CONNECT carried the target.
                #expect(proxy.connects() == ["10.0.0.1:80"])

                // The same target, without the flag, is refused before anything is connected to.
                let direct = try builder.build(feed: FeedFetchState(feedID: 1, url: target))
                #expect(direct.proxyURL == nil)
                do {
                    _ = try await fetcher.fetch(direct)
                    Issue.record("expected the private target to be refused")
                } catch let error as FetchError {
                    #expect(error == .privateNetworkHost("10.0.0.1"))
                }
            }
        }
    }
}
