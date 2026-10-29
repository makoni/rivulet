import Foundation
import Testing
@testable import RivuletCore

/// The feed-level rules the RSS adapter writes. Ported from Miniflux
/// `internal/reader/rss/parser_test.go`; each case names the upstream test it comes from, and a
/// traced case states the value the reference produces.
@Suite struct RSSFeedTests {
    private let now = ParsedDate(epochSeconds: 1_700_000_000, nanoseconds: 0, zoneName: "UTC",
        zoneOffsetSeconds: 0)

    private func parse(_ document: String, baseURL: String = "https://example.org/") throws -> ParsedFeed {
        try RSSAdapter.parse(baseURL: baseURL, data: Data(document.utf8), now: now)
    }

    // MARK: - The whole document

    /// `TestParseRss2Sample`, the reference's sample feed read end to end, with the image, the
    /// decoded description and the guid that is a permalink.
    @Test func sampleFeedIsReadEndToEnd() throws {
        let feed = try parse("<rss version=\"2.0\"><channel><title>Liftoff News</title>"
            + "<link>http://liftoff.msfc.nasa.gov/</link><description>Liftoff to Space Exploration.</description>"
            + "<image><url>http://liftoff.msfc.nasa.gov/HomePageXtra/MeatBall.gif</url>"
            + "<title>NASA</title><link>http://liftoff.msfc.nasa.gov/</link></image>"
            + "<language>en-us</language><pubDate>Tue, 10 Jun 2003 04:00:00 GMT</pubDate>"
            + "<managingEditor>editor@example.com</managingEditor>"
            + "<item><title>Star City</title><link>http://liftoff.msfc.nasa.gov/news/2003/news-starcity.asp</link>"
            + "<description>Star City at &lt;a href=\"http://howe.iki.rssi.ru/GCTC/gctc_e.htm\"&gt;Russia&lt;/a&gt;."
            + "</description><pubDate>Tue, 03 Jun 2003 09:39:21 GMT</pubDate>"
            + "<guid>http://liftoff.msfc.nasa.gov/2003-06-03.html#item573</guid></item></channel></rss>",
            baseURL: "http://liftoff.msfc.nasa.gov/rss.xml")

        #expect(feed.title == "Liftoff News")
        #expect(feed.description == "Liftoff to Space Exploration.")
        #expect(feed.feedURL == "http://liftoff.msfc.nasa.gov/rss.xml")
        #expect(feed.siteURL == "http://liftoff.msfc.nasa.gov/")
        #expect(feed.iconURL == "http://liftoff.msfc.nasa.gov/HomePageXtra/MeatBall.gif")
        #expect(feed.language == "en-us")

        let entry = try #require(feed.entries.first)
        #expect(feed.entries.count == 1)
        #expect(entry.date.epochSeconds == 1_054_633_161)
        #expect(entry.hash == "53a7095cd461de03a1e2c546ba6fce438af944af23fe1a46d8dd3ccd2929abd6")
        #expect(entry.url == "http://liftoff.msfc.nasa.gov/news/2003/news-starcity.asp")
        #expect(entry.title == "Star City")
        #expect(entry.content == "Star City at <a href=\"http://howe.iki.rssi.ru/GCTC/gctc_e.htm\">Russia</a>.")
        #expect(entry.author == "editor@example.com")
    }

    // MARK: - Title

    /// `TestParseFeedWithoutTitle` — an empty feed title falls back to the site URL.
    @Test func feedTitleFallsBackToTheSiteURL() throws {
        let feed = try parse("<rss version=\"2.0\"><channel><link>https://example.org/</link>"
            + "<item><link>https://example.org/item</link></item></channel></rss>")
        #expect(feed.title == "https://example.org/")
    }

    /// The feed title is unescaped once, while the entry title is unescaped twice. `TestParseFeedTitleWithHTMLEntity`
    /// and `TestParseItemTitleWithDoubleEncodedEntities` pin the two passes; the pair below is the
    /// case that separates them.
    @Test func feedTitleIsUnescapedOnceAndEntryTitleTwice() throws {
        let document = "<rss version=\"2.0\"><channel><title>&amp;amp;#39;a</title>"
            + "<link>https://example.org/</link><item><title>&amp;amp;#39;b</title>"
            + "<link>https://example.org/item</link></item></channel></rss>"
        let feed = try parse(document)
        #expect(feed.title == "&#39;a")
        #expect(try #require(feed.entries.first).title == "'b")
    }

