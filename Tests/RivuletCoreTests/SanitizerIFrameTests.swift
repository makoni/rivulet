import Foundation
import Testing
@testable import RivuletCore

/// The iframe rules of the sanitizer, ported from Miniflux
/// `internal/reader/sanitizer/sanitizer_test.go`: the domain allowlist, the two rewrites the
/// reference applies to an allowed source, and the attributes written for an allowed iframe.
///
/// The domain is compared against the option after the `www.` prefix is removed from both sides,
/// and the option itself is the domain of the embed URL override, which is what the two custom-URL
/// cases pin.
@Suite struct SanitizerIFrameTests {
    private let options = SanitizerOptions(openLinksInNewTab: true)
    private let baseURL = "http://example.com/"

    private func sanitize(_ input: String) -> String {
        Sanitizer.sanitize(baseURL: baseURL, rawHTML: input, options: options)
    }

    /// `TestInvalidIFrame`, `TestBlockedIFrameWithChildElements` and `TestSameDomainIFrame`: a
    /// source outside the allowlist drops the element, and a blocked iframe does not render its
    /// content.
    @Test(arguments: [
        (
            #"<iframe src="http://example.org/"></iframe>"#,
            ""
        ),
        (
            #"<iframe src="http://example.org/"><p>test</p></iframe>"#,
            ""
        ),
        (
            #"<iframe src="http://example.com/test"></iframe>"#,
            ""
        ),
    ]) func iframeOutsideTheAllowlistIsDroppedWithItsContent(input: String, expected: String) {
        #expect(sanitize(input) == expected)
    }

    /// `TestIFrameAllowList`
    @Test(arguments: [
        "bandcamp.com", "cdn.embedly.com", "dailymotion.com", "framatube.org", "open.spotify.com",
        "player.bilibili.com", "player.twitch.tv", "player.vimeo.com", "soundcloud.com", "vk.com",
        "w.soundcloud.com", "youtube-nocookie.com", "youtube.com",
    ]) func allowedDomainKeepsTheIframe(domain: String) throws {
        let input = "<iframe src=\"https://" + domain + "/video/test\"></iframe>"
        let output = sanitize(input)
        #expect(output.contains("<iframe"), "iframe from \(domain) should be allowed, got \(output)")
    }

    /// `TestIFrameWithChildElements`: an iframe is not allowed to have child nodes.
    @Test func allowedIframeKeepsItsAttributesAndTheSandbox() {
        let input = #"<iframe src="https://www.youtube.com/"><p>test</p></iframe>"#
        let expected = #"<iframe src="https://www.youtube.com/" sandbox="allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox" loading="lazy" referrerpolicy="strict-origin-when-cross-origin"></iframe>"#
        #expect(sanitize(input) == expected)
    }

    /// `TestIFrameWithReferrerPolicy`: the attribute itself is not in the allowlist, so what
    /// reaches the output is the one the reference writes for a YouTube embed.
    @Test func referrerpolicyOfAnInputAttributeIsNotKeptButTheEmbedWritesIt() {
        let input = #"<iframe src="https://www.youtube.com/embed/test123" referrerpolicy="strict-origin-when-cross-origin"></iframe>"#
        let expected = #"<iframe src="https://www.youtube-nocookie.com/embed/test123" sandbox="allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox" loading="lazy" referrerpolicy="strict-origin-when-cross-origin"></iframe>"#
        #expect(sanitize(input) == expected)
    }

