// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/xml (Apache-2.0); adapted for Swift/SQLite. The primitives
// are the ones `encoding/xml`'s `Decoder` reads through: `getc`/`ungetc`, `space`, `readName`,
// `name`, `nsname`, `text`, `attrval` and `readEntity`.

import Foundation

/// The byte cursor and the lexical primitives the tokenizer reads through.
///
/// The end of the document is recorded as the failure as soon as `getc` reaches it, but a primitive
/// that can return what it has read — `text` outside a CDATA section — still does, and the failure
/// is reported on the next read, which is where `mustgetc` differs. Names and text are built in
/// ``buffer``, which the tokenizer also writes into when it reads a comment or a directive:
/// `readName` does not clear it, so a name read while a character reference is being read still
/// starts where the reference started.
final class XMLScanner {
    /// The failure recorded so far, which is the only failure the primitives report.
    var failure: XMLError?

    private let bytes: [UInt8]
    private var position = 0
    var buffer: [UInt8] = []

    init(_ data: Data) {
        bytes = [UInt8](data)
    }

    // MARK: - Cursor

    /// Reads one byte, or records the end of the document as the failure, which is what `getc`
    /// does: once a failure is recorded nothing more is read. A primitive that can still return
    /// what it has read at the end — `text` outside a CDATA section — does so, and the failure is
    /// reported on the next read, which is where `mustgetc` differs from `getc`.
    func readByte() -> UInt8? {
        if failure != nil { return nil }
        guard position < bytes.count else {
            failure = .unexpectedEOF
            return nil
        }
        let byte = bytes[position]
        position += 1
        return byte
    }

    /// Puts the byte back. Once a failure is recorded the reference never reads again, so putting a
    /// byte back changes nothing there; `ungetc` itself does not look at the failure, which is why
    /// this is an equivalence rather than the same function.
    func unreadByte() {
        if failure != nil { return }
        position -= 1
    }

    // MARK: - Names

    /// Skips whitespace, which for the reference is only space, tab, line feed and carriage return.
    func skipSpace() {
        while let byte = readByte() {
            if byte == XMLByte.space || byte == XMLByte.tab || byte == XMLByte.lineFeed
                || byte == XMLByte.carriageReturn {
                continue
            }
            unreadByte()
            return
        }
    }

    /// Reads a name into the buffer without clearing it.
    func readName() -> Bool {
        guard let byte = readByte() else { return false }
        if isASCII(byte) && !XMLName.isNameByte(byte) {
            unreadByte()
            return false
        }
        buffer.append(byte)
        while true {
            guard let next = readByte() else { return false }
            if isASCII(next) && !XMLName.isNameByte(next) {
                unreadByte()
                break
            }
            buffer.append(next)
        }
        return true
    }

    /// Reads a name from a cleared buffer, which is what `name` does.
    func name() -> String? {
        buffer.removeAll(keepingCapacity: true)
        guard readName() else { return nil }
        let text = String(decoding: buffer, as: UTF8.self)
        guard XMLName.isValidName(text) else {
            failure = .invalidXMLName(text)
            return nil
        }
        return text
    }

