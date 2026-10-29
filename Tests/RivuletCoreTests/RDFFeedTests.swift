import Foundation
import Testing
@testable import RivuletCore

/// The feed-level rules the RDF adapter writes. Ported from Miniflux
/// `internal/reader/rdf/parser_test.go`; each case names the upstream test it comes from, and a
/// traced case states the value the reference produces.
@Suite struct RDFFeedTests {
    private let now = ParsedDate(epochSeconds: 1_700_000_000, nanoseconds: 0, zoneName: "UTC",
        zoneOffsetSeconds: 0)

    private func parse(_ document: String, baseURL: String = "https://example.org/feed") throws -> ParsedFeed {
        try RDFAdapter.parse(baseURL: baseURL, data: Data(document.utf8), now: now)
    }

    /// The shape the reference's `rdf` struct reads: `channel` and `item` are both direct children of
    /// the root, so the document below is written in that shape.
    private func document(_ channel: String, _ item: String, namespaces: String = "") -> String {
        let rdf = " xmlns:rdf=\"http://www.w3.org/1999-02-22-rdf-syntax-ns#\""
        let defaultNamespace = " xmlns=\"http://purl.org/rss/1.0/\""
        return "<rdf:RDF" + rdf + namespaces + defaultNamespace + "><channel>" + channel + "</channel>"
            + item + "</rdf:RDF>"
    }

    // MARK: - The whole document

    /// `TestParseRDFSample`, the reference's sample feed read end to end. The sample's items are direct
    /// children of the root, and the `rdf:Seq` inside `items` lists them without being read as one.
    @Test func sampleFeedIsReadEndToEnd() throws {
        let document = "<rdf:RDF xmlns:rdf=\"http://www.w3.org/1999-02-22-rdf-syntax-ns#\""
            + " xmlns=\"http://purl.org/rss/1.0/\">"
            + "<channel rdf:about=\"http://example.org/feed\"><title>Example Feed</title>"
            + "<link>http://example.org/pub</link>"
            + "<description>\n  Example description.\n  </description>"
            + "<items><rdf:Seq><rdf:li resource=\"http://example.org/a\" /></rdf:Seq></items>"
            + "</channel>"
            + "<image rdf:about=\"http://example.org/icon\"><title>Icon</title>"
            + "<url>http://example.org/icon.png</url></image>"
            + "<item rdf:about=\"http://example.org/a\"><title>First item</title>"
            + "<link>http://example.org/a</link><description>First description</description></item>"
            + "<item rdf:about=\"http://example.org/b\"><title>Second item</title>"
            + "<link>http://example.org/b</link>"
            + "<description>\n Second description\n </description></item>"
            + "</rdf:RDF>"
        let feed = try parse(document, baseURL: "http://example.org/feed")

        #expect(feed.title == "Example Feed")
        #expect(feed.description == "Example description.")
        #expect(feed.feedURL == "http://example.org/feed")
        #expect(feed.siteURL == "http://example.org/pub")

        // The reference has no icon field for this format, so the root-level `image` is not read.
        #expect(feed.iconURL == "")
        #expect(feed.ttlMinutes == 0)

        #expect(feed.entries.count == 2)
        #expect(try #require(feed.entries.first).hash
            == "6a2d6a47a2828fe021aefacd33629435a066843485eac81b46bf451f79461bdb")

