import Foundation
import Testing
@testable import RivuletCore

/// The Text construct the Atom 1.0 adapter reads, through its two entry points: `body()` for the
/// description and the content, and `title()` for the title. Ported from Miniflux
/// `internal/reader/atom/atom_10_test.go`; each case names the upstream test it comes from, and a
/// traced case states the value the reference produces.
///
/// The two entry points do not agree on a CDATA section, which is the pair the last case pins:
/// `title()` resolves what `body()` writes as it was read. Both read the character data as the
/// reader resolved it, which is what the tree keeps, so an entity in the text is not a boundary.
/// The boundary is the xhtml branch: the reference answers `innerxml`, the markup as the bytes it
/// read, while the tree keeps a reconstruction of the text it read, so
/// `TestParseEntryWithXHTMLSummary` and `TestParseEntryWithXHTMLContent` — whose stated value keeps
/// an entity — are not ported. The cases whose div has no entity are ported. The boundary is
/// recorded in `docs/parity.md`.
@Suite struct AtomTextConstructTests {
    private let now = ParsedDate(epochSeconds: 1_700_000_000, nanoseconds: 0, zoneName: "UTC",
        zoneOffsetSeconds: 0)

    private func entry(_ entryContent: String) throws -> ParsedEntry {
        let document = "<feed xmlns=\"http://www.w3.org/2005/Atom\"><link href=\"http://example.org/\"/>"
            + "<entry><link href=\"http://example.org/a\"/>" + entryContent + "</entry></feed>"
        let feed = try Atom10Adapter.parse(baseURL: "https://example.org/", data: Data(document.utf8), now: now)
        return try #require(feed.entries.first)
    }

    // MARK: - Title

    @Test(arguments: [
        // `TestParseEntryWithNumericCharacterReferenceTitle` — a character reference is resolved by
        // the reader, which is where the two entry points agree.
        ("<title>&#931; &#xDF;</title>", "Σ ß"),
        // `TestParseEntryWithPlainTextTitle`, the two entries: the type does not change the
        // reading.
        ("<title type=\"text\">AT&amp;T bought by SBC!</title>", "AT&T bought by SBC!"),
        ("<title>AT&amp;T bought by SBC!</title>", "AT&T bought by SBC!"),
        // `TestParseEntryWithDoubleEncodedEntitiesTitle` — a reference is resolved once, so the
        // double encoded one comes back with its ampersand.
        ("<title>&amp;#39;AT&amp;amp;T&amp;#39;</title>", "&#39;AT&amp;T&#39;"),
        // `TestParseEntryTitleWithWhitespaces` — the value is trimmed after the branch is taken.
        ("<title>\n\t\t\t\tSome Title\n\t\t</title>", "Some Title"),
        // `TestParseEntryWithHTMLTitle`, entry 1: the type does not change the reading.
        ("<title type=\"html\">&lt;code&gt;Code&lt;/code&gt; Test</title>", "<code>Code</code> Test"),
        // The same upstream case, its CDATA entries: inside a CDATA section the reader does not
        // resolve, so `title()` is the entry point that does.
        ("<title type=\"html\"><![CDATA[Test with “unicode quote”]]></title>", "Test with “unicode quote”"),
        ("<title>\n\t\t\t\t<![CDATA[Entry title with space around CDATA]]>\n\t\t</title>",
            "Entry title with space around CDATA"),
        ("<title type=\"html\"><![CDATA[<tag>]]></title>", "<tag>"),
        // `TestParseEntryWithXHTMLTitle` — the div is read as the reconstruction, which answers the
        // same as the reference when the markup has no entity.
        ("<title type=\"xhtml\">\n\t\t\t\t<div xmlns=\"http://www.w3.org/1999/xhtml\">\n"
            + "\t\t\t\tThis is <b>XHTML</b> content.\n\t \t\t</div></title>", "This is <b>XHTML</b> content."),
        // `TestParseEntryWithXHTMLTitleWithoutDiv` — without the div the element's own content is
        // read.
        ("<title type=\"xhtml\">\n  test\n  </title>", "test"),
    ]) func titleConstruct(titleElement: String, expected: String) throws {
        #expect(try entry(titleElement).title == expected)
    }

    /// `TestParseEntryWithEmptyXHTMLTitle` — an XHTML title with an empty div is empty, so the
    /// title falls back to the entry URL, which is what the chain answers here.
    @Test func emptyXHTMLTitleFallsBackToTheEntryURL() throws {
        let parsed = try entry("<title type=\"xhtml\"><div xmlns=\"http://www.w3.org/1999/xhtml\"/></title>")
        #expect(parsed.content == "")
        #expect(parsed.title == "http://example.org/a")
    }

