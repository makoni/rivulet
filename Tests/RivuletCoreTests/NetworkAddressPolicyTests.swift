import Testing
@testable import RivuletCore

/// Which resolved addresses a fetch may connect to. Ported from Miniflux
/// `internal/urllib.IsNonPublicIP` (Apache-2.0); the same set upstream refuses: private,
/// loopback, link-local, multicast, unspecified and the RFC 6598 shared address space.
@Suite struct NetworkAddressPolicyTests {
    private let deny = NetworkAddressPolicy(allowPrivateNetworks: false)
    private let allow = NetworkAddressPolicy(allowPrivateNetworks: true)

    @Test func publicAddressesAreAllowed() throws {
        for text in ["93.184.216.34", "8.8.8.8", "2001:db8::1", "100.63.255.255"] {
            let address = try #require(NetworkAddress.parse(text), Comment("\(text)"))
            #expect(deny.allows(address), Comment("\(text)"))
        }
    }

    @Test func privateAndReservedAddressesAreRefused() throws {
        for text in [
            "10.0.0.1",            // private
            "172.16.0.1",          // private
            "172.31.255.255",      // last private IPv4 address
            "192.168.1.1",         // private
            "100.64.0.0",          // RFC 6598 shared address space
            "100.64.255.255",
            "127.0.0.1",           // loopback
            "169.254.1.1",         // link-local
            "224.0.0.5",           // multicast
            "0.0.0.0",             // unspecified
            "fc00::1",             // unique local address
            "fd12:3456::78",
            "fe80::1",             // link-local
            "ff02::1",             // multicast
            "::",                  // unspecified
            "::1",                 // loopback
        ] {
            let address = try #require(NetworkAddress.parse(text), Comment("\(text)"))
            #expect(!deny.allows(address), Comment("\(text)"))
        }
    }

    @Test func anAddressThatIsNotAnAddressIsRefused() {
        // Upstream treats an unparsable address as non-public, so a hostname never passes.
        #expect(NetworkAddress.parse("feeds.example.com") == nil)
        #expect(!deny.allows(NetworkAddress.parse("10.0.0.1")))
        #expect(!deny.allows(nil))
    }

    @Test func theEscapeHatchAdmitsPrivateTargets() {
        let loopback = NetworkAddress.parse("127.0.0.1")
        #expect(allow.allows(loopback))
        #expect(allow.allows(NetworkAddress.parse("100.64.0.1")))
        // The escape hatch admits everything, which is why it exists for tests only.
        #expect(allow.allows(nil))
    }

    @Test func addressesRoundTripToTheirCanonicalText() throws {
        #expect(NetworkAddress.parse("2001:0db8:0000::0001")?.text == "2001:db8:0:0:0:0:0:1")
        #expect(NetworkAddress.parse("127.0.0.1")?.text == "127.0.0.1")
    }

    @Test func anAddressWithoutCompressionDoesNotReadPastItsGroups() {
        // Regression: `parse` read the second half of a `::` split even when there was none, so a
        // full-form address — or a plain hostname, which is what the fetcher hands it for a host
        // that is not an address — crashed instead of answering.
        let full = NetworkAddress.parse("2001:0db8:0000:0000:0000:0000:0000:0001")
        #expect(full == NetworkAddress.parse("2001:db8::1"))
        #expect(full?.text == "2001:db8:0:0:0:0:0:1")

        #expect(NetworkAddress.parse("fe80:0000:0000:0000:0000:0000:0000:0001")
            == .ipv6([0xFE, 0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]))
        #expect(NetworkAddress.parse("localhost") == nil)
    }
}
