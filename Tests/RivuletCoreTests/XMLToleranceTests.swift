import Foundation
import Testing
@testable import RivuletCore

/// The tolerance decision table for the XML quirks the plan names: the byte-order mark, garbage
/// before the prolog, character references, and `<![CDATA[`, with the two configuration choices
/// that decide them — `Strict = false` with no `AutoClose`, and `Entity = xml.HTMLEntity`.
///
/// The values are the reference's own, from running Miniflux v2.3.3 with the decoder that package
/// builds (`internal/reader/xml/decoder.go`: `Strict = false`, `Entity = xml.HTMLEntity`, no
/// `AutoClose`). Each row of the table in `docs/reference-notes.md` is pinned here, and every pin
/// compares the token stream the reference reports, so it can fail on the rule it names: a reader
/// that stripped the mark, resolved the larger HTML table, or applied `AutoClose` would report a
/// different stream. What a pin cannot pin is recorded with the table.
@Suite struct XMLToleranceTests {
    private let bom = "\u{FEFF}"
    private let prolog = "<?xml version=\"1.0\"?>"

    /// The tokens in the order the reference reports them, read through the path `decoder.go`
    /// builds, which is what makes a declared label matter.
    ///
    /// The stream ends where the reference's stream ends, and the end is not a token: the reference
    /// reports `io.EOF` there, while this port reports the same failure as ``XMLError``
    /// `unexpectedEOF` for a clean end and for an end reached inside an element alike. So the pins
    /// compare the tokens only, and the failures they name are the ones a stream can end with.
    private func stream(_ input: String) throws -> [String] {
        var values: [String] = []
        let tokenizer = XMLTokenizer(try XMLReader.prepared(Data(input.utf8)))
        while true {
            let token: XMLToken?
            do {
                token = try tokenizer.nextToken()
            } catch let failure as XMLError {
                if failure == .unexpectedEOF { return values }
                return values + ["error:\(name(of: failure))"]
            } catch {
                return values + ["error:other"]
            }
            guard let token else { return values }
            switch token {
            case .startElement(let name, _): values.append("start \(name.namespace):\(name.local)")
            case .endElement(let name): values.append("end \(name.namespace):\(name.local)")
            case .characterData(let value, let isCDATA):
                values.append("\(isCDATA ? "cdata" : "text") \(value)")
            case .processingInstruction(let target, let content):
                values.append("procinst \(target) \(content)")
            case .comment(let content): values.append("comment \(content)")
            case .directive(let content): values.append("directive \(content)")
            }
        }
    }

    private func name(of failure: XMLError) -> String {
        switch failure {
        case .unexpectedEOF: return "unexpectedEOF"
        case .invalidXMLName: return "invalidXMLName"
        case .unexpectedEndElement: return "unexpectedEndElement"
        case .invalidEndTag: return "invalidEndTag"
        case .elementNameExpected: return "elementNameExpected"
        case .attributeNameExpected: return "attributeNameExpected"
        case .processingInstructionTargetExpected: return "processingInstructionTargetExpected"
        case .unsupportedXMLVersion: return "unsupportedXMLVersion"
        case .malformedComment: return "malformedComment"
        case .malformedCDATA: return "malformedCDATA"
        case .unescapedBracketInText: return "unescapedBracketInText"
        case .unescapedAngleInAttributeValue: return "unescapedAngleInAttributeValue"
        case .selfClosingTagNotClosed: return "selfClosingTagNotClosed"
        case .endTagNamespaceMismatch: return "endTagNamespaceMismatch"
        case .illegalCharacterCode: return "illegalCharacterCode"
        case .charset: return "charset"
        }
    }

    // MARK: - The byte-order mark

    @Test func leadingBOMIsTextThatNothingStripsOnThisPath() throws {
         // The reference has no byte-order mark rule on the `Token()` path: the bytes of the mark
         // are
        // a run of text before the first element. A reader that skipped a mark, the way an HTML
        // tokenizer or a UTF-16 decoder does, would report no run here.
        let want = ["text \(bom)", "start :note", "text x", "end :note"]
        #expect(try stream("\(bom)<note>x</note>") == want)
    }