    /// `TestParseItemTitleWithCDATA`: inside a CDATA section the reference does not decode the
    /// references, so the second unescape pass is what resolves them.
    @Test func cdataTitleIsDecodedByTheSecondPass() throws {
        let feed = try parse("<rss version=\"2.0\"><channel><link>https://example.org/</link>"
            + "<item><title><![CDATA[Jenny&#8217;s Newsletter]]></title>"
            + "<link>https://example.org/item</link></item></channel></rss>")
        #expect(try #require(feed.entries.first).title == "Jenny\u{2019}s Newsletter")
    }

    // MARK: - URLs

    /// Traced: the feed URL is the base URL as the reference trims it, as long as nothing else claims
    /// it. `TestParseRss2Sample` pins the same value with an untrimmed base URL.
    @Test(arguments: [
        ("https://example.org/ ", "https://example.org/"),
        ("https://example.org/", "https://example.org/"),
    ]) func feedURLIsTheTrimmedBaseURL(baseURL: String, expected: String) throws {
        let feed = try parse(
            "<rss version=\"2.0\"><channel><title>Example</title><link>https://example.org/</link>"
                + "<item><title>Test</title><link>https://example.org/item</link></item></channel></rss>",
            baseURL: baseURL
        )
        #expect(feed.feedURL == expected)
    }

    /// `TestParseFeedWithFeedURLWithTrailingSpace`, `TestParseFeedWithRelativeFeedURL` and
    /// `TestParseFeedURLWithAtomLink`: the base URL is replaced only by an `atom:link` with `rel="self"`,
    /// and the href is resolved against the trimmed base URL, which is the value the reference uses as
    /// the base for that resolution.
    @Test(arguments: [
        ("https://example.org/ ", "<atom:link href=\"https://example.org/rss \" rel=\"self\"></atom:link>",
            "https://example.org/rss"),
        ("https://example.org/", "<atom:link href=\"/rss\" rel=\"self\"></atom:link>",
            "https://example.org/rss"),
    ]) func feedURLComesFromTheAtomSelfLink(baseURL: String, atomLink: String, expected: String) throws {
        let feed = try parse("<rss version=\"2.0\" xmlns:atom=\"http://www.w3.org/2005/Atom\"><channel>"
            + "<title>Example</title><link>https://example.org/</link>" + atomLink
            + "<item><title>Test</title><link>https://example.org/item</link></item></channel></rss>",
            baseURL: baseURL)
        #expect(feed.feedURL == expected)
    }

    /// Traced: any other relation is not read, and an empty href is skipped, so the base URL stays.
    @Test(arguments: [
        "<atom:link href=\"https://example.org/rss\" rel=\"alternate\"></atom:link>",
        "<atom:link href=\"  \" rel=\"self\"></atom:link>",
    ]) func otherAtomLinkRelationsAreNotRead(atomLink: String) throws {
        let feed = try parse("<rss version=\"2.0\" xmlns:atom=\"http://www.w3.org/2005/Atom\"><channel>"
            + "<title>Example</title><link>https://example.org/</link>" + atomLink
            + "<item><title>Test</title><link>https://example.org/item</link></item></channel></rss>")
        #expect(feed.feedURL == "https://example.org/")
    }

    /// Traced: `translate` leaves an undefined prefix as it was written, so without the declaration the
    /// atom link is not an atom link and the base URL stays.
    @Test func anAtomLinkWithoutItsDeclarationIsNotRead() throws {
        let feed = try parse("<rss version=\"2.0\"><channel><title>Example</title>"
            + "<link>https://example.org/</link><atom:link href=\"https://example.org/rss\" rel=\"self\">"
            + "</atom:link><item><title>Test</title><link>https://example.org/item</link></item>"
            + "</channel></rss>")
        #expect(feed.feedURL == "https://example.org/")
    }

    /// `TestParseFeedSiteURLWithTrailingSpace` and `TestParseFeedWithRelativeSiteURL`.
    @Test(arguments: [
        ("https://example.org/ ", "https://example.org/"),
        ("/example ", "https://example.org/example"),
    ]) func siteURLIsTrimmedAndResolved(linkValue: String, expected: String) throws {
        let feed = try parse("<rss version=\"2.0\"><channel><title>Example</title>"
            + "<link>" + linkValue + "</link><item><title>Test</title>"
            + "<link>https://example.org/item</link></item></channel></rss>")
        #expect(feed.siteURL == expected)
    }

