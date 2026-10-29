import Foundation
import Testing
@testable import RivuletCore

/// The feed-level rules the Atom 1.0 adapter writes. Ported from Miniflux
/// `internal/reader/atom/atom_10_test.go`; each case names the upstream test it comes from, and a
/// traced case states the value the reference produces.
///
/// The feed URL and the site URL come from two different relations of the same `link` element, so
/// the pair is kept apart here, and the entry chain resolves against the site URL rather than
/// against the base URL — which is what the case below pins.
@Suite struct AtomFeedTests {
    private let now = ParsedDate(epochSeconds: 1_700_000_000, nanoseconds: 0, zoneName: "UTC",
        zoneOffsetSeconds: 0)

    private func parse(_ document: String, baseURL: String = "https://example.org/") throws -> ParsedFeed {
        try Atom10Adapter.parse(baseURL: baseURL, data: Data(document.utf8), now: now)
    }

    // MARK: - The whole document

    /// `TestParseAtomSample`, the reference's sample feed read end to end.
    @Test func sampleFeedIsReadEndToEnd() throws {
        let feed = try parse("<feed xmlns=\"http://www.w3.org/2005/Atom\"><title>Example Feed</title>"
            + "<link href=\"http://example.org/\"/><updated>2003-12-13T18:30:02Z</updated>"
            + "<author><name>John Doe</name></author><id>urn:uuid:60a76c80-d399-11d9-b93C-0003939e0af6</id>"
            + "<entry><title>Atom-Powered Robots Run Amok</title>"
            + "<link href=\"http://example.org/2003/12/13/atom03\"/>"
            + "<id>urn:uuid:1225c695-cfb8-4ebb-aaaa-80da344efa6a</id>"
            + "<updated>2003-12-13T18:30:02Z</updated><summary>Some text.</summary></entry></feed>",
            baseURL: "http://example.org/feed.xml")

        #expect(feed.title == "Example Feed")
        #expect(feed.feedURL == "http://example.org/feed.xml")
        #expect(feed.siteURL == "http://example.org/")
        #expect(feed.iconURL == "")
        #expect(feed.entries.count == 1)

        let entry = try #require(feed.entries.first)
        #expect(entry.date.epochSeconds == 1_071_340_202)
        #expect(entry.hash == "3841e5cf232f5111fc5841e9eba5f4b26d95e7d7124902e0f7272729d65601a6")
        #expect(entry.url == "http://example.org/2003/12/13/atom03")
        #expect(entry.commentsURL == "")
        #expect(entry.title == "Atom-Powered Robots Run Amok")
        #expect(entry.content == "Some text.")
        #expect(entry.author == "John Doe")
    }

    /// `TestParseFeedWithSubtitle`: the description is the Text construct read through `body()`.
    @Test func feedDescriptionIsTheSubtitle() throws {
        let feed = try parse("<feed xmlns=\"http://www.w3.org/2005/Atom\"><title>Example Feed</title>"
            + "<subtitle>This is a subtitle</subtitle><link href=\"http://example.org/\"/>"
            + "<updated>2003-12-13T18:30:02Z</updated><id>urn:uuid:60a76c80-d399-11d9-b93C-0003939e0af6</id>"
            + "</feed>")
        #expect(feed.description == "This is a subtitle")
    }

    /// `TestParseFeedWithoutTitle` — an empty feed title falls back to the site URL.
    @Test func feedTitleFallsBackToTheSiteURL() throws {
        let feed = try parse("<feed xmlns=\"http://www.w3.org/2005/Atom\">"
            + "<link rel=\"alternate\" type=\"text/html\" href=\"https://example.org/\"/>"
            + "<link rel=\"self\" type=\"application/atom+xml\" href=\"https://example.org/feed\"/>"
            + "<updated>2003-12-13T18:30:02Z</updated></feed>")
        #expect(feed.title == "https://example.org/")
    }

    // MARK: - The two URLs the links give

    /// `TestParseFeedURL`: the feed URL is the `self` link and the site URL is the original link,
    /// so the two do not move each other.
    @Test func feedAndSiteURLsComeFromTheirOwnRelations() throws {
        let feed = try parse("<feed xmlns=\"http://www.w3.org/2005/Atom\"><title>Example Feed</title>"
            + "<link rel=\"alternate\" type=\"text/html\" href=\"https://example.org/\"/>"
            + "<link rel=\"self\" type=\"application/atom+xml\" href=\"https://example.org/feed\"/>"
            + "<updated>2003-12-13T18:30:02Z</updated></feed>")

        #expect(feed.siteURL == "https://example.org/")
        #expect(feed.feedURL == "https://example.org/feed")
    }

    /// `TestParseFeedWithRelativeFeedURL` — a relative link is resolved against the base URL.
    @Test func relativeFeedURLIsResolvedAgainstTheBaseURL() throws {
        let feed = try parse("<feed xmlns=\"http://www.w3.org/2005/Atom\"><title>Example Feed</title>"
            + "<link rel=\"alternate\" type=\"text/html\" href=\"https://example.org/\"/>"
            + "<link rel=\"self\" type=\"application/atom+xml\" href=\"/feed\"/>"
            + "<updated>2003-12-13T18:30:02Z</updated></feed>")
        #expect(feed.feedURL == "https://example.org/feed")
    }

