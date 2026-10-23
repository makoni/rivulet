import Foundation
import Testing
@testable import RivuletCore

/// Charset layer behavior that the fixture corpus does not cover: label resolution, the
/// WHATWG aliases, tolerance for invalid sequences, UTF-16 and the two XML helpers.
@Suite struct CharsetTests {
    // MARK: - Valid UTF-8 wins over the label

    @Test func validUTF8IgnoresAWrongLabel() throws {
        let data = Data("Café".utf8)
        #expect(try FeedCharset.decode(data, label: "ISO-8859-1") == data)
    }

    @Test func validUTF8IgnoresAnUnknownLabel() throws {
        let data = Data("테스트 피드".utf8)
        #expect(try FeedCharset.decode(data, label: "invalid") == data)
    }

    @Test func invalidUTF8WithAnUnknownLabelThrows() {
        let data = Data([0x43, 0x61, 0x66, 0xE9])
        #expect(throws: CharsetError.unsupportedLabel("bogus")) {
            try FeedCharset.decode(data, label: "bogus")
        }
    }

    @Test func illFormedUTF8BecomesOneReplacementCharacterPerMaximalSubpart() throws {
        // Port of the reference's `utf8Decoder` (`golang.org/x/text/encoding/unicode`), which is
        // what `charset.Lookup("utf-8")` returns: every maximal subpart of an ill-formed
        // subsequence becomes one U+FFFD, so the output is always valid UTF-8. Each case checks
        // both the replacement count and that the result is valid UTF-8, because checking only
        // the string would also pass for raw bytes read leniently.
        let cases: [(bytes: [UInt8], expected: String, note: String)] = [
            ([0xE0, 0xA4], "\u{FFFD}", "truncated sequence: one subpart"),
            ([0xC0, 0xAF], "\u{FFFD}\u{FFFD}", "overlong form: two subparts"),
            ([0xE0, 0xA4, 0x30], "\u{FFFD}0", "second byte outside the accept range"),
            ([0xED, 0xA0, 0x80], "\u{FFFD}\u{FFFD}\u{FFFD}", "surrogate form excluded"),
            ([0xE0, 0x80, 0x80], "\u{FFFD}\u{FFFD}\u{FFFD}", "overlong form excluded: only the lead"),
            ([0xF4, 0x90, 0x80, 0x80], "\u{FFFD}\u{FFFD}\u{FFFD}\u{FFFD}", "above U+10FFFF excluded"),
            ([0xF0, 0x9F, 0x93], "\u{FFFD}", "sequence cut off by the end of the document"),
            ([0xF0, 0x9F, 0x98, 0x80], "😀", "valid sequence"),
        ]
        for entry in cases {
            let decoded = try FeedCharset.decode(Data(entry.bytes), label: "utf-8")
            #expect(Fixtures.isValidUTF8(decoded), "\(entry.note)")
            #expect(Fixtures.utf8(decoded) == entry.expected, "\(entry.note)")
        }
    }

    // MARK: - Label resolution

    @Test func labelsAreMatchedCaseInsensitivelyAndTrimmed() throws {
        // Ported from `TestCharsetReaderWithKOI8RLabel` and
        // `TestCharsetReaderWithUppercaseKOI8RLabel`, which compare the whole output.
        let data = Data([0xF0, 0xD2, 0xC9, 0xD7, 0xC5, 0xD4, 0x20, 0xCD, 0xC9, 0xD2]) // "Привет мир"
        let expected = Data("Привет мир".utf8)
        #expect(try FeedCharset.decode(data, label: "koi8-r") == expected)
        #expect(try FeedCharset.decode(data, label: "  KOI8-R  ") == expected)
    }

    @Test func labelTablePinsTheWhatwgAliases() {
        #expect(CharsetEncoding.named("iso-8859-1") == .windows1252)
        #expect(CharsetEncoding.named("ascii") == .windows1252)
        #expect(CharsetEncoding.named("gb2312") == .gbk)
        #expect(CharsetEncoding.named("shift-jis") == .shiftJIS)
        #expect(CharsetEncoding.named("unicode") == .utf16le)
        #expect(CharsetEncoding.named("tis-620") == .windows874)
        #expect(CharsetEncoding.named("x-user-defined") == .xUserDefined)
        #expect(CharsetEncoding.named("hz-gb-2312") == .replacement)
        #expect(CharsetEncoding.named("cp437") == nil)
    }

    @Test func everyCanonicalEncodingResolvesToADecoderStrategy() {
        // The reference resolves every canonical name through `htmlindex.Get`, so a strategy must
        // exist for all of them; five cases (UTF-8, the two UTF-16s, x-user-defined, replacement)
        // are built in code and do not depend on the platform converter.
        for encoding in CharsetEncoding.allCases {
            #expect(encoding.decoderStrategy != nil, "no decoder strategy for \(encoding.rawValue)")
        }
    }

    // MARK: - Single-byte encodings

    @Test func iso88591LabelDecodesAsWindows1252() throws {
        // 0x92 is U+2019 in windows-1252 and a C1 control in true ISO-8859-1; the WHATWG
        // label table aliases `iso-8859-1` to windows-1252, exactly like the reference.
        let decoded = try FeedCharset.decode(Data([0x92]), label: "iso-8859-1")
        #expect(Fixtures.utf8(decoded) == "\u{2019}")
    }

    @Test func undefinedWindows1252BytesBecomeReplacementCharacters() throws {
        // Windows-1252 leaves 81, 8D, 8F, 90 and 9D undefined, so those positions become U+FFFD.
        let decoded = try FeedCharset.decode(Data([0x41, 0x81, 0x8D, 0x42]), label: "windows-1252")
        #expect(Fixtures.isValidUTF8(decoded))
        #expect(Fixtures.utf8(decoded) == "A\u{FFFD}\u{FFFD}B")
    }

    @Test func windows1251DecodesCyrillic() throws {
        let decoded = try FeedCharset.decode(Data([0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2]), label: "windows-1251")
        #expect(Fixtures.utf8(decoded) == "Привет")
    }

    // MARK: - Multi-byte encodings

    @Test func gbkAndGB2312ShareTheGBKCodec() throws {
        let bytes = Data([0xD6, 0xD0]) // "中"
        for label in ["gbk", "gb2312"] {
            #expect(Fixtures.utf8(try FeedCharset.decode(bytes, label: label)) == "中", "label \(label)")
        }
    }

    @Test func gb18030DecodesFourByteSequences() throws {
        let decoded = try FeedCharset.decode(Data([0x81, 0x30, 0x81, 0x30]), label: "gb18030")
        #expect(Fixtures.utf8(decoded) == "\u{80}")
    }

    @Test func incompleteMultibyteSequenceBecomesAReplacementCharacter() throws {
        let decoded = try FeedCharset.decode(Data([0xA4]), label: "big5")
        #expect(Fixtures.isValidUTF8(decoded))
        #expect(Fixtures.utf8(decoded) == "\u{FFFD}")
    }

    @Test func invalidMultibyteByteDoesNotLoseTheRestOfTheDocument() throws {
        // 0xFF is not a valid EUC-KR lead byte; the reference emits U+FFFD and keeps the "A".
        // Validity is what makes this test pin the decoding, because a lenient raw read of these
        // bytes produces the same string.
        let decoded = try FeedCharset.decode(Data([0xFF, 0x41]), label: "euc-kr")
        #expect(Fixtures.isValidUTF8(decoded))
        #expect(Fixtures.utf8(decoded) == "\u{FFFD}A")
    }

    @Test func eucJPIsDecoded() throws {
        // EUC-JP cannot be decoded by Foundation on Linux, so this covers the platform
        // fallback as well.
        let decoded = try FeedCharset.decode(Data([0xA4, 0xA2]), label: "euc-jp")
        #expect(Fixtures.utf8(decoded) == "あ")
    }

    @Test func shiftJISAndEUCKRDecode() throws {
        #expect(Fixtures.utf8(try FeedCharset.decode(Data([0x82, 0xA0]), label: "shift_jis")) == "あ")
        #expect(Fixtures.utf8(try FeedCharset.decode(Data([0xBE, 0xC8]), label: "euc-kr")) == "안")
    }

    // MARK: - UTF-16, user-defined and replacement

    @Test func utf16DecodingKeepsAByteOrderMark() throws {
        // The reference decodes UTF-16 with the IgnoreBOM policy, which writes a leading BOM
        // to the output instead of stripping it.
        let littleEndian = Data([0xFF, 0xFE, 0x41, 0x00, 0x2D, 0x4E])
        #expect(Fixtures.utf8(try FeedCharset.decode(littleEndian, label: "utf-16le")) == "\u{FEFF}A中")
        let bigEndian = Data([0xFE, 0xFF, 0x00, 0x41, 0x4E, 0x2D])
        #expect(Fixtures.utf8(try FeedCharset.decode(bigEndian, label: "utf-16be")) == "\u{FEFF}A中")
    }

    @Test func utf16LabelAloneMeansLittleEndian() throws {
        // [E9 00] is not valid UTF-8, so the label is honored; little-endian makes it "é"
        // where big-endian would be U+E900.
        let decoded = try FeedCharset.decode(Data([0xE9, 0x00]), label: "utf-16")
        #expect(Fixtures.utf8(decoded) == "é")
    }

    @Test func utf16OddTrailingByteBecomesAReplacementCharacter() throws {
        let decoded = try FeedCharset.decode(Data([0xE9, 0x00, 0x42]), label: "utf-16le")
        #expect(Fixtures.utf8(decoded) == "é\u{FFFD}")
    }

    @Test func utf16LoneSurrogateBecomesAReplacementCharacter() throws {
        // U+D800 without a low surrogate.
        let decoded = try FeedCharset.decode(Data([0x00, 0xD8]), label: "utf-16le")
        #expect(Fixtures.utf8(decoded) == "\u{FFFD}")
    }

    @Test func utf16SurrogatePairsDecode() throws {
        // U+1F600 as a surrogate pair, little-endian.
        let decoded = try FeedCharset.decode(Data([0x3D, 0xD8, 0x00, 0xDE]), label: "utf-16le")
        #expect(Fixtures.utf8(decoded) == "😀")
    }

    @Test func userDefinedMapsHighBytesIntoThePrivateUseArea() throws {
        let decoded = try FeedCharset.decode(Data([0x41, 0x80, 0xFF]), label: "x-user-defined")
        #expect(Fixtures.utf8(decoded) == "A\u{F780}\u{F7FF}")
    }

    @Test func replacementEncodingConsumesTheDocumentAndEmitsOneReplacementCharacter() throws {
        // Not valid UTF-8, so the label is honored. The reference's replacement decoder emits a
        // single U+FFFD at end of input and consumes the whole document, including the "A".
        let decoded = try FeedCharset.decode(Data([0xE9, 0x41]), label: "hz-gb-2312")
        #expect(Fixtures.isValidUTF8(decoded))
        #expect(Fixtures.utf8(decoded) == "\u{FFFD}")
    }

    @Test func invalidUTF8WithAUTF8ByteOrderMarkKeepsTheMarkAndReplacesTheRest() throws {
        // The byte-order-mark branch resolves to the reference's UTF-8 decoder, not to the
        // pass-through, so the mark survives as U+FEFF and the ill-formed bytes become U+FFFD.
        let data = Data([0xEF, 0xBB, 0xBF, 0xE0, 0x80, 0x80])
        let decoded = FeedCharset.decode(data, contentType: "text/html")
        #expect(Fixtures.isValidUTF8(decoded))
        #expect(Fixtures.utf8(decoded) == "\u{FEFF}\u{FFFD}\u{FFFD}\u{FFFD}")
    }

    @Test func iconvPathReplacesTheRejectedSequenceAndKeepsTheRest() throws {
        // Foundation cannot decode EUC-JP on Linux, so this pins the `iconv` path: the rejected
        // sequence becomes U+FFFD and the ASCII byte after it survives.
        let decoded = try FeedCharset.decode(Data([0xA4, 0x41]), label: "euc-jp")
        #expect(Fixtures.isValidUTF8(decoded))
        #expect(Fixtures.utf8(decoded) == "\u{FFFD}A")
    }

    // MARK: - HTML detection

    @Test func metaCharsetInsideTheDetectionWindowIsHonored() throws {
        let bytes = koi8rGreeting
        let data = html("<html><head><meta charset=\"koi8-r\"></head><body>", bytes)
        #expect(Fixtures.utf8(FeedCharset.decode(data, contentType: "text/html")).contains("Привет"))
    }

    @Test func metaCharsetFromTheHttpEquivContentAttribute() throws {
        let bytes = koi8rGreeting
        let data = html(
            "<html><head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=koi8-r\"></head>",
            bytes
        )
        #expect(Fixtures.utf8(FeedCharset.decode(data, contentType: "text/html")).contains("Привет"))
    }

    @Test func quotedContentTypeCharsetIsHonored() throws {
        let bytes = koi8rGreeting
        let data = html("<html><body>", bytes)
        let decoded = FeedCharset.decode(data, contentType: "text/html; charset=\"KOI8-R\"")
        #expect(Fixtures.utf8(decoded).contains("Привет"))
    }

    @Test func metaCharsetInsideACommentIsIgnored() throws {
        let bytes = koi8rGreeting
        let data = html("<html><!-- <meta charset=\"koi8-r\"> --><body>", bytes)
        let decoded = FeedCharset.decode(data, contentType: "text/html")
        #expect(Fixtures.isValidUTF8(decoded))
        #expect(Fixtures.utf8(decoded) == "<html><!-- <meta charset=\"koi8-r\"> --><body>ðÒÉ×ÅÔ")
    }

    @Test func unknownContentTypeCharsetFallsThroughToDetection() throws {
        // The reference's content-type step does not error on an unknown charset: `Lookup`
        // returns nil and detection continues, so the `windows-1252` default decodes the bytes
        // as mojibake instead of the KOI8-R label they would give.
        let data = html("<html><body>", koi8rGreeting)
        let decoded = FeedCharset.decode(data, contentType: "text/html; charset=bogus")
        #expect(Fixtures.utf8(decoded) == "<html><body>ðÒÉ×ÅÔ")
    }

    @Test func unknownMetaCharsetFallsBackToWindows1252() throws {
        let bytes = koi8rGreeting
        let data = html("<html><head><meta charset=\"bogus\"></head><body>", bytes)
        let decoded = FeedCharset.decode(data, contentType: "text/html")
        #expect(Fixtures.isValidUTF8(decoded))
        #expect(Fixtures.utf8(decoded) == "<html><head><meta charset=\"bogus\"></head><body>ðÒÉ×ÅÔ")
    }

    @Test func metaDeclaringUTF16PassesTheDocumentThrough() throws {
        // Port of `prescan`, which maps a `utf-16` declaration to `encoding.Nop`: the bytes are
        // returned as they are, even though they are not valid UTF-8.
        let bytes = Data([0xE0, 0xA4])
        let data = html("<html><head><meta charset=\"utf-16\"></head><body>", bytes)
        #expect(FeedCharset.decode(data, contentType: "text/html") == data)
    }

    @Test func contentTypeCharsetWinsOverTheMetaElement() throws {
        let data = html("<html><head><meta charset=\"koi8-r\"></head><body>", koi8rGreeting)
        // The bytes are not valid UTF-8, so the content-type charset is applied and the meta
        // element is never consulted: the reference's UTF-8 decoder replaces each maximal
        // subpart. If the meta element had won, these bytes would decode as KOI8-R.
        let decoded = FeedCharset.decode(data, contentType: "text/html; charset=UTF-8")
        #expect(Fixtures.isValidUTF8(decoded))
        #expect(Fixtures.utf8(decoded)
            == "<html><head><meta charset=\"koi8-r\"></head><body>"
                + String(repeating: "\u{FFFD}", count: 6))
    }

    @Test func contentTypeCharsetDecodesTheDocumentWithTheResolvedEncoding() throws {
        // Ported from `TestNewCharsetReaderWithKOI8RContentType`, which compares the whole
        // output. The bytes are not valid UTF-8, so the content-type charset is used.
        let data = Data([0xF0, 0xD2, 0xC9, 0xD7, 0xC5, 0xD4, 0x20, 0xCD, 0xC9, 0xD2]) // "Привет мир"
        #expect(FeedCharset.decode(data, contentType: "text/xml; charset=koi8-r") == Data("Привет мир".utf8))
    }

    @Test func byteOrderMarkSelectsUTF16() throws {
        let data = Data([0xFF, 0xFE, 0x41, 0x00])
        #expect(Fixtures.utf8(FeedCharset.decode(data, contentType: nil)) == "\u{FEFF}A")
    }

    @Test func validUTF8BytesPassThroughEvenWithAUTF8ByteOrderMark() throws {
        // The reference checks `utf8.Valid` before it looks at the mark, so this document is
        // returned as it is. The byte-order-mark branch itself is pinned by
        // `invalidUTF8WithAUTF8ByteOrderMarkKeepsTheMarkAndReplacesTheRest`.
        let data = Data([0xEF, 0xBB, 0xBF, 0x41])
        #expect(FeedCharset.decode(data, contentType: nil) == data)
    }

    // MARK: - XML declaration scan

    @Test func documentWithoutAnXMLDeclarationCountsAsUTF8() {
        #expect(FeedCharset.declaresUTF8XMLDeclaration(Data("<feed><title>x</title></feed>".utf8)))
    }

    @Test func utf8DeclarationIsRecognizedInAnyCaseAndQuoteStyle() {
        #expect(FeedCharset.declaresUTF8XMLDeclaration(Data("<?xml version='1.0' encoding='UTF-8'?><feed/>".utf8)))
        #expect(FeedCharset.declaresUTF8XMLDeclaration(Data("<?xml version=\"1.0\" encoding=\"Utf-8\"?><feed/>".utf8)))
    }

    @Test func onlyTheSpellingUTF8CountsAsUTF8() throws {
        // The reference compares the declared value with `utf-8` through EqualFold, so the
        // alias `utf8` is not recognized here; the document then takes the charset-reader
        // path, where its valid UTF-8 bytes still win and nothing is converted.
        #expect(!FeedCharset.declaresUTF8XMLDeclaration(Data("<?xml version=\"1.0\" encoding=\"utf8\"?><feed/>".utf8)))
        #expect(try FeedCharset.decode(Data("Café".utf8), label: "utf8") == Data("Café".utf8))
    }

    @Test func nonUTF8DeclarationsAreReported() throws {
        #expect(!FeedCharset.declaresUTF8XMLDeclaration(try Fixtures.data("encoding/iso-8859-1.xml")))
        #expect(!FeedCharset.declaresUTF8XMLDeclaration(try Fixtures.data("encoding/invalid-prolog.xml")))
        #expect(!FeedCharset.declaresUTF8XMLDeclaration(Data("<?xml version=\"1.0\" encoding=\"utf-16\"?><feed/>".utf8)))
    }

    @Test func encodingAssignmentInTheBodyIsScannedToo() {
        // The reference searches the whole document for `encoding=`, not only the prolog.
        let data = Data("<feed><title>encoding='koi8-r'</title></feed>".utf8)
        #expect(!FeedCharset.declaresUTF8XMLDeclaration(data))
    }

    // MARK: - Invalid XML character filtering

    @Test func illegalControlCharactersAreDropped() {
        // Mirrors upstream `TestXMLDocumentWithIllegalUnicodeCharacters`.
        let input = Data("Title & 中文\u{10}标题".utf8)
        #expect(Fixtures.utf8(FeedCharset.filterInvalidXMLCharacters(input)) == "Title & 中文标题")
    }

    @Test func legalWhitespaceIsKept() {
        let input = Data("A\tB\nC\rD".utf8)
        #expect(FeedCharset.filterInvalidXMLCharacters(input) == input)
    }

    @Test func delIsLegalXMLButNullIsNot() {
        let input = Data([0x41, 0x7F, 0x00, 0x42])
        #expect(Fixtures.utf8(FeedCharset.filterInvalidXMLCharacters(input)) == "A\u{7F}B")
    }

    @Test func invalidUTF8SequencesAreDropped() {
        // Mirrors upstream `TestFilterValidXMLCharsWithInvalidUTF8Sequence`: [A, C0 AF, B].
        let filtered = FeedCharset.filterInvalidXMLCharacters(Data([0x41, 0xC0, 0xAF, 0x42]))
        #expect(Fixtures.utf8(filtered) == "AB")
    }

    @Test func realReplacementCharactersAreDropped() {
        // The reference drops every U+FFFD it decodes, including one that was encoded in the
        // input; the resulting document loses them all.
        let input = Data("A\u{FFFD}B".utf8)
        #expect(Fixtures.utf8(FeedCharset.filterInvalidXMLCharacters(input)) == "AB")
    }

    // MARK: - Helpers

    /// "Привет" in KOI8-R, verified against `iconv`.
    private let koi8rGreeting = Data([0xF0, 0xD2, 0xC9, 0xD7, 0xC5, 0xD4])

    private func html(_ prefix: String, _ body: Data) -> Data {
        var data = Data(prefix.utf8)
        data.append(body)
        return data
    }
}
