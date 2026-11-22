// The header block as Go's `net/http` reads it for this path: `Header.Get` for one name, and
// `Request.BasicAuth` through `parseBasicAuth` (Apache-2.0 reference behavior); adapted for Swift.

import Foundation

/// The header block one request carries, read the way Go's `Header` map reads it.
///
/// The lines are the data this read works over, so the read is pinned as pure logic by
/// `RestV1HeadersTests`; the route half builds it from the request it was given.
struct RestV1Headers {
    /// The lines as they came in, in the order they arrived.
    let lines: [(name: String, value: String)]

    init(lines: [(name: String, value: String)]) {
        self.lines = lines
    }

    /// `Header.Get`: the first value carried for the name, and the empty value for a name the
    /// request does not carry, which is what the guard reads. Go canonicalizes names through
    /// `textproto`, so the two cases of one name count as one name and the first line is the value
    /// kept — the rule the pin that carries the name twice reads.
    func value(named name: String) -> String {
        for line in lines where line.name.lowercased() == name.lowercased() { return line.value }
        return ""
    }

    /// `Request.BasicAuth`: the pair read from the value this read answers for `Authorization`.
    ///
    /// `parseBasicAuth` compares the prefix case-insensitively, decodes the whole rest of the value
    /// — so a second space is part of what is decoded, and the alphabet does not have it — skips
    /// only the two newlines, fails on anything else the alphabet does not have, and splits the
    /// decoded value at the first colon. The quantum rule is the port's own, recorded in
    /// `docs/parity.md`: Go reports a last quantum shorter than four characters as an error even
    /// when the padding is at the end, where this read decodes it. A value whose padding is not at
    /// the end is an error on both sides, so nothing here tells the two readings apart for it.
    func basicCredentials() -> Credentials {
        let bytes = [UInt8](value(named: "Authorization").utf8)
        let prefix: [UInt8] = Array("Basic ".utf8)
        guard bytes.count >= prefix.count, Self.equalFoldASCII(bytes.prefix(prefix.count), prefix) else {
            return Credentials(name: "", password: "", read: false)
        }

        let encoded = String(decoding: bytes[prefix.count...].filter { $0 != 0x0A && $0 != 0x0D },
            as: UTF8.self)
        guard let decoded = Data(base64Encoded: encoded) else {
            return Credentials(name: "", password: "", read: false)
        }

        // `strings.Cut`: no separator is the half that reports the pair as not read.
        let parts = String(decoding: decoded, as: UTF8.self)
            .split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return Credentials(name: "", password: "", read: false) }
        return Credentials(name: String(parts[0]), password: String(parts[1]), read: true)
    }

    /// The pair `parseBasicAuth` answers: the name and the password, and whether the value was read
    /// at all, which is what `authOK` says upstream.
    struct Credentials {
        let name: String
        let password: String
        let read: Bool
    }

    /// `ascii.EqualFold` over bytes: each byte is read as its ASCII lowercase form, so the two
    /// cases of an ASCII letter are the same and nothing else is folded, which is narrower than
    /// Swift's `lowercased()`.
    private static func equalFoldASCII(_ left: ArraySlice<UInt8>, _ right: [UInt8]) -> Bool {
        for (a, b) in zip(left, right) where lowerASCII(a) != lowerASCII(b) { return false }
        return true
    }

    /// `ascii.lower`: an ASCII uppercase letter folded to its lowercase form, everything else as it
    /// is.
    private static func lowerASCII(_ byte: UInt8) -> UInt8 {
        byte >= 0x41 && byte <= 0x5A ? byte | 0x20 : byte
    }
}
