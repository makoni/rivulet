import Foundation
import Testing
@testable import RivuletCore

/// The entry-level rules the Atom 1.0 adapter writes. Ported from Miniflux
/// `internal/reader/atom/atom_10_test.go`; each case names the upstream test it comes from, and a
/// traced case states the value the reference produces.
///
/// The order the reference assembles an entry is the order the later steps read what the earlier
/// ones wrote: the URL before the content, the content before the title, and the title before the
/// hash — so the title fallbacks below are the content the entry already had, not the text
/// construct read again.
@Suite struct AtomEntryTests {
    private let now = ParsedDate(epochSeconds: 1_700_000_000, nanoseconds: 0, zoneName: "UTC",
        zoneOffsetSeconds: 0)

    private func entry(_ entryContent: String, baseURL: String = "https://example.org/") throws
        -> ParsedEntry {
        let feed = try Atom10Adapter.parse(baseURL: baseURL, data: Data(("<feed xmlns=\"http://www.w3.org/2005/Atom\">"
            + "<title>Example Feed</title><link href=\"http://example.org/\"/>"
            + "<author><name>John Doe</name></author>" + entryContent + "</feed>").utf8), now: now)
        return try #require(feed.entries.first)
    }

    // MARK: - URL

    @Test(arguments: [
        // `TestParseEntryWithRelativeURL`: a relative href is resolved against the site URL.
        ("<link href=\"something.html\"/><id>urn:uuid:x</id>", "http://example.org/something.html"),
        // `TestParseEntryURLWithTextHTMLType` and `TestParseEntryURLWithNoRelAndNoType`: the
        // relation may be carried by the type alone.
        ("<link href=\"http://example.org/something.html\" type=\"text/html\"/>",
            "http://example.org/something.html"),
        ("<link href=\"http://example.org/something.html\"/>", "http://example.org/something.html"),
        // `TestParseEntryURLWithAlternateRel`.
        ("<link href=\"http://example.org/something.html\" rel=\"alternate\"/>",
            "http://example.org/something.html"),
        // `TestParseEntryWithIDAsURL`: the entry with no link uses its ID when the ID is an
        // absolute URL, and the site URL when it is not.
        ("<id>http://www.example.org/entries/1</id>", "http://www.example.org/entries/1"),
        ("<id>mailto:john.doe@example.org</id>", "http://example.org/"),
        // Traced against `atom_10_adapter.go`: an entry with no link and no ID at all is the site
        // URL.
        ("", "http://example.org/"),
    ]) func entryURLChain(entryContent: String, expected: String) throws {
        #expect(try entry("<entry>\(entryContent)</entry>").url == expected)
    }

    /// Traced: the relation is compared with `strings.EqualFold`, so the ASCII fold is what makes
    /// an uppercase spelling match. This is the Atom path, which is a different function from the
    /// one `RSSEntryTests` pins.
    @Test func relationIsFoldedOnTheASCIIRange() throws {
        #expect(try entry("<entry><link href=\"http://example.org/a\" rel=\"Alternate\"/></entry>").url
            == "http://example.org/a")