    /// Traced: the single-value field takes the last element that matches at its own level, so the
    /// second div is the one read.
    @Test func xhtmlDivTakesTheLastMatch() throws {
        #expect(try entry("<summary type=\"xhtml\"><div xmlns=\"http://www.w3.org/1999/xhtml\">a</div>"
            + "<div xmlns=\"http://www.w3.org/1999/xhtml\">b</div></summary>").content == "b")
    }

    // MARK: - Content

    @Test(arguments: [
        // `TestParseEntryWithTextSummary`, the four entries: `body()` writes the character data the
        // reader resolved, and the four spellings of the text type read the same way.
        ("<summary>AT&amp;T &lt;S&gt;</summary>", "AT&T <S>"),
        ("<summary type=\"text\">AT&amp;T &lt;S&gt;</summary>", "AT&T <S>"),
        ("<summary type=\"text/plain\">AT&amp;T &lt;S&gt;</summary>", "AT&T <S>"),
        ("<summary type=\"text\"><![CDATA[AT&T <S>]]></summary>", "AT&T <S>"),
        // `TestParseEntryWithTextContent`, the four entries.
        ("<content>AT&amp;T &lt;strong&gt;Strong Element&lt;/strong&gt;</content>",
            "AT&T <strong>Strong Element</strong>"),
        ("<content type=\"text\">AT&amp;T &lt;strong&gt;Strong Element&lt;/strong&gt;</content>",
            "AT&T <strong>Strong Element</strong>"),
        ("<content type=\"text/plain\">AT&amp;T &lt;strong&gt;Strong Element&lt;/strong&gt;</content>",
            "AT&T <strong>Strong Element</strong>"),
        ("<content><![CDATA[AT&T <strong>Strong Element</strong>]]></content>",
            "AT&T <strong>Strong Element</strong>"),
        // `TestParseEntryWithHTMLSummary`, the three entries: the text the reader resolved, and the
        // CDATA entry where it did not resolve and `body()` writes the run as it was read.
        ("<summary type=\"html\">&lt;code&gt;std::unique_ptr&amp;lt;S&amp;gt; myvar;&lt;/code&gt;"
            + "</summary>", "<code>std::unique_ptr&lt;S&gt; myvar;</code>"),
        ("<summary type=\"text/html\">&lt;code&gt;std::unique_ptr&amp;lt;S&amp;gt; myvar;&lt;/code&gt;"
            + "</summary>", "<code>std::unique_ptr&lt;S&gt; myvar;</code>"),
        ("<summary type=\"html\"><![CDATA[<code>std::unique_ptr&lt;S&gt; myvar;</code>]]></summary>",
            "<code>std::unique_ptr&lt;S&gt; myvar;</code>"),
        // `TestParseEntryWithHTMLContent`, the three entries.
        ("<content type=\"html\">AT&amp;amp;T bought &lt;b&gt;by SBC&lt;/b&gt;!</content>",
            "AT&amp;T bought <b>by SBC</b>!"),
        ("<content type=\"text/html\">AT&amp;amp;T bought &lt;b&gt;by SBC&lt;/b&gt;!</content>",
            "AT&amp;T bought <b>by SBC</b>!"),
        ("<content type=\"html\"><![CDATA[AT&amp;T bought <b>by SBC</b>!]]></content>",
            "AT&amp;T bought <b>by SBC</b>!"),
        // Traced: the XHTML branch reads the markup, which is the reconstruction, so here the two
        // entry points answer the same way — with no entity in the div.
        ("<summary type=\"xhtml\"><div xmlns=\"http://www.w3.org/1999/xhtml\"><b>a</b></div></summary>",
            "<b>a</b>"),
    ]) func contentConstruct(contentElement: String, expected: String) throws {
        #expect(try entry(contentElement).content == expected)
    }

    /// The pair that separates the two entry points: the same CDATA section read as a title and as
    /// the content. `title()` resolves it, `body()` does not, so the two answers differ by the
    /// entities.
    @Test func theTwoEntryPointsDoNotAgreeOnCDATA() throws {
        let parsed = try entry("<title><![CDATA[a &amp; b]]></title><summary><![CDATA[a &amp; b]]></summary>")
        #expect(parsed.title == "a & b")
        #expect(parsed.content == "a &amp; b")
    }

    /// Traced: the content chain is content, then summary, then the media description, which
    /// `AtomMediaTests` pins for the third step.
    @Test func contentChainReadsContentBeforeSummary() throws {
        #expect(try entry("<content>Content</content><summary>Summary</summary>").content == "Content")
        #expect(try entry("<summary>Summary</summary>").content == "Summary")
    }
}
