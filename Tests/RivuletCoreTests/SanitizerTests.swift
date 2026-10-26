import Foundation
import Testing
@testable import RivuletCore

/// The sanitizer rules, ported from Miniflux `internal/reader/sanitizer/sanitizer.go`.
///
/// Every case names the upstream test it comes from. The reference wraps the input in `<body>`
/// before parsing, which the sanitizer does too, so a case that depends on the tree shape — the
/// implicit `p` close, a `td` outside a table, the depth limit — is a tree pin as much as a rule
/// pin.
@Suite struct SanitizerTests {
    private let options = SanitizerOptions(openLinksInNewTab: true)

    private func sanitize(_ input: String, baseURL: String = "http://example.org/") -> String {
        Sanitizer.sanitize(baseURL: baseURL, rawHTML: input, options: options)
    }

    /// `TestValidInput`
    @Test func allowedInputPassesThroughUnchanged() {
        let input =
            #"<p>This is a <strong>text</strong> with an image: <img src="http://example.org/" alt="Test" loading="lazy">.</p>"#
        #expect(sanitize(input) == input)
    }

    /// `TestImgSanitization`
    @Test(arguments: [
        (
            #"<img src="https://example.org/image.png" width="10" height="20">"#,
            #"<img src="https://example.org/image.png" width="10" height="20" loading="lazy">"#
        ),
        (
            #"<img src="https://example.org/image.png" width="10px" height="20px">"#,
            #"<img src="https://example.org/image.png" loading="lazy">"#
        ),
        (
            #"<img src="https://example.org/image.png" width="10px" height="20">"#,
            #"<img src="https://example.org/image.png" height="20" loading="lazy">"#
        ),
        (
            #"<img src="https://example.org/image.png" width="" height="">"#,
            #"<img src="https://example.org/image.png" loading="lazy">"#
        ),
        (
            #"<img src="https://example.org/image.png" width="10" height="20px">"#,
            #"<img src="https://example.org/image.png" width="10" loading="lazy">"#
        ),
        (
            #"<img src="https://example.org/image.png" width="-10" height="20">"#,
            #"<img src="https://example.org/image.png" height="20" loading="lazy">"#
        ),
        (
            #"<img src="https://example.org/image.png" width="10" height="-20">"#,
            #"<img src="https://example.org/image.png" width="10" loading="lazy">"#
        ),
        (
            #"<img src="data:text/plain;base64,SGVsbG8sIFdvcmxkIQ==" alt="Example">"#,
            ""
        ),
        (
            #"<img src="data:image/gif;base64,test" alt="Example">"#,
            #"<img src="data:image/gif;base64,test" alt="Example" loading="lazy">"#
        ),
        (
            #"<img srcset="example-320w.jpg, example-480w.jpg 1.5x,   example-640w.jpg 2x, example-640w.jpg 640w" src="example-640w.jpg" alt="Example">"#,
            #"<img srcset="http://example.org/example-320w.jpg, http://example.org/example-480w.jpg 1.5x, http://example.org/example-640w.jpg 2x, http://example.org/example-640w.jpg 640w" src="http://example.org/example-640w.jpg" alt="Example" loading="lazy">"#
        ),
        (
            #"<img srcset="example-320w.jpg, example-480w.jpg 1.5x,   example-640w.jpg 2x, example-640w.jpg 640w" alt="Example">"#,
            #"<img srcset="http://example.org/example-320w.jpg, http://example.org/example-480w.jpg 1.5x, http://example.org/example-640w.jpg 2x, http://example.org/example-640w.jpg 640w" alt="Example" loading="lazy">"#
        ),
        (
            #"<img srcset="https://stats.wordpress.com/tracker.png 1x, /example-640w.jpg 2x" src="/example-640w.jpg" alt="Example">"#,
            #"<img srcset="http://example.org/example-640w.jpg 2x" src="http://example.org/example-640w.jpg" alt="Example" loading="lazy">"#
        ),
        (
            #"<img srcset="javascript:alert(1) 1x, data:text/plain;base64,SGVsbG8= 2x" alt="Example">"#,
            ""
        ),
        (
            #"<img src="https://example.org/image.png" fetchpriority="high">"#,
            #"<img src="https://example.org/image.png" fetchpriority="high" loading="lazy">"#
        ),
        (
            #"<img src="https://example.org/image.png" fetchpriority="low">"#,
            #"<img src="https://example.org/image.png" fetchpriority="low" loading="lazy">"#
        ),
        (
            #"<img src="https://example.org/image.png" fetchpriority="auto">"#,
            #"<img src="https://example.org/image.png" fetchpriority="auto" loading="lazy">"#
        ),
        (
            #"<img src="https://example.org/image.png" fetchpriority="invalid">"#,
            #"<img src="https://example.org/image.png" loading="lazy">"#
        ),
        (
            #"<img src="https://example.org/image.png" decoding="sync">"#,
            #"<img src="https://example.org/image.png" decoding="sync" loading="lazy">"#
        ),
        (
            #"<img src="https://example.org/image.png" decoding="async">"#,
            #"<img src="https://example.org/image.png" decoding="async" loading="lazy">"#
        ),
        (
            #"<img src="https://example.org/image.png" decoding="auto">"#,
            #"<img src="https://example.org/image.png" decoding="auto" loading="lazy">"#
        ),
        (
            #"<img src="https://example.org/image.png" decoding="invalid">"#,
            #"<img src="https://example.org/image.png" loading="lazy">"#
        ),
    ]) func imgRule(input: String, expected: String) {
        #expect(sanitize(input) == expected)
    }

