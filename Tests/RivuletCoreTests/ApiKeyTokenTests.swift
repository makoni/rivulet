import Foundation
import Testing
@testable import RivuletCore

/// The generator the reference reads through `crypto/rand`, pinned as pure logic. The rule is the
/// shape it writes — 32 bytes as 64 lowercase hex characters — and that two calls answer different
/// values, which is the weakest form of a rule a test can state about randomness.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the byte count,
/// which fires the count line and the length line that follows from it; the way a byte is written
/// as digits, which fires only the length line, because the string the patch answers is shorter or
/// holds characters the alphabet does not have; the case, which fires only its own line, because a
/// byte written with the padding and the alphabet intact still reads as 64 characters; and the
/// fixed answer, which fires only its own line. Four of these five patches fire
/// `CreateApiKeyTests`' row pin as well, because the command derives the value it writes through
/// this same function, while the fixed-answer patch does not, because that pin reads the token as
/// the shape the generator writes and a fixed answer of that shape answers it.
///
/// What they cannot fail on: which generator the bytes come from, which no test reads, and the
/// reference's own wording for the value, which this port has none of.
///
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
