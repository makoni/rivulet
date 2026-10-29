import Foundation
import Testing
@testable import RivuletCore

/// The Atom 0.3 rules, which are not the Atom 1.0 ones: the Content construct reads through its
/// `mode` attribute and then escapes what it got, the date chain is `issued`, `modified`,
/// `created`, the author is one Person rather than a list, and the entry has no ID-as-URL fallback.
/// Ported from Miniflux `internal/reader/atom/atom_03_test.go`; each case names the upstream test
/// it comes from, and a traced case states the value the reference produces.
///
/// This format's structs have no icon, tags, comments, attachments or reading time, so those fields
/// are what the model starts with — the case at the end pins that nothing writes them.
@Suite struct Atom03Tests {
    private let now = ParsedDate(epochSeconds: 1_700_000_000, nanoseconds: 0, zoneName: "UTC",
        zoneOffsetSeconds: 0)

    private func parse(_ document: String, baseURL: String = "http://diveintomark.org/") throws
        -> ParsedFeed {
        try Atom03Adapter.parse(baseURL: baseURL, data: Data(document.utf8), now: now)
    }

    /// `TestParseAtom03`, the reference's sample feed read end to end.
    @Test func sampleFeedIsReadEndToEnd() throws {
        let feed = try parse("<feed version=\"0.3\" xmlns=\"http://purl.org/atom/ns#\">"
            + "<title>dive into mark</title>"
            + "<link rel=\"alternate\" type=\"text/html\" href=\"http://diveintomark.org/\"/>"
            + "<modified>2003-12-13T18:30:02Z</modified><author><name>Mark Pilgrim</name></author>"
            + "<entry><title>Atom 0.3 snapshot</title>"
            + "<link rel=\"alternate\" type=\"text/html\" href=\"http://diveintomark.org/2003-12-13/atom03\"/>"
            + "<id>tag:diveintomark.org,2003:3.2397</id><issued>2003-12-13T08:29:29-04:00</issued>"
            + "<modified>2003-12-13T18:30:02Z</modified><summary type=\"text/plain\">It&apos;s a test</summary>"
            + "<content type=\"text/html\" mode=\"escaped\"><![CDATA[<p>HTML content</p>]]></content>"
            + "</entry></feed>", baseURL: "http://diveintomark.org/atom.xml")

        #expect(feed.title == "dive into mark")
        #expect(feed.feedURL == "http://diveintomark.org/atom.xml")
        #expect(feed.siteURL == "http://diveintomark.org/")
        #expect(feed.entries.count == 1)

        let entry = try #require(feed.entries.first)
        #expect(entry.date.epochSeconds == 1_071_318_569)
        #expect(entry.date.zoneOffsetSeconds == -14400)
        #expect(entry.hash == "b70d30334b808f32e66eb19fabb263525cecd18f205720b583e84f7f295cf728")
        #expect(entry.url == "http://diveintomark.org/2003-12-13/atom03")
        #expect(entry.title == "Atom 0.3 snapshot")
        #expect(entry.content == "<p>HTML content</p>")
        #expect(entry.author == "Mark Pilgrim")
    }

