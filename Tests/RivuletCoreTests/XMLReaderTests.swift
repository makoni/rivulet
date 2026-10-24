import Foundation
import Testing
@testable import RivuletCore

/// The tolerant XML reader. Ported from Miniflux `internal/reader/xml/decoder.go`; the tests that
/// mirror an upstream assertion name the upstream test (`decoder_test.go`).
///
/// The tolerance rules are the configuration the reference builds: `Strict = false` and `Entity =
/// xml.HTMLEntity`, so unknown or malformed entities stay as written, a mismatched end tag closes
/// the element that is open, an attribute name without `=` becomes its own value, and an unquoted
/// attribute value is read only over name characters. The reader stops when the root element ends,
/// which is where `Decode` stops, so markup after the root is not read.
@Suite struct XMLReaderTests {
    /// A Latin-1 document, so a byte above 0x7F is not a valid UTF-8 sequence and the label is
    /// honored instead of the bytes winning.
    private func latin1(_ text: String) -> Data {
        Data(text.unicodeScalars.map { UInt8($0.value & 0xFF) })
    }

    /// The text the tokenizer gives for tokens of one kind. The reader keeps character data only,
    /// so the tokens it discards are read through the tokenizer here.
    private func contents(_ data: Data, of kind: (XMLToken) -> String?) throws -> [String] {
        let tokenizer = XMLTokenizer(data)
        var values: [String] = []
        while true {
            let token: XMLToken?
            do {
                token = try tokenizer.nextToken()
            } catch {
                break
            }
            guard let token else { break }
            if let value = kind(token) { values.append(value) }
        }
        return values
    }

    private func directiveContents(_ data: Data) throws -> [String] {
        try contents(data) { if case .directive(let content) = $0 { return content } else { return nil } }
    }

    private func commentContents(_ data: Data) throws -> [String] {
        try contents(data) { if case .comment(let content) = $0 { return content } else { return nil } }
    }

    private func characterDataContents(_ data: Data) throws -> [String] {
        try contents(data) { if case .characterData(let value) = $0 { return value } else { return nil } }
    }

    // MARK: - Ported fixture tests

    /// `TestXMLDocumentWithISO88591Encoding`
    @Test func iso88591DocumentIsDecodedWithThePrologLabel() throws {
        let root = try XMLReader.read(try Fixtures.data("xml/iso88591.xml"))
        #expect(root.name.local == "note")
        #expect(root.child(local: "to")?.text == "Anaïs")
        #expect(root.child(local: "from")?.text == "Jürgen")
    }

    /// `TestXMLDocumentWithISO88591FileEncodingButUTF8Prolog`: the prolog says UTF-8, so the bytes
    /// are not converted, and the illegal ones are dropped.
    @Test func utf8PrologOverNonUTF8BytesDropsTheIllegalOnes() throws {
        let root = try XMLReader.read(try Fixtures.data("xml/iso88591_utf8_mismatch.xml"))
        #expect(root.child(local: "to")?.text == "Anas")
        #expect(root.child(local: "from")?.text == "Jrgen")
    }

