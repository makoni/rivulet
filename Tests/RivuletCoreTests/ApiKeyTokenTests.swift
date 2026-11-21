import Foundation
import Testing
@testable import RivuletCore

/// The token value an api key is stored under, ported from Miniflux `internal/crypto/crypto.go`'s
/// `GenerateRandomStringHex(32)` at commit `c4d54f87` (Apache-2.0).
///
/// What these pins can fail on, each checked by patching the rule and reverting: the byte count,
/// which a patch that generated a different number of bytes fails on, and the form, which a patch
/// that wrote the bytes in uppercase fails on for the alphabet line and one that wrote them as
/// decimal digits fails on for the length line. Two calls answering the same value is the rule the
/// second pin reads, which a patch that fixed the answer fails on. The byte-count and form patches
/// are rules the command's row is written from, so they fire `CreateApiKeyTests` as well; the fixed
/// answer fires only the pin it names.
///
/// What they cannot fail on: the randomness of a single value, which no pin can read as a property
/// of one call — the pins read the alphabet, the length, and that two calls differ, which is the
/// weakest form of the rule a test can state. The reference reads its bytes through `crypto/rand`;
/// the port reads them through the standard library's system generator, which is the
/// cryptographically secure one on this platform, and that choice is recorded in `docs/parity.md`.
@Suite struct ApiKeyTokenTests {
    private static let hexCharacters: Set<Character> = [
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f",
    ]

    @Test func theTokenIsThirtyTwoBytesWrittenAsLowercaseHex() {
        #expect(ApiKeyToken.byteCount == 32, "the count the reference generates")

        let token = ApiKeyToken.generate()
        #expect(token.count == 64, "32 bytes read as hex are 64 characters")
        #expect(token.allSatisfy { Self.hexCharacters.contains($0) },
            "the hex alphabet, lowercase, which is what `hex.EncodeToString` writes")
    }

    @Test func twoCallsAnswerDifferentValues() {
        #expect(ApiKeyToken.generate() != ApiKeyToken.generate(),
            "a fixed answer would make every key the same token")
    }
}