    @Test func leadingBOMAfterThePrologIsStillText() throws {
        // The mark is not part of the prolog, so the instruction and the run are two tokens.
        let want = ["procinst xml version=\"1.0\"", "text \(bom)",
            "start :note", "text x", "end :note"]
        #expect(try stream("\(prolog)\(bom)<note>x</note>") == want)
    }

    @Test func bomInsideTextIsKept() throws {
        let want = ["start :note", "text \(bom)x", "end :note"]
        #expect(try stream("<note>\(bom)x</note>") == want)
    }

    @Test func bomAndGarbageBeforeThePrologAreOneRunOfText() throws {
        // The mark is not a boundary: the garbage and the mark are one run, because nothing before
        // the prolog is markup. A reader that skipped the pre-prolog text would report no run.
        let want = ["text \(bom)junk ", "procinst xml version=\"1.0\"",
            "start :note", "text x", "end :note"]
        #expect(try stream("\(bom)junk \(prolog)<note>x</note>") == want)
    }

    @Test func bomIsNotDecodedThroughTheDeclaredLabelWhileTheBytesAreValidUTF8() throws {
         // The label is consulted only when the bytes are not valid UTF-8, so the mark stays the
         // mark.
        // A reader that decoded these bytes as windows-1252 would write "ï»¿" instead.
        let want = ["text \(bom)", "procinst xml version=\"1.0\" encoding=\"windows-1252\"",
            "start :note", "text x", "end :note"]
        let input = "\(bom)<?xml version=\"1.0\" encoding=\"windows-1252\"?><note>x</note>"
        #expect(try stream(input) == want)
    }

    @Test func numericReferenceForTheMarkResolvesAndIsLegalText() throws {
         // U+FEFF is inside XML's `Char` production, so the reference resolves the reference and
         // keeps
        // the character. Only characters the production does not allow are a failure, which is the
        // case the reader tests pin (`&#0;` and `&#x1;`).
        let want = ["start :note", "text \(bom)", "end :note"]
        #expect(try stream("<note>&#xFEFF;</note>") == want)
    }

    @Test func markAfterTheRootIsTextToo() throws {
        // The mark is not only a leading thing: after the end tag of the root it is its own run,
        // because `Token()` reads past the root, where `Decode` stops. That run keeps the space the
        // input has after the end tag, so the pin shows two spaces between `text` and the mark.
        let want = ["start :note", "text \(bom)", "end :note", "text  \(bom)"]
        #expect(try stream("<note>&#xFEFF;</note> \(bom)") == want)
    }

    // MARK: - Garbage before the prolog

    @Test func garbageBeforeThePrologIsTextAtTheDocumentLevel() throws {
        // Non-strict mode: junk before the prolog is not a failure, it is a run. The reader tests
        // pin that the run is not part of the root; here the run itself is the value, so a reader
        // that dropped non-markup text would report an empty stream.
        let want = ["text junk before ", "procinst xml version=\"1.0\"",
            "start :note", "text x", "end :note"]
        #expect(try stream("junk before \(prolog)<note>x</note>") == want)
    }

    @Test func markupBeforeThePrologIsMarkupNotText() throws {
        // The garbage is text only where it is not markup: an element before the prolog is read as
        // tokens, so the run stops at it, and the single space between markup is a run of its own.
        let want = ["text junk ", "start :b", "text x", "end :b", "text  ",
            "procinst xml version=\"1.0\"", "start :note", "text y", "end :note"]
        #expect(try stream("junk <b>x</b> \(prolog)<note>y</note>") == want)
    }

    // MARK: - Character references