    /// `TestParseRss2Sample` keeps the image URL; it is resolved against the site URL, which is what
    /// the reference resolves the icon against.
    @Test(arguments: [
        ("http://liftoff.msfc.nasa.gov/HomePageXtra/MeatBall.gif",
            "http://liftoff.msfc.nasa.gov/HomePageXtra/MeatBall.gif"),
        ("/icon.gif", "https://example.org/icon.gif"),
    ]) func iconURLIsResolvedAgainstTheSiteURL(iconValue: String, expected: String) throws {
        let feed = try parse("<rss version=\"2.0\"><channel><title>Example</title>"
            + "<link>https://example.org/</link><image><url>" + iconValue + "</url></image>"
            + "<item><title>Test</title><link>https://example.org/item</link></item></channel></rss>")
        #expect(feed.iconURL == expected)
    }

    // MARK: - Language

    @Test(arguments: [
        ("<language>en-US</language>", "en-us"),
        ("<language>   </language>", ""),
        ("", ""),
    ]) func feedLanguageComesFromTheLanguageField(languageElement: String, expected: String) throws {
        let feed = try parse("<rss version=\"2.0\"><channel><title>Example</title>"
            + "<link>https://example.org/</link>" + languageElement
            + "<item><title>Test</title><link>https://example.org/item</link></item></channel></rss>")
        #expect(feed.language == expected)
    }

    /// `TestParseFeedWithDublinCoreChannelLanguage`: the channel language falls back to
    /// `dc:language`, and an entry inherits it because an item is part of the channel's content.
    @Test(arguments: [
        ("<dc:language>fr-FR</dc:language>", "fr-fr", "fr-fr"),
        ("<language>en-US</language><dc:language>fr-FR</dc:language>", "en-us", "en-us"),
    ]) func dublinCoreLanguageAndTheEntryInheritance(
        channelElement: String, expectedFeed: String, expectedEntry: String
    ) throws {
        let dc = " xmlns:dc=\"http://purl.org/dc/elements/1.1/\""
        let feed = try parse("<rss version=\"2.0\"" + dc + "><channel><title>Example</title>"
            + "<link>https://example.org/</link>" + channelElement
            + "<item><title>Test</title><link>https://example.org/item</link></item></channel></rss>")
        #expect(feed.language == expectedFeed)
        #expect(try #require(feed.entries.first).language == expectedEntry)
    }

    /// `TestParseItemWithDublinCoreLanguage`: an entry's own `dc:language` wins over the channel's.
    @Test func entryLanguageWinsOverTheChannelLanguage() throws {
        let dc = " xmlns:dc=\"http://purl.org/dc/elements/1.1/\""
        let feed = try parse("<rss version=\"2.0\"" + dc + "><channel><title>Example</title>"
            + "<link>https://example.org/</link><language>en-US</language>"
            + "<item><title>Item</title><link>https://example.org/item</link>"
            + "<dc:language>fr-FR</dc:language></item></channel></rss>")
        #expect(feed.language == "en-us")
        #expect(try #require(feed.entries.first).language == "fr-fr")
    }

    // MARK: - TTL

    @Test(arguments: [("60", 60), ("invalid", 0), ("", 0)]) func ttlMinutes(ttl: String, expected: Int) throws {
        let feed = try parse("<rss version=\"2.0\"><channel><title>Example</title>"
            + "<link>https://example.org/</link><ttl>" + ttl + "</ttl><item><title>Test</title>"
            + "<link>https://example.org/item</link></item></channel></rss>")
        #expect(feed.ttlMinutes == expected)
    }

    // MARK: - Tags

    /// `TestParseEntryWithCategories` — the entry list is sorted and deduplicated, and an empty
    /// category is not a tag. The feed categories are only used when the entry has none, which is
    /// what `TestParseFeedWithCategories` pins.
    @Test(arguments: [
        ("<item><title>Test</title><link>https://example.org/item</link></item>", ["Category 1", "Category 2"]),
        ("<item><title>Test</title><link>https://example.org/item</link>"
            + "<category>Category 3</category></item>", ["Category 3"]),
    ]) func entryTagsFallBackToTheFeedCategories(
        item: String, expected: [String]
    ) throws {
        let feed = try parse("<rss version=\"2.0\"><channel><title>Example</title>"
            + "<link>https://example.org/</link><category>Category 1</category>"
            + "<category><![CDATA[Category 2]]></category>" + item + "</channel></rss>")
        #expect(try #require(feed.entries.first).tags == expected)
    }

