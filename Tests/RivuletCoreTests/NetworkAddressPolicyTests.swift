import Testing
@testable import RivuletCore

/// Which resolved addresses a fetch may connect to. Ported from Miniflux
/// `internal/urllib.IsNonPublicIP` (Apache-2.0); the same set upstream refuses: private,
/// loopback, link-local, multicast, unspecified and the RFC 6598 shared address space.
/// (ported test: `TestIsNonPublicIP`, `internal/urllib/url_test.go`.)
@Suite struct NetworkAddressPolicyTests {
    private let deny = NetworkAddressPolicy(allowPrivateNetworks: false)
    private let allow = NetworkAddressPolicy(allowPrivateNetworks: true)

    /// The first twelve bytes of a 4-in-6 address, the form `getaddrinfo` answers with.
    private let prefix: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xFF, 0xFF]

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

    @Test func anOctetWithALeadingZeroIsNotAnAddressLikeGoRejectsIt() throws {
        // `netip.ParseAddr` — what `net.ParseIP` uses — rejects an octet with a leading zero, so
        // the reference never treats `010.1.1.1` as an address. Rivulet must not be more lenient.
        #expect(NetworkAddress.parse("010.1.1.1") == nil)
        #expect(NetworkAddress.parse("1.2.3.04") == nil)
        #expect(NetworkAddress.parse("10.1.1.1") == NetworkAddress.ipv4([10, 1, 1, 1]))
    }

    @Test func anEmptyOctetIsNotAnAddressLikeGoRejectsIt() throws {
        // Go rejects an IPv4 field with no digit, so `1..2.3.4`, `1.2.3.` and `.1.2.3.4` are not
        // addresses. A split that drops empty parts would accept them, and the policy would then
        // read a host as an address it should hand to the resolver instead.
        #expect(NetworkAddress.parse("1..2.3.4") == nil)
        #expect(NetworkAddress.parse("1.2.3.") == nil)
        #expect(NetworkAddress.parse(".1.2.3.4") == nil)
        #expect(NetworkAddress.parse("1.2.3.4") == NetworkAddress.ipv4([1, 2, 3, 4]))
    }

    @Test func aGroupIsNotLongerThanFourDigitsAndTheCompressionExpandsToAtLeastOneGroupLikeGo() throws {
        // Go reads at most four hex digits per group and requires `::` to stand for at least one
        // zero group, so `0abcd::1` and `1:2:3:4:5:6:7:8::` are not addresses even though the
        // numeric value still fits 16 bits.
        #expect(NetworkAddress.parse("0abcd::1") == nil)
        #expect(NetworkAddress.parse("1:2:3:4:5:6:7:8::") == nil)
        #expect(NetworkAddress.parse("abcd::1") != nil)
        #expect(NetworkAddress.parse("::") != nil)
    }

    @Test func addressesRoundTripToTheirCanonicalText() throws {
        #expect(NetworkAddress.parse("2001:0db8:0000::0001")?.text == "2001:db8:0:0:0:0:0:1")
        #expect(NetworkAddress.parse("127.0.0.1")?.text == "127.0.0.1")
    }

    @Test func mappedAddressesAreJudgedByTheIPv4RangesLikeUpstreamUnmapsThemFor() throws {
        // Upstream unmaps a 4-in-6 address before classifying it (`netip.Addr.Unmap()` in
        // `IsNonPublicIP`), and Go prints it in its IPv4 form, so a mapped private address is
        // refused and its canonical text is the dotted quad. A resolver hands the policy bytes, so
        // the test builds them the way `getaddrinfo` would.
        for quad in [[10, 0, 0, 1], [127, 0, 0, 1], [169, 254, 1, 1], [100, 64, 0, 1]] {
            let text = quad.map(String.init).joined(separator: ".")
            let mapped = NetworkAddress.ipv6(prefix + quad.map { UInt8($0) })
            #expect(!deny.allows(mapped), Comment("::ffff:\(text)"))
            #expect(allow.allows(mapped), Comment("escape hatch still admits ::ffff:\(text)"))
            #expect(mapped.text == text, Comment("canonical text for ::ffff:\(text)"))
        }

        let mappedPublic = NetworkAddress.ipv6(prefix + [93, 184, 216, 34].map { UInt8($0) })
        #expect(deny.allows(mappedPublic), Comment("a mapped public address stays public"))
        #expect(mappedPublic.text == "93.184.216.34")
    }

    @Test func aGroupIsNotAcceptedWithASignLikeGoParsesHexGroups() throws {
        // Go's parser reads groups as hex digits only, so "+1" is not a group; the numeric range
        // check alone would have accepted it. The dotted-quad path reads digits only as well.
        #expect(NetworkAddress.parse("::+1") == nil)
        #expect(NetworkAddress.parse("1.+2.3.4") == nil)
        #expect(NetworkAddress.parse("::1") == NetworkAddress.ipv6([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]))
    }

    @Test func aLoneColonIsNotTheCompressionLikeGoParsesAddresses() throws {
        // Go reads the omitted groups as `::` — two colons — so a lone leading colon is not an
        // empty group, and the form `:1:2:...` must not be accepted as an address.
        #expect(NetworkAddress.parse(":1:2:3:4:5:6:7:8") == nil)
        #expect(NetworkAddress.parse("1:2:3:4:5:6:7:8") != nil)
        #expect(NetworkAddress.parse("::1") != nil)
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