    /// `TestXMLDocumentWithKOI8REncoding`
    @Test func koi8rDocumentIsDecodedWithThePrologLabel() throws {
        let root = try XMLReader.read(try Fixtures.data("xml/koi8r.xml"))
        let channel = try #require(root.child(local: "channel"))
        #expect(channel.child(local: "title")?.text == "Пример RSS ленты")
        #expect(channel.child(local: "description")?.text == "Тестовая лента в кодировке KOI8-R")

        let items = channel.children(local: "item")
        #expect(items.count == 2)
        #expect(items[0].child(local: "title")?.text == "Первая новость")
        #expect(
            items[0].child(local: "description")?.text
                .contains("Привет мир! Ёжик, чай, Москва, Санкт-Петербург.") == true
        )
        #expect(items[1].child(local: "description")?.text.contains("Проверка специальных символов") == true)
    }

    /// `TestXMLDocumentWithIllegalUnicodeCharacters`: the illegal character is dropped before the
    /// document is read, so the title survives.
    @Test func illegalCharacterIsDroppedBeforeTheDocumentIsRead() throws {
        let document = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
            + "<rss version=\"2.0\"><title>Title & 中文\u{10}标题</title></rss>"
        let root = try XMLReader.read(Data(document.utf8))
        #expect(root.child(local: "title")?.text == "Title & 中文标题")
    }

    /// `TestXMLDocumentWindows251EncodedWithIllegalCharacters`: the bytes are valid UTF-8, so the
    /// declared windows-1251 never wins, and the illegal character is dropped.
    @Test func windows1251LabelOverValidUTF8BytesKeepsTheUTF8() throws {
        let data = Data(
            "<?xml version=\"1.0\" encoding=\"windows-1251\"?><rss version=\"2.0\"><title>Title & 中文\u{10}标题</title></rss>".utf8
        )
        #expect(try XMLReader.read(data).child(local: "title")?.text == "Title & 中文标题")
    }

    /// `TestXMLDocumentWithIncorrectEncodingField`: an unusable label is not an error while the
    /// bytes are valid UTF-8.
    @Test func unusableLabelIsNotAnErrorWhileTheBytesAreValidUTF8() throws {
        let data = Data(
            "<?xml version=\"1.0\" encoding=\"invalid\"?><rss version=\"2.0\"><title>Title & 中文\u{10}标题</title></rss>".utf8
        )
        #expect(try XMLReader.read(data).child(local: "title")?.text == "Title & 中文标题")
    }

    // MARK: - Entities

    @Test func baseEntitiesAndHTMLNamedEntitiesAreDecoded() throws {
        let root = try XMLReader.read(Data("<note>&amp; &lt; &gt; &quot; &apos; &nbsp; &copy;</note>".utf8))
        #expect(root.text == "& < > \" ' \u{A0} \u{A9}")
    }

    @Test func numericEntitiesAreDecoded() throws {
        #expect(try XMLReader.read(Data("<note>&#39; &#x27; &#160;</note>".utf8)).text == "' ' \u{A0}")
    }

    @Test func unknownNamedEntityIsLeftAsWritten() throws {
        // Non-strict mode leaves an unknown entity alone; `Strict = true` would fail the document.
        #expect(try XMLReader.read(Data("<note>&foo;</note>".utf8)).text == "&foo;")
    }

    @Test func entityAboveTheLargestRuneIsLeftAsWritten() throws {
        #expect(try XMLReader.read(Data("<note>&#1114112;</note>".utf8)).text == "&#1114112;")
    }

    @Test func numericEntityForASurrogateResolvesToTheReplacementCharacter() throws {
        // A surrogate is not a character, but the reference writes `string(rune(n))` for every
        // value up to the largest rune, and `string(rune(0xD800))` is the replacement character,
        // which is inside the `Char` production, so the text keeps it.
        #expect(try XMLReader.read(Data("<note>&#xD800;</note>".utf8)).text == "\u{FFFD}")
    }

    @Test func entityWithoutASemicolonIsLeftAsWritten() throws {
        #expect(try XMLReader.read(Data("<note>&amp more</note>".utf8)).text == "&amp more")
    }

    @Test func numericEntityResolvingOutsideTheCharacterProductionIsAnError() throws {
        // The document is filtered before it is tokenized, so an illegal character in the bytes is
        // gone, but a numeric reference resolves to one afterwards: `&#0;` and `&#12;` are
        // characters the `Char` production does not allow, and the reference fails on them when the
        // text is checked.
        #expect(throws: XMLError.illegalCharacterCode(0)) {
            try XMLReader.read(Data("<note>&#0;</note>".utf8))
        }
        #expect(throws: XMLError.illegalCharacterCode(12)) {
            try XMLReader.read(Data("<note x=\"&#12;\">y</note>".utf8))
        }
        // Tab, line feed and carriage return are in the production, and so is U+FFFD.
        #expect(try XMLReader.read(Data("<note>&#9;&#10;&#13;&#65533;</note>".utf8)).text == "\u{9}\u{A}\u{D}\u{FFFD}")
    }

    @Test func entitiesInsideCDATAAreNotDecoded() throws {
        #expect(try XMLReader.read(Data("<note><![CDATA[a &amp; b &lt;]]></note>".utf8)).text == "a &amp; b &lt;")
    }

    @Test func unescapedBracketOutsideCDATAIsAnError() {
        #expect(throws: XMLError.unescapedBracketInText) {
            try XMLReader.read(Data("<note>a ]]></note>".utf8))
        }
    }

    // MARK: - Tolerance of malformed markup

    @Test func attributeWithoutAValueBecomesItsOwnValue() throws {
        let note = try XMLReader.read(Data("<note attr>x</note>".utf8))
        #expect(note.attributes.count == 1)
        #expect(note.attributes[0].name.local == "attr")
        #expect(note.attributes[0].value == "attr")

        // The name stops at the whitespace and the value is the name itself. `readName` does not
        // clear the buffer, but `name()` clears it before reading, which is what the entity path
        // relies on.
        let doubled = try XMLReader.read(Data("<note attr >x</note>".utf8))
        #expect(doubled.attributes[0].value == "attr")
    }

    @Test func unquotedAttributeValueStopsAtTheFirstCharacterItDoesNotAccept() throws {
        // The reference reads an unquoted value over the characters `attrval` lists and puts the
        // character that stops it back, so `http://` gives `http:` and the first slash is left as
        // markup: it starts a self-closing element that is not closed by the second one. The class
        // `attrval` lists is not the one a name is read over, and it has no `.`, so a value stops
        // at a dot, the dot is put back, and `readName` reads `.b` at the next attribute position
        // as a name that `isName` rejects, because a name cannot start with a dot.
        #expect(throws: XMLError.selfClosingTagNotClosed) {
            try XMLReader.read(Data("<note><link href=http://></link></note>".utf8))
        }
        #expect(throws: XMLError.selfClosingTagNotClosed) {
            try XMLReader.read(Data("<note><link href=http://x></link></note>".utf8))
        }
        #expect(throws: XMLError.invalidXMLName(".b")) {
            try XMLReader.read(Data("<note href=a.b>x</note>".utf8))
        }
    }

    @Test func unescapedAngleInsideAQuotedAttributeValueIsAnError() {
        #expect(throws: XMLError.unescapedAngleInAttributeValue) {
            try XMLReader.read(Data("<note x=\"a<b\">y</note>".utf8))
        }
    }

    @Test func attributeWithoutANameIsAnError() {
        // `readName` stops at `!`, so the name is `title`, its value becomes `title` in non-strict
        // mode, and the second `!` has no name left for it.
        #expect(throws: XMLError.attributeNameExpected) {
            try XMLReader.read(Data("<note title!>x</note>".utf8))
        }
    }

    @Test func mismatchedEndTagClosesTheElementThatIsOpen() throws {
        // The reference closes `b` at `</a>` and keeps `</a>` for after it, which then closes the
        // root; `Decode` returns there, so the document parses.
        let root = try XMLReader.read(Data("<note><b>x</a></note>".utf8))
        #expect(root.child(local: "b")?.text == "x")
    }

    @Test func endTagWithNothingOpenIsAnError() {
        #expect(throws: XMLError.unexpectedEndElement("stray")) {
            try XMLReader.read(Data("</stray><note>x</note>".utf8))
        }
    }

    @Test func textBeforeThePrologIsIgnored() throws {
        let root = try XMLReader.read(Data("junk <?xml version=\"1.0\"?><note><to>x</to></note>".utf8))
        #expect(root.name.local == "note")
        #expect(root.child(local: "to")?.text == "x")
    }

    @Test func commentsAndDirectivesAreNotPartOfTheTree() throws {
        let root = try XMLReader.read(
            Data("<!DOCTYPE html><!-- <title>inside a comment</title> --><note><to>x</to></note>".utf8)
        )
        #expect(root.name.local == "note")
        #expect(root.child(local: "title") == nil)
        #expect(root.child(local: "to")?.text == "x")
    }

    @Test func carriageReturnAndCRLFInsideTextBecomeLineFeed() throws {
        #expect(try XMLReader.read(Data("<note>a\rb\r\nc</note>".utf8)).text == "a\nb\nc")
    }

    @Test func versionOtherThan10IsAnError() {
        #expect(throws: XMLError.unsupportedXMLVersion("1.1")) {
            try XMLReader.read(Data("<?xml version=\"1.1\"?><note>x</note>".utf8))
        }
    }

    @Test func emptyVersionIsNotAnError() throws {
        // The reference fails only a version that is present and is not `1.0`.
        #expect(try XMLReader.read(Data("<?xml version=\"\"?><note>x</note>".utf8)).text == "x")
    }

    @Test func instructionWithNoTargetIsAnError() {
        #expect(throws: XMLError.processingInstructionTargetExpected) {
            try XMLReader.read(Data("<note><?!x>y</note>".utf8))
        }
    }

    @Test func dashInsideACommentIsAnError() {
        #expect(throws: XMLError.malformedComment) {
            try XMLReader.read(Data("<note><!-- a -- b --></note>".utf8))
        }
        // `<!-` that is not the opening of a comment cannot be a directive either, so the reference
        // fails it before reading the rest.
        #expect(throws: XMLError.malformedComment) {
            try XMLReader.read(Data("<note><!-x>y</note>".utf8))
        }
    }

    @Test func directiveKeepsWhatPartiallyMatchesACommentOpening() throws {
        // The reference looks for `!--` after a `<` inside a directive. When the match fails it
        // keeps the characters it matched and the character that stopped it, and the `<` still
        // counts as nesting, so the directive ends at the second `>`.
        #expect(try directiveContents(Data("<!DOCTYPE a<!x>>".utf8)) == ["DOCTYPE a<!x>"])
        // A directive that does reach a comment writes it as a space, so that the markup parts it
        // separated do not become new markup when the directive is written back out.
        #expect(try directiveContents(Data("<!DOCTYPE a<!-- c -->b>".utf8)) == ["DOCTYPE a b"])
    }

    @Test func directiveHandlesTheCharacterThatStopsAPartialCommentMatchAgain() throws {
        // The reference writes the characters that matched and then handles the one that stopped
        // the match through the same switch, so a `>` in it still counts against the nesting: this
        // directive ends at the second `>`, not at the first one.
        #expect(try directiveContents(Data("<!a<!>b>".utf8)) == ["a<!>b"])
    }

    @Test func commentContentIsWhatTheTokenizerReads() throws {
        // The reader does not keep comments, so the content is read through the tokenizer: the
        // `-->` that ends the comment is not part of it.
        #expect(try commentContents(Data("<!--x-->".utf8)) == ["x"])
        // `b0` and `b1` are the two bytes before the one being read, so the terminator is the three
        // bytes written last, and the content is the buffer without them.
        #expect(try commentContents(Data("<!-- a -->x".utf8)) == [" a "])
    }

    @Test func textReturnsWhatItReadAtTheEndOfTheDocument() throws {
        // `text` returns what it has read when `getc` reaches the end of the document, so the token
        // it read is reported and the failure is left for the next read. Through the reader the
        // document still fails, because an element is open for the reader to close.
        let data = Data("<note>x".utf8)
        #expect(try characterDataContents(data) == ["x"])
        #expect(throws: XMLError.unexpectedEOF) { try XMLReader.read(data) }
    }

    @Test func characterReferenceCannotReachTheEndOfTheDocument() {
        // `text` may return what it has read at the end of the document, but the primitives that
        // read a reference or an unquoted value cannot, so the reference fails there.
        #expect(throws: XMLError.unexpectedEOF) {
            try XMLReader.read(Data("<note>&foo".utf8))
        }
        #expect(throws: XMLError.unexpectedEOF) {
            try XMLReader.read(Data("<note href=a".utf8))
        }
    }

    @Test func CDATAAtTheEndOfTheDocumentIsAnError() {
        // In a CDATA section the end of the document is a failure, unlike ordinary text, which
        // returns what it has read.
        #expect(throws: XMLError.unexpectedEOF) {
            try XMLReader.read(Data("<note><![CDATA[a".utf8))
        }
    }

    @Test func invalidCDATAOpeningIsAnError() {
        #expect(throws: XMLError.malformedCDATA) {
            try XMLReader.read(Data("<note><![CDATAb]></note>".utf8))
        }
    }

    @Test func unclosedElementAtTheEndOfTheDocumentIsAnError() {
        #expect(throws: XMLError.unexpectedEOF) {
            try XMLReader.read(Data("<note><to>x</to>".utf8))
        }
    }

    @Test func invalidXMLNameIsAnError() {
        // A digit cannot start a name, so `1tag` is not a name even though its bytes are name
        // bytes.
        #expect(throws: XMLError.invalidXMLName("1tag")) {
            try XMLReader.read(Data("<1tag>x</1tag>".utf8))
        }
    }

    @Test func nameWithCharactersOutsideTheNameClassesIsAnError() throws {
        // The reference accepts a name whose characters are letters, so a non-ASCII name is read as
        // a name; a punctuation mark is not one.
        #expect(try XMLReader.read(Data("<note><café>x</café></note>".utf8)).child(local: "café")?.text == "x")
        // A name that reads but is not one is only possible when every byte it reads is a name
        // byte, so punctuation ends the name and the reference then asks for a name at the
        // punctuation itself.
        #expect(throws: XMLError.attributeNameExpected) {
            try XMLReader.read(Data("<note><x!>y</x!></note>".utf8))
        }
    }

    @Test func endTagInAnotherNamespaceIsAnError() {
        // A mismatched local name is tolerated, but the reference still rejects an end tag whose
        // namespace is not the open element's, and the names it reports are the ones as written,
        // before the declarations are applied.
        #expect(throws: XMLError.endTagNamespaceMismatch(
            element: XMLName(namespace: "p", local: "x"),
            endTag: XMLName(namespace: "", local: "x")
        )) {
            try XMLReader.read(Data("<note><p:x xmlns:p=\"urn:p\"></x></p:x></note>".utf8))
        }
    }

    @Test func endOfDocumentIsReportedBeforeTheConstructBeingRead() {
        // `mustgetc` reports the end of the document before the byte it was comparing against, so
        // these fail as the end of the document rather than as the malformed markup they would have
        // been: the incomplete `<!-`, the incomplete `<![` and the end tag name that reaches the
        // end. A `<` not followed by `!` is an element name position instead, and `readName`
        // returns false there before writing anything, because `[` cannot start a name.
        #expect(throws: XMLError.unexpectedEOF) { try XMLReader.read(Data("<note><!-".utf8)) }
        #expect(throws: XMLError.unexpectedEOF) { try XMLReader.read(Data("<note><![".utf8)) }
        #expect(throws: XMLError.elementNameExpected) { try XMLReader.read(Data("<note><[".utf8)) }
        #expect(throws: XMLError.unexpectedEOF) { try XMLReader.read(Data("<note></name".utf8)) }
        #expect(throws: XMLError.unexpectedEOF) { try XMLReader.read(Data("<note href=a".utf8)) }
    }

    @Test func namePositionWithNoNameIsAnError() {
        // The reference keeps failing on markup it cannot read at all, even in non-strict mode: a
        // start tag with no name, an attribute position with no name, and an end tag that is not
        // closed by `>`.
        #expect(throws: XMLError.elementNameExpected) {
            try XMLReader.read(Data("<note><\"x\">y</\"x\"></note>".utf8))
        }
        #expect(throws: XMLError.attributeNameExpected) {
            try XMLReader.read(Data("<note \"y\">x</note>".utf8))
        }
        #expect(throws: XMLError.invalidEndTag("note")) {
            try XMLReader.read(Data("<note>x</note y>".utf8))
        }
        #expect(throws: XMLError.selfClosingTagNotClosed) {
            try XMLReader.read(Data("<note/ x>y</note>".utf8))
        }
        #expect(throws: XMLError.elementNameExpected) {
            try XMLReader.read(Data("<note>x</>y</note>".utf8))
        }
    }

    @Test func verticalTabIsNotTagWhitespaceAndIsRemovedFromTheDocument() throws {
        // The reference skips only space, tab, line feed and carriage return, so a vertical tab is
        // not tag whitespace. It is not an XML `Char` either, so it never reaches the tokenizer:
        // the character filter applied to the document removes it first, which leaves the next
        // attribute adjacent to the closing quote and reading its own value.
        let note = try XMLReader.read(Data("<note x=\"1\"\u{0B}y=\"2\">z</note>".utf8))
        #expect(note.attributes.map { "\($0.name.local)=\($0.value)" } == ["x=1", "y=2"])
        #expect(note.text == "z")
    }

    // MARK: - The reader's own contract

    @Test func readerStopsAtTheEndOfTheRootElement() throws {
        // `Decode` stops at the end of the root element, so markup after it is not read and the
        // reference never reaches the character reference that would fail it.
        #expect(try XMLReader.read(Data("<note>x</note>&#0;y".utf8)).text == "x")
    }

    @Test func emptyDocumentIsAnError() {
        #expect(throws: XMLError.unexpectedEOF) {
            try XMLReader.read(Data())
        }
    }

    // MARK: - Namespace resolution, as `encoding/xml` applies it

    @Test func defaultNamespaceAndPrefixesAreResolvedToURIs() throws {
        let document = "<feed xmlns=\"http://www.w3.org/2005/Atom\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\">"
            + "<entry><title>t</title><dc:creator>c</dc:creator></entry></feed>"
        let root = try XMLReader.read(Data(document.utf8))
        let entry = try #require(root.child(local: "entry"))
        #expect(root.name.namespace == "http://www.w3.org/2005/Atom")
        #expect(entry.child(local: "title")?.name.namespace == "http://www.w3.org/2005/Atom")
        #expect(entry.child(local: "creator")?.name.namespace == "http://purl.org/dc/elements/1.1/")

        // A declaration is kept as an attribute, and an attribute with no prefix is not moved into
        // the default namespace.
        #expect(root.attribute(local: "xmlns") == "http://www.w3.org/2005/Atom")
        #expect(root.attributes.count == 2)
    }

    @Test func namespaceMappingEndsWhenItsElementEnds() throws {
        let document = "<note xmlns:d=\"urn:d\"><a><d:x/></a><d:y xmlns:c=\"urn:c\"><c:z/></d:y></note>"
        let root = try XMLReader.read(Data(document.utf8))
        #expect(root.child(local: "a")?.child(local: "x")?.name.namespace == "urn:d")
        let y = try #require(root.child(local: "y"))
        #expect(y.name.namespace == "urn:d")
        #expect(y.child(local: "z")?.name.namespace == "urn:c")
    }

    @Test func undefinedPrefixStaysAsWritten() throws {
        // Non-strict mode records the undefined prefix as the namespace, instead of failing.
        let root = try XMLReader.read(Data("<note><p:x>c</p:x></note>".utf8))
        #expect(root.child(local: "x")?.name.namespace == "p")
    }

    @Test func xmlLanguageAttributeUsesTheXMLNamespace() throws {
        let root = try XMLReader.read(Data("<note xml:lang=\"en\">x</note>".utf8))
        #expect(root.attributes[0].name.namespace == "http://www.w3.org/XML/1998/namespace")
        #expect(root.attributes[0].value == "en")
    }
}
