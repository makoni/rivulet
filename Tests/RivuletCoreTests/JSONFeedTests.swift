import Foundation
import Testing
@testable import RivuletCore

/// The feed-level rules the JSON Feed adapter writes. Ported from Miniflux
/// `internal/reader/json/parser_test.go`; each case names the upstream test it comes from, and a
/// traced case states the value the reference produces.
///
/// The clock the date fallback reads is injected, so an entry that has no date carries the injected
/// value wherever the reference would have read the current time.
@Suite struct JSONFeedTests {
    private let now = ParsedDate(epochSeconds: 1_700_000_000, nanoseconds: 0, zoneName: "UTC",
        zoneOffsetSeconds: 0)

    private func parse(_ document: String, baseURL: String = "https://example.org/feed.json") throws -> ParsedFeed {
        try JSONFeedAdapter.parse(baseURL: baseURL, data: Data(document.utf8), now: now)
    }

    // MARK: - The whole document

    /// `TestParseJsonFeedVersion1`, read end to end. The icon is the favicon, because the reference
    /// looks at the favicon before the icon, and an entry with no date is the injected clock.
    @Test func sampleDocumentIsReadEndToEnd() throws {
        let feed = try parse("{\"title\": \"My Example Feed\", \"icon\": \"https://micro.blog/jsonfeed/avatar.jpg\", "
            + "\"favicon\": \"https://micro.blog/jsonfeed/favicon.png\", \"home_page_url\": \"https://example.org/\", "
            + "\"feed_url\": \"https://example.org/feed.json\", \"items\": [ "
            + "{ \"id\": \"2\", \"content_text\": \"This is a second item.\", \"url\": \"https://example.org/second-item\" }, "
            + "{ \"id\": \"1\", \"content_html\": \"<p>Hello, world!</p>\", \"url\": \"https://example.org/initial-post\" } ] }")

        #expect(feed.title == "My Example Feed")
        #expect(feed.description == "")
        #expect(feed.feedURL == "https://example.org/feed.json")
        #expect(feed.siteURL == "https://example.org/")
        #expect(feed.iconURL == "https://micro.blog/jsonfeed/favicon.png")
        #expect(feed.entries.count == 2)

        let second = try #require(feed.entries.first)
        #expect(second.hash == "d4735e3a265e16eee03f59718b9b5d03019c07d8b6c51f90da3a666eec13ab35")
        #expect(second.url == "https://example.org/second-item")
        #expect(second.title == "This is a second item.")
        #expect(second.content == "This is a second item.")

        let first = try #require(feed.entries.last)
        #expect(first.hash == "6b86b273ff34fce19d6b804eff5a3f5747ada4eaa22f1d49c01e52ddb7875b4b")
        #expect(first.url == "https://example.org/initial-post")
        #expect(first.title == "Hello, world!")
        #expect(first.content == "<p>Hello, world!</p>")

        // Neither entry has a date, so the date is the clock the reference reads.
        #expect(second.date == now)
        #expect(first.date == now)
    }

    /// `TestParseFeedWithDescription`
    @Test func descriptionIsWhatTheFeedDeclares() throws {
        let feed = try parse("{\"title\": \"My Example Feed\", \"description\": \"This is a sample feed.\"}")
        #expect(feed.description == "This is a sample feed.")
    }

    // MARK: - URLs

    /// `TestParseFeedWithFeedURLWithTrailingSpace` — every value the adapter writes is trimmed
    /// first, which is what the reference's `strings.TrimSpace` does on each field it reads.
    @Test func feedURLIsTrimmedBeforeItIsUsed() throws {
        let feed = try parse("{\"home_page_url\": \"https://example.org/\", "
            + "\"feed_url\": \"https://example.org/feed.json \", \"items\": []}")
        #expect(feed.feedURL == "https://example.org/feed.json")
    }

    /// `TestParseFeedWithRelativeFeedURL` — the feed URL resolves against the base URL, while the
    /// entry URL and the icon resolve against the site URL, which the entry and icon cases pin.
    @Test func feedURLResolvesAgainstTheBaseURL() throws {
        let feed = try parse("{\"home_page_url\": \"https://example.org/\", \"feed_url\": \"/feed.json\", \"items\": []}")
        #expect(feed.feedURL == "https://example.org/feed.json")
    }

    /// `TestParseFeedSiteURLWithTrailingSpace`
    @Test func siteURLIsTrimmedBeforeItIsUsed() throws {
        let feed = try parse("{\"home_page_url\": \"https://example.org/ \", \"feed_url\": \"/feed.json\", \"items\": []}")
        #expect(feed.siteURL == "https://example.org/")
    }

