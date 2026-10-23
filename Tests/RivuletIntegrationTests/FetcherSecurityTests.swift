import Foundation
import Testing
@testable import RivuletCore

/// The address side of the fetcher: the resolver seam, the policy that decides what a fetch may
/// connect to, the pin that keeps the client on the validated address, and the proxy hop, where the
/// reference keeps the check for direct connections only. Every server here is started for one test on
/// port 0, as `docs/testing.md` requires.
@Suite struct FetcherSecurityTests {
    @Test func privateTargetsAreRefusedWhenTheHatchIsOffAndAllowedWhenItIsOn() async throws {
        try await FetchTestSupport.withServer(behaviors: ["/feed": StubFeedServer.Behavior(body: Data("x".utf8))]) { server in
            try await FetchTestSupport.withFetcher(
                options: FetchTestSupport.options(allowPrivateNetworks: false)
            ) { fetcher in
                do {
                    _ = try await fetcher.fetch(FetchRequest(url: server.url("/feed"), headers: [:]))
                    Issue.record("expected the loopback target to be refused")
                } catch let error as FetchError {
                    #expect(error == .privateNetworkHost("127.0.0.1"))
                }
            }

            // The other half of the switch: with the escape hatch the same target is connected to.
            try await FetchTestSupport.withFetcher(
                options: FetchTestSupport.options(allowPrivateNetworks: true)
            ) { fetcher in
                let response = try await fetcher.fetch(FetchRequest(url: server.url("/feed"), headers: [:]))
                #expect(response.body == Data("x".utf8))
            }
        }
    }

    @Test func thePinnedAddressIsUsedWithoutResolvingTheHostAgain() async throws {
        // What this proves is one lookup through the seam — the fetcher is not asked to resolve the name
        // a second time. It cannot prove which address the client dialed, because the stub answers on
        // loopback and a system lookup of `localhost` would give the same answer. That claim belongs to
        // `theHopConnectsToTheAddressValidatedForItsHost`, where nothing else could answer the names.
        let resolver = CountingResolver(answer: NetworkAddress.parse("127.0.0.1")!)
        try await FetchTestSupport.withServer(behaviors: ["/feed": StubFeedServer.Behavior(body: Data("pinned".utf8))]) { server in
            try await FetchTestSupport.withFetcher(
                options: FetchTestSupport.options(allowPrivateNetworks: true),
                resolver: resolver
            ) { fetcher in
                let url = URL(string: "http://localhost:\(server.port)/feed")!
                let response = try await fetcher.fetch(FetchRequest(url: url, headers: [:]))
                #expect(response.body == Data("pinned".utf8))

                let calls = await resolver.calls
                #expect(calls == 1)
            }
        }
    }

    @Test func theHopConnectsToTheAddressValidatedForItsHost() async throws {
        // Both names are answered with the same stub address and nothing else could answer them, so a
        // response from the second hop proves the client used the address the policy validated. The
        // redirect has to name the second server's port, so that server starts first. On a cache hit the
        // client keeps the address validated when it was created for that host, so the address it
        // connects to is always one the policy admitted.
        let stub = NetworkAddress.parse("127.0.0.1")!
        let resolver = SeededResolver(answers: ["first.example": [stub], "second.example": [stub]])
        let body = Data("hop".utf8)

        let second = try await StubFeedServer.start(behaviors: ["/final": StubFeedServer.Behavior(body: body)])
        do {
            try await FetchTestSupport.withServer(behaviors: [
                "/first": StubFeedServer.Behavior(status: 302, headers: ["Location": "http://second.example:\(second.port)/final"]),
            ]) { first in
                try await FetchTestSupport.withFetcher(
                    options: FetchTestSupport.options(allowPrivateNetworks: true),
                    resolver: resolver
                ) { fetcher in
                    let response = try await fetcher.fetch(
                        FetchRequest(url: URL(string: "http://first.example:\(first.port)/first")!, headers: [:])
                    )
                    #expect(response.body == body)
                    #expect(response.effectiveURL == URL(string: "http://second.example:\(second.port)/final")!)

                    let asked = await resolver.hosts
                    #expect(asked == ["first.example", "second.example"])
                }
            }
        } catch {
            try await second.stop()
            throw error
        }
        try await second.stop()
    }

    @Test func everyDirectRedirectHopGoesThroughTheResolverSeam() async throws {
        // Upstream checks the address on every direct dial, so a hop to another host goes through
        // the policy rather than a lookup inside the client. This proves the seam is consulted for
        // the hop and that a hop the seam cannot answer stops the fetch: the escape hatch is on so
        // the first hop can be answered with the stub's address, and the second name is answered
        // with nothing. A refusal at a hop is not observable here — the only address the first hop
        // could reach is the stub, which a denying policy would itself refuse.
        let stub = NetworkAddress.parse("127.0.0.1")!
        let resolver = SeededResolver(answers: ["first.example": [stub]])

        try await FetchTestSupport.withServer(behaviors: [
            "/first": StubFeedServer.Behavior(status: 302, headers: ["Location": "http://second.example/final"]),
        ]) { server in
            try await FetchTestSupport.withFetcher(
                options: FetchTestSupport.options(allowPrivateNetworks: true),
                resolver: resolver
            ) { fetcher in
                let url = URL(string: "http://first.example:\(server.port)/first")!
                do {
                    _ = try await fetcher.fetch(FetchRequest(url: url, headers: [:]))
                    Issue.record("expected the hop that does not resolve to stop the fetch")
                } catch let error as FetchError {
                    #expect(error == .hostnameResolution("second.example"))
                }

                let asked = await resolver.hosts
                #expect(asked == ["first.example", "second.example"])
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

        try await FetchTestSupport.withProxy(response: Data("HTTP/1.1 200 OK\r\nContent-Length: 7\r\n\r\nproxied".utf8)) { proxy in
            let options = FetchTestSupport.options(proxyURL: proxy.base.absoluteString, allowPrivateNetworks: false)
            let builder = FetchRequestBuilder(options: options)

            try await FetchTestSupport.withFetcher(options: options) { fetcher in
                let proxied = try builder.build(feed: FeedFetchState(feedID: 1, url: target, fetchViaProxy: true))
                #expect(proxied.proxyURL == proxy.base)

                let response = try await fetcher.fetch(proxied)
                #expect(response.status == 200)
                #expect(response.body == canned)
                #expect(response.effectiveURL == target)

                // The proxy is the hop the client connected to, and the CONNECT carried the target.
                #expect(proxy.connects() == ["10.0.0.1:80"])

                // The same target, without the flag, is refused: the policy runs before the client is
                // picked, so nothing connects to it.
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

    @Test func proxyURLsUseThePortsUpstreamAssumesWhenTheyGiveNone() throws {
        // `internal/reader/fetcher/request_builder.go` falls back to ports 80, 443 and 1080. A stub
        // proxy on port 0 cannot show this, because the URL would have to name a fixed port, so the
        // helper is checked directly.
        #expect(Fetcher.proxyTarget(from: URL(string: "http://proxy.example")!).port == 80)
        #expect(Fetcher.proxyTarget(from: URL(string: "https://proxy.example")!).port == 443)
        #expect(Fetcher.proxyTarget(from: URL(string: "socks5://proxy.example")!).port == 1080)
        #expect(Fetcher.proxyTarget(from: URL(string: "http://proxy.example:8080")!).port == 8080)
    }
}
