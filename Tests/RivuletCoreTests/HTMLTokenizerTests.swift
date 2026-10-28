import Foundation
import Testing
@testable import RivuletCore

/// The tokenizer rules the sanitizer renders through, pinned through its output: character
/// references, raw text, comments, attribute reading, newline normalization and NUL.
///
/// These are traced against `golang.org/x/net/html` (BSD-3-Clause) rather than ported from a
/// reference test, because the reference has no test for this area; `docs/parity.md` records where
/// the ported subset stops. Except the three cases the sanitizer output cannot show — a tag name or
/// an attribute key carrying a NUL is never in the allowlist, and the shape of the entity table is
/// not a rule the sanitizer runs through — every case is asserted through `Sanitizer.sanitize`, so
/// what is pinned is the rule as the sanitizer sees it.
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

    /// A name outside that set is only in the table with its semicolon, so the name the reader
    /// passes to `resolve` has to keep it: the reader is already past the character it stopped on.
    /// `nGt;` is one of the paired references and is not in the 106 short names.
    @Test func semicolonStaysPartOfTheNameForANameOutsideTheShortSet() {
        #expect(sanitize("<p>a&nGt;b</p>") == "<p>a\u{226B}\u{20D2}b</p>")
        #expect(sanitize("<p>a&nGt b</p>") == "<p>a&amp;nGt b</p>")
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

    /// The content of a raw text element is data, not markup: a nested tag inside it is written as
    /// text, and a `>` inside it is data too. The two raw states whose content is still written are
    /// `title` and `textarea`, so the escaped content is what can fail. For `script`, `style` and
    /// `noscript` the content is dropped with the tag, so those cannot show the rule.
    @Test(arguments: [
        ("<p>a</p><title><em>x</em></title><p>b</p>", "<p>a</p>&lt;em&gt;x&lt;/em&gt;<p>b</p>"),
        ("<p>a</p><textarea><em>x</em></textarea><p>b</p>", "<p>a</p>&lt;em&gt;x&lt;/em&gt;<p>b</p>"),
        ("<p>a</p><title>x>y</title><p>b</p>", "<p>a</p>x&gt;y<p>b</p>"),
        ("<p>a</p><textarea>x>y</textarea><p>b</p>", "<p>a</p>x&gt;y<p>b</p>"),
    ]) func rawTextElementContentIsNotMarkup(input: String, expected: String) {
        #expect(sanitize(input) == expected)
    }

    /// A `<` that does not begin a tag is text: `Next` reconsumes it into the accumulated text.
    @Test func lessThanThatDoesNotBeginATagIsText() {
        #expect(sanitize("<p>a < b</p>") == "<p>a &lt; b</p>")
    }

    /// An empty raw text element writes nothing for itself, but `Next` still reads its end tag, so
    /// the rest of the document survives.
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

    /// `TagAttr` replaces NUL in the key as well as in the value. The key cannot be seen through
    /// the sanitizer output, because a name carrying U+FFFD is not in the allowlist, so this is
    /// asserted through the tokenizer itself.
    @Test func attributeKeyNULIsReplaced() throws {
        let token = try #require(HTMLTokenizer("<ul id\u{00}=\"a\"></ul>").next())
        #expect(token.attributes.first?.name == "id\u{FFFD}")
    }

    /// `EscapeString` escapes the six characters it knows, the two numeric forms it prefers over
    /// the named ones, and the carriage return.
    @Test(arguments: [
        ("<p>a&#13;b</p>", "<p>a&#13;b</p>"),
        ("<ul id=\"a&#13;b\"></ul>", "<ul id=\"a&#13;b\"></ul>"),
        ("<pre>a\"b</pre>", "<pre>a&#34;b</pre>"),
        ("<pre>a'b</pre>", "<pre>a&#39;b</pre>"),
        ("<ul id=\"a'b\"></ul>", "<ul id=\"a&#39;b\"></ul>"),
    ]) func escapeFormsAreTheNumericOnes(input: String, expected: String) {
        #expect(sanitize(input) == expected)
    }

    /// A comment and an empty `</>` are tokens the reference keeps in the tree and the renderer
    /// skips. A `>` inside the data does not end it, and `--!>` does. A `>` that is the whole data
    /// ends it, which is the `beginning` rule.
    @Test(arguments: [
        ("<p>a<!-- <em>x</em> -->b</p>", "<p>ab</p>"),
        ("<p>a</>b</p>", "<p>ab</p>"),
        ("<p>a<!--x>y-->b</p>", "<p>ab</p>"),
        ("<p>a<!--x--!>b</p>", "<p>ab</p>"),
        ("<p>a<!>b</p>", "<p>ab</p>"),
        ("<p>a<!-->b</p>", "<p>ab</p>"),
    ]) func commentIsNotRendered(input: String, expected: String) {
        #expect(sanitize(input) == expected)
    }

    /// At the end of the input the trailing dashes are not part of the data, which is what
    /// `calculateAbruptCommentDataEnd` answers with. The renderer writes nothing for a comment, so
    /// this is asserted through the tokenizer: the data and where the next token begins.
    @Test(arguments: [
        ("<!-->b", "", "b"),
        ("<!--x--", "x", ""),
        ("<!--x--!>", "x", ""),
        ("<!--x-", "x", ""),
    ]) func commentDataEndsWhereTheReferenceEndsIt(input: String, data: String, following: String) throws {
        let tokenizer = HTMLTokenizer(input)
        let comment = try #require(tokenizer.next())
        #expect(comment.kind == .comment && comment.data == data, Comment(rawValue: input))

        // An empty `following` means the input ends inside the comment, so the reader has to answer
        // with nothing rather than with an empty token.
        if following.isEmpty {
            #expect(tokenizer.next() == nil, Comment(rawValue: input))
        } else {
            #expect(tokenizer.next()?.data == following, Comment(rawValue: input))
        }
    }

    /// `readMarkupDeclaration` is the two-dash comment only when the two bytes after `<!` are two
    /// dashes; a doctype and a processing instruction are comment tokens to the reader, and any
    /// other `<!` or `<?` is a bogus comment that closes at the first `>`. None of their data
    /// reaches the output, so what these cases pin is where the token ends.
    @Test(arguments: [
        ("<p>a<!a>b</p>", "<p>ab</p>"),
        ("<p>a<?xml?>b</p>", "<p>ab</p>"),
        ("<!DOCTYPE html><p>x</p>", "<p>x</p>"),
        ("<!doc x<p>x</p>", "x<p></p>"),
    ]) func bogusCommentAndDoctypeCloseAtTheFirstAngle(input: String, expected: String) {
        #expect(sanitize(input) == expected)
    }

    /// A solidus where the value would begin ends the tag, but a solidus after the `=` is the
    /// unquoted value, which `readTagAttrVal` reads through the default branch of its quote switch.
    /// The value is asserted through `alt`, because a URL attribute resolves an empty value to the
    /// base, which is the string the solidus resolves to as well, so `src` cannot show the rule.
    @Test func solidusAfterTheEqualsSignIsTheUnquotedValue() {
        #expect(sanitize(#"<img src="http://example.org/i.png" alt=/>"#) ==
            #"<img src="http://example.org/i.png" alt="/" loading="lazy">"#)
    }

    /// A duplicate attribute name is read once, as `readTag` keeps only the first of each name.
    @Test func duplicateAttributeNameIsKeptOnce() {
        #expect(sanitize(#"<ul id="a" id="b">x</ul>"#) == #"<ul id="a">x</ul>"#)
    }

    /// `readTagAttrVal` opens by skipping whitespace, so the whitespace between a name and `=` is
    /// consumed before the `=` is read and is not part of the name.
    @Test func whitespaceBetweenTheNameAndTheEqualsSignIsSkipped() {
        #expect(sanitize(#"<ul id ="x">y</ul>"#) == #"<ul id="x">y</ul>"#)
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

    /// The leading-newline rule reads the data as the token was read, before the NUL is removed, so
    /// a block that starts with a NUL keeps its newline.
    @Test func leadingNewlineOfAPreBlockSurvivesALeadingNUL() {
        #expect(sanitize("<pre>\u{00}\nx</pre>") == "<pre>\nx</pre>")
    }

    /// Newlines in text and in an attribute value are normalized to LF, a lone CR as well as CRLF.
    @Test(arguments: [
        ("<p>a\r\nb</p>", "<p>a\nb</p>"),
        ("<p>a\rb</p>", "<p>a\nb</p>"),
        ("<ul id=\"a\r\nb\"></ul>", "<ul id=\"a\nb\"></ul>"),
    ]) func newlineIsNormalized(input: String, expected: String) {
        #expect(sanitize(input) == expected)
    }

    /// A newline at the start of a `pre` or `listing` block is ignored when it is the first thing
    /// in it, as the insertion mode for text does. `listing` is not in the tag allowlist, so its
    /// content is what shows the rule.
    @Test(arguments: [
        ("<pre>\nx</pre>", "<pre>x</pre>"),
        ("<listing>\nx</listing>", "x"),
        ("<p>\nx</p>", "<p>\nx</p>"),
    ]) func leadingNewlineOfABlockIsIgnored(input: String, expected: String) {
        #expect(sanitize(input) == expected)
    }

    /// An end tag for `p` when no `p` is open inserts an empty one, and `</br>` is read as a start
    /// tag, both as the insertion mode for those two does.
    @Test(arguments: [
        ("x</p>", "x<p></p>"),
        ("x</br>", "x<br>"),
    ]) func endTagThatHasNoOpenElement(input: String, expected: String) {
        #expect(sanitize(input) == expected)
    }

    /// The shape `docs/parity.md` documents for the table: the semicolon forms are stored once,
    /// every short name resolves to the value its semicolon form resolves to, and the paired
    /// references are kept apart.
    @Test func entityTableShapeMatchesTheDocumentedNumbers() {
        #expect(HTMLEntityTable.namedReferences.count == 2032)
        #expect(HTMLEntityTable.namesWithoutSemicolon.count == 106)
        #expect(HTMLEntityTable.pairedReferences.count == 93)
        for name in HTMLEntityTable.namesWithoutSemicolon {
            // The value has to exist for the short name, otherwise both sides answer with nothing.
            #expect(HTMLEntityTable.resolve(name) != nil, Comment(rawValue: name))
            #expect(HTMLEntityTable.resolve(name) == HTMLEntityTable.resolve(name + ";"),
                Comment(rawValue: name))
        }
        #expect(HTMLEntityTable.resolve("copy;") == Unicode.Scalar(0x00A9))
        #expect(HTMLEntityTable.resolve("amp test") == nil)
    }
}