    /// `TestInvidiousIFrame`: the instance option puts the source domain through the allowlist.
    @Test func invidiousInstanceIsAllowedThroughTheOption() {
        let input = #"<iframe src="https://yewtu.be/watch?v=video_id"></iframe>"#
        let expected = #"<iframe src="https://yewtu.be/watch?v=video_id" sandbox="allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox" loading="lazy"></iframe>"#
        #expect(
            Sanitizer.sanitize(baseURL: baseURL, rawHTML: input,
                options: SanitizerOptions(openLinksInNewTab: true, invidiousInstance: "yewtu.be")) == expected
        )
    }

    /// `TestCustomYoutubeEmbedURL`: the override domain is compared after the `www.` prefix.
    @Test func customEmbedURLAllowsItsOwnDomain() {
        let input = #"<iframe src="https://www.invidious.custom/embed/1234"></iframe>"#
        let expected = #"<iframe src="https://www.invidious.custom/embed/1234" sandbox="allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox" loading="lazy"></iframe>"#
        let custom = SanitizerOptions(
            openLinksInNewTab: true,
            youTubeEmbedURLPrefix: "https://www.invidious.custom/embed/"
        )
        #expect(Sanitizer.sanitize(baseURL: baseURL, rawHTML: input, options: custom) == expected)
    }

    /// `TestReplaceYoutubeURL`
    @Test func youtubeEmbedIsRewrittenToTheOverride() {
        let input = #"<iframe src="http://www.youtube.com/embed/test123?version=3&#038;rel=1&#038;fs=1&#038;autohide=2&#038;showsearch=0&#038;showinfo=1&#038;iv_load_policy=1&#038;wmode=transparent"></iframe>"#
        let expected = #"<iframe src="https://www.youtube-nocookie.com/embed/test123?version=3&amp;rel=1&amp;fs=1&amp;autohide=2&amp;showsearch=0&amp;showinfo=1&amp;iv_load_policy=1&amp;wmode=transparent" sandbox="allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox" loading="lazy" referrerpolicy="strict-origin-when-cross-origin"></iframe>"#
        #expect(sanitize(input) == expected)
    }

    /// `TestReplaceSecureYoutubeURL`, `TestReplaceSecureYoutubeURLWithParameters` and
    /// `TestReplaceYoutubeURLAlreadyReplaced`
    @Test(arguments: [
        (
            #"<iframe src="https://www.youtube.com/embed/test123"></iframe>"#,
            #"<iframe src="https://www.youtube-nocookie.com/embed/test123" sandbox="allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox" loading="lazy" referrerpolicy="strict-origin-when-cross-origin"></iframe>"#
        ),
        (
            #"<iframe src="https://www.youtube.com/embed/test123?rel=0&amp;controls=0"></iframe>"#,
            #"<iframe src="https://www.youtube-nocookie.com/embed/test123?rel=0&amp;controls=0" sandbox="allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox" loading="lazy" referrerpolicy="strict-origin-when-cross-origin"></iframe>"#
        ),
        (
            #"<iframe src="https://www.youtube-nocookie.com/embed/test123?rel=0&amp;controls=0" sandbox="allow-scripts allow-same-origin"></iframe>"#,
            #"<iframe src="https://www.youtube-nocookie.com/embed/test123?rel=0&amp;controls=0" sandbox="allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox" loading="lazy" referrerpolicy="strict-origin-when-cross-origin"></iframe>"#
        ),
    ]) func youtubeEmbedRewrite(input: String, expected: String) {
        #expect(sanitize(input) == expected)
    }

    /// `TestReplaceProtocolRelativeYoutubeURL`
    @Test func protocolRelativeYoutubeSourceIsRewritten() {
        let input = #"<iframe src="//www.youtube.com/embed/Bf2W84jrGqs" width="560" height="314" allowfullscreen="allowfullscreen"></iframe>"#
        let expected = #"<iframe src="https://www.youtube-nocookie.com/embed/Bf2W84jrGqs" width="560" height="314" allowfullscreen="allowfullscreen" sandbox="allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox" loading="lazy" referrerpolicy="strict-origin-when-cross-origin"></iframe>"#
        #expect(sanitize(input) == expected)
    }

    /// `TestReplaceYoutubeURLWithCustomURL`
    @Test func youtubeEmbedRewriteUsesTheCustomOverride() {
        let input = #"<iframe src="https://www.youtube.com/embed/test123?version=3&#038;rel=1&#038;fs=1&#038;autohide=2&#038;showsearch=0&#038;showinfo=1&#038;iv_load_policy=1&#038;wmode=transparent"></iframe>"#
        let expected = #"<iframe src="https://invidious.custom/embed/test123?version=3&amp;rel=1&amp;fs=1&amp;autohide=2&amp;showsearch=0&amp;showinfo=1&amp;iv_load_policy=1&amp;wmode=transparent" sandbox="allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox" loading="lazy" referrerpolicy="strict-origin-when-cross-origin"></iframe>"#
        let custom = SanitizerOptions(
            openLinksInNewTab: true,
            youTubeEmbedURLPrefix: "https://invidious.custom/embed/"
        )
        #expect(Sanitizer.sanitize(baseURL: baseURL, rawHTML: input, options: custom) == expected)
    }

    /// Traced against `sanitizer.go`: `dnt=1` is appended only for the `/video/` path, so a Vimeo
    /// source outside that path is written as it was read.
    @Test func vimeoDoNotTrackIsWrittenOnlyForTheVideoPath() {
        let input = #"<iframe src="https://player.vimeo.com/user/12345"></iframe>"#
        let expected = #"<iframe src="https://player.vimeo.com/user/12345" sandbox="allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox" loading="lazy"></iframe>"#
        #expect(sanitize(input) == expected)
    }

    /// `TestVimeoIframeRewriteWithQueryString` and `TestVimeoIframeRewriteWithoutQueryString`
    @Test(arguments: [
        (
            #"<iframe src="https://player.vimeo.com/video/123456?title=0&amp;byline=0"></iframe>"#,
            #"<iframe src="https://player.vimeo.com/video/123456?title=0&amp;byline=0&amp;dnt=1" sandbox="allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox" loading="lazy"></iframe>"#
        ),
        (
            #"<iframe src="https://player.vimeo.com/video/123456"></iframe>"#,
            #"<iframe src="https://player.vimeo.com/video/123456?dnt=1" sandbox="allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox" loading="lazy"></iframe>"#
        ),
    ]) func vimeoPlayerGetsTheDoNotTrackParameter(input: String, expected: String) {
        #expect(sanitize(input) == expected)
    }
}
