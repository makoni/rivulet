import Foundation
import Testing
@testable import RivuletCore

/// The truncated text the format adapters write, the rule `TruncateHTML` implements: the tags are
/// dropped, every run of whitespace becomes one space, and the limit counts runes, not bytes.
///
/// A space counts toward the limit when the word that follows it is still written, but it is not
/// written when nothing printable is left in the word. The ellipsis is appended when the input has
/// more runes than the limit.
@Suite struct TruncateHTMLTests {
    /// `TestTruncateHTML`
    @Test(arguments: [
        ("text lower than limit", "This is a <strong>bug 🐛</strong>.", 50, "This is a bug 🐛."),
        ("text above limit", "This is <strong>HTML</strong>.", 4, "This…"),
        ("unicode text above limit", "This is a <strong>bike 🚲</strong>.", 4, "This…"),
        ("multiline text above limit", "\n\t\tThis is a <strong>bike\n\t\t🚲</strong>.\n\n\t", 15,
            "This is a bike…"),
        ("multiline text lower than limit", "\n\t\tThis is a <strong>bike\n 🚲</strong>.\n\n\t", 20,
            "This is a bike 🚲."),
        ("multiple spaces", "hello    world   test", 20, "hello world test"),
        ("tabs and newlines", "hello\t\tworld\n\ntest", 20, "hello world test"),
        ("truncation with unicode", "hello world 你好", 11, "hello world…"),
        ("html stripping", "<p>hello    <b>world</b>   test</p>", 20, "hello world test"),
        ("no truncation needed", "hello world", 20, "hello world"),
        ("just enough characters", "Hello", 5, "Hello"),
        ("just enough unicode characters", "Привет", 6, "Привет"),
        ("spaces around tag", "hello <br/> world", 20, "hello world"),
        ("leading spaces", "  hello world", 5, "hello…"),
        ("text above limit with space at the end", "hello world", 6, "hello…"),
        ("leading space before tag", " <a>hello</a>", 15, "hello"),
        ("space-only tokens in between tags", "hello <br/>\t<a> </a>world", 15, "hello world"),
        ("truncate mid-word", "hello world", 8, "hello wo…"),
        ("truncate mid-word with unicode", "Съешь ещё этих мягких французских булок, да выпей же чаю",
            25, "Съешь ещё этих мягких фра…"),
        ("negative limit", "whatever", -10, "…"),
        ("zero limit", "whatever", 0, "…"),
    ]) func truncateHTMLCase(name: String, input: String, limit: Int, expected: String) {
        #expect(TruncateHTML.truncate(input, limit: limit) == expected, Comment(rawValue: name))
    }

    /// `unicode.IsSpace` is the `White_Space` table Go generates from the UCD property, not the
    /// three sets its comment names, so `U+0085`, `U+00A0` and `U+2028` split a word while `U+001E`
    /// and `U+200F` do not, and the separator that is written back is the single ASCII space. The
    /// word that is not split is 11 code points, so it fits under the limit and is written as read.
    @Test(arguments: [
        ("hello\u{00A0}world", 12, "hello world"),
        ("hello\u{0085}world", 12, "hello world"),
        ("hello\u{2028}world", 12, "hello world"),
        ("hello\u{001E}world", 12, "hello\u{001E}world"),
        ("hello\u{200F}world", 12, "hello\u{200F}world"),
    ]) func theTableSplitsWordsAndTheSetsTheCommentNamesDoNot(input: String, limit: Int, expected: String) {
        #expect(TruncateHTML.truncate(input, limit: limit) == expected, Comment(rawValue: input))
    }

    /// The limit counts runes, so a character that is more than one code point is more than one
    /// against the limit. A Swift `Character` is a grapheme cluster, so the walk has to be over the
    /// scalars, not over the characters.
    @Test func limitCountsScalarsNotGraphemes() {
        #expect(TruncateHTML.truncate("e\u{0301}x", limit: 2) == "e\u{0301}…")
    }

    /// The space before a word counts toward the limit even though the ellipsis is what the count
    /// decides, so a word that would fit is cut short by the space in front of it.
    @Test func spaceCountsTowardTheLimit() {
        #expect(TruncateHTML.truncate("a bb", limit: 3) == "a b…")
    }
}
