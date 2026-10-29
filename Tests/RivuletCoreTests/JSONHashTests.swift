import Foundation
import Testing
@testable import RivuletCore

/// The entry identity the JSON Feed adapter writes. Ported from Miniflux
/// `internal/reader/json/parser_test.go`; each case names the upstream test it comes from, and a
/// traced case states the value the reference produces.
///
/// The chain is the four values in the order the reference walks them — `id`, `url`,
/// `external_url`, and then the three content fields concatenated — and the first one that is not
/// empty after the trim is the value hashed.
@Suite struct JSONHashTests {
    private let now = ParsedDate(epochSeconds: 1_700_000_000, nanoseconds: 0, zoneName: "UTC",
        zoneOffsetSeconds: 0)

    private func parse(_ document: String) throws -> ParsedFeed {
        try JSONFeedAdapter.parse(baseURL: "https://example.org/feed.json", data: Data(document.utf8), now: now)
    }

    private func hash(_ item: String) throws -> String {
        try #require(parse("{\"items\": [ \(item) ]}").entries.first?.hash)
    }

    /// `TestParseItemHashPrefersIDOverURL`
    @Test func hashPrefersIDToURL() throws {
        #expect(try hash("{\"id\": \"id-value\", \"url\": \"https://example.org/article\"}")
            == "908ccaff84d840a6cdbfe80a42937106458bfc7a59918e51e6e91d17b9a28bc9")
    }

    /// `TestParseItemHashUsesURLWhenNoID`
    @Test func hashUsesURLWhenThereIsNoID() throws {
        #expect(try hash("{\"url\": \"https://example.org/article\"}")
            == "9eba6b3c57ce169e19742b249a7f7542a620751a5c4b2f2c4990684f7e655f70")
    }

    /// `TestParseItemHashUsesExternalURLFallback`
    @Test func hashUsesExternalURLWhenThereIsNoURL() throws {
        #expect(try hash("{\"external_url\": \"https://example.org/external\"}")
            == "6b69f4bb444fc3d49f4a97666c51199a772b58862f7e86bf51f04ab68a128ad5")
    }

    /// `TestParseItemHashFallsBackToContent` — the last value in the chain is the three content
    /// fields concatenated, in the order the reference writes them.
    @Test func hashFallsBackToTheContentFields() throws {
        #expect(try hash("{\"content_text\": \"Text\", \"content_html\": \"<p>HTML</p>\", \"summary\": \"Summary\"}")
            == "335a20026e200cd32897f93dd806d8bdc3a2249b020d8f00405819353b4cc97f")
    }

    // MARK: - What the chain reads

    /// Traced: the chain reads the fields as the shape holds them rather than the model values, so
    /// the URL is hashed before it is resolved, which is what a relative URL separates here from
    /// the entry URL.
    @Test func chainReadsTheFieldsAsTheyWereRead() throws {
        let entry = try #require(parse("{\"home_page_url\": \"https://example.org/\", "
            + "\"items\": [ { \"url\": \"something.html\" } ]}").entries.first)
        #expect(entry.hash == "ee952ca7333c4babbebc8d5dfcda59341281d5f76a680ce2978426949d2970ed")
        #expect(entry.url == "https://example.org/something.html")
    }

    /// Traced: the content part hashes the plain text as the format wrote it, even though the
    /// content the entry gets is the escaped version of the same value.
    @Test func contentPartOfTheChainIsNotEscaped() throws {
        let entry = try #require(parse("{\"items\": [ { \"content_text\": \"a & b\" } ]}").entries.first)
        #expect(entry.hash == "cbc644a20893a549b9c1d042133f3356adb67ffa4ea5a169071d09965327743f")
        #expect(entry.content == "a &amp; b")
    }

    /// Traced: each value is trimmed before the chain looks at it, so a value that is only
    /// whitespace moves on to the next, and an item with nothing to hash keeps the identity the
    /// model starts with.
    @Test func whitespaceIsNotAValueInTheChain() throws {
        #expect(try hash("{\"id\": \"  \", \"url\": \" https://example.org/article \" }")
            == "9eba6b3c57ce169e19742b249a7f7542a620751a5c4b2f2c4990684f7e655f70")
        #expect(try hash("{\"id\": \"   \"}") == "")
    }
}
