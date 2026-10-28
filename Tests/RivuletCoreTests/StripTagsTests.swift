import Foundation
import Testing
@testable import RivuletCore

/// The text layer the format adapters read through: the tags are dropped and what is written is the
/// text tokens the tokenizer reads, decoded the way `Text()` decodes them and trimmed the way Go
/// trims the result.
@Suite struct StripTagsTests {
    /// `TestStripTags`
    @Test func stripTagsRemovesTheTagsAndTrimsTheResult() {
        let input = "This <a href=\"/test.html\">link is relative</a> and <strong>this</strong> " +
            "image: <img src=\"../folder/image.png\"/>"
        #expect(StripTags.strip(input) == "This link is relative and this image:")
    }

    /// A text token is decoded, which is what `Text()` does for the states that are not raw.
    @Test(arguments: [
        ("<p>&amp;</p>", "&"),
        ("<p>&nGt;b</p>", "\u{226B}\u{20D2}b"),
    ]) func textTokenIsDecoded(input: String, expected: String) {
        #expect(StripTags.strip(input) == expected)
    }

    /// The raw states keep what is written, except `title` and `textarea`, which `Text()` decodes
    /// because the tokenizer does not flag them as raw.
    @Test(arguments: [
        ("<script>&amp;</script>", "&amp;"),
        ("<style>&amp;</style>", "&amp;"),
        ("<title>&amp;</title>", "&"),
        ("<textarea>&amp;</textarea>", "&"),
    ]) func rawTextStateKeepsItsDataExceptTitleAndTextarea(input: String, expected: String) {
        #expect(StripTags.strip(input) == expected)
    }

    /// A text token keeps its NUL: the tokenizer flags only the raw-text, comment and doctype
    /// states as converting, so the U+FFFD rule is the insertion mode's, not `Text()`'s. The
    /// insertion mode is not what this layer runs through, so a text token keeps the NUL and a raw
    /// state converts it.
    @Test(arguments: [
        ("<p>a\u{00}b</p>", "a\u{00}b"),
        ("<title>a\u{00}b</title>", "a\u{FFFD}b"),
    ]) func textTokenKeepsNULAndRawStateConvertsIt(input: String, expected: String) {
        #expect(StripTags.strip(input) == expected)
    }

    /// Newlines are normalized whatever the state, which `Text()` does before the decode, and the
    /// result is trimmed with `unicode.IsSpace`, so the leading and trailing whitespace is gone.
    @Test(arguments: [
        ("<p>a\r\nb</p>", "a\nb"),
        ("<p>a\rb</p>", "a\nb"),
        ("  hello  ", "hello"),
        ("\u{0085}hello\u{00A0}", "hello"),
    ]) func newlinesAreNormalizedAndTheResultIsTrimmed(input: String, expected: String) {
        #expect(StripTags.strip(input) == expected)
    }

    /// Non-text tokens are skipped, which is what `stripIter` does before it yields.
    @Test(arguments: [
        ("<!--comment-->text", "text"),
        ("<!doctype html>text", "text"),
        ("text<p></p>", "text"),
        ("<p>a</p>", "a"),
    ]) func onlyTextTokensAreYielded(input: String, expected: String) {
        #expect(StripTags.strip(input) == expected)
    }
}