    /// Reads a name and splits the prefix from the local part, which is what `nsname` does: with
    /// more than one colon there is no name, and an empty part on either side leaves the whole text
    /// as the local part.
    func namespaceName() -> XMLName? {
        guard let text = name() else { return nil }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count > 2 { return nil }
        var name = XMLName(namespace: "", local: text)
        if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
            name.namespace = String(parts[0])
            name.local = String(parts[1])
        }
        return name
    }

    // MARK: - Comments

    /// Whether the next bytes are the opening of a comment, which is what the directive reader asks
    /// before it skips one. When the match fails, the characters that matched are written to the
    /// buffer and the one that stopped it is put back, because the directive keeps it and handles
    /// it again: a `>` in it still counts against the nesting.
    func startsComment() -> Bool {
        let opening = Array("!--".utf8)
        var matched = 0
        for expected in opening {
            guard let byte = readByte() else { return false }
            guard byte == expected else {
                buffer.append(contentsOf: opening[0..<matched])
                unreadByte()
                return false
            }
            matched += 1
        }
        return true
    }

    func skipToCommentEnd() {
        var previous: UInt8 = 0
        var previousPrevious: UInt8 = 0
        while true {
            guard let byte = readByte() else { return }
            if previousPrevious == XMLByte.hyphen && previous == XMLByte.hyphen
                && byte == XMLByte.greaterThan {
                return
            }
            previousPrevious = previous
            previous = byte
        }
    }

    // MARK: - Text

    /// Reads text up to the closing quote, the end of a CDATA section, a `<` outside one, or the
    /// end of the document. Character references are decoded, and unescaped carriage returns become
    /// line feeds.
    func text(quote: UInt8?, cdata: Bool) -> String? {
        buffer.removeAll(keepingCapacity: true)
        var previous: UInt8 = 0
        var previousPrevious: UInt8 = 0
        var truncated = 0
        input: while true {
            guard let byte = readByte() else {
                // In a CDATA section the end of the document is reported; ordinary text returns
                // what it has read, which is what `text` does when `getc` fails.
                if cdata { return nil }
                break input
            }
            if previousPrevious == XMLByte.rightBracket && previous == XMLByte.rightBracket
                && byte == XMLByte.greaterThan {
                if cdata {
                    truncated = 2
                    break input
                }
                failure = .unescapedBracketInText
                return nil
            }
            if byte == XMLByte.lessThan && !cdata {
                if quote != nil {
                    failure = .unescapedAngleInAttributeValue
                    return nil
                }
                unreadByte()
                break input
            }
            if quote == byte { break input }
            if byte == XMLByte.ampersand && !cdata {
                if !appendCharacterReference(startingAt: buffer.count) { return nil }
                previousPrevious = 0
                previous = 0
                continue
            }
            if byte == XMLByte.carriageReturn {
                buffer.append(XMLByte.lineFeed)
            } else if previous != XMLByte.carriageReturn || byte != XMLByte.lineFeed {
                buffer.append(byte)
            }
            previousPrevious = previous
            previous = byte
        }
        buffer.removeSubrange((buffer.count - truncated)..<buffer.count)
        return checkCharacterProduction()
    }

    /// Writes one character reference to the buffer with its `&` already in it: the character it
    /// resolves to, or the reference as written when it does not. Returns whether the read is
    /// clean, which is the difference between leaving the text as read and reporting the failure.
    private func appendCharacterReference(startingAt start: Int) -> Bool {
        buffer.append(XMLByte.ampersand)
        if let resolved = characterReference(startingAfter: start) {
            buffer.removeSubrange(start..<buffer.count)
            buffer.append(contentsOf: String(resolved).utf8)
            return true
        }
        return failure == nil
    }

    /// Checks the text against XML's `Char` production, which `text` does after reading it. The
    /// document is filtered before tokenizing, so this is reached only through a numeric character
    /// reference, whose value is not part of the document's bytes.
    private func checkCharacterProduction() -> String? {
        let text = String(decoding: buffer, as: UTF8.self)
        for scalar in text.unicodeScalars where !FeedCharset.isXMLCharacter(scalar) {
            failure = .illegalCharacterCode(scalar.value)
            return nil
        }
        return text
    }

    // MARK: - Character classes

    private func isASCII(_ byte: UInt8) -> Bool { byte < 0x80 }

    private func isDigit(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
    }

    private func isHexLetter(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "f")
            || byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "F")
    }

    /// Consumes one character reference with its `&` already in the buffer, and returns the
    /// character it resolves to. Non-strict mode keeps the reference as written when it does not
    /// resolve.
    private func characterReference(startingAfter ampersandIndex: Int) -> Unicode.Scalar? {
        guard let byte = readByte() else { return nil }
        if byte == XMLByte.hash {
            buffer.append(XMLByte.hash)
            guard var current = readByte() else { return nil }
            var base = 10
            if current == XMLByte.lowercaseX {
                base = 16
                buffer.append(current)
                guard let next = readByte() else { return nil }
                current = next
            }
            let digitsStart = buffer.count
            while isDigit(current) || base == 16 && isHexLetter(current) {
                buffer.append(current)
                guard let next = readByte() else { return nil }
                current = next
            }
            guard current == XMLByte.semicolon else {
                unreadByte()
                return nil
            }
            let digits = String(decoding: buffer[digitsStart...], as: UTF8.self)
            buffer.append(XMLByte.semicolon)
            guard let value = UInt32(digits, radix: base), value <= 0x10FFFF else { return nil }
            // A surrogate is not a character, but the reference writes `string(rune(n))` for it,
            // which is the replacement character.
            if value >= 0xD800 && value <= 0xDFFF { return Unicode.Scalar(0xFFFD) }
            return Unicode.Scalar(value)
        }

        unreadByte()
        if !readName() && failure != nil { return nil }
        guard let byte = readByte() else { return nil }
        guard byte == XMLByte.semicolon else {
            unreadByte()
            return nil
        }
        // The name is read from the buffer before the `;` is added to it.
        let entity = String(decoding: buffer[(ampersandIndex + 1)...], as: UTF8.self)
        buffer.append(XMLByte.semicolon)
        guard XMLName.isValidName(entity) else { return nil }
        return XMLEntityTable.resolve(entity)
    }
}
