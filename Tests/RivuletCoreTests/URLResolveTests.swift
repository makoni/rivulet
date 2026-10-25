import Foundation
import Testing
@testable import RivuletCore

/// Relative URL resolution against a base URL, ported from `internal/urllib`. The cases are the
/// upstream `TestAbsoluteURL` corpus (`internal/urllib/url_test.go`), run through both reference
/// paths the upstream test runs them through: parsing the base each time, and passing a base that
/// is already parsed.
@Suite struct URLResolveTests {
    private struct Scenario {
        var name: String
        var base: String
        var relative: String
        var expected: String
        var wantsError: Bool
        var runsWithParsedBase: Bool
        var passesNilParsedBase: Bool
    }

    private static let scenarios: [Scenario] = [
        Scenario(name: "absolute path", base: "https://example.org/folder/", relative: "/path/file.ext",
            expected: "https://example.org/path/file.ext", wantsError: false, runsWithParsedBase: true,
            passesNilParsedBase: false),
        Scenario(name: "relative path", base: "https://example.org/folder/", relative: "path/file.ext",
            expected: "https://example.org/folder/path/file.ext", wantsError: false, runsWithParsedBase: true,
            passesNilParsedBase: false),
        Scenario(name: "dot path root", base: "https://example.org/path", relative: "./",
            expected: "https://example.org/", wantsError: false, runsWithParsedBase: true,
            passesNilParsedBase: false),
        Scenario(name: "dot path folder", base: "https://example.org/folder/", relative: "./",
            expected: "https://example.org/folder/", wantsError: false, runsWithParsedBase: true,
            passesNilParsedBase: false),
        Scenario(name: "missing slash in base", base: "https://example.org/folder", relative: "path/file.ext",
            expected: "https://example.org/path/file.ext", wantsError: false, runsWithParsedBase: true,
            passesNilParsedBase: false),
        Scenario(name: "already absolute", base: "https://example.org/folder/",
            relative: "https://example.org/path/file.ext", expected: "https://example.org/path/file.ext",
            wantsError: false, runsWithParsedBase: true, passesNilParsedBase: false),
        Scenario(name: "protocol relative", base: "https://www.example.org/",
            relative: "//static.example.org/path/file.ext", expected: "https://static.example.org/path/file.ext",
            wantsError: false, runsWithParsedBase: true, passesNilParsedBase: false),
        Scenario(name: "magnet keeps scheme", base: "https://www.example.org/",
            relative: "magnet:?xt=urn:btih:c12fe1c06bba254a9dc9f519b335aa7c1367a88a",
            expected: "magnet:?xt=urn:btih:c12fe1c06bba254a9dc9f519b335aa7c1367a88a", wantsError: false,
            runsWithParsedBase: true, passesNilParsedBase: false),
        Scenario(name: "magnet with query", base: "https://www.example.org/",
            relative: "magnet:?xt.1=urn:sha1:YNCKHTQCWBTRNJIV4WNAE52SJUQCZO5C&xt.2=urn:sha1:TXGCZQTH26NL6OUQAJJPFALHG2LTGBC7",
            expected: "magnet:?xt.1=urn:sha1:YNCKHTQCWBTRNJIV4WNAE52SJUQCZO5C&xt.2=urn:sha1:TXGCZQTH26NL6OUQAJJPFALHG2LTGBC7",
            wantsError: false, runsWithParsedBase: true, passesNilParsedBase: false),
        Scenario(name: "empty relative returns base", base: "https://example.org/folder/", relative: "",
            expected: "https://example.org/folder/", wantsError: false, runsWithParsedBase: true,
            passesNilParsedBase: false),
        Scenario(name: "invalid base errors", base: "://bad", relative: "path/file.ext", expected: "",
            wantsError: true, runsWithParsedBase: false, passesNilParsedBase: false),
        Scenario(name: "absolute ignores invalid base", base: "://bad",
            relative: "https://example.org/path/file.ext", expected: "https://example.org/path/file.ext",
            wantsError: false, runsWithParsedBase: true, passesNilParsedBase: true),
    ]

    /// `TestAbsoluteURL`
    @Test func relativeValuesResolveAgainstTheBase() throws {
        for scenario in Self.scenarios {
            if scenario.wantsError {
                #expect(throws: URLParseError.self, "expected an error for \(scenario.name)") {
                    try URLResolution.resolveToAbsolute(base: scenario.base, relative: scenario.relative)
                }
                continue
            }

            #expect(try URLResolution.resolveToAbsolute(base: scenario.base, relative: scenario.relative)
                == scenario.expected, "unexpected result for \(scenario.name)")

            guard scenario.runsWithParsedBase else { continue }
            var parsedBase: ParsedURL?
            if !scenario.passesNilParsedBase { parsedBase = try ParsedURL.parse(scenario.base) }
            #expect(try URLResolution.resolveToAbsolute(parsedBase: parsedBase, relative: scenario.relative)
                == scenario.expected, "unexpected parsed-base result for \(scenario.name)")
        }
    }

    // MARK: - Pins traced against Go's `net/url`

    /// The reference forces `https:` for a value that begins with the authority marker, whatever
    /// the base scheme is: an `http` base still answers with `https`.
    @Test func authorityMarkerTakesHttpsWhateverTheBaseSchemeIs() throws {
        #expect(try URLResolution.resolveToAbsolute(base: "http://example.org/", relative: "//host/p")
            == "https://host/p")
    }

    /// A value that already has an `http` or `https` prefix is returned as it was read, before any
    /// parsing of the base, which is why an invalid base does not stop it.
    @Test func httpPrefixedRelativeValueIsReturnedAsRead() throws {
        #expect(try URLResolution.resolveToAbsolute(base: "://bad", relative: "http://example.org/p")
            == "http://example.org/p")
    }

    /// A reference that resolves to an absolute URL is returned as it was read, before the base is
    /// used: a scheme that is not `http` or `https` still counts as absolute.
    @Test func schemeCarryingReferenceIsReturnedAsReadBeforeTheBaseIsUsed() throws {
        #expect(try URLResolution.resolveToAbsolute(base: "https://example.org/", relative: "mailto:a@b")
            == "mailto:a@b")
    }

    /// A relative reference that carries no path still has its path cleaned, because Go's
    /// `ResolveReference` joins through `resolvePath`.
    @Test func pathlessRelativeReferenceKeepsTheCleanedBasePath() throws {
        let base = try ParsedURL.parse("https://example.org/a/./b/")
        #expect(try URLResolution.resolveToAbsolute(parsedBase: base, relative: "")
            == "https://example.org/a/b/")
    }
}
