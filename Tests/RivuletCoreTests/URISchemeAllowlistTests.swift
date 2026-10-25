import Foundation
import Testing
@testable import RivuletCore

/// The URI-scheme allowlist for URLs in sanitized feed content, ported from the reference's
/// `HasValidURIScheme` (`internal/reader/sanitizer/url.go`). The scheme is the part before the
/// first colon, and the comparison is case-insensitive per RFC 3986 §3.1.
@Suite struct URISchemeAllowlistTests {
    /// `TestHasValidURIScheme`
    @Test func allowedAndRejectedSchemes() {
        let allowed: Set<String> = [
            "http://example.org/article",
            "https://example.org/article",
            "mailto:author@example.org",
            "magnet:?xt=urn:btih:abc",
            "tel:+15551234567",
            "ftp://example.org/file",
            "feed:https://example.org/",
            "webcal://example.org/cal",
            // Case-insensitive matching.
            "HTTPS://example.org",
            "MailTo:author@host",
            "SVN+SSH://example.org",
        ]
        let rejected: Set<String> = [
            // Schemes that enable script execution or local resource access.
            "javascript:alert(1)",
            "data:text/html,<script>alert(1)</script>",
            "vbscript:msgbox(1)",
            "file:///etc/passwd",
            // Missing or malformed scheme.
            "",
            "example.org",
            "/relative/path",
            "//evil.example.org/path",
            // Case-insensitive match still rejects these.
            "JavaScript:alert(1)",
            "VBScript:msgbox(1)",
        ]

        for input in allowed {
            #expect(URISchemeAllowlist.hasValidScheme(input), "\(input) should be allowed")
        }
        for input in rejected {
            #expect(!URISchemeAllowlist.hasValidScheme(input), "\(input) should be rejected")
        }
    }

    /// The allowlist is the reference's, so a scheme it lists is accepted even when the value is
    /// not an HTTP URL, and a scheme it does not list is rejected even when the value is well
    /// formed.
    @Test func schemesOutsideTheCommonOnesAreInTableOrderNotByShape() {
        #expect(URISchemeAllowlist.hasValidScheme("ssh://example.org/p"))
        #expect(URISchemeAllowlist.hasValidScheme("opener:x"))
        #expect(URISchemeAllowlist.hasValidScheme("hack:x"))
        #expect(!URISchemeAllowlist.hasValidScheme("blob:https://example.org/x"))
        #expect(!URISchemeAllowlist.hasValidScheme("httpx://example.org/p"))
    }

    /// The empty scheme in front of a colon is rejected, as the reference checks it before the
    /// table.
    @Test func emptySchemeBeforeAColonIsRejected() {
        #expect(!URISchemeAllowlist.hasValidScheme(":x"))
    }
}
