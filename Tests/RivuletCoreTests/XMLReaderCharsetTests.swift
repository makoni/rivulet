import Foundation
import Testing
@testable import RivuletCore
/// The charset path the reader takes before tokenizing. Ported from Miniflux
/// `internal/reader/xml/decoder.go`. The tests here pin the path decision and the label lookup, and
/// the deviations from the reference are recorded in `docs/parity.md`. The ported fixture tests of
/// the same upstream file, which name the upstream assertion they mirror, are in
/// `XMLReaderTests.swift`.
///
/// The path is decided by the first `encoding=` of the whole document, as `hasUTF8XMLDeclaration`
/// does, while the label itself is resolved by `procInst`, which is applied to an instruction token
/// whose target is `xml`. The two lookups are not the same, and a document can pass through one
/// without the other.
@Suite struct XMLReaderCharsetTests {
    /// A Latin-1 document, so a byte above 0x7F is not a valid UTF-8 sequence and the label is
    /// honored instead of the bytes winning.
    private func latin1(_ text: String) -> Data {
        Data(text.unicodeScalars.map { UInt8($0.value & 0xFF) })
    }
    @Test func readerRejectsAnUnresolvableLabelForNonUTF8Bytes() {
        // The reference resolves the label only when it is the one `procInst` reads from an
        // instruction token, and this document is not valid UTF-8, so `charset.NewReaderLabel`
        // fails.
        let data = latin1("<?xml version=\"1.0\" encoding=\"bogus\"?><note><to>\u{93}</to></note>")
        #expect(throws: XMLError.charset(CharsetError.unsupportedLabel("bogus"))) {
            try XMLReader.read(data)
        }
    }
    @Test func labelFromBodyTextDecidesThePathButIsNeverResolved() throws {
        // `procInst` is applied to an instruction token, so text that writes `encoding=` decides
        // which branch the reference takes but is never resolved: the reference fails such a
        // document, while Rivulet removes the illegal bytes.
        let data = latin1("text with encoding=\"bogus\" inside <note><to>a\u{93}b</to></note>")
        #expect(try XMLReader.read(data).child(local: "to")?.text == "ab")
    }
    @Test func labelOfAnInstructionReadAfterTextConvertsTheDocument() throws {
        // The instruction token is read wherever it is, so text before it does not stop the
        // conversion.
        let data = latin1("junk <?xml encoding=\"iso-8859-1\"?><note><to>a\u{E0}b</to></note>")
        #expect(try XMLReader.read(data).child(local: "to")?.text == "a\u{E0}b")
    }
    @Test func labelOfTheFirstInstructionWithTheTargetXMLIsUsed() throws {
        // An instruction with another target comes first, so `procInst` is applied to the second
        // one.
        let data = latin1("<?pi x?><?xml encoding=\"iso-8859-1\"?><note><to>a\u{E0}b</to></note>")
        #expect(try XMLReader.read(data).child(local: "to")?.text == "a\u{E0}b")
    }
    @Test func instructionStartInsideMarkupCountsHereAlthoughTheReferenceReadsItAsText() throws {
        // The label scan reads `<?` occurrences in the bytes, so the `<?` inside this comment is
        // taken as an instruction start. The reference only reaches `procInst` at a token boundary,
        // so it resolves nothing here, and its invalid-UTF-8 check fails later, on the byte inside
        // `<to>`. Recorded in `docs/parity.md`.
        let data = latin1("<!-- <?xml encoding=\"iso-8859-1\"?> --><note><to>a\u{E0}b</to></note>")
        #expect(try XMLReader.read(data).child(local: "to")?.text == "a\u{E0}b")
    }
    @Test func theWholeDocumentIsConvertedRatherThanThePartAfterTheInstruction() throws {
        // `switchToReader` converts from the instruction on, so the bytes read before it stay as
        // they are and the reference fails on them. Rivulet resolves the label once for the whole
        // document, so the same bytes decode. Recorded in `docs/parity.md`.
        let data = latin1("<note><to>a\u{E0}b</to><?xml encoding=\"iso-8859-1\"?></note>")
        #expect(try XMLReader.read(data).child(local: "to")?.text == "a\u{E0}b")
    }
}