    /// `TestNonImgWithFetchPriorityAttribute` and `TestNonImgWithDecodingAttribute`: the two
    /// validators belong to `img`, so the attribute is dropped on any other tag.
    @Test func mediaValidatorsDoNotApplyToOtherTags() {
        #expect(sanitize(#"<p fetchpriority="high">Text</p>"#) == "<p>Text</p>")
        #expect(sanitize(#"<p decoding="async">Text</p>"#) == "<p>Text</p>")
    }

    /// `TestMediumImgWithSrcset`
    @Test func mediumImgKeepsItsAttributesInInputOrder() {
        let input = #"<img alt="Image for post" class="t u v ef aj" src="https://miro.medium.com/max/5460/1*aJ9JibWDqO81qMfNtqgqrw.jpeg" srcset="https://miro.medium.com/max/552/1*aJ9JibWDqO81qMfNtqgqrw.jpeg 276w, https://miro.medium.com/max/1000/1*aJ9JibWDqO81qMfNtqgqrw.jpeg 500w" sizes="500px" width="2730" height="3407">"#
        let expected = #"<img alt="Image for post" src="https://miro.medium.com/max/5460/1*aJ9JibWDqO81qMfNtqgqrw.jpeg" srcset="https://miro.medium.com/max/552/1*aJ9JibWDqO81qMfNtqgqrw.jpeg 276w, https://miro.medium.com/max/1000/1*aJ9JibWDqO81qMfNtqgqrw.jpeg 500w" sizes="500px" width="2730" height="3407" loading="lazy">"#
        #expect(sanitize(input) == expected)
    }

    /// `TestSelfClosingTags`
    @Test(arguments: [
        ("<p>Line<br>Break</p>", "<p>Line<br>Break</p>"),
        ("<p>Before</p><hr><p>After</p>", "<p>Before</p><hr><p>After</p>"),
        (
            #"<p>Image <img src="http://example.org/image.png" alt="Test"></p>"#,
            #"<p>Image <img src="http://example.org/image.png" alt="Test" loading="lazy"></p>"#
        ),
        (
            #"<picture><source src="http://example.org/video.mp4" type="video/mp4"></picture>"#,
            #"<picture><source src="http://example.org/video.mp4" type="video/mp4"></picture>"#
        ),
        ("<p>soft<wbr>break</p>", "<p>soft<wbr>break</p>"),
    ]) func selfClosingTag(input: String, expected: String) {
        #expect(sanitize(input) == expected)
    }

    /// `TestTable`
    @Test func tableKeepsItsRows() {
        let input =
            #"<table><tr><th>A</th><th colspan="2">B</th></tr><tr><td>C</td><td>D</td><td>E</td></tr></table>"#
        #expect(sanitize(input) == input)
    }

