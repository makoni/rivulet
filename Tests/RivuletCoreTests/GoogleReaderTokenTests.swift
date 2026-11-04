import Foundation
import Testing
@testable import RivuletCore

/// The token the reference builds in `getAuthToken` (`internal/googlereader/middleware.go` at
/// `c4d54f87`): the name, a slash, and the hex of
/// `hmac_sha256(key: name + stored_hash, message: empty)`. The goldens below are that run's output
/// at the toolchain `go.mod` pins.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the name part is
/// written as read, which a patch that lowercased it fails on the mixed-case golden; the key is the
/// join of the name and the stored value, which a patch that put the submitted password in the key
/// fails, because the golden is computed from the stored value; the digest is over the empty
/// message, which a patch that hashed the join with a plain SHA-256 fails, and which a patch that
/// swapped key and message fails — the values named below are what those two reads give; the digest
/// is written as lowercase hex, which a patch that wrote it uppercase fails; the separator is the
/// slash, which a patch that joined with the colon the Fever rule uses fails; and the structure
/// rule reads exactly two parts with empty parts kept, which a patch that dropped the empty part
/// fails on the leading-slash input.
///
/// What these pins cannot fail on: the hash function itself — HMAC-SHA256 is the reference's
/// choice, and a golden can only read what the same input produced upstream; the constant-time form
/// of the compare, which the reference uses (`crypto/subtle`) and no test can read; and that the
/// compare is on the whole token, because the name part is also what finds the row, so a patch that
/// compared only the digest answers the same for every input this suite can build.
@Suite struct GoogleReaderTokenTests {
    private let storedHash = "$2a$10$hOrIpoEkDKAMFrOt2/k1yeyHBaZKOwK8zEg9JVchReOAtQZ5mEeFu"

    @Test func theGoldenForTheStoredHashJoin() throws {
        #expect(GoogleReaderToken.derive(username: "userone", storedHash: storedHash) ==
            "userone/cb4f382fa4467e865dd77085df73ec241fc2c74b54adbff3b7df9aeed53ad4f1",
            "the reference's output for the same join")

        // The name as read: the same stored value with a mixed-case name is a different token, so a
        // patch that lowercased the name before writing it fails here.
        #expect(GoogleReaderToken.derive(username: "GrName", storedHash: storedHash) ==
            "GrName/40aea4fe75db5d46476cc30fe0311d43782b8b59f525269cb6f613b38be31867",
            "the name part keeps its case")
    }

    @Test func theDigestIsOverTheEmptyMessageWithTheJoinAsTheKey() throws {
        let token = GoogleReaderToken.derive(username: "userone", storedHash: storedHash)

        // A patch that hashed the join with a plain SHA-256 instead of the HMAC answers this.
        let plainHash = "6490ed2fc7408f3cedc66ced033771839ea960fd4033191383507789b0386133"
        #expect(token != "userone/" + plainHash, "not a plain hash of the join: \(token)")

        // A patch that swapped the key and the message answers this.
        let swapped = "d098a2ca1f034ae61d68e81e5f1674f5367a21be564004cbcf9181856e9809e3"
        #expect(token != "userone/" + swapped, "not the HMAC with key and message swapped: \(token)")

        // The key is the stored value: a patch that read the value the client sends would have to
        // answer the digest for a password, and no password produces this golden.
        #expect(token == "userone/cb4f382fa4467e865dd77085df73ec241fc2c74b54adbff3b7df9aeed53ad4f1",
            "the key is the name joined with the stored hash")
    }

    @Test func theDigestIsWrittenAsLowercaseHex() throws {
        let token = GoogleReaderToken.derive(username: "userone", storedHash: storedHash)
        let digest = try #require(GoogleReaderToken.digest(ofToken: token))
        #expect(digest == "cb4f382fa4467e865dd77085df73ec241fc2c74b54adbff3b7df9aeed53ad4f1",
            "the reference writes hex in lowercase")
        #expect(digest == digest.lowercased(), "no upper-case letter in the value: \(digest)")
    }

    @Test func theSeparatorIsTheSlashTheReferenceJoinsWith() throws {
        let token = GoogleReaderToken.derive(username: "userone", storedHash: storedHash)
        let name = try #require(GoogleReaderToken.name(ofToken: token))
        let digest = try #require(GoogleReaderToken.digest(ofToken: token))

        // Read against the golden, not against the value the same type just built: comparing the
        // token with `name + "/" + digest` would state the rule with the rule and could not fail. A
        // patch that joined with the colon the Fever rule uses reads this token as one part, so the
        // two requires answer nothing here, and the golden equality fails.
        #expect(name == "userone", "the part before the separator: \(name)")
        #expect(digest == "cb4f382fa4467e865dd77085df73ec241fc2c74b54adbff3b7df9aeed53ad4f1",
            "the part after it, read as the reference's golden")
    }

    @Test func theCompareAnswersForEqualStringsOnly() throws {
        let token = GoogleReaderToken.derive(username: "userone", storedHash: storedHash)
        #expect(GoogleReaderToken.matches(expected: token, given: token), "the same value matches")

        // A patch that compared only the prefix of the given value would answer true for this, so
        // the whole value is what the rule reads.
        let longer = token + "x"
        #expect(!GoogleReaderToken.matches(expected: token, given: longer),
            "the given value is read whole, not as a prefix")
        #expect(!GoogleReaderToken.matches(expected: token, given: "userone/abc"),
            "the same name with another digest does not match")
    }

    @Test func theStructureRuleReadsExactlyTwoPartsAndKeepsEmptyOnes() throws {
        #expect(GoogleReaderToken.name(ofToken: "userone/abc") == "userone", "the two-part token")
        #expect(GoogleReaderToken.name(ofToken: "abc") == nil,
            "one part is not the structure the reference reads")
        #expect(GoogleReaderToken.name(ofToken: "a/b/c") == nil, "three parts are not it either")

        // Go's `strings.Split` keeps an empty part, so a leading slash is a two-part token with an
        // empty name; a patch that dropped empty parts would read one part here and answer nil.
        #expect(GoogleReaderToken.name(ofToken: "/abc") == "",
            "the empty name part is kept: \(GoogleReaderToken.name(ofToken: "/abc") ?? "nil")")
    }
}
