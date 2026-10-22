import Foundation
import Testing
@testable import RivuletCore

/// Resolution, pinning and the client cache. The policy decides which addresses a fetch may connect
/// to; the fetcher resolves a direct hop through the seam and pins the client it builds to a validated
/// address, so a later lookup — the classic DNS-rebinding trick — cannot change the target, and a cached
/// client keeps the address it was built with. What the cache guarantees is the key it is
/// built from, and that is what is asserted here.
@Suite struct AddressResolutionTests {
    /// Answers the first lookup with `first`, every later lookup with `later`, and counts calls.
    actor RecordingResolver: AddressResolver {
        private let first: [NetworkAddress]
        private let later: [NetworkAddress]
        private(set) var calls = 0

        init(first: [NetworkAddress], later: [NetworkAddress] = []) {
            self.first = first
            self.later = later
        }

        func resolve(host: String) async throws -> [NetworkAddress] {
            calls += 1
            return calls == 1 ? first : later
        }
    }

    private func fetcher(
        resolver: any AddressResolver,
        allowPrivateNetworks: Bool = false
    ) -> Fetcher {
        Fetcher(options: FetcherOptions(
            timeout: .seconds(1),
            userAgent: FetcherOptions.defaultUserAgent,
            acceptHeader: FetcherOptions.defaultAcceptHeader,
            maxBodySize: 1024,
            maxRedirects: 1,
            decompression: true,
            ignoreHTTPCache: false,
            proxyURL: nil,
            allowPrivateNetworks: allowPrivateNetworks
        ), resolver: resolver)
    }

    @Test func publicAddressIsPinnedAndNotResolvedAgain() async throws {
        let resolver = RecordingResolver(
            first: [NetworkAddress.parse("93.184.216.34")!],
            later: [NetworkAddress.parse("127.0.0.1")!]
        )
        let pinned = try await fetcher(resolver: resolver).resolveAndPin(host: "example.com")

        #expect(pinned == NetworkAddress.parse("93.184.216.34"))
        let calls = await resolver.calls
        #expect(calls == 1)
        // One lookup, and the answer it gave is what the fetcher pins. That the client then connects to
        // the pinned address rather than resolving again is proven in
        // `Tests/RivuletIntegrationTests/FetcherSecurityTests.swift`; here only the single lookup is
        // observable.
    }

    @Test func everyAnsweredAddressIsValidatedBeforeConnecting() async throws {
        let resolver = RecordingResolver(
            first: [NetworkAddress.parse("93.184.216.34")!, NetworkAddress.parse("10.0.0.1")!]
        )
        do {
            _ = try await fetcher(resolver: resolver).resolveAndPin(host: "example.com")
            Issue.record("expected the private address in the answer to be refused")
        } catch let error as FetchError {
            #expect(error == .privateNetworkHost("example.com"))
        }
    }

    @Test func aHostThatDoesNotResolveIsRefused() async throws {
        let resolver = RecordingResolver(first: [])
        do {
            _ = try await fetcher(resolver: resolver).resolveAndPin(host: "example.com")
            Issue.record("expected a resolution failure")
        } catch let error as FetchError {
            #expect(error == .hostnameResolution("example.com"))
        }
    }

    @Test func theCacheKeyKeepsHostsAndProxyDecisionsApart() throws {
        // What the cache guarantees is a mechanism, not something a connection can show: two hosts
        // answered with the same stub address behave the same whichever client serves them. So the key
        // itself is asserted — it is what makes "a pin is never reused for another host or a proxied
        // request" true.
        #expect(Fetcher.cacheKey(host: "a.example", proxyURL: nil)
            != Fetcher.cacheKey(host: "b.example", proxyURL: nil))
        #expect(Fetcher.cacheKey(host: "a.example", proxyURL: nil)
            != Fetcher.cacheKey(host: "a.example", proxyURL: URL(string: "http://proxy.example:8080")!))
    }

    @Test func theSystemResolverAnswersANumericHostWithoutContactingAnyone() async throws {
        // The resolver is the public API that cannot be tested against a network. A numeric host is the
        // part that can: `getaddrinfo` answers a numeric host from the string itself, so nothing is
        // contacted. This is also the only place the byte order of the raw `addrinfo` layout is pinned.
        let resolver = SystemAddressResolver()
        let v4 = try await resolver.resolve(host: "127.0.0.1")
        #expect(v4 == [.ipv4([127, 0, 0, 1])])

        let v6 = try await resolver.resolve(host: "::1")
        #expect(v6 == [.ipv6([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1])])
    }

    @Test func theHostFromABracketedUrlIsTheAddressWithoutBrackets() throws {
        // The pin and the `dnsOverride` key both come from `URL.host`, and they agree because Foundation
        // gives the bracketed form back without brackets on Linux. If a future release kept the brackets,
        // `NetworkAddress.parse` would read the host as a name instead of an address, and the policy would
        // look the bracketed text up rather than classify it. Go's parser rejects brackets too, so the
        // address itself is the value either way.
        #expect(URL(string: "http://[::1]:8080/feed")?.host == "::1")

        // A bracket is not part of the address text, which Go's `netip.ParseAddr` rejects too, so the
        // value that reaches `parse` has to be the host without them.
        #expect(NetworkAddress.parse("[::1]") == nil)
    }

    @Test func anAddressHostIsCheckedWithoutALookup() async throws {
        let resolver = RecordingResolver(first: [])

        do {
            _ = try await fetcher(resolver: resolver).resolveAndPin(host: "::1")
            Issue.record("expected the loopback address to be refused")
        } catch let error as FetchError {
            #expect(error == .privateNetworkHost("::1"))
        }

        // With the escape hatch an address host is pinned directly, without a lookup.
        let pinned = try await fetcher(resolver: resolver, allowPrivateNetworks: true)
            .resolveAndPin(host: "127.0.0.1")
        #expect(pinned == NetworkAddress.parse("127.0.0.1"))
        let calls = await resolver.calls
        #expect(calls == 0)
    }

    @Test func theEscapeHatchPinsPrivateTargetsForTests() async throws {
        let resolver = RecordingResolver(first: [NetworkAddress.parse("127.0.0.1")!])
        let pinned = try await fetcher(resolver: resolver, allowPrivateNetworks: true)
            .resolveAndPin(host: "localhost")
        #expect(pinned == NetworkAddress.parse("127.0.0.1"))
    }
}
