// Ported from Miniflux internal/googlereader/middleware.go's `getAuthToken` (Apache-2.0); adapted
// for Swift/SQLite, through the pre-approved `swift-crypto`.

import Crypto
import Foundation

/// The Google Reader token the reference hands out.
///
/// Upstream builds it in `getAuthToken`: the name, a slash, and the hex of
/// `hmac_sha256(key: name + stored_hash, message: empty)`, where the second part of the key is the
/// stored hash, not the value the client sends. `GoogleReaderTokenTests` pins each of those against
/// the reference's own output at the toolchain `go.mod` pins. The token is stateless — nothing
/// stores it — so the same row always answers the same value.
public enum GoogleReaderToken {
    /// The token for one row: the name as it is stored, the slash, and the lowercase hex.
    public static func derive(username: String, storedHash: String) -> String {
        let key = SymmetricKey(data: Data((username + storedHash).utf8))
        return username + "/" + hex(HMAC<SHA256>.authenticationCode(for: Data(), using: key))
    }

    /// The name part of the `name/hash` structure the reference's middleware reads, which is what
    /// its storage lookup is compared against. `GoogleReaderTokenTests` pins the part count and
    /// that an empty part is kept, as Go's `strings.Split` keeps it.
    public static func name(ofToken token: String) -> String? {
        Self.parts(ofToken: token)?.first.map(String.init)
    }

    /// The digest part of the same structure.
    public static func digest(ofToken token: String) -> String? {
        Self.parts(ofToken: token)?.last.map(String.init)
    }

    /// The compare the auth path does. Upstream uses `crypto/subtle.ConstantTimeCompare`, so this
    /// runs in constant time too; no test can read the timing, so what `GoogleReaderTokenTests`
    /// pins is the answer, including that the value is read whole rather than as a prefix.
    public static func matches(expected: String, given: String) -> Bool {
        let expectedBytes = Data(expected.utf8)
        let givenBytes = Data(given.utf8)
        guard expectedBytes.count == givenBytes.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(expectedBytes, givenBytes) {
            difference |= left ^ right
        }
        return difference == 0
    }

    /// Exactly the two parts Go's `strings.Split` gives, with empty parts kept, or nothing.
    private static func parts(ofToken token: String) -> [Substring]? {
        let parts = token.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 2 ? parts : nil
    }

    /// `hex.EncodeToString`: two digits per byte, in lowercase.
    private static func hex(_ mac: some Sequence<UInt8>) -> String {
        mac.map { String(format: "%02x", $0) }.joined()
    }
}
