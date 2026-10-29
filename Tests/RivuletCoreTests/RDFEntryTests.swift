import Foundation
import Testing
@testable import RivuletCore

/// The entry-level rules the RDF adapter writes: the fallback chains, the title and URL fallbacks,
/// the date, the author and the hash. Ported from Miniflux `internal/reader/rdf/parser_test.go`;
/// each case names the upstream test it comes from, and a traced case states the value the reference
/// produces.
@Suite struct RDFEntryTests {
    private let now = ParsedDate(epochSeconds: 1_700_000_000, nanoseconds: 0, zoneName: "UTC",
        zoneOffsetSeconds: 0)

    private let baseNamespaces = " xmlns:rdf=\"http://www.w3.org/1999-02-22-rdf-syntax-ns#\""
        + " xmlns=\"http://purl.org/rss/1.0/\""
    private let dcNamespace = " xmlns:dc=\"http://purl.org/dc/elements/1.1/\""
    private let contentNamespace = " xmlns:content=\"http://purl.org/rss/1.0/modules/content/\""

    private func parse(_ item: String, channel: String = "", namespaces: String = "",
        baseURL: String = "https://example.org/feed") throws -> ParsedFeed {
        let document = "<rdf:RDF" + baseNamespaces + namespaces + "><channel>" + channel + "</channel>"
            + item + "</rdf:RDF>"
        return try RDFAdapter.parse(baseURL: baseURL, data: Data(document.utf8), now: now)
    }

    private func entry(_ item: String, channel: String = "", namespaces: String = "",
        baseURL: String = "https://example.org/feed") throws -> ParsedEntry {
        try #require(parse(item, channel: channel, namespaces: namespaces, baseURL: baseURL).entries.first)
    }

    // MARK: - Title

    /// Traced: the item title tag names the RSS 1.0 namespace, while the channel title tag names none, so
    /// without a declared default namespace the entry title is empty and falls back to the URL, while the
    /// feed title is still read.
    @Test func itemTitleNeedsTheNamespaceTheChannelTitleDoesNot() throws {
        let document = "<rdf:RDF xmlns:rdf=\"http://www.w3.org/1999-02-22-rdf-syntax-ns#\"><channel>"
            + "<title>Example</title><link>http://example.org/</link></channel>"
            + "<item><title>Item</title><link>http://example.org/item</link></item></rdf:RDF>"
        let feed = try RDFAdapter.parse(baseURL: "https://example.org/feed", data: Data(document.utf8), now: now)
        #expect(feed.title == "Example")
        #expect(try #require(feed.entries.first).title == "http://example.org/item")
    }

