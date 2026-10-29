// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/xml (Apache-2.0); adapted for Swift/SQLite. The tokenizer is
// `encoding/xml`'s `Decoder` with the configuration the reference builds (`Strict = false`, `Entity
// = xml.HTMLEntity`).

import Foundation

/// The byte-level tokenizer behind ``XMLReader``: it assembles tokens from the primitives of
/// ``XMLScanner`` and keeps the namespace scope.
///
/// The tolerance that follows from the reference's configuration: unknown and malformed character
/// references stay as written, an attribute name without `=` becomes its own value, an unquoted
/// attribute value is read only over name characters, a mismatched end tag closes the element that
/// is open, and an undefined prefix is kept as written. Only the failures non-strict mode can still
/// reach are reported, as ``XMLError``.
///
/// Two parts of Go's decoder are not ported: the invalid UTF-8 check of `text`, because
/// ``XMLReader`` removes invalid sequences before the document is tokenized, and the `AutoClose`
/// list, which the reference never sets. The `Char` production check of `text` is ported, because a
/// numeric character reference can still reach it after the filter, and `translate`'s
/// `DefaultSpace` fallback is not, because the reference never sets that field. The reader change
/// `CharsetReader` performs is made before tokenizing, so the tokenizer reads one document and
/// never switches readers.
final class XMLTokenizer {
    private enum Kind {
        case element, namespaceDeclaration, endOfInput
    }

    private struct StackEntry {
        var kind: Kind
        var name: XMLName
        /// Whether the namespace recorded here was already declared, so closing the element
        /// restores it instead of removing it.
        var wasDeclared: Bool
    }

    private static let xmlnsPrefix = "xmlns"
    private static let xmlPrefix = "xml"
    private static let xmlNamespace = "http://www.w3.org/XML/1998/namespace"

    private let scanner: XMLScanner
    private var pendingClose: XMLName?
    private var namespaces: [String: String] = [:]
    private var stack: [StackEntry] = []

    init(_ data: Data) {
        scanner = XMLScanner(data)
    }

    // MARK: - Reading tokens

    /// The next token, or `nil` at the point where `Decode` stops: the end-of-input marker pushed
    /// under the root element, or the end of the document.
    func nextToken() throws -> XMLToken? {
        if stack.last?.kind == .endOfInput { return nil }
        if let failure = scanner.failure { throw failure }

        guard let token = rawToken() else { throw scanner.failure ?? .unexpectedEOF }
        switch token {
        case .startElement(var name, var attributes):
            recordDeclarations(in: attributes)
            pushElement(name)
            translate(&name, isElementName: true)
            for index in attributes.indices { translate(&attributes[index].name, isElementName: false) }
            return .startElement(name, attributes)
        case .endElement(var name):
            guard popElement(&name) else { throw scanner.failure ?? .unexpectedEndElement(name.local) }
            return .endElement(name)
        default:
            return token
        }
    }

    /// Marks where `Decode` stops for a value read as a plain struct: `unmarshal` returns after the
    /// root's end tag. The reference's `pushEOF` marks a single element only when the value's type
    /// implements `UnmarshalXML`, which Miniflux does for two types, and this port has no value
    /// layer to check that a value consumed its whole element; `docs/parity.md` records the
    /// difference.
    func pushEndOfInputMarker() {
        guard var index = stack.lastIndex(where: { $0.kind == .element }) else { return }
        // The declarations below an element belong to it, so the marker goes under them.
        while index > 0 && stack[index - 1].kind == .namespaceDeclaration { index -= 1 }
        let marker = StackEntry(kind: .endOfInput, name: XMLName(namespace: "", local: ""), wasDeclared: false)
        stack.insert(marker, at: index)
    }

    func popEndOfInputMarker() -> Bool {
        guard stack.last?.kind == .endOfInput else { return false }
        stack.removeLast()
        return true
    }

    private func rawToken() -> XMLToken? {
        if scanner.failure != nil { return nil }
        if let pendingClose {
            self.pendingClose = nil
            return .endElement(pendingClose)
        }

        guard let byte = scanner.readByte() else { return nil }
        guard byte == XMLByte.lessThan else {
            scanner.unreadByte()
            guard let data = scanner.text(quote: nil, cdata: false) else { return nil }
            return .characterData(data, isCDATA: false)
        }

        guard let marker = scanner.readByte() else { return nil }
        switch marker {
        case XMLByte.slash: return endElementToken()
        case XMLByte.questionMark: return processingInstructionToken()
        case XMLByte.exclamation: return declarationToken()
        default: return startElementToken()
        }
    }