    @Test func theResolvedTableIsTheSmallOneXMLCarriesNotTheTableTheSanitizerReads() throws {
         // `Entity = xml.HTMLEntity` is the 252-entry map `encoding/xml` carries, which has `copy`
         // but
         // not `NewLine` or `colon`, while the table the sanitizer reads resolves both. A reader
         // that
         // used the larger table would write a line feed here, so these pins can fail on the
         // boundary.
        let copyRow = ["start :note", "text \u{00A9}", "end :note"]
        let newlineRow = ["start :note", "text &NewLine;", "end :note"]
        let colonRow = ["start :note", "text &colon;", "end :note"]
        #expect(try stream("<note>&copy;</note>") == copyRow)
        #expect(try stream("<note>&NewLine;</note>") == newlineRow)
        #expect(try stream("<note>&colon;</note>") == colonRow)
    }

    @Test func aReferenceToTheLargestResolvableCharacterIsTextWhileOnePastItIsNot() throws {
        // U+10FFFF is the largest character the reference can write, so `&#x110000;` stays as
         // written: it cannot be resolved to anything. Pins for `&#xD800;` (U+FFFD) and for a
         // failure
        // are in the reader tests; the boundary between text and failure is what this row adds.
        let resolves = ["start :note", "text &#x110000;", "end :note"]
        let fails = ["start :note", "error:illegalCharacterCode"]
        #expect(try stream("<note>&#x110000;</note>") == resolves)
        #expect(try stream("<note>&#x1f;</note>") == fails)
    }

    // MARK: - CDATA

    @Test func aCDATARunIsReportedAsTextAndItsEntitiesAreNotDecoded() throws {
         // Inside `<![CDATA[` the characters are read as they are written, which is what makes the
         // run
         // a `cdata` production here rather than plain text: a reader that resolved references
         // inside
        // the section would write "a & b".
        let want = ["start :note", "cdata a &amp; b", "end :note"]
        #expect(try stream("<note><![CDATA[a &amp; b]]></note>") == want)
    }

    @Test func aCDATARunEndsAtTheFirstCharacterItCannotRead() throws {
        // `]]>` ends the run and what follows is another run: the two cannot be one, because the
        // marker that started the first is not part of the second.
        let want = ["start :note", "cdata a &amp; b", "text c", "end :note"]
        #expect(try stream("<note><![CDATA[a &amp; b]]>c</note>") == want)
    }

    @Test func CDATAAtTheDocumentLevelIsText() throws {
        // Outside an element the section is still content, so the run appears in the stream. A pin
         // through the tree could not see it, because the reader keeps only what is inside an
         // element.
        let want = ["text \(bom)", "start :note", "cdata x", "end :note"]
        #expect(try stream("\(bom)<note><![CDATA[x]]></note>") == want)
    }

    // MARK: - AutoClose

    @Test func noAutoCloseIsSetSoAnOpenElementIsClosedByTheNextEndTagNotByTheNextToken() throws {
         // `AutoClose` is never set by the reference, so `br` is not closed at the token after it;
         // it
        // is closed by the end tag the mismatch path invents, which comes after `to` is closed. A
        // reader that applied `xml.HTMLAutoClose` would write `end br` before `start to`.
        let want = ["start :note", "start :br", "text x", "start :to", "text y",
            "end :to", "end :br", "end :note"]
        #expect(try stream("<note><br>x<to>y</note>") == want)
    }

    // MARK: - What the pins cannot pin

    @Test func aStreamThatEndsInAFailurePinsTheCaseNotTheMessage() throws {
        // The reference's failure is a message ("illegal character code U+001F", "unescaped ]]> not
        // in CDATA section"); the port models each as one `XMLError` case, and the case is what can
         // fail. So a pin here compares the case: it pins the class of failure the table records,
         // not
         // the wording, and it cannot pin whether the end of the stream was clean or reached inside
         // an
        // element, which the reference tells apart only in its message.
        let bracketRow = ["start :note", "error:unescapedBracketInText"]
        let cdataRow = ["start :note", "error:malformedCDATA"]
        let commentRow = ["error:malformedComment"]
        let namespaceRow = ["start x:y", "error:endTagNamespaceMismatch"]
        #expect(try stream("<note>x]]></note>") == bracketRow)
        #expect(try stream("<note><![BAD]x></note>") == cdataRow)
        #expect(try stream("<!-- a -- b --><note>x</note>") == commentRow)
        #expect(try stream("<x:y></y>") == namespaceRow)
    }
}

