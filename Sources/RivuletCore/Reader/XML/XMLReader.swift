// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/xml/decoder.go (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// Reads a document into a tree, the way the reference reads one: the bytes are prepared with the
/// charset rule the reference applies, and the tokens of the tolerant tokenizer are assembled.
enum XMLReader {
    /// Reads the document and returns its root element.
    ///
    /// The reader stops where `Decode` stops, which is the end of the root element, so markup after it
    /// is not read. Characters the reference removes before decoding are removed here too.
    ///
    /// - Throws: ``XMLError`` for markup the reference cannot read even in non-strict mode, and
    ///   ``CharsetError/unsupportedLabel(_:)`` when the document is not valid UTF-8 and its XML
    ///   declaration names a label that cannot be resolved.
    static func read(_ data: Data) throws -> XMLElement {
        let tokenizer = XMLTokenizer(try prepared(data))
        var open: [XMLElement] = []

        while true {
            guard let token = try tokenizer.nextToken() else { throw XMLError.unexpectedEOF }
            switch token {
            case .startElement(let name, let attributes):
                if open.isEmpty { tokenizer.pushEndOfInputMarker() }
                open.append(XMLElement(name: name, attributes: attributes, children: [], text: ""))
            case .endElement(let name):
                guard let closed = open.popLast() else { throw XMLError.unexpectedEndElement(name.local) }
                if !open.isEmpty { open[open.count - 1].children.append(closed) }
                if tokenizer.popEndOfInputMarker() { return closed }
            case .characterData(let text):
                if !open.isEmpty { open[open.count - 1].text += text }
            case .comment, .directive, .processingInstruction:
                break // Comments, directives and instructions are not part of the tree.
            }
        }
    }

    /// The bytes the tokenizer reads: the two branches of `NewXMLDecoder`. When the document declares
    /// UTF-8, or declares nothing, the illegal characters are removed and the bytes are read as they
    /// are; otherwise the reference's `CharsetReader` converts them with the label of the declaration,
    /// and the result is filtered the same way.
    ///
    /// The label is read from the XML declaration, as `procInst` does. A label written in body text
    /// decides which path the reference takes but never converts the document, which is the difference
    /// recorded in `docs/parity.md`.
    static func prepared(_ data: Data) throws -> Data {
        if FeedCharset.declaresUTF8XMLDeclaration(data) {
            return FeedCharset.filterInvalidXMLCharacters(data)
        }
        guard let label = prologDeclaredLabel(data) else {
            return FeedCharset.filterInvalidXMLCharacters(data)
        }
        do {
            return FeedCharset.filterInvalidXMLCharacters(try FeedCharset.decode(data, label: label))
        } catch let error as CharsetError {
            throw XMLError.charset(error)
        }
    }

    /// The label `procInst("encoding", content)` reads from the document's XML declaration, which is
    /// the only place the reference consults `CharsetReader`: a document without a declaration is not
    /// converted, whatever its body says.
    private static func prologDeclaredLabel(_ data: Data) -> String? {
        let bytes = [UInt8](data)
        guard let start = bytes.firstIndex(of: UInt8(ascii: "<")), start + 1 < bytes.count,
              bytes[start + 1] == UInt8(ascii: "?") else { return nil }

        var index = start + 2
        var target = [UInt8]()
        while index < bytes.count && XMLName.isNameByte(bytes[index]) {
            target.append(bytes[index])
            index += 1
        }
        guard String(decoding: target, as: UTF8.self) == "xml" else { return nil }

        let content = bytes[index...]
        guard let end = content.firstRange(of: [UInt8(ascii: "?"), UInt8(ascii: ">")]) else { return nil }
        return XMLInstructionParameter.value(
            of: "encoding",
            in: String(decoding: content[content.startIndex ..< end.lowerBound], as: UTF8.self)
        )
    }
}