    private func endElementToken() -> XMLToken? {
        guard let name = scanner.namespaceName() else {
            if scanner.failure == nil { scanner.failure = .elementNameExpected }
            return nil
        }
        scanner.skipSpace()
        guard let byte = scanner.readByte() else { return nil }
        guard byte == XMLByte.greaterThan else {
            scanner.failure = .invalidEndTag(name.local)
            return nil
        }
        return .endElement(name)
    }

    private func processingInstructionToken() -> XMLToken? {
        guard let target = scanner.name() else {
            if scanner.failure == nil { scanner.failure = .processingInstructionTargetExpected }
            return nil
        }
        scanner.skipSpace()
        scanner.buffer.removeAll(keepingCapacity: true)
        var previous: UInt8 = 0
        while true {
            guard let byte = scanner.readByte() else { return nil }
            scanner.buffer.append(byte)
            if previous == XMLByte.questionMark && byte == XMLByte.greaterThan { break }
            previous = byte
        }
        let content = String(decoding: scanner.buffer.dropLast(2), as: UTF8.self) // chop ?>

        // Only a version that is present is checked, so an empty one is not an error.
        if target == Self.xmlPrefix,
           let version = XMLInstructionParameter.value(of: "version", in: content),
           !version.isEmpty,
           version != "1.0" {
            scanner.failure = .unsupportedXMLVersion(version)
            return nil
        }
        return .processingInstruction(target: target, content: content)
    }

    private func declarationToken() -> XMLToken? {
        guard let marker = scanner.readByte() else { return nil }
        switch marker {
        case XMLByte.hyphen: return commentToken()
        case XMLByte.leftBracket: return cdataToken()
        default: return directiveToken(from: marker)
        }
    }

    private func commentToken() -> XMLToken? {
        guard let byte = scanner.readByte() else { return nil }
        guard byte == XMLByte.hyphen else {
            scanner.failure = .malformedComment
            return nil
        }
        scanner.buffer.removeAll(keepingCapacity: true)
        var previous: UInt8 = 0
        var previousPrevious: UInt8 = 0
        while true {
            guard let byte = scanner.readByte() else { return nil }
            // The byte is written before the terminator is checked, as in the reference, so the
            // three bytes written last are the `-->` that ends the comment and are not part of its
            // content.
            scanner.buffer.append(byte)
            if previousPrevious == XMLByte.hyphen && previous == XMLByte.hyphen {
                guard byte == XMLByte.greaterThan else {
                    scanner.failure = .malformedComment
                    return nil
                }
                break
            }
            previousPrevious = previous
            previous = byte
        }
        return .comment(String(decoding: scanner.buffer.dropLast(3), as: UTF8.self))
    }

    private func cdataToken() -> XMLToken? {
        for expected in Array("CDATA[".utf8) {
            guard let byte = scanner.readByte() else { return nil }
            guard byte == expected else {
                scanner.failure = .malformedCDATA
                return nil
            }
        }
        guard let data = scanner.text(quote: nil, cdata: true) else { return nil }
        return .characterData(data, isCDATA: true)
    }

    private func directiveToken(from first: UInt8) -> XMLToken? {
        scanner.buffer.removeAll(keepingCapacity: true)
        scanner.buffer.append(first)
        var quoted: UInt8 = 0
        var depth = 0
        while true {
            guard let byte = scanner.readByte() else { return nil }
            if quoted == 0 && byte == XMLByte.greaterThan && depth == 0 { break }
            scanner.buffer.append(byte)
            if quoted != 0 {
                if byte == quoted { quoted = 0 }
                continue
            }
            switch byte {
            case XMLByte.doubleQuote, XMLByte.singleQuote: quoted = byte
            case XMLByte.greaterThan: depth -= 1
            case XMLByte.lessThan:
                // A comment inside a directive is skipped and replaced with a space, so that the
                // parts it separated do not become new markup when the directive is written back
                // out.
                guard scanner.startsComment() else { depth += 1; continue }
                scanner.buffer.removeLast()
                scanner.skipToCommentEnd()
                scanner.buffer.append(XMLByte.space)
            default: break
            }
        }
        return .directive(String(decoding: scanner.buffer, as: UTF8.self))
    }

    private func startElementToken() -> XMLToken? {
        scanner.unreadByte()
        guard let name = scanner.namespaceName() else {
            if scanner.failure == nil { scanner.failure = .elementNameExpected }
            return nil
        }

        var attributes: [XMLAttribute] = []
        while true {
            scanner.skipSpace()
            guard let byte = scanner.readByte() else { return nil }
            if byte == XMLByte.slash {
                guard let next = scanner.readByte() else { return nil }
                guard next == XMLByte.greaterThan else {
                    scanner.failure = .selfClosingTagNotClosed
                    return nil
                }
                // Only the start half of a self-closing element is reported now.
                pendingClose = name
                return .startElement(name, attributes)
            }
            if byte == XMLByte.greaterThan { break }
            scanner.unreadByte()
            guard let attribute = attributeToken() else { return nil }
            attributes.append(attribute)
        }
        return .startElement(name, attributes)
    }

