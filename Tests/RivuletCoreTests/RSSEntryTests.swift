import Foundation
import Testing
@testable import RivuletCore

/// The entry-level rules the RSS adapter writes: the fallback chains, the title and URL fallbacks,
/// the date, the comments URL and the podcast duration. Ported from Miniflux
/// `internal/reader/rss/parser_test.go`; each case names the upstream test it comes from, and a
/// traced case states the value the reference produces.
@Suite struct RSSEntryTests {
    private let now = ParsedDate(epochSeconds: 1_700_000_000, nanoseconds: 0, zoneName: "UTC",
        zoneOffsetSeconds: 0)

    private func entry(_ item: String, namespaces: String = "", channel: String = "") throws -> ParsedEntry {
        let feed = try feed(channel, item, namespaces: namespaces)
        return try #require(feed.entries.first)
    }

    private func feed(_ channel: String, _ item: String, namespaces: String = "") throws -> ParsedFeed {
        let document = "<rss version=\"2.0\"" + namespaces + "><channel><title>Example</title>"
            + "<link>https://example.org/</link>" + channel + item + "</channel></rss>"
        return try RSSAdapter.parse(baseURL: "https://example.org/", data: Data(document.utf8), now: now)
    }

    private func item(_ content: String) -> String {
        "<item><title>Test</title><link>https://example.org/item</link>" + content + "</item>"
    }

    // MARK: - Title

    /// `TestParseEntryWithDCTitleOnly` and `TestParseEntryWithMediaTitle`: `dc:title` wins over the
    /// item title, and `media:title` is not read by this format at all.
    @Test(arguments: [
        (" xmlns:dc=\"http://purl.org/dc/elements/1.1/\"", "<dc:title>Entry Title</dc:title>", "Entry Title"),
        (" xmlns:media=\"http://search.yahoo.com/mrss/\"", "<media:title>Media Title</media:title>", "Test"),
    ]) func titleChainPriority(namespaces: String, element: String, expected: String) throws {
        let parsed = try entry(item(element), namespaces: namespaces)
        #expect(parsed.title == expected)
    }

    /// `TestParseItemTitleWithInnerHTML` and `TestParseItemTitleWithWhitespaces`: the title is the
    /// character data read in document order, trimmed, with the markup dropped.
    @Test(arguments: [
        ("<title>Test: <b>bold</b></title>", "Test: bold"),
        ("<title>\n\t\tSome Title\n\t</title>", "Some Title"),
        ("<title>&lt;/example&gt;</title>", "</example>"),
        ("<title>&#931; &#xDF;</title>", "\u{3A3} \u{DF}"),
    ]) func itemTitleIsTheCharacterDataInDocumentOrder(titleElement: String, expected: String) throws {
        let parsed = try entry("<item>" + titleElement + "<link>https://example.org/item</link></item>")
        #expect(parsed.title == expected)
    }

    /// `TestParseEntryWithoutTitleButWithDescription`: an entry with no title falls back to the
    /// content truncated through `TruncateHTML`, which is the walk that collapses whitespace runs, not
    /// the walk that keeps them, and the last resort is the URL.
    @Test(arguments: [
        ("<description>a\n b</description>", "a b"),
        ("", "https://example.org/item"),
    ]) func titleFallbackChain(description: String, expected: String) throws {
        let parsed = try entry("<item><link>https://example.org/item</link>" + description + "</item>")
        #expect(parsed.title == expected)
    }

    /// Traced: a field tagged `",chardata"` reads the character data at the element's own level only, so
    /// markup inside the description is not the entry content, and the title falls back to the URL. The
    /// tags are dropped by `TruncateHTML` only when they are part of the value it is given, as in the
    /// escaped form below.
    @Test(arguments: [
        ("<description><p>Line <b>1</b></p></description>", "", "https://example.org/item"),
        ("<description>&lt;p&gt;Line &lt;b&gt;1&lt;/b&gt;&lt;/p&gt;</description>",
            "<p>Line <b>1</b></p>", "Line 1"),
    ]) func markupCountsAsContentOnlyWhenItIsText(description: String, expectedContent: String,
        expectedTitle: String) throws {
        let parsed = try entry("<item><link>https://example.org/item</link>" + description + "</item>")
        #expect(parsed.content == expectedContent)
        #expect(parsed.title == expectedTitle)
    }