    /// `TestSourceSanitization`
    @Test(arguments: [
        (
            #"<picture><source media="(min-width: 800px)" srcset="elva-800w.jpg"></picture>"#,
            #"<picture><source media="(min-width: 800px)" srcset="http://example.org/elva-800w.jpg"></picture>"#
        ),
        (
            #"<picture><source src="video.mp4" type="video/mp4"></picture>"#,
            #"<picture><source src="http://example.org/video.mp4" type="video/mp4"></picture>"#
        ),
        (
            #"<picture><source srcset="https://stats.wordpress.com/tracker.png 1x, /elva-800w.jpg 2x"></picture>"#,
            #"<picture><source srcset="http://example.org/elva-800w.jpg 2x"></picture>"#
        ),
        (
            #"<picture><source srcset="javascript:alert(1) 1x, data:text/plain;base64,SGVsbG8= 2x"></picture>"#,
            "<picture></picture>"
        ),
    ]) func sourceRule(input: String, expected: String) {
        #expect(sanitize(input) == expected)
    }

    /// `TestVideoTag`
    @Test func videoGetsControls() {
        let input =
            #"<p>My valid <video src="videofile.webm" autoplay poster="posterimage.jpg">fallback</video>.</p>"#
        let expected =
            #"<p>My valid <video src="http://example.org/videofile.webm" poster="http://example.org/posterimage.jpg" controls>fallback</video>.</p>"#
        #expect(sanitize(input) == expected)
    }

    /// `TestAudioAndSourceTag`
    @Test func audioGetsControlsAndItsSourceIsResolved() {
        let input =
            #"<p>My music <audio controls="controls"><source src="foo.wav" type="audio/wav"></audio>.</p>"#
        let expected =
            #"<p>My music <audio controls><source src="http://example.org/foo.wav" type="audio/wav"></audio>.</p>"#
        #expect(sanitize(input) == expected)
    }

    /// `TestInvalidTag`, `TestUnknownTag` and `TestInvalidNestedTag`: a tag that is not allowed is
    /// not written, but its content still is.
    @Test(arguments: [
        ("<p>My invalid <z>tag</z>.</p>", "<p>My invalid tag.</p>"),
        ("<p>My invalid <unknown>tag</unknown>.</p>", "<p>My invalid tag.</p>"),
        (
            "<p>My invalid <z>tag with some <em>valid</em> tag</z>.</p>",
            "<p>My invalid tag with some <em>valid</em> tag.</p>"
        ),
    ]) func disallowedTagKeepsItsContent(input: String, expected: String) {
        #expect(sanitize(input) == expected)
    }

    /// `TestEspaceAttributes`: a `td` outside a table is not an element, so the escaped attribute
    /// value never reaches the output.
    @Test func tableCellOutsideATableIsNotAnElement() {
        #expect(sanitize(#"<td rowspan="<b>injection</b>">text</td>"#) == "text")
    }

