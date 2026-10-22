import Foundation

/// Decides which resolved addresses a fetch may connect to.
///
/// Ported from Miniflux `internal/urllib.IsNonPublicIP` (Apache-2.0): the same set upstream
/// refuses — private, loopback, link-local, multicast, unspecified and the RFC 6598 shared
/// address space. An address that is not an address counts as non-public, like Go's `nil`. A 4-in-6
/// address is classified through its IPv4 form, as Go unmaps it before checking.
///
/// The check runs on the address resolved and pinned for the hop, not on a name resolved again
/// later, so a second lookup cannot swap in a private target.
///
/// Internal: the fetcher is the only caller, and the address policy is not something a stage later
/// builds a feed from. The tests reach it through `@testable import`.
struct NetworkAddressPolicy: Sendable, Equatable {
    /// Escape hatch for private targets (`FETCHER_ALLOW_PRIVATE_NETWORKS`), off by default and
    /// meant for tests: when it is on, every address is admitted.
    let allowPrivateNetworks: Bool

    /// Creates a policy.
    init(allowPrivateNetworks: Bool) {
        self.allowPrivateNetworks = allowPrivateNetworks
    }

    /// Whether a connection to `address` is allowed.
    func allows(_ address: NetworkAddress?) -> Bool {
        if allowPrivateNetworks {
            return true
        }
        guard let address else {
            return false
        }
        return !isPrivate(address)
    }

    // Go unmaps a 4-in-6 address before classifying it (`netip.Addr.Unmap()` in `IsNonPublicIP`), so
    // the IPv4 ranges apply to a mapped address too.
    private func isPrivate(_ address: NetworkAddress) -> Bool {
        if let mapped = address.unmapped {
            return isPrivate(mapped)
        }
        switch address {
        case .ipv4(let bytes):
            return isPrivateV4(bytes)
        case .ipv6(let bytes):
            return isPrivateV6(bytes)
        }
    }

    // RFC 6598 shared address space, checked first like upstream, then the ranges Go's
    // `IsPrivate`, `IsLoopback`, `IsLinkLocalUnicast`, `IsLinkLocalMulticast`, `IsMulticast` and
    // `IsUnspecified` cover for IPv4.
    private func isPrivateV4(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 4 else {
            return true
        }
        let (a, b) = (bytes[0], bytes[1])
        switch a {
        case 10:
            return true
        case 172 where (16...31).contains(b):
            return true
        case 192 where b == 168:
            return true
        case 100 where (64...127).contains(b):
            return true // 100.64.0.0/10
        case 127:
            return true
        case 169 where b == 254:
            return true
        case 224...239:
            return true
        case 0 where b == 0 && bytes[2] == 0 && bytes[3] == 0:
            return true // 0.0.0.0
        default:
            return false
        }
    }

    // Go's `IsPrivate` covers fc00::/7, `IsLinkLocalUnicast` fe80::/10, `IsMulticast` ff00::/8,
    // `IsLoopback` ::1 and `IsUnspecified` ::.
    private func isPrivateV6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else {
            return true
        }
        if bytes[0] & 0xFE == 0xFC {
            return true // fc00::/7
        }
        if bytes[0] == 0xFE && bytes[1] & 0xC0 == 0x80 {
            return true // fe80::/10
        }
        if bytes[0] == 0xFF {
            return true // ff00::/8
        }
        if bytes[0...14].allSatisfy({ $0 == 0 }) {
            // ::1 loopback, or :: unspecified
            return bytes[15] == 1 || bytes[15] == 0
        }
        return false
    }
}
