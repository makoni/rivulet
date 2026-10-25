import Foundation
import Testing
@testable import RivuletCore

/// The URL rules the reader answers with, ported from `internal/urllib`. A value that does not
/// parse is answered with as it was read, which is why the cases below that contain a character the
/// host class rejects return the input rather than a host.
@Suite struct URLRulesTests {
    /// `TestIsRelativePath`
    @Test func relativePathClassification() {
        let relative: Set<String> = ["path/to/file.ext", "./path/to/file.ext", "../path/to/file.ext",
            "file.ext", "./file.ext", "../file.ext", "/absolute/path", "path?query=value", "path#fragment",
            "path?query#fragment"]
        let notRelative: Set<String> = ["https://example.org/file.ext", "http://example.org/file.ext",
            "//example.org/file.ext", "//example.org", "/\\example.org", "\\example.org",
            "path\\to\\file.ext", "ftp://example.org/file.ext", "mailto:user@example.org",
            "magnet:?xt=urn:btih:example", "",
            "magnet:?xt.1=urn:sha1:YNCKHTQCWBTRNJIV4WNAE52SJUQCZO5C"]

        for input in relative {
            #expect(URLRules.isRelativePath(input), "\(input) should be a relative path")
        }
        for input in notRelative {
            #expect(!URLRules.isRelativePath(input), "\(input) should not be a relative path")
        }
    }

    /// A backslash is rejected before parsing, because a browser would read `/\evil.com` as an open
    /// redirect while Go reads it as an ordinary path character.
    @Test func backslashIsRejectedBeforeParsing() {
        #expect(!URLRules.isRelativePath("/a\\b"))
    }

    /// `TestIsAbsoluteURL`
    @Test func absoluteURLClassification() {
        let absolute: Set<String> = ["https://example.org/file.pdf",
            "https://example.org/file.pdf?download=1#page=2"]
        let notAbsolute: Set<String> = ["mailto:user@example.org", "data:text/plain,hello",
            "magnet:?xt.1=urn:sha1:YNCKHTQCWBTRNJIV4WNAE52SJUQCZO5C&xt.2=urn:sha1:TXGCZQTH26NL6OUQAJJPFALHG2LTGBC7",
            "invalid url", "/relative/path", "//example.org/path", " https://example.org/path",
            "\thttps://example.org/path"]

        for input in absolute {
            #expect(URLRules.isAbsoluteURL(input), "\(input) should be an absolute URL")
        }
        for input in notAbsolute {
            #expect(!URLRules.isAbsoluteURL(input), "\(input) should not be an absolute URL")
        }
    }

    /// The `http` or `https` prefix is checked on the value as it was read, before parsing, so a
    /// value that starts with whitespace is not absolute even though Go would trim it when parsing.
    @Test func prefixIsCheckedOnTheValueAsRead() {
        #expect(!URLRules.isAbsoluteURL(" https://example.org/path"))
    }

    /// `TestRootURL`
    @Test func rootKeepsSchemeAndHostOnly() {
        let cases: [(String, String)] = [
            ("", ""),
            ("https://example.org/path/file.ext", "https://example.org/"),
            ("https://example.org/path/file.ext?test=abc", "https://example.org/"),
            ("//static.example.org/path/file.ext", "https://static.example.org/"),
            ("https://example|org/path/file.ext", "https://example|org/path/file.ext"),
            ("/relative/path", "/relative/path"),
            ("http://example.org:8080/path", "http://example.org:8080/"),
        ]
        for (input, expected) in cases {
            #expect(URLRules.rootURL(input) == expected, "unexpected root for \(input)")
        }
    }

    /// `TestIsHTTPS`
    @Test func httpsClassification() {
        #expect(URLRules.isHTTPS("https://example.org/"))
        #expect(!URLRules.isHTTPS("http://example.org/"))
        #expect(!URLRules.isHTTPS("https://example|org/"))
    }

    /// `TestDomain`
    @Test func domainIsTheHostAsRead() {
        #expect(URLRules.domain("https://static.example.org/") == "static.example.org")
        #expect(URLRules.domain("https://example|org/") == "https://example|org/")
    }

    /// `TestDomainWithoutWWW`
    @Test func domainWithoutWWWRemovesOnlyTheLeadingPrefix() {
        let cases: [(String, String)] = [
            ("https://www.example.org/", "example.org"),
            ("https://example.org/", "example.org"),
            ("https://www.sub.example.org/", "sub.example.org"),
            ("https://example|org/", "https://example|org/"),
        ]
        for (input, expected) in cases {
            #expect(URLRules.domainWithoutWWW(input) == expected, "unexpected domain for \(input)")
        }
    }

    @Test func hostNameIsTheHostWithoutItsPort() throws {
        #expect(try ParsedURL.parse("https://example.org:8080/").hostName == "example.org")
        #expect(try ParsedURL.parse("http://[::1]:1055/p").host == "[::1]:1055")
        // Go's `Hostname` reports a bracketed host without its brackets.
        #expect(try ParsedURL.parse("http://[::1]:1055/p").hostName == "::1")
    }
}
