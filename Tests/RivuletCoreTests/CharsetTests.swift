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
        // subsequence becomes one U+FFFD, so the output is always valid UTF-8.
        #expect(Fixtures.utf8(try FeedCharset.decode(Data([0xE0, 0xA4]), label: "utf-8")) == "\u{FFFD}")
        #expect(Fixtures.utf8(try FeedCharset.decode(Data([0xC0, 0xAF]), label: "utf-8")) == "\u{FFFD}\u{FFFD}")
        #expect(Fixtures.utf8(try FeedCharset.decode(Data([0xE0, 0xA4, 0x30]), label: "utf-8")) == "\u{FFFD}0")
        #expect(Fixtures.utf8(try FeedCharset.decode(Data([0xED, 0xA0, 0x80]), label: "utf-8"))
            == "\u{FFFD}\u{FFFD}\u{FFFD}")
        #expect(Fixtures.utf8(try FeedCharset.decode(Data([0xE0, 0x80, 0x80]), label: "utf-8"))
            == "\u{FFFD}\u{FFFD}\u{FFFD}")   // overlong form excluded: only the lead is a subpart
        #expect(Fixtures.utf8(try FeedCharset.decode(Data([0xF4, 0x90, 0x80, 0x80]), label: "utf-8"))
            == "\u{FFFD}\u{FFFD}\u{FFFD}\u{FFFD}")   // above U+10FFFF excluded
        #expect(Fixtures.utf8(try FeedCharset.decode(Data([0xF0, 0x9F, 0x93]), label: "utf-8")) == "\u{FFFD}")
        #expect(Fixtures.utf8(try FeedCharset.decode(Data([0xF0, 0x9F, 0x98, 0x80]), label: "utf-8")) == "😀")
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

    @Test func everyCanonicalEncodingHasAPlatformConverter() {
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
        let decoded = try FeedCharset.decode(Data([0x41, 0x81, 0x8D, 0x42]), label: "windows-1252")
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
        #expect(Fixtures.utf8(decoded) == "\u{FFFD}")
    }

    @Test func invalidMultibyteByteDoesNotLoseTheRestOfTheDocument() throws {
        // 0xFF is not a valid EUC-KR lead byte; the reference emits U+FFFD and keeps the "A".
        let decoded = try FeedCharset.decode(Data([0xFF, 0x41]), label: "euc-kr")
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

    @Test func replacementEncodingProducesOneReplacementCharacter() throws {
        // 0xE9 alone is not valid UTF-8, so the label is honored; the reference's replacement
        // decoder emits a single U+FFFD and discards the rest of the document.
        let decoded = try FeedCharset.decode(Data([0xE9]), label: "hz-gb-2312")
        #expect(Fixtures.utf8(decoded) == "\u{FFFD}")
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
        #expect(!Fixtures.utf8(decoded).contains("Привет"))
    }

    @Test func unknownMetaCharsetFallsBackToWindows1252() throws {
        let bytes = koi8rGreeting
        let data = html("<html><head><meta charset=\"bogus\"></head><body>", bytes)
        let decoded = FeedCharset.decode(data, contentType: "text/html")
        #expect(!Fixtures.utf8(decoded).contains("Привет"))
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

    @Test func utf8ByteOrderMarkPassesThrough() throws {
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