    private func attributeToken() -> XMLAttribute? {
        guard let name = scanner.namespaceName() else {
            if scanner.failure == nil { scanner.failure = .attributeNameExpected }
            return nil
        }
        scanner.skipSpace()
        guard let byte = scanner.readByte() else { return nil }
        if byte != XMLByte.equals {
            // Non-strict mode takes the name as its own value.
            scanner.unreadByte()
            return XMLAttribute(name: name, value: name.local)
        }
        scanner.skipSpace()
        guard let value = attributeValue() else { return nil }
        return XMLAttribute(name: name, value: value)
    }

    private func attributeValue() -> String? {
        guard let byte = scanner.readByte() else { return nil }
        if byte == XMLByte.doubleQuote || byte == XMLByte.singleQuote {
            return scanner.text(quote: byte, cdata: false)
        }

        // An unquoted value is read over the characters `attrval` lists, and the character that
        // stops it is put back, which is why `href=http://` gives `http:` and the slash continues
        // as markup. This class is not the one `readName` reads a name over: it has no `.`, so
        // `href=a.b` gives `a` and the `.` is left for the next attribute position, where
        // `readName` reads it as the start of a name and `isName` then rejects it. `attrval` clears
        // the buffer it inherits from the name read, so a name that is its own value is not written
        // twice.
        scanner.buffer.removeAll(keepingCapacity: true)
        scanner.unreadByte()
        while true {
            guard let current = scanner.readByte() else { return nil }
            guard XMLName.isAttributeValueByte(current) else {
                scanner.unreadByte()
                break
            }
            scanner.buffer.append(current)
        }
        return String(decoding: scanner.buffer, as: UTF8.self)
    }

    // MARK: - Namespace state

    private func pushElement(_ name: XMLName) {
        stack.append(StackEntry(kind: .element, name: name, wasDeclared: false))
    }

    private func pushNamespace(_ local: String, previous: String, wasDeclared: Bool) {
        let entry = StackEntry(kind: .namespaceDeclaration,
                               name: XMLName(namespace: previous, local: local),
                               wasDeclared: wasDeclared)
        stack.append(entry)
    }

    /// Records the declarations of a start tag before its name is translated, which is the order
    /// `encoding/xml` uses: the translations listed in the attributes apply to the element name
    /// too.
    private func recordDeclarations(in attributes: [XMLAttribute]) {
        for attribute in attributes {
            if attribute.name.namespace == Self.xmlnsPrefix {
                pushNamespace(attribute.name.local,
                              previous: namespaces[attribute.name.local] ?? "",
                              wasDeclared: namespaces[attribute.name.local] != nil)
                namespaces[attribute.name.local] = attribute.value
            }
            if attribute.name.namespace.isEmpty && attribute.name.local == Self.xmlnsPrefix {
                pushNamespace("", previous: namespaces[""] ?? "", wasDeclared: namespaces[""] != nil)
                namespaces[""] = attribute.value
            }
        }
    }

    private func popElement(_ name: inout XMLName) -> Bool {
        guard let entry = stack.popLast(), entry.kind == .element else {
            scanner.failure = .unexpectedEndElement(name.local)
            return false
        }
        if entry.name.local != name.local {
            // Non-strict mode closes the element that is open and keeps the written name for after
            // it.
            pendingClose = name
            name = entry.name
            return true
        }
        if entry.name.namespace != name.namespace {
            scanner.failure = .endTagNamespaceMismatch(element: entry.name, endTag: name)
            return false
        }
        translate(&name, isElementName: true)
        while let entry = stack.last, entry.kind != .element && entry.kind != .endOfInput {
            stack.removeLast()
            if entry.wasDeclared { namespaces[entry.name.local] = entry.name.namespace }
            else { namespaces[entry.name.local] = nil }
        }
        return true
    }

    private func translate(_ name: inout XMLName, isElementName: Bool) {
        if name.namespace == Self.xmlnsPrefix { return }
        if name.namespace.isEmpty && !isElementName { return }
        if name.namespace == Self.xmlPrefix { name.namespace = Self.xmlNamespace }
        if name.namespace.isEmpty && name.local == Self.xmlnsPrefix { return }
        // Go's `translate` falls back to `DefaultSpace` for a name with no prefix; the reference
        // never sets that field, so the fallback would assign the empty string and change nothing.
        if let declared = namespaces[name.namespace] { name.namespace = declared }
    }
}
