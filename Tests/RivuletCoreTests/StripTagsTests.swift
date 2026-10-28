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

    /// A data-state text token keeps its NUL, because `Text()` converts only in the states the
    /// tokenizer flags as converting — the raw-text states and CDATA — and for a comment token. A
    /// raw-state text token converts it, because the flag is set there.
    @Test(arguments: [
        ("<p>a\u{00}b</p>", "a\u{00}b"),
        ("<title>a\u{00}b</title>", "a\u{FFFD}b"),
    ]) func textTokenKeepsNULAndRawStateConvertsIt(input: String, expected: String) {
        #expect(StripTags.strip(input) == expected)
    }

    /// `unicode.IsSpace` answers with the `White_Space` table Go generates from the UCD property,
    /// which is not the three sets its comment names. The table has the eight Latin-1 characters
    /// the comment lists, so they are trimmed. The two sets the comment adds give `U+200E` and
    /// `U+200F`, and the four separators `U+001C` to `U+001F` are in none of the three, so none of
    /// the six is trimmed, which is what a reading of the comment alone gets wrong.
    @Test(arguments: [
        ("a\u{001C}", "a\u{001C}"),
        ("a\u{001D}b", "a\u{001D}b"),
        ("a\u{001E}b\u{001F}", "a\u{001E}b\u{001F}"),
        ("a\u{200E}b\u{200F}", "a\u{200E}b\u{200F}"),
    ]) func theTableIsNotTheSetsTheCommentNames(input: String, expected: String) {
        #expect(StripTags.strip(input) == expected, Comment(rawValue: input))
    }

    /// The members the table does have, through the two halves the Latin-1 comment does not name:
    /// `U+2000` and `U+3000` are in the table, so the trim removes them.
    @Test(arguments: [
        ("\u{2028}a\u{3000}", "a"),
        ("\u{2000}a\u{00A0}", "a"),
    ]) func tableMembersAreTrimmed(input: String, expected: String) {
        #expect(StripTags.strip(input) == expected, Comment(rawValue: input))
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

    /// The script escaping states are not ported, and the text layer is what makes that observable,
    /// because it writes the content of a raw state: the reference reads a `</script>` inside the
    /// escape as data and ends the token at the one that closes the escaped state, so it writes
    /// `<!--<script </script>x`. The port ends the raw state at the first `</script>`, which is
    /// what this case pins. Nothing in the corpus covers it.
    @Test func rawStateEndsAtTheFirstCloseTagWithoutTheEscapingStates() {
        #expect(StripTags.strip("<script><!--<script </script>x</script>") == "<!--<script x")
    }
}