    /// `TestParseRDFItemWithDuplicateTitleElement` and `TestParseRDFItemWithDublinCoreTitleElement`:
    /// the item title is read first, so it wins over `dc:title`, which is the other way round from RSS.
    @Test(arguments: [
        ("<title>Item Title</title><dc:title/>", "Item Title"),
        ("<dc:title>Dublin Core Title</dc:title>", "Dublin Core Title"),
    ]) func itemTitleWinsOverDublinCoreTitle(itemTitle: String, expected: String) throws {
        #expect(try entry("<item>" + itemTitle + "<link>http://example.org/item</link>"
            + "<description>Test</description></item>", namespaces: dcNamespace).title == expected)
    }

    /// The title is decoded once more than the content is: `TestParseItemWithEncodedHTMLTitle` and
    /// `TestParseRDFWithEncodedHTMLDescription` are the same input read by the two rules.
    @Test func titleIsDecodedOnceAndContentIsNotDecodedAgain() throws {
        let parsed = try entry("<item><title>AT&amp;amp;T</title><description>AT&amp;amp;T</description>"
            + "<link>http://example.org/item</link></item>")
        #expect(parsed.title == "AT&T")
        #expect(parsed.content == "AT&amp;T")
    }

    /// `TestParseRDFItemWitEmptyTitleElement` — a title that is only whitespace is empty after the trim,
    /// so the entry title falls back to the entry URL, which is the last resort for this format: the
    /// reference does not read `TruncateHTML` here, which is what RSS uses first.
    @Test func titleFallsBackToTheEntryURL() throws {
        #expect(try entry("<item><title> </title><description>Test</description>"
            + "<link>http://example.org/item</link></item>").title == "http://example.org/item")
    }

    // MARK: - Content

    /// `TestParseRDFWithContentEncoded`: `content:encoded` is read before the description, and the
    /// tokenizer leaves a CDATA section as it was written.
    @Test func contentEncodedWinsOverTheDescription() throws {
        #expect(try entry("<item><title>Item Title</title><link>http://example.org/item</link>"
            + "<content:encoded><![CDATA[<p>Test</p>]]></content:encoded>"
            + "<description>Not used</description></item>", namespaces: contentNamespace).content
            == "<p>Test</p>")
    }

    /// Traced: the content is the character data at the element's own level, kept as the tokens read it.
    /// The reference trims the feed description, but not an entry's content.
    @Test(arguments: [
        ("<description>Test</description>", "Test"),
        ("<description>\n\tTest\n\t</description>", "\n\tTest\n\t"),
    ]) func entryContentIsNotTrimmed(description: String, expected: String) throws {
        #expect(try entry("<item><title>Test</title><link>http://example.org/item</link>"
            + description + "</item>").content == expected)
    }

    /// Traced: the `Description` field tag names no namespace, so `dc:description` is the description for
    /// this format, and the value is the character data as the tokens read it.
    @Test func dublinCoreDescriptionIsTheDescription() throws {
        #expect(try entry("<item><title>Test</title><link>http://example.org/item</link>"
            + "<dc:description>Not content</dc:description></item>", namespaces: dcNamespace).content
            == "Not content")
    }

    // MARK: - URL

    /// `TestParseItemWithoutLink` and `TestParseItemRelativeURL`: an entry with no link falls back to
    /// the site URL, and a relative link is resolved against the site URL.
    @Test(arguments: [
        ("<link>http://example.org/item</link>", "http://example.org/item"),
        ("<link> </link>", "http://example.org/"),
        ("<link>something.html</link>", "http://example.org/something.html"),
    ]) func entryURLChain(linkElement: String, expected: String) throws {
        #expect(try entry("<item><title>Title</title><description>Test</description>"
            + linkElement + "</item>", channel: "<link>http://example.org/</link>").url == expected)
    }

    /// Traced: the entry is resolved against the site URL rather than the feed URL, so the path the site
    /// URL has is part of the answer. Resolving against the feed URL would drop it.
    @Test func relativeEntryLinkIsResolvedAgainstTheSiteURL() throws {
        let feed = try parse("<item><title>Title</title><description>Test</description>"
            + "<link>post.html</link></item>", channel: "<link>/blog/</link>")
        #expect(feed.siteURL == "https://example.org/blog/")
        #expect(try #require(feed.entries.first).url == "https://example.org/blog/post.html")
    }

    /// `TestParseFeedWithURLWrappedInSpaces`: the value the reference resolves is the trimmed text, so
    /// the whitespace the tokens kept around the link is not part of the URL.
    @Test func entryURLIsTrimmedBeforeItIsResolved() throws {
        #expect(try entry("<item><title>Test</title><description>Test</description>"
            + "<link>\n\thttp://example.org/item?rss=1\n\t</link></item>").url
            == "http://example.org/item?rss=1")
    }

    /// Traced: when the relative value cannot be parsed the reference keeps the link as it read it, so the
    /// entry URL is the link rather than empty. This is an escape the parser refuses, because a control
    /// character cannot reach this branch through the reader: the reference removes the bytes it filters
    /// before decoding.
    @Test func entryURLStaysAsWrittenWhenResolutionFails() throws {
        #expect(try entry("<item><title>Title</title><description>Test</description>"
            + "<link>test%zz.html</link></item>", channel: "<link>http://example.org/</link>").url
            == "test%zz.html")
    }

    // MARK: - Hash

    /// `TestParseItemWithoutLink`: without a link the hash is the title plus the description.
    /// Traced: those are the values as the tokens read them, not as the adapter trims them for the title.
    @Test(arguments: [
        ("<title>Title</title><description>Test</description>",
            "37f5223ebd58639aa62a49afbb61df960efb7dc5db5181dfb3cedd9a49ad34c6"),
        ("<title>Title </title><description>Test</description>",
            "9018a429717fdfb605462dcc1e426f8bc999c333d59e48380e253edb0fb369c2"),
    ]) func hashWithoutALinkUsesTheRawValues(itemContent: String, expected: String) throws {
        #expect(try entry("<item>" + itemContent + "</item>").hash == expected)
    }

    /// Traced: the hash reads the link as the adapter trimmed it, before it is resolved, which is why
    /// this case hashes a different value from the URL it stores.
    @Test func hashUsesTheUnresolvedLink() throws {
        let parsed = try entry("<item><title>Title</title><description>Test</description>"
            + "<link>  something.html  </link></item>", channel: "<link>http://example.org/</link>")
        #expect(parsed.url == "http://example.org/something.html")
        #expect(parsed.hash == "ee952ca7333c4babbebc8d5dfcda59341281d5f76a680ce2978426949d2970ed")
    }

    // MARK: - Date

    /// `TestParseItemWithDublicCoreDate`, `TestParseItemWithoutDate` and
    /// `TestParseItemWithInvalidDublicCoreDate`: the date is read from `dc:date`, and a value that is
    /// empty or cannot be read is the clock.
    @Test(arguments: [
        ("<dc:date>2018-04-10T05:00:00+00:00</dc:date>", 1_523_336_400),
        ("<dc:date>20-04-10T05:00:00+00:00</dc:date>", 1_700_000_000),
        ("", 1_700_000_000),
    ]) func dateComesFromDublinCore(dateElement: String, expectedEpoch: Int64) throws {
        #expect(try entry("<item><title>Title</title><description>Test</description>"
            + "<link>http://example.org/item</link>" + dateElement + "</item>",
            namespaces: dcNamespace).date.epochSeconds == expectedEpoch)
    }

    /// Traced: `pubDate` is not a field of this format, so a document with only a `pubDate` is the clock,
    /// even though the same value is the entry date for RSS.
    @Test func pubDateIsNotRead() throws {
        #expect(try entry("<item><title>Title</title><description>Test</description>"
            + "<link>http://example.org/item</link><pubDate>Tue, 10 Apr 2018 05:00:00 GMT</pubDate></item>")
            .date == now)
    }

    // MARK: - Author and the fields this format does not read

    /// `TestParseItemWithEncodedHTMLInDCCreatorField` and `TestParseItemWithOnlyFeedAuthor`: the item
    /// creator wins over the channel one, and the value is read through `StripTags`.
    @Test(arguments: [
        ("<dc:creator>Item creator</dc:creator>", "Item creator"),
        ("", "Channel creator"),
    ]) func authorChainThroughStripTags(itemCreator: String, expected: String) throws {
        #expect(try entry("<item><title>Title</title><link>http://example.org/item</link>"
            + itemCreator + "</item>", channel: "<dc:creator>Channel creator</dc:creator>",
            namespaces: dcNamespace).author == expected)
    }

    /// Traced: the choice is made on the value as the tokens read it, so a creator that is only whitespace
    /// wins, and `StripTags` answers empty for it — the reference does not trim before the branch, which is
    /// what leaves nothing to fall back to.
    @Test func creatorChoiceIsMadeOnTheValueAsRead() throws {
        #expect(try entry("<item><title>Title</title><link>http://example.org/item</link>"
            + "<dc:creator>  </dc:creator></item>", channel: "<dc:creator>Channel creator</dc:creator>",
            namespaces: dcNamespace).author == "")
    }

    @Test func authorIsReadThroughStripTags() throws {
        #expect(try entry("<item><title>Title</title><link>http://example.org/item</link>"
            + "<dc:creator>&lt;a href=&quot;http://example.org/author1&quot;>Author 1&lt;/a&gt; "
            + "(University 1)</dc:creator></item>", namespaces: dcNamespace).author
            == "Author 1 (University 1)")
    }

    /// Traced: this format has no tag fields, so an entry keeps the empty list the model starts with,
    /// even when the document carries the elements RSS reads.
    @Test func tagsAreNotRead() throws {
        #expect(try entry("<item><title>Title</title><link>http://example.org/item</link>"
            + "<dc:subject>XML</dc:subject></item>", namespaces: dcNamespace).tags == [])
    }

    @Test func enclosuresAreNotRead() throws {
        let parsed = try entry("<item><title>Title</title><link>http://example.org/item</link>"
            + "<enclosure url=\"http://example.org/media.mp3\" length=\"1\" type=\"audio/mpeg\" />"
            + "</item>")
        #expect(parsed.enclosures.isEmpty)
    }

    /// Traced: the comments URL and the reading time are not written by this adapter either.
    @Test func commentsAndReadingTimeAreNotRead() throws {
        let parsed = try entry("<item><title>Title</title><link>http://example.org/item</link>"
            + "<comments>http://example.org/comments</comments></item>")
        #expect(parsed.commentsURL == "")
        #expect(parsed.readingTimeMinutes == 0)
    }
}