    /// `TestParseFeedWithRelativeSiteURL` — the entry URL is resolved against the site URL, not
    /// against the base URL, which is what makes the third assertion different from the first.
    @Test func entryURLIsResolvedAgainstTheSiteURLRatherThanTheBaseURL() throws {
        let feed = try parse("<feed xmlns=\"http://www.w3.org/2005/Atom\"><title>Example Feed</title>"
            + "<link href=\"/blog/atom.xml\" rel=\"self\" type=\"application/atom+xml\"/>"
            + "<link href=\"/blog \"/><entry><title>Test</title>"
            + "<link href=\"/blog/article.html\"/><id>/blog/article.html</id>"
            + "<updated>2003-12-13T18:30:02Z</updated><summary>Some text.</summary></entry></feed>")

        #expect(feed.feedURL == "https://example.org/blog/atom.xml")
        #expect(feed.siteURL == "https://example.org/blog")
        #expect(try #require(feed.entries.first).url == "https://example.org/blog/article.html")
    }

    /// `TestParseFeedSiteURLWithTrailingSpace` and `TestParseFeedWithFeedURLWithTrailingSpace`: the
    /// href is trimmed before it is resolved, so the trailing space does not reach the URL.
    @Test func linkHrefIsTrimmedBeforeItIsResolved() throws {
        #expect(try parse("<feed xmlns=\"http://www.w3.org/2005/Atom\"> <link href=\"http://example.org \"/></feed>")
            .siteURL == "http://example.org")
        #expect(try parse("<feed xmlns=\"http://www.w3.org/2005/Atom\"><link href=\"/blog/atom.xml  \" "
            + "rel=\"self\" type=\"application/atom+xml\"/></feed>").feedURL
            == "https://example.org/blog/atom.xml")
    }

    /// Traced: this adapter uses the base URL as it was given, which is where it differs from the
    /// RSS adapter — `model.Feed` is filled with `baseURL` before anything is resolved, so a
    /// trailing space stays in the feed URL.
    @Test func feedURLIsTheBaseURLAsItWasGiven() throws {
        #expect(try parse("<feed xmlns=\"http://www.w3.org/2005/Atom\"></feed>",
            baseURL: "https://example.org/ ").feedURL == "https://example.org/ ")
    }

    // MARK: - The feed title

    /// `TestParseTitleWithSingleQuote`, `TestParseTitleWithEncodedSingleQuote`,
    /// `TestParseTitleWithSingleQuoteAndHTMLType` and `TestParseWithHTMLEntity`: the feed title is
    /// the Text construct read through `body()`, so it is decoded once and the `type` attribute
    /// does not change it. `AtomTextConstructTests` pins the branch that does change it for an
    /// entry title.
    @Test(arguments: [
        ("<title>' or ’</title>", "' or ’"),
        ("<title type=\"html\">Test&#39;s Blog</title>", "Test's Blog"),
        ("<title type=\"html\">O’Hara</title>", "O’Hara"),
        ("<title>Example &nbsp; Feed</title>", "Example \u{00a0} Feed"),
    ]) func feedTitleIsDecodedOnce(titleElement: String, expected: String) throws {
        let feed = try parse("<feed xmlns=\"http://www.w3.org/2005/Atom\">\(titleElement)"
            + "<link href=\"http://example.org/\"/></feed>")
        #expect(feed.title == expected)
    }

    /// `TestParseWithInvalidCharacterEntity` — an entity the table does not have is left as it was
    /// written, so the URL keeps the ampersand.
    @Test func unknownEntityInAURLStaysAsWritten() throws {
        #expect(try parse("<feed xmlns=\"http://www.w3.org/2005/Atom\">"
            + "<link href=\"http://example.org/a&b\"/></feed>").siteURL == "http://example.org/a&b")
    }

    // MARK: - Icon

    /// `TestParseFeedWithIconURL` — the icon is resolved against the site URL, not against the base
    /// URL, so a relative icon is resolved from the site root, which is what `url.Parse` keeps: the
    /// base path is not a directory.
    @Test func iconIsResolvedAgainstTheSiteURL() throws {
        #expect(try parse("<feed xmlns=\"http://www.w3.org/2005/Atom\"><title>Example Feed</title>"
            + "<link href=\"http://example.org/\"/><icon>http://example.org/icon.png</icon></feed>").iconURL
            == "http://example.org/icon.png")

        let feed = try parse("<feed xmlns=\"http://www.w3.org/2005/Atom\"><link href=\"/blog\"/>"
            + "<icon>/icon.png</icon></feed>")
        #expect(feed.siteURL == "https://example.org/blog")
        #expect(feed.iconURL == "https://example.org/icon.png")
    }

    /// Traced: the reference reads `icon` first and only then `logo`, so `logo` is used when `icon`
    /// is empty and never when it is not. The corpus has no `logo` case, so this is traced against
    /// `atom_10_adapter.go`.
    @Test func logoIsUsedOnlyWhenIconIsMissing() throws {
        #expect(try parse("<feed xmlns=\"http://www.w3.org/2005/Atom\"><link href=\"http://example.org/\"/>"
            + "<icon>http://example.org/icon.png</icon><logo>http://example.org/logo.png</logo></feed>")
            .iconURL == "http://example.org/icon.png")
        #expect(try parse("<feed xmlns=\"http://www.w3.org/2005/Atom\"><link href=\"http://example.org/\"/>"
            + "<logo>http://example.org/logo.png</logo></feed>").iconURL == "http://example.org/logo.png")
    }

    /// `TestParseInvalidXml` — a document that is not XML fails, and the failure is the reader's.
    @Test func documentThatIsNotXMLFails() {
        #expect(throws: XMLError.unexpectedEOF) {
            try Atom10Adapter.parse(baseURL: "https://example.org/", data: Data("garbage".utf8), now: now)
        }
    }
}
