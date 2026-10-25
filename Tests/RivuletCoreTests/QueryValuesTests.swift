import Foundation
import Testing
@testable import RivuletCore

/// Query parsing and re-encoding, ported from Go's `net/url` (`url.Values`, `ParseQuery`,
/// `Values.Encode`). The reference reads the query as a map, so `encode` writes the pairs in sorted
/// key order, which is what makes a sanitized URL reproducible.
@Suite struct QueryValuesTests {
    @Test func parseKeepsPairsAsDecodedValues() throws {
        let query = QueryValues.parse("name=John%20Doe&utm_source=newsletter")
        #expect(query.values["name"] == ["John Doe"])
        #expect(query.values["utm_source"] == ["newsletter"])
    }

    /// A plus in a query is a space when read, and comes back as a plus when written, because the
    /// writer encodes a query component with spaces as `+`.
    @Test func plusIsReadAsSpaceAndWrittenAsPlus() throws {
        let query = QueryValues.parse("a=b+c")
        #expect(query.values["a"] == ["b c"])
        #expect(query.encode() == "a=b+c")
    }

    /// A plus that was percent-escaped stays a percent-escaped plus.
    @Test func escapedPlusStaysEscapedWhenWritten() throws {
        #expect(QueryValues.parse("a=b%2Bc").encode() == "a=b%2Bc")
    }

    /// The upstream `TestRemoveTrackingParams` case that shows the writer sorts the keys: the pair
    /// that survives is written on its own, but a query with two surviving pairs comes back sorted.
    @Test func encodeWritesPairsInSortedKeyOrder() throws {
        #expect(QueryValues.parse("b=2&a=1").encode() == "a=1&b=2")
        #expect(QueryValues.parse("c=3&b=2&a=1").encode() == "a=1&b=2&c=3")
    }

    @Test func duplicateValuesAreKeptInTheirOrder() throws {
        #expect(QueryValues.parse("a=b&a=c&a=d").values["a"] == ["b", "c", "d"])
        #expect(QueryValues.parse("a=c&a=b").encode() == "a=c&a=b")
    }

    /// A token with no `=` is a key with an empty value, which is what the upstream case
    /// `Non-standard URL parameter with no tracker` relies on: `crop/1420x708/format/webp` is one
    /// key with an empty value, and its path characters are escaped when the query is re-encoded.
    @Test func tokenWithoutSeparatorIsAKeyWithAnEmptyValue() throws {
        let query = QueryValues.parse("crop/1420x708/format/webp")
        #expect(query.values["crop/1420x708/format/webp"] == [""])
        #expect(query.encode() == "crop%2F1420x708%2Fformat%2Fwebp=")
    }

    /// A malformed percent escape is skipped rather than failing the query, as `ParseQuery` does.
    @Test func malformedEscapeIsSkipped() throws {
        let query = QueryValues.parse("id=1&x=%zz")
        #expect(query.values["id"] == ["1"])
        #expect(query.values["x"] == nil)
        #expect(query.encode() == "id=1")
    }

    @Test func emptyQueryParsesToNoPairsAndEncodesToEmpty() throws {
        #expect(QueryValues.parse("").values.isEmpty)
        #expect(QueryValues.parse("").encode() == "")
    }

    /// Go reads only `&` as a pair separator and reports a semicolon inside a pair as an error,
    /// which `Query()` discards — so a pair carrying one never reaches the cleaned query.
    @Test func pairWithSemicolonIsSkipped() throws {
        #expect(QueryValues.parse("a=1;b=2").values.isEmpty)
        #expect(QueryValues.parse("a=1;b=2").encode() == "")
        #expect(QueryValues.parse("a=1&b=2;c=3").encode() == "a=1")
    }

    @Test func urlQueryIsTheParsedQueryOfItsRawQuery() throws {
        let parsed = try ParsedURL.parse("https://example.org/p?b=2&a=1")
        #expect(parsed.query().encode() == "a=1&b=2")
    }
}