        let feed = try Atom10Adapter.parse(baseURL: "https://example.org/",
            data: Data(("<feed xmlns=\"http://www.w3.org/2005/Atom\"><link rel=\"SELF\" "
                + "href=\"/feed\"/></feed>").utf8), now: now)
        #expect(feed.feedURL == "https://example.org/feed")
    }

    // MARK: - Title

    @Test(arguments: [
        // `TestParseEntryWithoutTitleButWithURL`: nothing to read, so the title is the entry URL.
        ("<link href=\"http://example.org/2003/12/13/atom03\"/><id>urn:uuid:x</id>",
            "http://example.org/2003/12/13/atom03", ""),
        // `TestParseEntryWithoutTitleButWithSummary`: the title is the content, cleaned up.
        ("<link href=\"http://example.org/2003/12/13/atom03\"/><summary>Some text.</summary>",
            "Some text.", "Some text."),
    ]) func titleFallsBackToTheContentAndThenToTheURL(entryContent: String, expectedTitle: String,
        expectedContent: String) throws {
        let parsed = try entry("<entry>\(entryContent)</entry>")
        #expect(parsed.content == expectedContent)
        #expect(parsed.title == expectedTitle)
    }

    /// `TestParseEntryWithoutTitleButWithXHTMLContent`: the title is `TruncateHTML` of the content,
    /// which is the XHTML branch of the Text construct read through the tokenizer, so the entities
    /// the reconstruction holds are decoded there.
    @Test func titleFallbackDecodesTheContent() throws {
        let parsed = try entry("<entry><link href=\"http://example.org/2003/12/13/atom03\"/>"
            + "<content type=\"xhtml\"><div xmlns=\"http://www.w3.org/1999/xhtml\">"
            + "AT&amp;T bought <b>by SBC</b>!</div></content></entry>")
        #expect(parsed.content == "AT&T bought <b>by SBC</b>!")
        #expect(parsed.title == "AT&T bought by SBC!")
    }

    // MARK: - Author

    @Test(arguments: [
        // `TestParseEntryWithAuthorName` — the name wins over the email, each trimmed on its own.
        ("<author><name>Me</name><email>me@localhost</email></author>", "Me"),
        // `TestParseEntryWithoutAuthorName` — an empty name falls back to the email.
        ("<author><name></name><email>me@localhost</email></author>", "me@localhost"),
        // `TestParseEntryWithMultipleAuthors` — the names are joined in sorted order.
        ("<author><name>Alice</name></author><author><name>Bob</name></author>", "Alice, Bob"),
        // `TestParseFeedWithEntryWithoutAuthor` — the entry falls back to the feed author.
        ("", "John Doe"),
        // `TestParseFeedWithMultipleAuthors` — the feed names are sorted and deduplicated too.
        ("<author><name>Alice</name></author><author><name>Bob</name></author>"
            + "<author><name>Bob</name></author>", "Alice, Bob"),
    ]) func entryAuthor(entryContent: String, expected: String) throws {
        #expect(try entry("<entry>\(entryContent)</entry>").author == expected)
    }

    /// `TestParseFeedWithoutAuthor` — with no author at either level the entry has none. The helper
    /// above carries a feed author, so this case builds the feed itself.
    @Test func entryWithoutAnyAuthor() throws {
        let feed = try Atom10Adapter.parse(baseURL: "https://example.org/",
            data: Data(("<feed xmlns=\"http://www.w3.org/2005/Atom\"><link href=\"http://example.org/\"/>"
                + "<entry><link href=\"http://example.org/a\"/></entry></feed>").utf8), now: now)
        #expect(try #require(feed.entries.first).author == "")
    }

    /// Traced: the names are sorted, not kept in document order, so an entry written the other way
    /// round answers the same way as the corpus case above.
    @Test func authorsAreSortedAndNotKeptInDocumentOrder() throws {
        #expect(try entry("<entry><author><name>Bob</name></author><author><name>Alice</name></author>"
            + "</entry>").author == "Alice, Bob")
    }

    // MARK: - Tags

    /// `TestParseItemWithCategories` — the label wins over the term, a name that is empty after the
    /// trim is not a name at all, and a repeated name is not inserted twice.
    @Test func entryCategoriesReadLabelThenTerm() throws {
        let parsed = try entry("<entry><link href=\"http://www.example.org/entries/1\"/>"
            + "<category term=\"ZZZZ\"/><category term=\"ZZZZ\"/><category term=\" \"/>"
            + "<category term=\"Technology\" label=\"Science\"/></entry>")
        #expect(parsed.tags == ["Science", "ZZZZ"])
    }

    /// `TestParseFeedWithCategories` — an entry with no categories falls back to the feed's.
    @Test func entryTagsFallBackToTheFeedCategories() throws {
        let feed = try Atom10Adapter.parse(baseURL: "https://example.org/",
            data: Data(("<feed xmlns=\"http://www.w3.org/2005/Atom\"><link href=\"http://example.org/\"/>"
                + "<category term=\"C term\" label=\"C label\"/><category term=\"B term\" label=\"B label\"/>"
                + "<category term=\"B term\" label=\"B label\"/><category term=\"A term\" label=\"A label\"/>"
                + "<entry><link href=\"http://www.example.org/entries/1\"/></entry></feed>").utf8), now: now)
        #expect(try #require(feed.entries.first).tags == ["A label", "B label", "C label"])
    }

    // MARK: - Date

    @Test(arguments: [
        // `TestParseEntryWithPublished` — published alone.
        ("<published>2003-12-13T18:30:02Z</published>", 1_071_340_202),
        // `TestParseEntryWithPublishedAndUpdated` — published wins over updated.
        ("<published>2002-11-12T18:30:02Z</published><updated>2003-12-13T18:30:02Z</updated>",
            1_037_125_802),
        // Traced: a value that cannot be read is skipped rather than ending the chain, so the next
        // one is used. This is what separates "first value" from "first value that reads".
        ("<published>not a date</published><updated>2003-12-13T18:30:02Z</updated>", 1_071_340_202),
        // Traced: with nothing to read the entry gets the clock the call injected.
        ("", 1_700_000_000),
    ]) func entryDate(entryContent: String, expected: Int64) throws {
        #expect(try entry("<entry><link href=\"http://example.org/a\"/>\(entryContent)</entry>").date
            .epochSeconds == expected)
    }

    // MARK: - Comments

    @Test(arguments: [
        // `TestParseRepliesLinkRelationWithHTMLType` and
        // `TestParseRepliesLinkRelationWithXHTMLType`: the type gate decides, whatever the order
        // the links are written in.
        ("<link rel=\"replies\" type=\"application/atom+xml\" href=\"http://www.example.org/c.xml\"/>"
            + "<link rel=\"replies\" type=\"text/html\" href=\"http://www.example.org/c.html\"/>",
            "http://www.example.org/c.html"),
        ("<link rel=\"replies\" type=\"application/atom+xml\" href=\"http://www.example.org/c.xml\"/>"
            + "<link rel=\"replies\" type=\"application/xhtml+xml\" href=\"http://www.example.org/c.xhtml\"/>",
            "http://www.example.org/c.xhtml"),
        // `TestParseRepliesLinkRelationWithNoType` — a missing type is the assumed Atom type, which
        // the gate does not accept.
        ("<link rel=\"replies\" href=\"http://www.example.org/c.xml\"/>", ""),
        // `TestAbsoluteCommentsURL` — only an absolute URL is kept.
        ("<link rel=\"replies\" type=\"text/html\" href=\"invalid url\"/>", ""),
    ]) func entryCommentsURL(entryContent: String, expected: String) throws {
        #expect(try entry("<entry><link href=\"http://www.example.org/entries/1\"/>"
            + "\(entryContent)</entry>").commentsURL == expected)
    }
}
