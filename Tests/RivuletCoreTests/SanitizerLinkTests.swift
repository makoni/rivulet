import Foundation
import Testing
@testable import RivuletCore

/// The link rules of the sanitizer, ported from Miniflux
/// `internal/reader/sanitizer/sanitizer_test.go`: resolution against the base URL, the URI-scheme
/// allowlist, the tracking-parameter cleaner and the attributes written for an anchor.
///
/// The scheme table itself is pinned by `URISchemeAllowlistTests`; what this suite pins is that the
/// sanitizer keeps an allowed scheme and drops a disallowed one, and that the attributes it writes
/// come after the ones it kept from the input, in the reference's order.
@Suite struct SanitizerLinkTests {
    private let options = SanitizerOptions(openLinksInNewTab: true)

    private func sanitize(_ input: String, baseURL: String = "http://example.org/") -> String {
        Sanitizer.sanitize(baseURL: baseURL, rawHTML: input, options: options)
    }

    /// `TestRelativeURL`
    @Test func relativeHrefAndSrcAreResolvedAgainstTheBaseURL() {
        let input =
            #"<p>This <a href="/test.html">link is relative</a> and this image: <img src="../folder/image.png"></p>"#
        let expected =
            #"<p>This <a href="http://example.org/test.html" rel="noopener noreferrer" referrerpolicy="no-referrer" target="_blank">link is relative</a> and this image: <img src="http://example.org/folder/image.png" loading="lazy"></p>"#
        #expect(sanitize(input) == expected)
    }

    /// `TestProtocolRelativeURL`: an authority marker takes `https:` whatever the base scheme is.
    @Test func protocolRelativeHrefTakesHTTPS() {
        let input = #"<p>This <a href="//static.example.org/index.html">link is relative</a>.</p>"#
        let expected =
            #"<p>This <a href="https://static.example.org/index.html" rel="noopener noreferrer" referrerpolicy="no-referrer" target="_blank">link is relative</a>.</p>"#
        #expect(sanitize(input) == expected)
    }

    /// `TestLinkWithTarget` and `TestLinkWithNoTarget`
    @Test(arguments: [
        (
            true,
            #"<p>This link is <a href="http://example.org/index.html">an anchor</a></p>"#,
            #"<p>This link is <a href="http://example.org/index.html" rel="noopener noreferrer" referrerpolicy="no-referrer" target="_blank">an anchor</a></p>"#
        ),
        (
            false,
            #"<p>This link is <a href="http://example.org/index.html">an anchor</a></p>"#,
            #"<p>This link is <a href="http://example.org/index.html" rel="noopener noreferrer" referrerpolicy="no-referrer">an anchor</a></p>"#
        ),
    ]) func anchorAttributesFollowTheOption(openLinksInNewTab: Bool, input: String, expected: String) {
        #expect(
            Sanitizer.sanitize(baseURL: "http://example.org/", rawHTML: input,
                options: SanitizerOptions(openLinksInNewTab: openLinksInNewTab)) == expected
        )
    }

    /// `TestAnchorLink`: an in-document anchor is kept as it was read, and the anchor attributes
    /// the reference writes for a resolved link are not written for it.
    @Test func inDocumentAnchorIsKeptWithoutTheAnchorAttributes() {
        let input = "<p>This link is <a href=\"#some-anchor\">an anchor</a></p>"
        #expect(sanitize(input) == input)
    }

    /// `TestInvalidURLScheme`
    @Test func disallowedSchemeDropsTheLinkButNotTheText() {
        #expect(sanitize(#"<p>This link is <a src="file:///etc/passwd">not valid</a></p>"#) ==
            "<p>This link is not valid</p>")
    }

    /// `TestURISchemes`
    @Test(arguments: [
        ("apt", "apt:some-package?channel=test"),
        ("bitcoin", "bitcoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W"),
        ("callto", "callto:12345679"),
        ("feed-double-slash", "feed://example.com/rss.xml"),
        ("feed-https", "feed:https://example.com/rss.xml"),
        ("geo", "geo:13.4125,103.8667"),
        ("itms", "itms://itunes.com/apps/my-app-name"),
        ("itms-apps", "itms-apps://itunes.com/apps/my-app-name"),
        ("magnet", "magnet:?xt.1=urn:sha1:YNCKHTQCWBTRNJIV4WNAE52SJUQCZO5C&amp;xt.2=urn:sha1:TXGCZQTH26NL6OUQAJJPFALHG2LTGBC7"),
        ("mailto", "mailto:jsmith@example.com?subject=A%20Test&amp;body=My%20idea%20is%3A%20%0A"),
        ("news-double-slash", "news://news.server.example/*"),
        ("news-single-colon", "news:example.group.this"),
        ("nntp", "nntp://news.server.example/example.group.this"),
        ("rtmp", "rtmp://mycompany.com/vod/mp4:mycoolvideo.mov"),
        ("sip", "sip:+1-212-555-1212:1234@gateway.com;user=phone"),
        ("sips", "sips:alice@atlanta.com?subject=project%20x&amp;priority=urgent"),
        ("skype", "skype:echo123?call"),
        ("spotify", "spotify:track:2jCnn1QPQ3E8ExtLe6INsx"),
        ("steam", "steam://settings/account"),
        ("svn", "svn://example.org"),
        ("svn-ssh", "svn+ssh://example.org"),
        ("tel", "tel:+1-201-555-0123"),
        ("webcal", "webcal://example.com/calendar.ics"),
        ("xmpp", "xmpp:user@host?subscribe&amp;type=subscribed"),
    ]) func allowedSchemeIsKeptAsItWasRead(name: String, href: String) {
        let input = "<p>This link is <a href=\"" + href + "\">valid</a></p>"
        let expected = "<p>This link is <a href=\"" + href +
            "\" rel=\"noopener noreferrer\" referrerpolicy=\"no-referrer\" target=\"_blank\">valid</a></p>"
        #expect(sanitize(input) == expected, Comment(rawValue: name))
    }

    /// `TestBlacklistedLink`
    @Test func blacklistedResourceDropsTheElement() {
        #expect(sanitize(#"<p>This image is not valid <img src="https://stats.wordpress.com/some-tracker"></p>"#) ==
            "<p>This image is not valid </p>")
    }

    /// `TestLinkWithTrackers` and `TestImageSrcWithTrackers`: the cleaner runs on the resolved
    /// value only when it has a query to clean.
    @Test(arguments: [
        (
            #"<p>This link has trackers <a href="https://example.com/page?utm_source=newsletter">Test</a></p>"#,
            #"<p>This link has trackers <a href="https://example.com/page" rel="noopener noreferrer" referrerpolicy="no-referrer" target="_blank">Test</a></p>"#
        ),
        (
            #"<p>This image has trackers <img src="https://example.org/?id=123&utm_source=newsletter&utm_medium=email&fbclid=abc123"></p>"#,
            #"<p>This image has trackers <img src="https://example.org/?id=123" loading="lazy"></p>"#
        ),
    ]) func trackingParametersAreRemovedFromTheResolvedValue(input: String, expected: String) {
        #expect(sanitize(input) == expected)
    }
}
