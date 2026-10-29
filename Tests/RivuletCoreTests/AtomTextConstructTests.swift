import Foundation
import Testing
@testable import RivuletCore

/// The Text construct the Atom 1.0 adapter reads, through its two entry points: `body()` for the
/// description and the content, and `title()` for the title. Ported from Miniflux
/// `internal/reader/atom/atom_10_test.go`; each case names the upstream test it comes from, and a
/// traced case states the value the reference produces.
///
/// The two entry points do not agree on a CDATA section, which is the pair the last case pins:
/// `title()` decodes what `body()` writes as it was read. `body()` reads the character data the
/// reader decoded, and the xhtml branch reads the markup, which the tree keeps as a
/// reconstruction of the text it read. So a case whose text carries entities, or whose value
/// comes from markup inside the element, cannot be pinned against the reference. Those are not
/// ported: entry 1 of `TestParseEntryWithHTMLTitle`, `TestParseEntryWithHTMLSummary`,
/// `TestParseEntryWithHTMLContent`, `TestParseEntryWithXHTMLTitle`,
/// `TestParseEntryWithXHTMLContent`, `TestParseEntryWithXHTMLSummary`,
/// `TestParseTitleWithSingleQuote`, `TestParseTitleWithEncodedSingleQuote` and entry 1 of
/// `TestParseTitleWithSingleQuoteAndHTMLType`, plus every entry whose stated value is the text
/// the element has plus the markup of a child. Only cases whose value the tree and the reference
/// answer the same way are ported here, and the boundary is recorded in `docs/parity.md`.
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
        // `TestParseEntryWithNumericCharacterReferenceTitle` — a character reference is decoded by
        // the reader, which is where the two entry points agree.
        ("<title>&#931; &#xDF;</title>", "Σ ß"),
        // `TestParseEntryTitleWithWhitespaces` — the value is trimmed after the branch is taken.
        ("<title>\n\t\t\t\tSome Title\n\t\t</title>", "Some Title"),
        // `TestParseEntryWithHTMLTitle`, the entry with no entities in its text: a run inside a
        // CDATA section is read without decoding, so `title()` is the one that decodes it.
        ("<title type=\"html\"><![CDATA[Test with “unicode quote”]]></title>", "Test with “unicode quote”"),
        ("<title>\n\t\t\t\t<![CDATA[Entry title with space around CDATA]]>\n\t\t</title>",
            "Entry title with space around CDATA"),
        // The same upstream case, its self-closing entry.
        ("<title type=\"html\"><![CDATA[<tag>]]></title>", "<tag>"),
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
        // `TestParseEntryWithTextSummary` and `TestParseEntryWithTextContent`, read with text that
        // has no entities and no markup inside: `body()` writes the character data the reader
        // decoded, and the four spellings of the text type read the same way.
        ("<summary>Some text.</summary>", "Some text."),
        ("<summary type=\"text\">Some text.</summary>", "Some text."),
        ("<summary type=\"text/plain\">Some text.</summary>", "Some text."),
        ("<summary type=\"text\"><![CDATA[Some text.]]></summary>", "Some text."),
        ("<content>Some text.</content>", "Some text."),
        ("<content type=\"text\">Some text.</content>", "Some text."),
        ("<content type=\"text/plain\">Some text.</content>", "Some text."),
        ("<content><![CDATA[Some text.]]></content>", "Some text."),
        // `TestParseEntryWithHTMLSummary` and `TestParseEntryWithHTMLContent`, their CDATA entries:
        // inside a CDATA section the reader does not decode, so `body()` writes the run as it was
        // read.
        ("<summary type=\"html\"><![CDATA[Some text.]]></summary>", "Some text."),
        ("<content type=\"html\"><![CDATA[Some text.]]></content>", "Some text."),
        // Traced: the XHTML branch reads the markup, which is the reconstruction, so here the two
        // entry points answer the same way.
        ("<summary type=\"xhtml\"><div xmlns=\"http://www.w3.org/1999/xhtml\">test</div></summary>", "test"),
    ]) func contentConstruct(contentElement: String, expected: String) throws {
        #expect(try entry(contentElement).content == expected)
    }

    /// The pair that separates the two entry points: the same CDATA section read as a title and as
    /// the content. `title()` decodes it, `body()` does not, so the two answers differ by the
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
