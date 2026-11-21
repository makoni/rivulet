// Ported from Miniflux internal/crypto/crypto.go's `GenerateRandomStringHex` (Apache-2.0); adapted
// for Swift: the port reads its bytes through the standard library's system generator, which is the
// cryptographically secure one on this platform, where the reference reads `crypto/rand`.

import Foundation

/// The token value an api key is stored under.
public enum ApiKeyToken {
    /// `GenerateRandomStringHex(32)`: the number of bytes the reference generates for one key.
    public static let byteCount = 32

    /// One token value: `byteCount` random bytes written as lowercase hex, which is 64 characters.
    public static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0 ..< byteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
