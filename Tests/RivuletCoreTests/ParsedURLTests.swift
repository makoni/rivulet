import Foundation
import Testing
@testable import RivuletCore

/// The URL shape the reader resolves through, ported from Go's `net/url` (`url.Parse`).
///
/// Only the parts the reader uses are ported: the fields `parse` fills, the string it rebuilds, the
/// host and escape rules that decide whether a value parses at all. Every pin in this suite is
/// traced against Go's source, because the reference has no corpus for the parsed form itself; the
/// corpus pins are in `URLResolveTests` and `URLRulesTests`. The subset boundary is recorded in
/// `docs/parity.md`.
@Suite struct ParsedURLTests {
    // MARK: - Fields parse fills

    @Test func parseFillsTheFieldsGoFills() throws {
        let parsed = try ParsedURL.parse("https://user:pass@example.org:8080/folder/a%20b?q=1")
        #expect(parsed.scheme == "https")
        #expect(parsed.isOpaquePath == false)
        #expect(parsed.userInfo == "user:pass")
        #expect(parsed.host == "example.org:8080")
        #expect(parsed.path == "/folder/a b")
        #expect(parsed.rawPath == "")
        #expect(parsed.rawQuery == "q=1")
        #expect(parsed.fragment == "")
    }

    /// Go lower-cases the scheme, so `RootURL` and `String()` rebuild it lower-cased whatever the
    /// input case was.
    @Test func schemeIsLowerCasedOnParse() throws {
        let parsed = try ParsedURL.parse("HTTPS://Example.org/P")
        #expect(parsed.scheme == "https")
        #expect(parsed.description == "https://Example.org/P")
    }

    /// A path keeps the form it was read as when that form is not the canonical encoding of the
    /// decoded path — Go's `RawPath`, and its documented case `http://golang.org/a%2Fb`.
    @Test func pathKeepsTheReadingWhenItIsNotCanonical() throws {
        let parsed = try ParsedURL.parse("https://example.org/a%2Fb")
        #expect(parsed.path == "/a/b")
        #expect(parsed.rawPath == "/a%2Fb")
        #expect(parsed.escapedPath == "/a%2Fb")
        #expect(parsed.description == "https://example.org/a%2Fb")
    }

    /// A path that is already canonical has no recorded raw form.
    @Test func canonicalPathHasNoRawPath() throws {
        let parsed = try ParsedURL.parse("https://example.org/a%20b")
        #expect(parsed.path == "/a b")
        #expect(parsed.rawPath == "")
        #expect(parsed.escapedPath == "/a%20b")
        #expect(parsed.description == "https://example.org/a%20b")
    }

    /// A reading that is not canonical but is not a valid encoding either is recorded and then
    /// rebuilt canonically, which is Go's `EscapedPath` refusing to use a `RawPath` it cannot
    /// decode back.
    @Test func recordedPathThatIsNotValidEncodingRebuildsCanonical() throws {
        let parsed = try ParsedURL.parse("https://example.org/a b")
        #expect(parsed.path == "/a b")
        #expect(parsed.rawPath == "/a b")
        #expect(parsed.escapedPath == "/a%20b")
        #expect(parsed.description == "https://example.org/a%20b")
    }

    /// A fragment follows the same rule as the path, which is the upstream case `RawFragment:
    /// "foo%26bar"`: in fragment mode Go escapes nothing, so a value read as `%26` is not canonical
    /// and is kept as it was read.
    @Test func fragmentKeepsTheReadingWhenItIsNotCanonical() throws {
        let parsed = try ParsedURL.parse("https://example.org/#a%26b")
        #expect(parsed.fragment == "a&b")
        #expect(parsed.rawFragment == "a%26b")
        #expect(parsed.description == "https://example.org/#a%26b")
    }

    /// A scheme with no authority keeps its rest as it was read, which is why `mailto:` values are
    /// not resolved against the feed URL.
    @Test func schemeWithoutAuthorityKeepsItsRestAsRead() throws {
        let parsed = try ParsedURL.parse("mailto:user@example.org")
        #expect(parsed.scheme == "mailto")
        #expect(parsed.isOpaquePath == true)
        #expect(parsed.host == "")
        #expect(parsed.opaqueRaw == "user@example.org")
        #expect(parsed.path == "")
        #expect(parsed.description == "mailto:user@example.org")
    }

