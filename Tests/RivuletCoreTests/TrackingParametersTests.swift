import Foundation
import Testing
@testable import RivuletCore

/// Tracking-parameter removal, ported from `internal/reader/urlcleaner`
/// (`TestRemoveTrackingParams`).
///
/// The reference compares the parameter name lower-cased against the table and the `utm_`/`mtm_`
/// prefixes, and it writes the query back only when it removed something, so a URL with no tracker
/// is returned as it was read.
@Suite struct TrackingParametersTests {
    private struct Case {
        var name: String
        var input: String
        var base: String
        var feed: String
        var expected: String
    }

    private static let cases: [Case] = [
        Case(name: "URL with tracking parameters",
            input: "https://example.com/page?id=123&utm_source=newsletter&utm_medium=email&fbclid=abc123",
            base: "", feed: "", expected: "https://example.com/page?id=123"),
        Case(name: "URL with only tracking parameters",
            input: "https://example.com/page?utm_source=newsletter&utm_medium=email", base: "", feed: "",
            expected: "https://example.com/page"),
        Case(name: "URL with no tracking parameters",
            input: "https://example.com/page?id=123&foo=bar", base: "", feed: "",
            expected: "https://example.com/page?id=123&foo=bar"),
        Case(name: "URL with no parameters", input: "https://example.com/page", base: "", feed: "",
            expected: "https://example.com/page"),
        Case(name: "URL with mixed case tracking parameters",
            input: "https://example.com/page?UTM_SOURCE=newsletter&utm_MEDIUM=email", base: "", feed: "",
            expected: "https://example.com/page"),
        Case(name: "URL with tracking parameters and fragments",
            input: "https://example.com/page?id=123&utm_source=newsletter#section1", base: "", feed: "",
            expected: "https://example.com/page?id=123#section1"),
        Case(name: "URL with only tracking parameters and fragments",
            input: "https://example.com/page?utm_source=newsletter#section1", base: "", feed: "",
            expected: "https://example.com/page#section1"),
        Case(name: "URL with only one tracking parameter",
            input: "https://example.com/page?utm_source=newsletter", base: "", feed: "",
            expected: "https://example.com/page"),
        Case(name: "URL with encoded characters",
            input: "https://example.com/page?name=John%20Doe&utm_source=newsletter", base: "", feed: "",
            expected: "https://example.com/page?name=John+Doe"),
        Case(name: "ref parameter for another url", input: "https://example.com/page?ref=test.com",
            base: "https://example.com/page", feed: "", expected: "https://example.com/page?ref=test.com"),
        Case(name: "ref parameter for feed url", input: "https://example.com/page?ref=feed.com",
            base: "https://example.com/page", feed: "http://feed.com", expected: "https://example.com/page"),
        Case(name: "ref parameter for site url", input: "https://example.com/page?ref=example.com",
            base: "https://example.com/page", feed: "", expected: "https://example.com/page"),
        Case(name: "ref parameter for base url", input: "https://example.com/page?ref=example.com",
            base: "https://example.com", feed: "https://feedburned.com/example",
            expected: "https://example.com/page"),
        Case(name: "ref parameter for base url on subdomain",
            input: "https://blog.exploits.club/some-path?ref=blog.exploits.club",
            base: "https://blog.exploits.club/some-path", feed: "https://feedburned.com/exploit.club",
            expected: "https://blog.exploits.club/some-path"),
        Case(name: "Non-standard URL parameter with no tracker",
            input: "https://example.com/foo.jpg?crop/1420x708/format/webp", base: "https://example.com/page",
            feed: "", expected: "https://example.com/foo.jpg?crop/1420x708/format/webp"),
        Case(name: "Invalid URL", input: "https://example|org/", base: "https://example.com/page", feed: "",
            expected: ""),
        Case(name: "Non-HTTP URL", input: "mailto:user@example.org", base: "https://example.com/page", feed: "",
            expected: "mailto:user@example.org"),
        Case(name: "Matomo tracking URL",
            input: "https://example.com/?mtm_campaign=2020_august_promo&mtm_source=newsletter&mtm_medium=email&mtm_content=primary-cta",
            base: "https://example.com", feed: "", expected: "https://example.com/"),
    ]

    /// `TestRemoveTrackingParams`. The upstream test ignores the parse errors and passes whatever
    /// it got, so a value that does not parse reaches the cleaner as `nil`, and the cleaner answers
    /// with an error for that.
    @Test func trackingParametersAreRemovedAndTheQueryIsRewritten() throws {
        for testCase in Self.cases {
            if testCase.expected.isEmpty {
                #expect(throws: TrackingParametersError.missingURL, "expected an error for \(testCase.name)") {
                    try self.cleaned(testCase)
                }
                continue
            }
            #expect(try self.cleaned(testCase) == testCase.expected,
                "unexpected result for \(testCase.name)")
        }
    }

    /// A value that fails to parse is the nil the cleaner rejects. Upstream reaches the same case
    /// through an ignored parse error.
    @Test func unparseableInputIsRejected() {
        #expect(throws: URLParseError.invalidHost(character: "|")) { try ParsedURL.parse("https://example|org/") }
        #expect(throws: TrackingParametersError.missingURL) {
            try TrackingParameters.remove(base: try ParsedURL.parse("https://example.com/page"), feed: nil,
                input: try ParsedURL.parse("https://example.com/page"))
        }
    }

    /// When nothing is removed the URL is returned as it was read, so the pairs keep their order.
    /// The reference reaches these cases with a URL parsed from an empty string, which is not nil,
    /// so the empty host it reports is what a `ref` value is compared against.
    @Test func queryWithoutTrackersKeepsItsOrder() throws {
        let input = try ParsedURL.parse("https://example.com/page?zz=1&ab=2")
        #expect(try TrackingParameters.remove(base: ParsedURL(), feed: ParsedURL(), input: input)
            == "https://example.com/page?zz=1&ab=2")
    }

    /// When a pair is removed the query is written back in sorted key order, which is what makes
    /// the result reproducible for the same input whatever order the feed declared.
    @Test func queryThatLostAPairIsWrittenBackSorted() throws {
        let input = try ParsedURL.parse("https://example.com/page?zz=9&utm_x=1&id=123")
        #expect(try TrackingParameters.remove(base: ParsedURL(), feed: ParsedURL(), input: input)
            == "https://example.com/page?id=123&zz=9")
    }

    /// The outbound `ref` rule looks at every value of the parameter, so a duplicate list is
    /// removed as a whole when one of its values is the site host.
    @Test func outboundParameterIsRemovedWhenAnyOfItsValuesMatchesAHost() throws {
        let input = try ParsedURL.parse("https://example.com/page?ref=x&ref=example.com")
        let result = try TrackingParameters.remove(base: try ParsedURL.parse("https://example.com/page"),
            feed: try ParsedURL.parse("https://feedburned.com/example"), input: input)
        #expect(result == "https://example.com/page")
    }

    /// The upstream test ignores the parse error and passes whatever it got, so a value that does
    /// not parse reaches the cleaner as `nil`.
    private func parsed(_ value: String) -> ParsedURL? {
        try? ParsedURL.parse(value)
    }

    private func cleaned(_ testCase: Case) throws -> String {
        try TrackingParameters.remove(base: self.parsed(testCase.base), feed: self.parsed(testCase.feed),
            input: self.parsed(testCase.input))
    }
}
