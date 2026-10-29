import Foundation
import Testing
@testable import RivuletCore

/// The language the Atom adapters write. Ported from Miniflux
/// `internal/reader/atom/atom_10_test.go` and `internal/reader/atom/atom_03_test.go`; each case
/// names the upstream test it comes from, and a traced case states the value the reference
/// produces.
///
/// The reference reads `xml:lang` through a namespace-qualified field tag, so an attribute from
/// another namespace cannot override it, and an unqualified `lang` is not the XML one. The
/// inheritance is modelled as the adapter's own fallback — the entry's attribute, then the feed's —
/// which is what the reference's adapter code does on purpose, and which for an entry is the whole
/// chain the decoder carries; the tree has no parent link, so the inheritance is not modelled as a
/// walk.
@Suite struct AtomLanguageTests {
    private let now = ParsedDate(epochSeconds: 1_700_000_000, nanoseconds: 0, zoneName: "UTC",
        zoneOffsetSeconds: 0)

    private func entryLanguage(_ document: String) throws -> String {
        let feed = try Atom10Adapter.parse(baseURL: "http://example.org/feed.xml", data: Data(document.utf8),
            now: now)
        return try #require(feed.entries.first).language
    }

    private func atom03EntryLanguage(_ document: String) throws -> String {
        let feed = try Atom03Adapter.parse(baseURL: "http://diveintomark.org/atom.xml", data: Data(document.utf8),
            now: now)
        return try #require(feed.entries.first).language
    }

    // MARK: - The attribute itself

    @Test(arguments: [
        // `TestParseFeedWithLanguage` — normalized, as `Language.Normalize` answers.
        ("<feed xmlns=\"http://www.w3.org/2005/Atom\" xml:lang=\"fr-CA\"><entry></entry></feed>", "fr-ca"),
        // `TestParseFeedWithoutLanguage` — nothing declared, nothing written.
        ("<feed xmlns=\"http://www.w3.org/2005/Atom\"><entry></entry></feed>", ""),
        // `TestParseFeedWithUnqualifiedLangAttribute` — an unqualified `lang` is not the XML
        // namespace, so the field tag does not match it.
        ("<feed xmlns=\"http://www.w3.org/2005/Atom\" lang=\"de\"><entry></entry></feed>", ""),
        // `TestParseFeedWithForeignLangAttribute` — the other namespace cannot override the real
        // one.
        ("<feed xmlns=\"http://www.w3.org/2005/Atom\" xmlns:foo=\"http://example.org/ns\" "
            + "xml:lang=\"fr-CA\" foo:lang=\"zz\"><entry xml:lang=\"fr-CA\" foo:lang=\"zz\"></entry></feed>",
            "fr-ca"),
        // `TestParseEntryWithLanguage` — the entry's own attribute wins over the feed's.
        ("<feed xmlns=\"http://www.w3.org/2005/Atom\" xml:lang=\"en\">"
            + "<entry xml:lang=\"fr-CA\"></entry></feed>", "fr-ca"),
        // `TestParseEntryWithoutLanguageInheritsFeedLanguage`.
        ("<feed xmlns=\"http://www.w3.org/2005/Atom\" xml:lang=\"en\"><entry></entry></feed>", "en"),
        // `TestParseEntryWithoutAnyLanguage`.
        ("<feed xmlns=\"http://www.w3.org/2005/Atom\"><entry></entry></feed>", ""),
    ]) func atom10EntryLanguage(document: String, expected: String) throws {
        #expect(try entryLanguage(document) == expected)
    }

    /// `TestParseAtom03WithLanguage` — the same rule through the 0.3 structs: the entry's own
    /// attribute, otherwise the feed's, and the foreign namespace left out.
    @Test func atom03EntryLanguageInheritsTheFeedValue() throws {
        let document = "<feed version=\"0.3\" xmlns=\"http://purl.org/atom/ns#\" "
            + "xmlns:foo=\"http://example.org/ns\" xml:lang=\"fr-CA\" foo:lang=\"zz\">"
            + "<entry xml:lang=\"pt-BR\" foo:lang=\"zz\"></entry></feed>"

        #expect(try atom03EntryLanguage(document) == "pt-br")
    }

    /// Traced: the feed-level value is what the second entry of the same upstream case reads, which
    /// is the half that separates the entry's own attribute from the fallback.
    @Test func secondEntryOfTheUpstreamCaseInheritsToo() throws {
        let feed = try Atom03Adapter.parse(baseURL: "http://diveintomark.org/atom.xml",
            data: Data(("<feed version=\"0.3\" xmlns=\"http://purl.org/atom/ns#\" "
                + "xmlns:foo=\"http://example.org/ns\" xml:lang=\"fr-CA\" foo:lang=\"zz\">"
                + "<entry xml:lang=\"pt-BR\" foo:lang=\"zz\"></entry><entry></entry></feed>").utf8), now: now)

        #expect(feed.language == "fr-ca")
        #expect(feed.entries.count == 2)
        #expect(feed.entries[1].language == "fr-ca")
    }

    /// Traced: the inheritance is the adapter's fallback rather than a walk up the tree, so a value
    /// declared on an element that is not the entry is not inherited — which is the boundary
    /// recorded in `docs/parity.md`.
    @Test func inheritanceIsTheFeedValueAndNotAParentWalk() throws {
        let feed = try Atom10Adapter.parse(baseURL: "http://example.org/feed.xml",
            data: Data(("<feed xmlns=\"http://www.w3.org/2005/Atom\" xml:lang=\"en\"><author xml:lang=\"fr\">"
                + "<name>x</name></author><entry></entry></feed>").utf8), now: now)

        #expect(feed.language == "en")
        #expect(try #require(feed.entries.first).language == "en")
    }
}