    /// `magnet:?xt=...` has the query cut before the opaque check, so its opaque form is empty and
    /// the string is rebuilt as the scheme followed by the query.
    @Test func opaqueSchemeWithOnlyAQueryRebuildsToItsReading() throws {
        let parsed = try ParsedURL.parse("magnet:?xt=urn:btih:abc")
        #expect(parsed.scheme == "magnet")
        #expect(parsed.isOpaquePath == false)
        #expect(parsed.path == "")
        #expect(parsed.rawQuery == "xt=urn:btih:abc")
        #expect(parsed.description == "magnet:?xt=urn:btih:abc")
    }

    /// A query is kept as it was read; only `query()` decodes it.
    @Test func queryIsKeptAsReadInRebuiltString() throws {
        let parsed = try ParsedURL.parse("https://example.org/p?b=a+c")
        #expect(parsed.rawQuery == "b=a+c")
        #expect(parsed.description == "https://example.org/p?b=a+c")
    }

    /// A value that ends with a single `?` keeps it, which is Go's `ForceQuery`, and a reference
    /// with a forced empty query does not take the base query.
    @Test func forcedEmptyQueryIsKeptAndNotInherited() throws {
        let forced = try ParsedURL.parse("https://example.org/p?")
        #expect(forced.forceQuery == true)
        #expect(forced.rawQuery == "")
        #expect(forced.description == "https://example.org/p?")

        let base = try ParsedURL.parse("https://example.org/p?base=1")
        #expect(base.resolving(reference: forced).description == "https://example.org/p?")
    }

    /// Go's `OmitHost`: a scheme followed by a path with no authority is rebuilt without the
    /// authority marker, and `ResolveReference` does not hand that flag to the resolved value.
    @Test func schemeWithNoAuthorityAndASlashPathKeepsItsShape() throws {
        let parsed = try ParsedURL.parse("http:/a")
        #expect(parsed.omitHost == true)
        #expect(parsed.host == "")
        #expect(parsed.description == "http:/a")
        #expect(parsed.resolving(reference: try ParsedURL.parse("b")).description == "http:///b")
    }

    @Test func urlWithoutSchemeAndHostIsAPathOnlyValue() throws {
        let parsed = try ParsedURL.parse("/relative/path")
        #expect(parsed.scheme == "")
        #expect(parsed.host == "")
        #expect(parsed.path == "/relative/path")
        #expect(parsed.description == "/relative/path")
    }

    /// An empty value parses to an empty URL rather than failing, which is what the
    /// tracking-parameter cleaner relies on: the reference parses an empty string and gets a URL it
    /// does not treat as nil.
    @Test func emptyInputParsesToAnEmptyValue() throws {
        let parsed = try ParsedURL.parse("")
        #expect(parsed == ParsedURL())
        #expect(parsed.description == "")
    }

    // MARK: - Host and escape rules

