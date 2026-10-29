// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/xml/decoder.go (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// Reads a document into a tree, the way the reference reads one: the bytes are prepared with the
/// charset rule the reference applies, and the tokens of the tolerant tokenizer are assembled.
///
/// Content pieces are appended as the tokens come, so an element keeps its content in document order,
/// which is what the format adapters need: the reference reads an element's content two ways, and the
/// two do not agree.
enum XMLReader {
    /// Reads the document and returns its root element.
    ///
    /// The reader stops where `Decode` stops, which is the end of the root element, so markup after
    /// it is not read. Characters the reference removes before decoding are removed here too.
    ///
    /// - Throws: ``XMLError`` for markup the reference cannot read even in non-strict mode, and
    /// ``CharsetError/unsupportedLabel(_:)`` when the document is not valid UTF-8 and its XML
    /// declaration names a label that cannot be resolved.
    static func read(_ data: Data) throws -> XMLElement {
        let tokenizer = XMLTokenizer(try prepared(data))
        var open: [XMLElement] = []

        while true {
            guard let token = try tokenizer.nextToken() else { throw XMLError.unexpectedEOF }
            switch token {
            case .startElement(let name, let attributes):
                if open.isEmpty { tokenizer.pushEndOfInputMarker() }
                open.append(XMLElement(name: name, attributes: attributes, content: []))
            case .endElement(let name):
                guard let closed = open.popLast() else { throw XMLError.unexpectedEndElement(name.local) }
                if !open.isEmpty { open[open.count - 1].content.append(.element(closed)) }
                if tokenizer.popEndOfInputMarker() { return closed }
            case .characterData(let text, let isCDATA):
                if !open.isEmpty { open[open.count - 1].content.append(.text(text: text, isCDATA: isCDATA)) }
            case .comment, .directive, .processingInstruction:
                break // Comments, directives and instructions are not part of the tree.
            }
        }
    }

    /// The bytes the tokenizer reads: the two branches of `NewXMLDecoder`. When the document
    /// declares UTF-8, or declares nothing, the illegal characters are removed and the bytes are
    /// read as they are; otherwise the reference's `CharsetReader` converts them with the label of
    /// the first `xml` instruction, and the result is filtered the same way.
    ///
    /// A label written in body text decides which path the reference takes but is never resolved
    /// there, because `procInst` is applied to an instruction token. The reference converts from
    /// the instruction on, while the label is applied to the whole document here, and a `<?` inside
    /// markup counts as an instruction start; both are recorded in `docs/parity.md`.
    static func prepared(_ data: Data) throws -> Data {
        if FeedCharset.declaresUTF8XMLDeclaration(data) {
            return FeedCharset.filterInvalidXMLCharacters(data)
        }
        guard let label = instructionDeclaredLabel(data) else {
            return FeedCharset.filterInvalidXMLCharacters(data)
        }
        do {
            return FeedCharset.filterInvalidXMLCharacters(try FeedCharset.decode(data, label: label))
        } catch let error as CharsetError {
            throw XMLError.charset(error)
        }
    }

    /// The label `procInst("encoding", content)` reads, which is the only place the reference
    /// consults `CharsetReader`: it is applied to an instruction token, so the label comes from the
    /// first instruction whose target is `xml`, wherever that instruction is and whatever text
    /// comes before it. A document with no such instruction is not converted, whatever its body
    /// text says.
    ///
    /// The scan reads instruction starts byte by byte, so a `<?` inside a comment, a CDATA section
    /// or a quoted attribute value counts as one here, while the reference only reaches `procInst`
    /// at a token boundary; that approximation is recorded in `docs/parity.md`.
    private static func instructionDeclaredLabel(_ data: Data) -> String? {
        let bytes = [UInt8](data)
        var index = 0
        while index + 1 < bytes.count {
            guard bytes[index] == UInt8(ascii: "<"), bytes[index + 1] == UInt8(ascii: "?") else {
                index += 1
                continue
            }

            var position = index + 2
            var target = [UInt8]()
            while position < bytes.count && XMLName.isNameByte(bytes[position]) {
                target.append(bytes[position])
                position += 1
            }
            guard String(decoding: target, as: UTF8.self) == "xml" else {
                index = position
                continue
            }

            let content = bytes[position...]
            guard let end = content.firstRange(of: [UInt8(ascii: "?"), UInt8(ascii: ">")]) else { return nil }
            return XMLInstructionParameter.value(
                of: "encoding",
                in: String(decoding: content[content.startIndex ..< end.lowerBound], as: UTF8.self)
            )
        }
        return nil
    }
}