        let entry = try #require(feed.entries.last)
        #expect(entry.url == "http://example.org/b")
        #expect(entry.title == "Second item")
        #expect(entry.hash == "13161e97f2d0cbfd5cfe62240392c4ba8792e19c0de710c06da495c19e9a7c15")
        #expect(entry.content == "\n Second description\n ")
        #expect(entry.date == now)
    }

    /// `TestParseRDFSampleWithDublinCore`, the reference's second sample: the channel creator is the
    /// author an entry falls back to, and the entry's own creator wins over it.
    @Test func dublinCoreSampleReadsTheChannelAndTheItemCreator() throws {
        let dc = " xmlns:dc=\"http://purl.org/dc/elements/1.1/\""
        let feed = try parse(document("<title>Meerkat</title><link>http://example.org</link>"
            + "<dc:creator>Channel creator</dc:creator>"
            + "<dc:date>2000-01-01T12:00+00:00</dc:date>",
            "<item><title>Item title</title><link>http://example.org/item</link>"
            + "<dc:creator>Item creator</dc:creator></item>", namespaces: dc),
            baseURL: "http://example.org/feed.rdf")

        #expect(feed.title == "Meerkat")
        #expect(feed.feedURL == "http://example.org/feed.rdf")
        #expect(feed.siteURL == "http://example.org")

        let entry = try #require(feed.entries.first)
        #expect(entry.author == "Item creator")
        #expect(entry.hash == "60deb8081c9dd831a248efda7e2e818e09fe5ff6dc024c57282dcebc2b3d4c76")

        let fallback = try parse(document("<title>Meerkat</title><link>http://example.org</link>"
            + "<dc:creator>Channel creator</dc:creator>", "<item><title>Item title</title>"
            + "<link>http://example.org/item</link></item>", namespaces: dc))
        #expect(try #require(fallback.entries.first).author == "Channel creator")
    }

    // MARK: - Title

    /// `TestParseRDFFeedWithEmptyTitle` — an empty feed title falls back to the base URL, not to the
    /// site URL, which is what separates this format from RSS.
    @Test func feedTitleFallsBackToTheBaseURL() throws {
        let feed = try parse(document("<link>http://example.org/item</link>",
            "<item><title>Example</title><link>http://example.org/item</link></item>"))
        #expect(feed.title == "https://example.org/feed")
    }

    /// Traced: the fallback is the base URL as it was passed in, not as the reference trims it for the
    /// feed URL, so the whitespace stays on the title.
    @Test func titleFallbackKeepsTheBaseURLAsWritten() throws {
        let feed = try parse(document("<link>http://example.org/item</link>",
            "<item><title>Example</title><link>http://example.org/item</link></item>"),
            baseURL: "  https://example.org/feed  ")
        #expect(feed.title == "  https://example.org/feed  ")
        #expect(feed.feedURL == "https://example.org/feed")
    }

    /// The feed title is read through `StripTags`, which is a different pass from the entry title:
    /// `TestParseFeedWithHTMLEntity` pins the entity decoding, and the two cases below separate the
    /// markup the walk drops from a decoded reference, which is what the walk reads as text.
    @Test(arguments: [
        ("<title>&lt;b&gt;Example&lt;/b&gt;</title>", "Example"),
        ("<title>&amp;lt;b&amp;gt;Example&amp;lt;/b&amp;gt;</title>", "<b>Example</b>"),
    ]) func feedTitleIsReadThroughStripTags(titleElement: String, expected: String) throws {
        let feed = try parse(document(titleElement + "<link>http://example.org/</link>",
            "<item><title>Example</title><link>http://example.org/item</link></item>"))
        #expect(feed.title == expected)
    }

    @Test func feedTitleKeepsTheDecodedEntity() throws {
        let feed = try parse(document("<title>Example &nbsp; Feed</title><link>http://example.org/</link>",
            "<item><title>Example</title><link>http://example.org/item</link></item>"))
        #expect(feed.title == "Example \u{00A0} Feed")
    }

    // MARK: - URLs

    /// `TestParseRDFFeedWithEmptyLink`: the site URL is empty, and resolving nothing against the feed
    /// URL is the feed URL itself.
    @Test func siteURLFallsBackToTheFeedURL() throws {
        let feed = try parse(document("<title>Example Feed</title>",
            "<item><title>Example</title><link>http://example.org/item</link></item>"))
        #expect(feed.siteURL == "https://example.org/feed")
        #expect(feed.feedURL == "https://example.org/feed")
    }

    /// `TestParseRDFFeedWithRelativeLink` and `TestParseRDFFeedSiteURLWithTrailingSpace`: the value the
    /// reference resolves is the trimmed link, and the base for that resolution is the feed URL.
    @Test(arguments: [
        ("/test/index.html  ", "https://example.org/test/index.html"),
        ("http://example.org/test/index.html ", "http://example.org/test/index.html"),
    ]) func siteURLIsTrimmedAndResolved(linkValue: String, expected: String) throws {
        let feed = try parse(document("<title>Example Feed</title><link>" + linkValue + "</link>",
            "<item><title>Example</title><link>http://example.org/item</link></item>"))
        #expect(feed.siteURL == expected)
        #expect(feed.feedURL == "https://example.org/feed")
    }

    /// `TestParseFeedWithInvalidCharacterEntity`: a bare ampersand is not a reference, so the value the
    /// reference resolves is the link as it was written.
    @Test func invalidCharacterEntityStaysAsWritten() throws {
        let feed = try parse(document("<title>Example Feed</title><link>http://example.org/a&b</link>",
            "<item><title>Example</title><link>http://example.org/item</link></item>"))
        #expect(feed.siteURL == "http://example.org/a&b")
    }

    /// Traced: when the link cannot be parsed the site URL keeps the trimmed value, because the reference
    /// assigns it before the resolution and overwrites it only on success. An escape the parser refuses is
    /// what reaches this branch, since the control characters it also refuses are removed before decoding.
    @Test func siteURLStaysAsWrittenWhenResolutionFails() throws {
        let feed = try parse(document("<title>Example Feed</title><link>  test%zz.html  </link>",
            "<item><title>Example</title><link>http://example.org/item</link></item>"))
        #expect(feed.siteURL == "test%zz.html")
    }

    // MARK: - Language

    /// `TestParseFeedWithChannelLanguage`, `TestParseFeedWithItemLanguage` and
    /// `TestParseFeedWithoutLanguage`: the language is read from `dc:language` only, an entry inherits the
    /// channel language, and its own value wins.
    @Test(arguments: [
        ("<dc:language>EN-us</dc:language>", "", "en-us", "en-us"),
        ("<dc:language>en</dc:language>", "<dc:language>fr_CA</dc:language>", "en", "fr-ca"),
        ("", "", "", ""),
    ]) func languageComesFromDublinCore(channelElement: String, itemElement: String, expectedFeed: String,
        expectedEntry: String) throws {
        let dc = " xmlns:dc=\"http://purl.org/dc/elements/1.1/\""
        let feed = try parse(document("<title>Example Feed</title><link>http://example.org/</link>"
            + channelElement, "<item><title>Item</title><link>http://example.org/item</link>"
            + itemElement + "</item>", namespaces: dc))
        #expect(feed.language == expectedFeed)
        #expect(try #require(feed.entries.first).language == expectedEntry)
    }

    /// Traced: the reference has no plain `language` field for this format, so a language element in the
    /// RSS 1.0 namespace reads empty even though the same element is the feed language for RSS.
    @Test func plainLanguageElementIsNotRead() throws {
        let feed = try parse(document("<title>Example Feed</title><link>http://example.org/</link>"
            + "<language>en-US</language>", "<item><title>Item</title>"
            + "<link>http://example.org/item</link></item>"))
        #expect(feed.language == "")
        #expect(try #require(feed.entries.first).language == "")
    }

    // MARK: - What this format does not read

    /// Traced: the fields the reference's `rdf` struct has are title, link, description and the
    /// Dublin Core ones, so the icon and the cache lifetime are not read, and an item inside the channel
    /// is not an entry, because items are read at the root level.
    @Test func anItemInsideTheChannelIsNotRead() throws {
        let feed = try parse(document("<title>Example Feed</title><link>http://example.org/</link>"
            + "<image><url>http://example.org/icon.png</url></image><ttl>60</ttl>"
            + "<item><title>Inside the channel</title><link>http://example.org/item</link></item>",
            "<item><title>At the root</title><link>http://example.org/root</link></item>"))
        #expect(feed.iconURL == "")
        #expect(feed.ttlMinutes == 0)
        #expect(feed.entries.count == 1)
        #expect(try #require(feed.entries.first).title == "At the root")
    }

    // MARK: - Failure

    /// `TestParseInvalidXml` — a document with no element at all fails, which is where the reference stops
    /// looking for the start element.
    @Test func aDocumentWithNoElementFails() throws {
        #expect(throws: XMLError.unexpectedEOF) { try parse("garbage") }
    }
}