    /// `TestParseAtom03WithoutSiteURL` — with no link the site URL is the base URL as it was given.
    @Test func siteURLFallsBackToTheBaseURL() throws {
        #expect(try parse("<feed version=\"0.3\" xmlns=\"http://purl.org/atom/ns#\"></feed>",
            baseURL: "http://diveintomark.org/atom.xml").siteURL == "http://diveintomark.org/atom.xml")
    }

    /// `TestParseAtom03WithoutFeedTitle` — an empty feed title falls back to the site URL.
    @Test func feedTitleFallsBackToTheSiteURL() throws {
        #expect(try parse("<feed version=\"0.3\" xmlns=\"http://purl.org/atom/ns#\">"
            + "<link rel=\"alternate\" type=\"text/html\" href=\"http://diveintomark.org/\"/>"
            + "<entry><id>tag:x</id></entry></feed>").title == "http://diveintomark.org/")
    }

    // MARK: - Entry title

    @Test(arguments: [
        // `TestParseAtom03WithoutEntryTitleButWithLink` — nothing to read, so the title is the
        // entry URL.
        ("<link rel=\"alternate\" type=\"text/html\" href=\"http://diveintomark.org/2003-12-13/atom03\"/>"
            + "<id>tag:x</id>", "http://diveintomark.org/2003-12-13/atom03", ""),
        // `TestParseAtom03WithoutEntryTitleButWithSummary`: the title is the content cleaned up,
        // which is where the escape the content construct applied is decoded again.
        ("<link rel=\"alternate\" type=\"text/html\" href=\"http://diveintomark.org/a\"/><id>tag:x</id>"
            + "<summary type=\"text/plain\">It&apos;s a test</summary>", "It's a test", "It&#39;s a test"),
        // `TestParseAtom03WithoutEntryTitleButWithXMLContent` — the tags are stripped from the
        // content.
        ("<link rel=\"alternate\" type=\"text/html\" href=\"http://diveintomark.org/a\"/><id>tag:x</id>"
            + "<content mode=\"xml\" type=\"text/html\"><p>Some text.</p></content>", "Some text.",
            "<p>Some text.</p>"),
    ]) func entryTitleChain(entryContent: String, expectedTitle: String, expectedContent: String) throws {
        let parsed = try entry(entryContent)
        #expect(parsed.content == expectedContent)
        #expect(parsed.title == expectedTitle)
    }

    // MARK: - Content construct

    @Test(arguments: [
        // `TestParseAtom03WithXMLContent` — mode `xml` is the markup the element has.
        ("<content mode=\"xml\" type=\"text/html\"><p>Some text.</p></content>", "<p>Some text.</p>"),
        // `TestParseAtom03WithBase64Content` — mode `base64` is decoded before the media type is
        // read.
        ("<content mode=\"base64\" type=\"text/html\">PHA+U29tZSB0ZXh0LjwvcD4=</content>", "<p>Some text.</p>"),
        // `TestParseAtom03WithSummaryOnly` — with no type, and with a type that is not `text/html`,
        // the value is escaped, which is what writes `&#39;` for the apostrophe.
        ("<summary type=\"text/plain\">It&apos;s a test</summary>", "It&#39;s a test"),
        // Traced: the default mode is the character data, not the markup.
        ("<content>It&apos;s a test</content>", "It&#39;s a test"),
        // Traced: only `type == "text/html"` skips the escape, and the comparison is not a fold.
        ("<content mode=\"escaped\" type=\"text/html\">&lt;p&gt;</content>", "<p>"),
        ("<content mode=\"escaped\" type=\"html\">&lt;p&gt;</content>", "&lt;p&gt;"),
    ]) func contentConstruct(entryContent: String, expected: String) throws {
        #expect(try entry(entryContent).content == expected)
    }

    /// Traced: `base64.DecodeString` skips a carriage return and a line feed and fails on any other
    /// character, so a value that cannot be read leaves the content empty rather than half-read.
    @Test func base64ReadsTheTwoNewlinesAndFailsOnAnythingElse() throws {
        #expect(try entry("<content mode=\"base64\" type=\"text/html\">"
            + "PHA+\nU29tZSB0ZXh0LjwvcD4=\r\n</content>").content == "<p>Some text.</p>")
        #expect(try entry("<content mode=\"base64\" type=\"text/html\">PHA+ U29tZSB0ZXh0LjwvcD4=</content>")
            .content == "")
    }

    // MARK: - Author

    /// Traced: the entry has one Person, not a list, so the last `author` element at its own level
    /// is the one the field holds, and the entry author wins over the feed author.
    @Test func singlePersonReadsTheLastMatch() throws {
        let parsed = try entry("<author><name>Entry</name></author><author><name>Later</name></author>")
        #expect(parsed.author == "Later")
    }

    // MARK: - Date

    @Test(arguments: [
        // `TestParseAtom03` pins `issued` winning over `modified`; the chain continues to
        // `created`.
        ("<issued>2003-12-13T08:29:29-04:00</issued><modified>2003-12-13T18:30:02Z</modified>",
            1_071_318_569),
        ("<created>2003-12-14T08:29:29-04:00</created>", 1_071_404_969),
        ("<modified>2003-12-13T18:30:02Z</modified><created>2003-12-14T08:29:29-04:00</created>",
            1_071_340_202),
        ("", 1_700_000_000),
    ]) func entryDate(entryContent: String, expected: Int64) throws {
        #expect(try entry(entryContent).date.epochSeconds == expected)
    }

    // MARK: - What this format does not read

    /// Traced: there is no ID-as-URL fallback in this format, so an entry with no link keeps what
    /// the model starts with, and the fields the reference's struct does not have are also what the
    /// model starts with.
    @Test func atom03EntryReadsNoTagsAttachmentsOrComments() throws {
        let parsed = try entry("<id>http://www.example.org/entries/1</id>"
            + "<media:group><media:content url=\"http://example.org/file.mp4\" type=\"audio/mpeg\"/>"
            + "</media:group>")

        #expect(parsed.url == "")
        #expect(parsed.tags.isEmpty)
        #expect(parsed.enclosures.isEmpty)
        #expect(parsed.commentsURL == "")
        #expect(parsed.readingTimeMinutes == 0)
    }

    private func entry(_ entryContent: String) throws -> ParsedEntry {
        let feed = try parse("<feed version=\"0.3\" xmlns=\"http://purl.org/atom/ns#\""
            + " xmlns:media=\"http://search.yahoo.com/mrss/\">"
            + "<entry>\(entryContent)</entry></feed>")
        return try #require(feed.entries.first)
    }
}