    /// The upstream cases `TestIsHTTPS` and `TestDomain` both answer through this: the value does
    /// not parse, so the caller returns what it was given.
    @Test func invalidCharacterInHostFailsToParse() {
        #expect(throws: URLParseError.invalidHost(character: "|")) {
            try ParsedURL.parse("https://example|org/")
        }
    }

    /// Go reports a bracket that opens inside the host as an invalid IP-literal.
    @Test func bracketInsideHostFailsToParse() {
        #expect(throws: URLParseError.invalidHost(character: "[")) { try ParsedURL.parse("http://a[::1]/") }
    }

    @Test func unclosedBracketHostFailsToParse() {
        #expect(throws: URLParseError.unclosedBracketHost) { try ParsedURL.parse("http://[::1") }
    }

    @Test func invalidPortFailsToParse() {
        #expect(throws: URLParseError.invalidPort(":abc")) { try ParsedURL.parse("http://example.org:abc/") }
        #expect(throws: URLParseError.invalidPort("1055")) { try ParsedURL.parse("http://[::1]1055/") }
    }

    @Test func invalidEscapeInPathFailsToParse() {
        #expect(throws: URLParseError.invalidEscape("%zz")) { try ParsedURL.parse("https://example.org/a%zz") }
    }

    /// Go reads the host through its host mode, where a byte at or above DEL is part of the host
    /// and a percent escape may only carry one, so an internationalised host parses there. The
    /// exception is `%25`, which carries the percent sign of a zone identifier.
    @Test func hostAcceptsNonASCIIBytesAndOnlyTheirEscapes() throws {
        #expect(try ParsedURL.parse("http://fooébar/").host == "fooébar")
        #expect(try ParsedURL.parse("http://foo%c3%a9bar/").host == "fooébar")
        #expect(try ParsedURL.parse("http://foo%25bar/").host == "foo%bar")
        #expect(throws: URLParseError.invalidEscape("%2f")) { try ParsedURL.parse("http://foo%2fbar/") }
    }

    /// Go enforces strict colons for `http` and `https`, so the port is read at the first colon
    /// there; another scheme keeps the historical reading of the last colon.
    @Test func portIsReadAtTheFirstColonForHTTPAndHTTPSSchemes() throws {
        #expect(throws: URLParseError.invalidPort(":bar:80")) {
            try ParsedURL.parse("http://foo:bar:80/")
        }
        #expect(try ParsedURL.parse("ftp://foo:bar:80/").host == "foo:bar:80")
    }

    /// Go checks the user part against the class RFC 3986 §3.2.1 allows, and it does that after the
    /// host is read, so a value with both a bad host and a bad user reports the host.
    @Test func userPartOutsideTheUserinfoClassFailsToParse() throws {
        #expect(throws: URLParseError.invalidUserinfo("a\"b")) {
            try ParsedURL.parse("http://a\"b@host/")
        }
        #expect(throws: URLParseError.invalidHost(character: "|")) {
            try ParsedURL.parse("http://a\"b@bad|host/")
        }
        // The delimiter between the user and the host is the last `@`, so one inside the user part
        // is allowed, as in `username:p@ssword@google.com`.
        #expect(try ParsedURL.parse("http://user:p@ss@example.org/").userInfo == "user:p@ss")
    }

    /// Go reports a colon at the start of the value as a missing protocol scheme.
    @Test func emptySchemeBeforeAColonFailsToParse() {
        #expect(throws: URLParseError.missingScheme) { try ParsedURL.parse("://bad") }
    }

    /// A value with no scheme whose first path segment carries a colon is the error Go reports for
    /// values like `cache_object:foo/bar` read as a relative reference.
    @Test func colonInFirstSegmentOfARelativeValueFailsToParse() {
        #expect(throws: URLParseError.colonInFirstSegment("123:x")) { try ParsedURL.parse("123:x") }
    }

    /// A value that is not read as a scheme at all is a path, not an error: Go only errors when the
    /// colon is the first character.
    @Test func invalidSchemeCharacterIsNoSchemeNotAnError() throws {
        let parsed = try ParsedURL.parse("a?b:c")
        #expect(parsed.scheme == "")
        #expect(parsed.rawQuery == "b:c")
        #expect(parsed.path == "a")
    }

    /// Go refuses control characters, which is what keeps a header or a fragment from being
    /// injected through a feed value. The check is made on the part before the fragment.
    @Test func controlCharacterFailsToParse() {
        #expect(throws: URLParseError.controlCharacter("\n")) { try ParsedURL.parse("https://example.org/a\nb") }
        #expect(throws: URLParseError.controlCharacter("\t")) { try ParsedURL.parse("\thttps://example.org/p") }
    }

    /// Because the check is made on the part before the fragment, a control character that is
    /// inside the fragment is accepted, as Go accepts it.
    @Test func controlCharacterInsideTheFragmentIsAccepted() throws {
        #expect(try ParsedURL.parse("https://example.org/p#\n").fragment == "\n")
    }

    @Test func hostNameIsHostWithoutPortOrBrackets() throws {
        #expect(try ParsedURL.parse("https://example.org:8080/p").hostName == "example.org")
        #expect(try ParsedURL.parse("https://example.org/p").hostName == "example.org")
        #expect(try ParsedURL.parse("http://[::1]:1055/p").host == "[::1]:1055")
        #expect(try ParsedURL.parse("http://[::1]:1055/p").hostName == "::1")
    }

    // MARK: - ResolveReference

    @Test func dotSegmentsResolveAgainstTheBasePath() throws {
        let base = try ParsedURL.parse("https://example.org/a/b/c")
        #expect(base.resolving(reference: try ParsedURL.parse("../d")).description
            == "https://example.org/a/d")
        #expect(base.resolving(reference: try ParsedURL.parse("./x")).description
            == "https://example.org/a/b/x")
        // A `..` at the start of the reference drops the segment before it, which for a base path
        // without a trailing slash means the whole path.
        #expect(try ParsedURL.parse("https://example.org/a/b").resolving(reference: try ParsedURL.parse("../c"))
            .description == "https://example.org/c")
    }

    @Test func emptyRelativeTakesTheBasePathQueryAndFragment() throws {
        let base = try ParsedURL.parse("https://example.org/folder/?q=1#f")
        #expect(base.resolving(reference: try ParsedURL.parse("")).description
            == "https://example.org/folder/?q=1#f")
        #expect(try ParsedURL.parse("https://example.org/folder/").resolving(reference: ParsedURL())
            .description == "https://example.org/folder/")
    }

    /// A reference that carries a query but no path keeps the base path, and the base path is
    /// cleaned on the way through `resolvePath`, as Go's `ResolveReference` does.
    @Test func queryOnlyReferenceKeepsTheCleanedBasePath() throws {
        let dotPath = try ParsedURL.parse("https://example.org/a/./b/")
        let resolved = dotPath.resolving(reference: try ParsedURL.parse("?q=1"))
        #expect(resolved.path == "/a/b/")
        #expect(resolved.description == "https://example.org/a/b/?q=1")

        // Cleaning pops the whole segment before a `..`, not just the characters of the segment.
        let parentPath = try ParsedURL.parse("https://example.org/a/../b/")
        #expect(parentPath.resolving(reference: try ParsedURL.parse("?q=1")).path == "/b/")
    }

    @Test func relativeReferenceTakesSchemeAndHostFromBase() throws {
        let base = try ParsedURL.parse("https://example.org/folder/")
        let resolved = base.resolving(reference: try ParsedURL.parse("path/file.ext"))
        #expect(resolved.scheme == "https")
        #expect(resolved.host == "example.org")
        #expect(resolved.path == "/folder/path/file.ext")
    }

    @Test func hostInRelativeReferenceIsKeptAndOnlySchemeIsTaken() throws {
        let base = try ParsedURL.parse("https://example.org/")
        let resolved = base.resolving(reference: try ParsedURL.parse("//static.example.org/path/./x"))
        #expect(resolved.scheme == "https")
        #expect(resolved.host == "static.example.org")
        // Go cleans the path of a reference that carries an authority.
        #expect(resolved.description == "https://static.example.org/path/x")
    }

    @Test func opaqueReferenceIsReturnedAsRead() throws {
        let base = try ParsedURL.parse("https://example.org/")
        let resolved = base.resolving(reference: try ParsedURL.parse("mailto:user@example.org"))
        #expect(resolved.scheme == "mailto")
        #expect(resolved.opaqueRaw == "user@example.org")
        #expect(resolved.description == "mailto:user@example.org")
    }

    @Test func cleanPathRemovesDotSegmentsAndKeepsTheTrailingSlash() throws {
        let base = try ParsedURL.parse("https://example.org/")
        #expect(base.resolving(reference: try ParsedURL.parse("a/./b")).path == "/a/b")
        #expect(base.resolving(reference: try ParsedURL.parse("a/../b")).path == "/b")
        #expect(base.resolving(reference: try ParsedURL.parse("a/")).path == "/a/")
        #expect(base.resolving(reference: try ParsedURL.parse("..")).path == "/")
        // A double slash inside the path is not collapsed, which is Go's `resolvePath`.
        #expect(base.resolving(reference: try ParsedURL.parse("a//b")).path == "/a//b")
    }
}