    /// Traced: the limit counts code points, so a word that is exactly the limit stays whole and a longer
    /// one is cut, with the ellipsis written after what is left.
    @Test func titleFallbackCountsCodePoints() throws {
        let limit = String(repeating: "a", count: 100)
        #expect(try entry("<item><link>https://example.org/item</link><description>" + limit
            + "</description></item>").title == limit)
        #expect(try entry("<item><link>https://example.org/item</link><description>" + limit + "a"
            + "</description></item>").title == limit + "\u{2026}")
    }

    // MARK: - URL

    @Test(arguments: [
        ("", "<guid isPermaLink=\"false\">1234</guid>", "https://example.org/"),
        ("", "<guid isPermaLink=\"true\">https://example.org/a</guid>", "https://example.org/a"),
        ("", "<guid>https://example.org/a</guid>", "https://example.org/a"),
        ("", "<link>item.html</link>", "https://example.org/item.html"),
        (" xmlns:feedburner=\"http://rssnamespace.org/feedburner/ext/1.0\"",
            "<link>https://example.org/item</link><feedburner:origLink>http://example.org/original</feedburner:origLink>",
            "http://example.org/original"),
        (" xmlns:atom=\"http://www.w3.org/2005/Atom\"", "<atom:link href=\"https://example.org/a\" />",
            "https://example.org/a"),
        (" xmlns:atom=\"http://www.w3.org/2005/Atom\"",
            "<atom:link rel=\"payment\" href=\"https://example.org/a\" />"
                + "<atom:link rel=\"alternate\" href=\"https://example.org/b\" />", "https://example.org/b"),
        (" xmlns:atom=\"http://www.w3.org/2005/Atom\"",
            "<atom:link rel=\"alternate\" href=\"  \" />", "https://example.org/"),
        ("", "<guid isPermaLink=\"false\">guid</guid>", "https://example.org/"),
    ]) func entryURLChain(namespaces: String, content: String, expected: String) throws {
        let parsed = try entry("<item>" + content + "</item>", namespaces: namespaces)
        #expect(parsed.url == expected)
    }

    /// `TestParseEntryWithoutLinkAndWithEnclosureURLs`: an entry with no URL at all falls back to the
    /// site URL, and then to the first enclosure URL.
    @Test func entryURLFallsBackToTheFirstEnclosure() throws {
        let parsed = try entry("<item><guid isPermaLink=\"false\">guid</guid>"
            + "<enclosure url=\" \" length=\"1\" type=\"audio/mpeg\" />"
            + "<enclosure url=\"https://audio-file\" length=\"1\" type=\"audio/mpeg\" /></item>")
        #expect(parsed.url == "https://audio-file")
    }

    // MARK: - Content

    @Test(arguments: [
        (" xmlns:content=\"http://purl.org/rss/1.0/modules/content/\"",
            "<content:encoded><![CDATA[<p>Example</p>]]></content:encoded><description>Description.</description>",
            "<p>Example</p>"),
        ("", "<description>this is &lt;b&gt;bold&lt;/b&gt;</description>", "this is <b>bold</b>"),
        ("", "<description><![CDATA[5 &lt; 8]]></description>", "5 &lt; 8"),
        (" xmlns:itunes=\"http://www.itunes.com/dtds/podcast-1.0.dtd\"",
            "<itunes:subtitle>Subtitle</itunes:subtitle><itunes:summary>Summary</itunes:summary>", "Summary"),
        (" xmlns:itunes=\"http://www.itunes.com/dtds/podcast-1.0.dtd\"",
            "<itunes:subtitle>Subtitle</itunes:subtitle>", "Subtitle"),
        (" xmlns:googleplay=\"http://www.google.com/schemas/play-podcasts/1.0\""
            + " xmlns:itunes=\"http://www.itunes.com/dtds/podcast-1.0.dtd\"",
            "<itunes:subtitle>Subtitle</itunes:subtitle>"
                + "<googleplay:description>Description</googleplay:description>", "Description"),
        (" xmlns:media=\"http://search.yahoo.com/mrss/\"",
            "<media:description type=\"plain\">Media Description</media:description>", ""),
    ]) func contentChain(namespaces: String, content: String, expected: String) throws {
        let parsed = try entry("<item><link>https://example.org/item</link>" + content + "</item>",
            namespaces: namespaces)
        #expect(parsed.content == expected)
    }

    // MARK: - Date

    @Test(arguments: [
        ("", "<pubDate>Tue, 03 Jun 2003 09:39:21 GMT</pubDate>", 1_054_633_161),
        (" xmlns:dc=\"http://purl.org/dc/elements/1.1/\"",
            "<pubDate>Tue, 03 Jun 2003 09:39:21 GMT</pubDate><dc:date>2002-09-29T23:40:06-05:00</dc:date>",
            1_033_360_806),
        ("", "<pubDate>not a date</pubDate>", 1_700_000_000),
        ("", "", 1_700_000_000),
    ]) func entryDateChain(namespaces: String, dateElement: String, expected: Int64) throws {
        let parsed = try entry("<item><link>https://example.org/item</link>" + dateElement + "</item>",
            namespaces: namespaces)
        #expect(parsed.date.epochSeconds == expected)
    }

    // MARK: - Author

    @Test(arguments: [
        ("", "<author>by <a href=\"/author/foobar\">Foo Bar</a></author>", "by Foo Bar"),
        ("", "<author>\n\t\t\t\t\t<![CDATA[by Foo Bar]]>\n\t\t\t\t</author>", "by Foo Bar"),
        (" xmlns:atom=\"http://www.w3.org/2005/Atom\"", "<atom:author><name>Foo Bar</name></atom:author>",
            "Foo Bar"),
        (" xmlns:atom=\"http://www.w3.org/2005/Atom\"",
            "<atom:author><email>author@example.org</email></atom:author>", "author@example.org"),
        (" xmlns:dc=\"http://purl.org/dc/elements/1.1/\"", "<dc:creator>Me (me@example.com)</dc:creator>",
            "Me (me@example.com)"),
        (" xmlns:itunes=\"http://www.itunes.com/dtds/podcast-1.0.dtd\"", "<itunes:author>Someone</itunes:author>",
            "Someone"),
        (" xmlns:googleplay=\"http://www.google.com/schemas/play-podcasts/1.0\""
            + " xmlns:itunes=\"http://www.itunes.com/dtds/podcast-1.0.dtd\""
            + " xmlns:dc=\"http://purl.org/dc/elements/1.1/\"",
            "<googleplay:author>Google</googleplay:author><itunes:author>Itunes</itunes:author>"
                + "<dc:creator>Creator</dc:creator>", "Google"),
        ("", "<author></author>", ""),
    ]) func entryAuthorChain(namespaces: String, authorElement: String, expected: String) throws {
        let parsed = try entry("<item><link>https://example.org/item</link>" + authorElement + "</item>",
            namespaces: namespaces)
        #expect(parsed.author == expected)
    }

    /// The entry author is what decides first; the channel author is the fallback, and its own order
    /// is iTunes, Google Play, the owner, the managing editor, then the webmaster — which is what
    /// `TestParseFeedWithManagingEditor` pins against `TestParseFeedWithWebmaster`.
    @Test(arguments: [
        (" xmlns:itunes=\"http://www.itunes.com/dtds/podcast-1.0.dtd\"",
            "<itunes:author>Someone</itunes:author>", "Someone"),
        (" xmlns:itunes=\"http://www.itunes.com/dtds/podcast-1.0.dtd\"",
            "<itunes:owner><itunes:name>John Doe</itunes:name>"
                + "<itunes:email>john.doe@example.com</itunes:email></itunes:owner>", "John Doe"),
        (" xmlns:itunes=\"http://www.itunes.com/dtds/podcast-1.0.dtd\"",
            "<itunes:owner><itunes:email>john.doe@example.com</itunes:email></itunes:owner>",
            "john.doe@example.com"),
        (" xmlns:googleplay=\"http://www.google.com/schemas/play-podcasts/1.0\""
            + " xmlns:itunes=\"http://www.itunes.com/dtds/podcast-1.0.dtd\"",
            "<googleplay:author>Google</googleplay:author><itunes:author>Itunes</itunes:author>", "Itunes"),
        ("", "<managingEditor>editor@example.com</managingEditor>"
            + "<webMaster>webmaster@example.com</webMaster>", "editor@example.com"),
        ("", "<webMaster>webmaster@example.com</webMaster>", "webmaster@example.com"),
    ]) func feedAuthorIsTheFallback(namespaces: String, channelElement: String, expected: String) throws {
        let parsed = try entry("<item><link>https://example.org/item</link></item>", namespaces: namespaces,
            channel: channelElement)
        #expect(parsed.author == expected)
    }

    /// The entry's own author wins over the channel's, which is the order `TestParseEntryWithAuthorAndInnerHTML`
    /// is read through.
    @Test func entryAuthorWinsOverTheChannelAuthor() throws {
        let parsed = try entry("<item><link>https://example.org/item</link><author>Entry Author</author></item>",
            channel: "<author>Channel Author</author>")
        #expect(parsed.author == "Entry Author")
    }

    // MARK: - Comments and duration

    @Test(arguments: [
        ("<comments>https://example.org/comments</comments>", "https://example.org/comments"),
        ("<comments>\n\t\t\t\t\tSome text\n\t\t\t\t</comments>", ""),
        ("<comments>item.html</comments>", ""),
        ("", ""),
    ]) func commentsURLIsKeptOnlyWhenItIsAbsolute(commentsElement: String, expected: String) throws {
        let parsed = try entry("<item><link>https://example.org/item</link>" + commentsElement + "</item>")
        #expect(parsed.commentsURL == expected)
    }

    @Test(arguments: [
        (" xmlns:itunes=\"http://www.itunes.com/dtds/podcast-1.0.dtd\"", "<itunes:duration>1:23:45</itunes:duration>",
            83),
        (" xmlns:itunes=\"http://www.itunes.com/dtds/podcast-1.0.dtd\"", "<itunes:duration>invalid</itunes:duration>",
            0),
        (" xmlns:itunes=\"http://www.itunes.com/dtds/podcast-1.0.dtd\"",
            "<itunes:duration>1:2:3:4</itunes:duration>", 0),
        (" xmlns:itunes=\"http://www.itunes.com/dtds/podcast-1.0.dtd\"", "<itunes:duration>90</itunes:duration>", 1),
        ("", "", 0),
    ]) func podcastDurationInMinutes(namespaces: String, durationElement: String, expected: Int) throws {
        let parsed = try entry("<item><link>https://example.org/item</link>" + durationElement + "</item>",
            namespaces: namespaces)
        #expect(parsed.readingTimeMinutes == expected)
    }
}
