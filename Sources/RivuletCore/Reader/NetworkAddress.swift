import Foundation

/// An IP address, held as bytes so the policy can classify ranges without a resolver.
public enum NetworkAddress: Sendable, Equatable {
    /// Four bytes for IPv4.
    case ipv4([UInt8])

    /// Sixteen bytes for IPv6.
    case ipv6([UInt8])

    /// Parses a dotted-quad or a colon-separated address (with the `::` compression) the way Go's
    /// parser reads one: every field must have a digit, a group is at most four hex digits, and
    /// `::` stands for at least one zero group. Returns nil when the text is not an address — a
    /// hostname is not an address — and zone scopes are not accepted.
    ///
    /// The text is trimmed first, which Go's parser does not do; recorded in
    /// `docs/reference-notes.md`.
    public static func parse(_ text: String) -> NetworkAddress? {
        let value = text.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !value.contains("%") else {
            return nil
        }

        // Go decides by shape: a value with a dot is the four-field form, otherwise the groups.
        if value.contains(".") {
            return parseIPv4(value)
        }
        return parseIPv6(value)
    }

    private static func parseIPv4(_ value: String) -> NetworkAddress? {
        // Go requires a digit in every field, so an empty octet is not an address; a split that
        // drops empty parts would accept `1..2.3.4` or `1.2.3.` and the policy would then read a
        // host as an address instead of handing it to the resolver.
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else {
            return nil
        }

        var bytes: [UInt8] = []
        for part in parts {
            // Go reads ASCII digits only here, so a signed group is not a group even though the
            // numeric range check alone would accept "+2", and an octet with a leading zero is
            // rejected.
            guard !part.isEmpty,
                isASCIIDigits(part),
                part.first != "0" || part.count == 1,
                let number = Int(part),
                (0...255).contains(number)
            else {
                return nil
            }
            bytes.append(UInt8(number))
        }
        return .ipv4(bytes)
    }

    private static func parseIPv6(_ value: String) -> NetworkAddress? {
        // Split on `::` at most once: the groups before it, the groups after it, and the zeros
        // in between. Without `::` there is nothing to expand, so the second half does not exist.
        let halves = value.components(separatedBy: "::")
        guard halves.count <= 2, let head = hexGroups(in: halves[0]) else {
            return nil
        }

        var groups = head
        if halves.count == 2 {
            // Go requires `::` to stand for at least one zero group, so a form that leaves nothing
            // to expand is not an address.
            guard let tail = hexGroups(in: halves[1]) else {
                return nil
            }
            let missing = 8 - groups.count - tail.count
            guard missing >= 1 else {
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
    /// number in range. An empty half is an empty list, which is what `::` at either end means; a
    /// lone colon inside a half is not a group, as Go reads the omitted groups as `::`. Named so
    /// the value built from it in `parseIPv6` is not confused with the function.
    private static func hexGroups(in text: String) -> [Int]? {
        guard !text.isEmpty else {
            return []
        }
        var groups: [Int] = []
        for part in text.split(separator: ":", omittingEmptySubsequences: false) {
            // Go's address parser reads ASCII hex digits only — at most four of them, so "+1" and
            // "0abcd" are not groups even though the numeric range check alone would accept them.
            // `Character.isHexDigit` is the ASCII set, which is what Go reads.
            guard !part.isEmpty,
                part.count <= 4,
                part.allSatisfy(\.isHexDigit),
                let number = Int(part, radix: 16),
                (0...65_535).contains(number)
            else {
                return nil
            }
            groups.append(number)
        }
        return groups
    }

    /// ASCII digits only. `Character.isNumber` is true for a digit in any script, which Go's parser
    /// does not read and `Int(_:)` would not convert, so the check here is the narrower one.
    private static func isASCIIDigits(_ text: Substring) -> Bool {
        text.allSatisfy { $0 >= "0" && $0 <= "9" }
    }

    /// The IPv4 form of a 4-in-6 address — what Go's `netip.Addr.Unmap()` gives — or nil when the
    /// bytes are a plain IPv6 address. The policy classifies the unmapped form, like upstream does.
    var unmapped: NetworkAddress? {
        switch self {
        case .ipv4:
            return nil
        case .ipv6(let bytes):
            guard bytes.count == 16,
                bytes[0...9].allSatisfy({ $0 == 0 }),
                bytes[10] == 0xFF,
                bytes[11] == 0xFF
            else {
                return nil
            }
            return .ipv4(Array(bytes[12...15]))
        }
    }

    /// Canonical text: lowercase, without leading zeros, no compression — the form handed to the
    /// client as the pinned address. A 4-in-6 address prints in its IPv4 form, as Go prints it.
    public var text: String {
        switch self {
        case .ipv4(let bytes):
            return bytes.map { String($0) }.joined(separator: ".")
        case .ipv6(let bytes):
            if let v4 = unmapped {
                return v4.text
            }
            var groups: [String] = []
            for index in 0..<8 {
                let group = Int(bytes[index * 2]) << 8 | Int(bytes[index * 2 + 1])
                groups.append(String(group, radix: 16))
            }
            return groups.joined(separator: ":")
        }
    }
}
