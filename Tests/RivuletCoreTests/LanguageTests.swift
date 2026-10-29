import Testing
@testable import RivuletCore

/// The language tags the format adapters write. Ported from Miniflux
/// `internal/reader/language/language_test.go` (`TestNormalize`), which is ported in full.
///
/// The filter is the part that matters: the value is feed-controlled, so a tag outside the BCP-47
/// alphabet is rejected rather than stripped, and a value longer than the bound is rejected before
/// the alphabet is looked at.
@Suite struct LanguageTests {
    /// `TestNormalize`, the accepted cases.
    @Test(arguments: [
        ("", ""),
        ("   ", ""),
        ("en", "en"),
        ("EN", "en"),
        ("en_US", "en-us"),
        ("EN-us", "en-us"),
        ("pt-BR", "pt-br"),
        ("  fr-FR  ", "fr-fr"),
        ("zh-hant-cn-x-private1-private2", "zh-hant-cn-x-private1-private2"),
    ]) func normalizeKeepsTagsInTheAlphabet(input: String, expected: String) {
        #expect(Language.normalize(input) == expected)
    }

    /// `TestNormalize`, the values outside the tag alphabet, which are rejected and not stripped.
    @Test(arguments: [
        ("en US", ""),
        ("en-US, de-DE", ""),
        ("en\u{00}us", ""),
        ("en\u{202E}us", ""),
        ("français", ""),
        ("\"><script>", ""),
    ]) func normalizeRejectsValuesOutsideTheTagAlphabet(input: String, expected: String) {
        #expect(Language.normalize(input) == expected)
    }

    /// `TestNormalize`: non-ASCII is rejected even where Unicode case folding would map it to
    /// ASCII, because the fold happens in the same pass as the charset check and only the ASCII
    /// range is lower-cased here.
    @Test(arguments: [
        ("\u{212A}O", ""),
        ("\u{0130}-en", ""),
    ]) func normalizeDoesNotCaseFoldNonASCII(input: String, expected: String) {
        #expect(Language.normalize(input) == expected)
    }

    /// `TestNormalize`, the length bound. The bound is checked on the bytes, before the alphabet.
    @Test(arguments: [
        (String(repeating: "a", count: 51), ""),
        ("en-" + String(repeating: "a", count: 100), ""),
    ]) func normalizeRejectsValuesLongerThanTheBound(input: String, expected: String) {
        #expect(Language.normalize(input) == expected)
    }

    /// The bound is a bound, not a truncation: exactly 50 is accepted. A multibyte value whose
    /// byte count passes the bound is still rejected by the alphabet check.
    @Test func theBoundAcceptsExactlyItsLength() {
        #expect(Language.normalize(String(repeating: "a", count: 50)) == String(repeating: "a", count: 50))
        #expect(Language.normalize("a" + String(repeating: "é", count: 25)) == "")
    }

    /// Trimming is `strings.TrimSpace` on the same set as `unicode.IsSpace`, so a value that is
    /// only whitespace, or only whitespace inside the tag, answers empty.
    @Test(arguments: [
        ("\u{00A0}en\u{00A0}", "en"),
        ("\u{0009}en-us\u{000A}", "en-us"),
        ("\u{001C}en", ""),
    ]) func normalizeTrimsOnTheUnicodeSpaceSet(input: String, expected: String) {
        #expect(Language.normalize(input) == expected)
    }
}
