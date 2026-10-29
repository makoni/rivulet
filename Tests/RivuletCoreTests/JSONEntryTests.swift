import Foundation
import Testing
@testable import RivuletCore

/// The entry-level rules the JSON Feed adapter writes. Ported from Miniflux
/// `internal/reader/json/parser_test.go`; each case names the upstream test
/// it comes from, and a traced case states the value the reference produces.
@Suite struct JSONEntryTests {
    private let now = ParsedDate(epochSeconds: 1_700_000_000, nanoseconds: 0, zoneName: "UTC",
        zoneOffsetSeconds: 0)

    private func parse(_ document: String, baseURL: String = "https://example.org/feed.json") throws -> ParsedFeed {
        try JSONFeedAdapter.parse(baseURL: baseURL, data: Data(document.utf8), now: now)
    }

    /// The first entry of a document whose `items` array holds one item,
    /// read through the feed's own site URL, which is the home page here.
    private func entry(_ item: String, siteURL: String = "https://example.org/",
        baseURL: String = "https://example.org/feed.json") throws -> ParsedEntry {
        try #require(parse("{\"home_page_url\": \"\(siteURL)\", \"items\": [ \(item) ]}", baseURL: baseURL)
            .entries.first)
    }

    // MARK: - URL

    /// `TestParseItemWithRelativeURL` — the entry resolves against the site URL rather than
    /// against the base URL, which is what separates it from the feed URL's own resolution.
    @Test func entryURLResolvesAgainstTheSiteURL() throws {
        #expect(try entry("{\"url\": \"something.html\"}", siteURL: "https://example.org/feed/").url
            == "https://example.org/feed/something.html")
    }

    /// `TestParseItemWithRelativeURL`, as the upstream document reads it: the site URL is
    /// the home page, so the last segment of its path is what the relative value replaces.
    @Test func relativeEntryURLResolvesThroughTheSiteURL() throws {
        #expect(try entry("{\"url\": \"something.html\", \"date_published\": \"2016-02-09T14:22:00-07:00\"}").url
            == "https://example.org/something.html")
    }

    /// `TestParseItemWithExternalURLAndNoURL` — the chain is `url` then
    /// `external_url`, and the value is resolved before the field is written.
    @Test func entryURLFallsBackToExternalURL() throws {
        #expect(try entry("{\"external_url\": \"some_page.html\"}").url == "https://example.org/some_page.html")
    }

    /// `TestParseItemWithExternalURLAndURL` — `url` wins, so the external URL is never read.
    @Test func entryURLPrefersURLToExternalURL() throws {
        #expect(try entry("{\"url\": \"https://example.org/article\", \"external_url\": \"https://example.org/another-article\"}").url
            == "https://example.org/article")
    }

    // MARK: - Title

    /// `TestParseItemWithMissingTitleUsesSummaryFallback`: the title chain is the summary, then the
    /// content text, then the content HTML, each read through `TruncateHTML` at the limit of 100.
    @Test func entryTitleUsesSummaryFallback() throws {
        let item = try entry("{\"summary\": \"Summary title\", \"content_text\": \"Content text title\", "
            + "\"content_html\": \"<p>HTML title</p>\"}")
        #expect(item.title == "Summary title")
        // The content is the HTML field, which is HTML as the format wrote it: not escaped.
        #expect(item.content == "<p>HTML title</p>")
    }

    /// `TestParseItemWithMissingTitleUsesContentTextFallback` — a summary that is only whitespace
    /// is nothing after the walk, so the next value in the chain is what the title gets.
    @Test func entryTitleUsesContentTextFallback() throws {
        #expect(try entry("{\"summary\": \" \", \"content_text\": \"Content text title\"}").title
            == "Content text title")
    }

    /// `TestParseItemWithMissingTitleUsesHTMLFallback` — the tags are dropped by the walk,
    /// which is what the reference's `TruncateHTML` does, and the title is not escaped.
    @Test func entryTitleUsesHTMLFallback() throws {
        #expect(try entry("{\"summary\": \"\", \"content_text\": \"\", \"content_html\": \"<p>HTML title</p>\"}").title
            == "HTML title")
    }

    /// `TestParseItemWithMissingTitleUsesURLFallback` — with nothing to
    /// fall back on, the title is the entry URL as the chain resolved it.
    @Test func entryTitleFallsBackToTheEntryURL() throws {
        #expect(try entry("{\"url\": \"https://example.org/item\"}").title == "https://example.org/item")
    }

    /// `TestParseItemWithTooLongUnicodeTitle`: the title the item declares is
    /// the value as it was read, with no truncation. The reference counts bytes
    /// and runes, which are two different lengths here — 110 bytes and 93 runes
    /// — and Swift's grapheme count is neither, because the emoji is a cluster.
    @Test func titleIsTheValueAsItWasRead() throws {
        let title = "I’m riding my electric bike and came across this castle. It’s called “Schloss Richmond”. 🚴‍♂️"
        let item = try entry("{\"title\": \"\(title)\"}")
        #expect(item.title == title)
        #expect(item.title.unicodeScalars.count == 93)
        #expect([UInt8](item.title.utf8).count == 110)
    }

    /// `TestParseItemTitleWithXMLTags` — the title is not
    /// escaped, so markup-like characters stay as they were read.
    @Test func titleKeepsMarkupLikeCharacters() throws {
        #expect(try entry("{\"title\": \"</example>\"}").title == "</example>")
    }

    /// Traced: a fallback value longer than the limit is the walk's output, so
    /// the title is the part the limit leaves plus the ellipsis the count adds.
    @Test func titleFallbackIsTruncatedAtTheLimit() throws {
        let long = String(repeating: "a", count: 101)
        #expect(try entry("{\"summary\": \"\(long)\"}").title == String(repeating: "a", count: 100) + "\u{2026}")
    }

    // MARK: - Content

    /// `TestParseItemWithPlainTextContentContainingHTMLCharacters` — `content_text`
    /// and `summary` are plain text per the 1.1 spec, so they are escaped before
    /// being stored, while `content_html` is stored as the format wrote it.
    @Test func plainTextContentIsEscaped() throws {
        #expect(try entry("{\"content_text\": \"Use <div> literally: a & b < c\"}").content
            == "Use &lt;div&gt; literally: a &amp; b &lt; c")
    }

    /// Traced: the content chain is `content_html`, then `content_text`, then `summary`, each
    /// trimmed on its own, so a field that is nothing moves on to the plain text, which is escaped.
    @Test func contentChainOrderIsHTMLThenTextThenSummary() throws {
        #expect(try entry("{\"content_html\": \"\", \"content_text\": \"a & b\", \"summary\": \"s\"}").content
            == "a &amp; b")
        #expect(try entry("{\"content_html\": \" \", \"content_text\": \"\", \"summary\": \"x & y\"}").content
            == "x &amp; y")
    }

    // MARK: - Date

    /// `TestParseItemWithInvalidDate` — a value that cannot be read is not a
    /// failure: the entry moves on through the chain and ends at the clock.
    @Test func unparseableDateFallsBackToTheClock() throws {
        #expect(try entry("{\"date_published\": \"Tomorrow\"}").date == now)
    }

    /// Traced: the date chain is `date_published` then `date_modified`,
    /// and a value the parser cannot read moves on to the next rather
    /// than failing the document, which is what the first case below pins.
    @Test func dateChainMovesOnPastAValueItCannotRead() throws {
        #expect(try entry("{\"date_published\": \"Tomorrow\", \"date_modified\": \"2020-01-02T03:04:05Z\"}").date
            .epochSeconds == 1577934245)
        #expect(try entry("{\"date_published\": \"\", \"date_modified\": \"2016-02-09T14:22:00-07:00\"}").date
            .epochSeconds == 1455052920)
    }

    // MARK: - Language

    /// `TestParseItemWithLanguage` — the item's own tag wins.
    @Test func entryLanguageIsItsOwnTag() throws {
        #expect(try entry("{\"language\": \"fr-FR\"}").language == "fr-fr")
    }

    /// `TestParseItemWithoutLanguageInheritsFeedLanguage` — an item declares a language only
    /// when it differs from the feed's, so an empty one is the feed's, already normalized.
    @Test func entryLanguageInheritsTheFeedLanguage() throws {
        let feed = try parse("{\"language\": \"en-US\", \"items\": [ { \"content_text\": \"Hello\" } ]}")
        #expect(try #require(feed.entries.first).language == "en-us")
    }

    // MARK: - Tags

    /// `TestParseItemTags` — the tags are trimmed, sorted by the byte
    /// comparison, and deduplicated, and an empty name is not a name.
    @Test func tagsAreTrimmedSortedAndDeduplicated() throws {
        #expect(try entry("{\"tags\": [ \" tag 1\", \" \", \"tag 2\", \"tag 2\", \"aaa\" ]}").tags
            == ["aaa", "tag 1", "tag 2"])
    }

    // MARK: - An entry with nothing

    /// Traced: an item that declares nothing is the model as the adapter starts
    /// it, with the clock as the date, because every chain answers empty.
    /// This is `model.NewEntry` before the adapter writes anything to it.
    @Test func emptyItemIsTheModelAsItStarts() throws {
        let item = try entry("{ }")
        #expect(item.hash == "")
        #expect(item.title == "")
        #expect(item.url == "")
        #expect(item.commentsURL == "")
        #expect(item.author == "")
        #expect(item.content == "")
        #expect(item.language == "")
        #expect(item.date == now)
        #expect(item.tags.isEmpty)
        #expect(item.enclosures.isEmpty)
        #expect(item.readingTimeMinutes == 0)
    }

    /// Traced: a value that cannot be resolved is skipped rather than written,
    /// which is what the reference logs a debug line for. With a base URL that
    /// is not a URL and no home page the site URL is that base, so the chain
    /// answers empty, and the title is the entry URL, which is empty as well.
    @Test func entryURLThatCannotResolveIsSkipped() throws {
        let entry = try #require(parse("{\"items\": [ { \"url\": \"something.html\" } ] }", baseURL: "://bad")
            .entries.first)
        #expect(entry.url == "")
        #expect(entry.title == "")
    }
}
