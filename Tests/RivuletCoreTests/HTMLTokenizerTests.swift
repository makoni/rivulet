import Foundation
import Testing
@testable import RivuletCore

/// The tokenizer rules the sanitizer renders through, pinned through its output: character
/// references, raw text, comments, attribute reading, newline normalization and NUL.
///
/// These are traced against `golang.org/x/net/html` (BSD-3-Clause) rather than ported from a
/// reference test, because the reference has no test for this area; `docs/parity.md` records where
/// the ported subset stops. Except the tag-name case, which the sanitizer output cannot show
/// because such a name is never in the allowlist, every case is asserted through
/// `Sanitizer.sanitize`, so what is pinned is the rule as the sanitizer sees it.
@Suite struct HTMLTokenizerTests {
    private let options = SanitizerOptions(openLinksInNewTab: true)
    private let baseURL = "http://example.org/"

    private func sanitize(_ input: String) -> String {
        Sanitizer.sanitize(baseURL: baseURL, rawHTML: input, options: options)
    }

    /// A named reference is decoded in text without its semicolon, which is the set the HTML5 table
    /// lists without one.
    @Test func namedReferenceInTextDoesNotNeedTheSemicolon() {
        #expect(sanitize("<p>&amp test</p>") == "<p>&amp; test</p>")
        #expect(sanitize("<pre>x&copy=y</pre>") == "<pre>x©=y</pre>")
    }

    /// In an attribute value a named reference without the semicolon is left as it is when the
    /// character after it is `=`, which is the rule `unescape` applies only in the attribute mode.
    @Test func namedReferenceInAnAttributeValueIsLeftBeforeAnEqualsSign() {
        let kept = #"<img src="http://example.org/i.png" title="x&copy=y">"#
        #expect(sanitize(kept) ==
            #"<img src="http://example.org/i.png" title="x&amp;copy=y" loading="lazy">"#)

        // The same reference is decoded when the next character is not `=`.
        let decoded = #"<img src="http://example.org/i.png" title="x&copy z">"#
        #expect(sanitize(decoded) == #"<img src="http://example.org/i.png" title="x© z" loading="lazy">"#)
    }

    /// The content of a raw text element is data, not markup, so a nested tag inside `script` is
    /// not a node the sanitizer can render.
    @Test func rawTextElementContentIsNotMarkup() {
        #expect(sanitize("<p>a</p><script><em>x</em></script><p>b</p>") == "<p>a</p><p>b</p>")
    }

    /// A `<` that does not begin a tag is text: `Next` reconsumes it into the accumulated text.
    @Test func lessThanThatDoesNotBeginATagIsText() {
        #expect(sanitize("<p>a < b</p>") == "<p>a &lt; b</p>")
    }

    /// An empty raw text element emits no text token, but `Next` still reads its end tag, so the
    /// rest of the document is not lost.
    @Test(arguments: ["script", "style", "title"]) func emptyRawTextElementKeepsReading(element: String) {
        #expect(sanitize("<p>a</p><\(element)></\(element)><p>b</p>") == "<p>a</p><p>b</p>")
    }

    /// `readRawEndTag` accepts `/` before `>`, so `</script/>` ends the raw text.
    @Test func rawTextEndTagWithASolidusEndsTheRawText() {
        #expect(sanitize("<p>a</p><script></script/><p>b</p>") == "<p>a</p><p>b</p>")
    }

    /// `TagName` replaces NUL with U+FFFD, as `TagAttr` does for a key and a value.
    @Test func tagNameNULIsReplaced() throws {
        let token = try #require(HTMLTokenizer("<di\u{00}v>").next())
        #expect(token.name == "di\u{FFFD}v")
    }

    /// `EscapeString` escapes a carriage return as `&#13;`, after a character reference has
    /// decoded it.
    @Test(arguments: [
        ("<p>a&#13;b</p>", "<p>a&#13;b</p>"),
        ("<ul id=\"a&#13;b\"></ul>", "<ul id=\"a&#13;b\"></ul>"),
    ]) func carriageReturnIsEscaped(input: String, expected: String) {
        #expect(sanitize(input) == expected)
    }

    /// A comment and an empty `</>` are tokens the reference keeps in the tree and the renderer
    /// skips. A `>` inside the data does not end it, and `--!>` does.
    @Test(arguments: [
        ("<p>a<!-- <em>x</em> -->b</p>", "<p>ab</p>"),
        ("<p>a</>b</p>", "<p>ab</p>"),
        ("<p>a<!--x>y-->b</p>", "<p>ab</p>"),
        ("<p>a<!--x--!>b</p>", "<p>ab</p>"),
        ("<p>a<!>b</p>", "<p>ab</p>"),
    ]) func commentIsNotRendered(input: String, expected: String) {
        #expect(sanitize(input) == expected)
    }

    /// A duplicate attribute name is read once, as `readTag` keeps only the first of each name.
    @Test func duplicateAttributeNameIsKeptOnce() {
        #expect(sanitize(#"<ul id="a" id="b">x</ul>"#) == #"<ul id="a">x</ul>"#)
    }

    /// The tag name is lower-cased before the allowlist is checked.
    @Test func tagNameIsLowerCased() {
        #expect(sanitize("<P>x</P>") == "<p>x</p>")
    }

    /// NUL is removed from a text token by the insertion mode, while the tokenizer replaces it with
    /// U+FFFD in the states it flags as converting (raw text, comment, doctype) and in an attribute
    /// key or value, which `TagAttr` does whatever the state. `TagName` replaces it too, so a name
    /// carrying a NUL is not in the allowlist.
    @Test(arguments: [
        ("<p>a\u{00}b</p>", "<p>ab</p>"),
        ("<img src=\"http://example.org/i.png\" title=\"a\u{00}b\">",
            "<img src=\"http://example.org/i.png\" title=\"a\u{FFFD}b\" loading=\"lazy\">"),
    ]) func nulInTextAndInAnAttributeValue(input: String, expected: String) {
        #expect(sanitize(input) == expected)
    }

    /// Newlines in text and in an attribute value are normalized to LF.
    @Test(arguments: [
        ("<p>a\r\nb</p>", "<p>a\nb</p>"),
        ("<ul id=\"a\r\nb\"></ul>", "<ul id=\"a\nb\"></ul>"),
    ]) func newlineIsNormalized(input: String, expected: String) {
        #expect(sanitize(input) == expected)
    }

    /// A newline at the start of a `pre` block is ignored when it is the first thing in it, as the
    /// insertion mode for text does.
    @Test func leadingNewlineOfAPreBlockIsIgnored() {
        #expect(sanitize("<pre>\nx</pre>") == "<pre>x</pre>")
        #expect(sanitize("<p>\nx</p>") == "<p>\nx</p>")
    }

    /// An end tag for `p` when no `p` is open inserts an empty one, and `</br>` is read as a start
    /// tag, both as the insertion mode for those two does.
    @Test(arguments: [
        ("x</p>", "x<p></p>"),
        ("x</br>", "x<br>"),
    ]) func endTagThatHasNoOpenElement(input: String, expected: String) {
        #expect(sanitize(input) == expected)
    }
}
