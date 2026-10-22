import Foundation
import Testing
@testable import RivuletCore

/// Resolution and pinning. The policy decides which addresses a fetch may connect to; the fetcher
/// resolves a host once and connects to that validated address, so a later lookup — the classic
/// DNS-rebinding trick — cannot change the target.
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
        // The pinned address is the one the client connects to, so the second answer is never
        // read: a resolver that would return loopback on a later lookup cannot swap in a target.
        #expect(calls == 1)
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