    /// `TestParseFeedWithRelativeSiteURL`
    @Test func siteURLResolvesAgainstTheBaseURL() throws {
        let feed = try parse("{\"home_page_url\": \"/home \", \"feed_url\": \"/feed.json\", \"items\": []}")
        #expect(feed.siteURL == "https://example.org/home")
    }

    /// `TestParseFeedWithoutTitle` — the title falls back to the site URL.
    @Test func feedTitleFallsBackToTheSiteURL() throws {
        let feed = try parse("{\"home_page_url\": \"https://example.org/\", \"items\": []}")
        #expect(feed.title == "https://example.org/")
    }

    /// `TestParseFeedWithoutHomePage` — the site URL falls back to the feed URL, which is also the
    /// value the title falls back to.
    @Test func siteURLFallsBackToTheFeedURL() throws {
        let feed = try parse("{\"feed_url\": \"https://example.org/feed.json\", \"items\": []}")
        #expect(feed.siteURL == "https://example.org/feed.json")
        #expect(feed.title == "https://example.org/feed.json")
    }

    /// `TestParseFeedWithoutFeedURL` — the feed URL falls back to the base URL, which is then the
    /// site URL as well.
    @Test func feedURLFallsBackToTheBaseURL() throws {
        let feed = try parse("{\"items\": []}")
        #expect(feed.feedURL == "https://example.org/feed.json")
        #expect(feed.siteURL == "https://example.org/feed.json")
    }

    // MARK: - Icon

    /// `TestParseFeedFavicon`, read together with `TestParseFeedIcon`: the reference walks the
    /// favicon first and stops at the first value it can resolve, so the favicon wins when both are
    /// present.
    @Test func iconIsTheFaviconWhenBothArePresent() throws {
        let feed = try parse("{\"favicon\": \"https://example.org/favicon.png\", \"icon\": \"https://example.org/icon.png\", "
            + "\"home_page_url\": \"https://example.org/\", \"items\": []}")
        #expect(feed.iconURL == "https://example.org/favicon.png")
    }

    /// `TestParseFeedIcon` — the icon is what the model gets when there is no favicon.
    @Test func iconIsUsedWhenThereIsNoFavicon() throws {
        let feed = try parse("{\"icon\": \"https://example.org/jsonfeed/icon.png\", \"home_page_url\": \"https://example.org/\", "
            + "\"items\": []}")
        #expect(feed.iconURL == "https://example.org/jsonfeed/icon.png")
    }

    /// Traced: the icon resolves against the site URL rather than the base URL, so a relative icon
    /// resolves through the site URL's path, and a value the resolver cannot read is skipped, which
    /// is what the reference logs a debug line for.
    @Test func iconResolvesAgainstTheSiteURL() throws {
        let feed = try parse("{\"favicon\": \"favicon.png\", \"home_page_url\": \"https://example.org/feed/\", \"items\": []}")
        #expect(feed.iconURL == "https://example.org/feed/favicon.png")

        let skipped = try parse("{\"favicon\": \"favicon.png\", \"items\": []}", baseURL: "://bad")
        #expect(skipped.iconURL == "")
    }

    // MARK: - Language

    /// `TestParseFeedWithLanguage`
    @Test func languageIsNormalized() throws {
        let feed = try parse("{\"language\": \"en-US\", \"items\": []}")
        #expect(feed.language == "en-us")
    }

    /// `TestParseFeedWithoutLanguage`
    @Test func languageIsEmptyWhenTheFeedDoesNotDeclareOne() throws {
        let feed = try parse("{\"items\": []}")
        #expect(feed.language == "")
    }

    // MARK: - A document that is not an object

    /// `TestParseNullJSONFeed`: `literalStore` ignores null for a struct target, so the walk
    /// reports no failure, every field is what the shape started with, and the fallbacks decide the
    /// model.
    @Test func nullDocumentFillsTheModelFromTheFallbacks() throws {
        let feed = try parse("null")
        #expect(feed.title == "https://example.org/feed.json")
        #expect(feed.feedURL == "https://example.org/feed.json")
        #expect(feed.siteURL == "https://example.org/feed.json")
        #expect(feed.description == "")
        #expect(feed.language == "")
        #expect(feed.iconURL == "")
        #expect(feed.entries.isEmpty)
    }

    /// `TestParseInvalidJSON` — the failure the machine reports is what `Parse` returns, which the
    /// reference wraps in its "unable to parse feed" line.
    @Test func garbageFailsTheRead() {
        #expect(throws: JSONError.unexpectedCharacter(character: 0x67,
            context: "looking for beginning of value")) {
            try parse("garbage")
        }
    }
}