    /// `TestXmlEntities`
    @Test func textIsDecodedThenReEscaped() {
        #expect(sanitize("<pre>echo \"test\" &gt; /etc/hosts</pre>") ==
            "<pre>echo &#34;test&#34; &gt; /etc/hosts</pre>")
    }

    /// `TestMathML` and `TestInvalidMathMLXMLNamespace`
    @Test(arguments: [
        (
            #"<math xmlns="http://www.w3.org/1998/Math/MathML"><msup><mi>x</mi><mn>2</mn></msup></math>"#,
            #"<math xmlns="http://www.w3.org/1998/Math/MathML"><msup><mi>x</mi><mn>2</mn></msup></math>"#
        ),
        (
            #"<math xmlns="http://example.org"><msup><mi>x</mi><mn>2</mn></msup></math>"#,
            #"<math xmlns="http://www.w3.org/1998/Math/MathML"><msup><mi>x</mi><mn>2</mn></msup></math>"#
        ),
    ]) func mathMLNamespaceIsAlwaysTheCanonicalOne(input: String, expected: String) {
        #expect(sanitize(input) == expected)
    }

    /// `TestBlockedResourcesSubstrings`
    @Test(arguments: [
        #"<p>Before paragraph.</p><img src="http://stats.wordpress.com/something.php" alt="Blocked Resource"><p>After paragraph.</p>"#,
        #"<p>Before paragraph.</p><img src="http://twitter.com/share?text=This+is+google+a+search+engine&url=https%3A%2F%2Fwww.google.com" alt="Blocked Resource"><p>After paragraph.</p>"#,
        #"<p>Before paragraph.</p><img src="http://www.facebook.com/sharer.php?u=https%3A%2F%2Fwww.google.com%[title]=This+Is%2C+Google+a+search+engine" alt="Blocked Resource"><p>After paragraph.</p>"#,
    ]) func blockedResourceDropsTheElementButNotTheParagraph(input: String) {
        #expect(sanitize(input) == "<p>Before paragraph.</p><p>After paragraph.</p>")
    }

    /// `TestAttrLowerCase`
    @Test(arguments: [
        (
            #"<a HrEF="http://example.com" HIddEN>test</a>"#,
            ""
        ),
        (
            #"<a HrEF="http://example.com">test</a>"#,
            #"<a href="http://example.com" rel="noopener noreferrer" referrerpolicy="no-referrer" target="_blank">test</a>"#
        ),
    ]) func attributeNameIsLowercasedBeforeItIsChecked(input: String, expected: String) {
        #expect(sanitize(input, baseURL: "http://example.org/") == expected)
    }

    /// `TestHiddenParagraph`
    @Test func hiddenElementIsNotRendered() {
        let input = #"<p>Before paragraph.</p><p hidden>This should <em>not</em> appear in the <strong>output</strong></p><p>After paragraph.</p>"#
        #expect(sanitize(input) == "<p>Before paragraph.</p><p>After paragraph.</p>")
    }

    /// `TestAttributesAreStripped`
    @Test func strippedAttributesAndTheImplicitParagraphClose() {
        let input = #"<p style="color: red;">Some text.<hr style="color: blue"/>Test.</p>"#
        #expect(sanitize(input) == "<p>Some text.</p><hr>Test.<p></p>")
    }

    /// `TestReplaceScript`, `TestReplaceStyle` and `TestReplaceNoscript`
    @Test(arguments: [
        (
            #"<p>Before paragraph.</p><script type="text/javascript">alert("1");</script><p>After paragraph.</p>"#,
            "<p>Before paragraph.</p><p>After paragraph.</p>"
        ),
        (
            "<p>Before paragraph.</p><style>body { background-color: #ff0000; }</style><p>After paragraph.</p>",
            "<p>Before paragraph.</p><p>After paragraph.</p>"
        ),
        (
            #"<p>Before paragraph.</p><noscript>Inside <code>noscript</code> tag with an image: <img src="http://example.org/" alt="Test" loading="lazy"></noscript><p>After paragraph.</p>"#,
            "<p>Before paragraph.</p><p>After paragraph.</p>"
        ),
    ]) func blockedTagDropsItsContent(input: String, expected: String) {
        #expect(sanitize(input) == expected)
    }

    /// `Test1x1PixelTracker` and `Test0x0PixelTracker`
    @Test(arguments: [
        (
            #"<p><img src="https://tracker1.example.org/" height="1" width="1"> and <img src="https://tracker2.example.org/" height="1" width="1"/></p>"#,
            "<p> and </p>"
        ),
        (
            #"<p><img src="https://tracker1.example.org/" height="0" width="0"> and <img src="https://tracker2.example.org/" height="0" width="0"/></p>"#,
            "<p> and </p>"
        ),
    ]) func pixelTrackerIsIgnored(input: String, expected: String) {
        #expect(sanitize(input) == expected)
    }

    /// `TestDeeplyNestedpage`: the reference refuses nesting deeper than 512 open elements, which
    /// is what the two cases below pin. `<html>` and `<body>` count in the stack.
    @Test func nestingAboveTheDepthLimitFailsTheParse() {
        var input = "test"
        for _ in 0..<(512 - 2) { input = "<div>" + input + "</div>" }
        #expect(sanitize(input) == "test")

        input = "test"
        for _ in 0..<(512 - 1) { input = "<div>" + input + "</div>" }
        #expect(sanitize(input) == "")
    }

    /// `inBodyIM` reads `</html>` as `</body>` and reprocesses it, and the body stays open, so
    /// content after it is still part of the body. Traced against `parse.go`.
    @Test func endTagForHtmlDoesNotEndTheParse() {
        #expect(sanitize("<p>a</p></html><p>b</p>") == "<p>a</p><p>b</p>")
    }

    /// `inTableBodyIM` pops the open `tbody` (or `thead`/`tfoot`) before it reprocesses the start
    /// tag that follows, which is why a section or a caption is not ignored. Traced against
    /// `parse.go`.
    @Test(arguments: [
        (
            "<table><tbody><thead><tr><th>H</th></tr></thead></table>",
            "<table><thead><tr><th>H</th></tr></thead></table>"
        ),
        (
            "<table><tbody><caption>C</caption></table>",
            "<table><caption>C</caption></table>"
        ),
    ]) func tableBodyIsPoppedByTheNextSectionStartTag(input: String, expected: String) {
        #expect(sanitize(input) == expected)
    }
}