    @Test func entryTagsAreSortedAndDeduplicated() throws {
        let feed = try parse("<rss version=\"2.0\"><channel><title>Example</title>"
            + "<link>https://example.org/</link><item><title>Test</title>"
            + "<link>https://example.org/item</link><category>Category 1</category>"
            + "<category><![CDATA[Category 2]]></category><category>Category 2</category>"
            + "<category>Category 0</category><category>   </category></item></channel></rss>")
        #expect(try #require(feed.entries.first).tags == ["Category 0", "Category 1", "Category 2"])
    }

    /// `TestParseFeedWithItunesCategories` and `TestParseFeedWithGooglePlayCategory`: the nested
    /// `itunes:category` reads the parent and every subcategory, and the attribute value is the tag.
    @Test(arguments: [
        (" xmlns:itunes=\"http://www.itunes.com/dtds/podcast-1.0.dtd\"",
            "<itunes:category text=\"Society &amp; Culture\"><itunes:category text=\"Documentary\" />"
                + "</itunes:category>", ["Documentary", "Society & Culture"]),
        (" xmlns:itunes=\"http://www.itunes.com/dtds/podcast-1.0.dtd\"",
            "<itunes:category text=\"Health\" />", ["Health"]),
        (" xmlns:itunes=\"http://www.itunes.com/dtds/podcast-1.0.dtd\"",
            "<itunes:category text=\"  \" />", []),
        (" xmlns:gplay=\"http://www.google.com/schemas/play-podcasts/1.0\"",
            "<gplay:category text=\"Art\"></gplay:category>", ["Art"]),
    ]) func feedTagsFromThePodcastCategories(
        namespace: String, categoryElement: String, expected: [String]
    ) throws {
        let feed = try parse("<rss version=\"2.0\"" + namespace + "><channel><title>Example</title>"
            + "<link>https://example.org/</link>" + categoryElement
            + "<item><title>Test</title><link>https://example.org/item</link></item></channel></rss>")
        #expect(try #require(feed.entries.first).tags == expected)
    }

    /// `TestParseEntryWithMediaCategories`: only the categories that carry a label are tags.
    @Test func mediaCategoriesAreTagsByLabel() throws {
        let media = " xmlns:media=\"http://search.yahoo.com/mrss/\""
        let feed = try parse("<rss version=\"2.0\"" + media + "><channel><title>Example</title>"
            + "<link>https://example.org/</link><item><title>Test</title>"
            + "<link>https://example.org/item</link>"
            + "<media:category label=\"Visual Art\">visual_art</media:category>"
            + "<media:category label=\"Ace Ventura - Pet Detective\">arts</media:category>"
            + "<media:category>no label</media:category></item></channel></rss>")
        #expect(try #require(feed.entries.first).tags == ["Ace Ventura - Pet Detective", "Visual Art"])
    }

    // MARK: - The default namespace

    /// Go's `translate` falls back to the decoder's `DefaultSpace`, which the reference sets to `rss`
    /// for this format, so a name with no prefix is read as an RSS name.
    @Test func namesWithNoPrefixResolveToTheRSSNamespace() throws {
        let feed = try parse("<rss version=\"2.0\"><channel><title>Example</title>"
            + "<link>https://example.org/</link><item><title>Item</title>"
            + "<link>https://example.org/item</link></item></channel></rss>")
        #expect(feed.title == "Example")
        #expect(try #require(feed.entries.first).title == "Item")
    }

    /// Traced from `translate`: the default space only stands in when the document declares no default
    /// namespace. Once one is declared, `rss channel` matches nothing, so the whole feed reads empty and
    /// the only value left is the title fallback on the resolved base URL.
    @Test func aDeclaredDefaultNamespaceIsNotTheDefaultSpace() throws {
        let feed = try parse("<rss version=\"2.0\" xmlns=\"http://purl.org/dc/elements/1.1/\"><channel>"
            + "<title>Example</title><link>https://example.org/</link><item><title>Item</title>"
            + "<link>https://example.org/item</link></item></channel></rss>")
        #expect(feed.title == "https://example.org/")
        #expect(feed.entries.isEmpty)
    }
}
