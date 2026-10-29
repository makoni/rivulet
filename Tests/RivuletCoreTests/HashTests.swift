import Testing
@testable import RivuletCore

/// The hash the adapters write for an entry identity. Ported from Miniflux
/// `internal/crypto/crypto.go` (`SHA256`), which has no test file upstream, so these values are
/// traced from Go's `crypto/sha256` and `encoding/hex`; the same values are what the corpus asserts,
/// and the RSS suite pins them through the adapter.
@Suite struct HashTests {
    @Test(arguments: [
        ("dup-guid", "22561495b53d916c228504600fda7c06cefc55a80395bbdf007102a6e9070d3f"),
        ("dup-guid|https://example.org/b", "3479bd288c08f8d2f8e992aa511a267ee50b18e22a4c475a4862c15c4d4f675b"),
        ("Item 1", "c5ddfeffb275254140796b8c080f372d65ebb1b0590e238b191f595d5fcd32ca"),
        ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
    ]) func sha256OfTheValue(input: String, expected: String) {
        #expect(Hashes.sha256(input) == expected)
    }

    /// Traced: the input is hashed as its UTF-8 bytes, so a non-ASCII value hashes the encoding
    /// form, not the code point.
    @Test func nonASCIIInputIsHashedAsUTF8Bytes() {
        #expect(Hashes.sha256("é") == "4a99557e4033c3539de2eb65472017cad5f9557f7a0625a09f1c3f6e2ba69c4c")
    }

    /// Traced: `hex.EncodeToString` writes lower-case, which is what the stored hash keeps.
    @Test func theHexIsLowerCaseAndExactlyOneBlockWide() {
        let hash = Hashes.sha256("guid-a")
        #expect(hash.count == 64)
        #expect(hash == hash.lowercased())
    }
}
