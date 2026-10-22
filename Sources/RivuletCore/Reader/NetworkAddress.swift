import Foundation

/// An IP address, held as bytes so the policy can classify ranges without a resolver.
public enum NetworkAddress: Sendable, Equatable {
    /// Four bytes for IPv4.
    case ipv4([UInt8])

    /// Sixteen bytes for IPv6.
    case ipv6([UInt8])

    /// Parses a dotted-quad or a colon-separated address (with the `::` compression), or nil when
    /// the text is not an address — a hostname is not an address. Zone scopes are not accepted.
    public static func parse(_ text: String) -> NetworkAddress? {
        let value = text.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !value.contains("%") else {
            return nil
        }

        if value.contains(".") {
            let parts = value.split(separator: ".")
            guard parts.count == 4 else {
                return nil
            }
            var bytes: [UInt8] = []
            for part in parts {
                guard let number = Int(part), (0...255).contains(number) else {
                    return nil
                }
                bytes.append(UInt8(number))
            }
            return .ipv4(bytes)
        }

        // Split on `::` at most once: the groups before it, the groups after it, and the zeros
        // in between. Without `::` there is nothing to expand, so the second half does not exist.
        let halves = value.components(separatedBy: "::")
        guard halves.count <= 2, let head = groups(in: halves[0]) else {
            return nil
        }
        var tail: [Int] = []
        if halves.count == 2 {
            guard let parsed = groups(in: halves[1]) else {
                return nil
            }
            tail = parsed
        }

        var groups = head
        if halves.count == 2 {
            let missing = 8 - groups.count - tail.count
            guard missing >= 0 else {
                return nil
            }
            groups.append(contentsOf: repeatElement(0, count: missing))
            groups.append(contentsOf: tail)
        }
        guard groups.count == 8 else {
            return nil
        }

        var bytes: [UInt8] = []
        for group in groups {
            bytes.append(UInt8(group >> 8))
            bytes.append(UInt8(group & 0xFF))
        }
        return .ipv6(bytes)
    }

    /// The colon-separated 16-bit groups of one half of the address, or nil when a group is not a
    /// number in range. An empty half is an empty list, which is what `::` at either end means.
    private static func groups(in text: String) -> [Int]? {
        guard !text.isEmpty else {
            return []
        }
        var groups: [Int] = []
        for part in text.split(separator: ":") {
            guard let number = Int(part, radix: 16), (0...65_535).contains(number) else {
                return nil
            }
            groups.append(number)
        }
        return groups
    }

    /// Canonical text: lowercase, without leading zeros, no compression — the form handed to the
    /// client as the pinned address.
    public var text: String {
        switch self {
        case .ipv4(let bytes):
            return bytes.map { String($0) }.joined(separator: ".")
        case .ipv6(let bytes):
            var groups: [String] = []
            for index in 0..<8 {
                let group = Int(bytes[index * 2]) << 8 | Int(bytes[index * 2 + 1])
                groups.append(String(group, radix: 16))
            }
            return groups.joined(separator: ":")
        }
    }
}
