// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/sanitizer, which reads through golang.org/x/net/html
// (`token.go`) (Apache-2.0 / BSD-3-Clause); adapted for Swift/SQLite.

import Foundation

/// The HTML tokenizer the sanitizer reads through.
///
/// The states the reference has are the ones this port reads through: data, tag open, the attribute
/// key and value states, the self-closing start tag state, the character reference state, the raw
/// text states and the comment state. Two of the reference's states are not ported, because the
/// sanitizer answers without them: CDATA, which the reference enters only inside foreign content,
/// and the script escaping states, which change nothing for a tag the sanitizer drops. Where the
/// subset stops is recorded in `docs/parity.md`.
final class HTMLTokenizer {
    /// The elements whose content is read as data rather than as markup, the list `readStartTag`
    /// uses to flag the next token as raw.
    static let rawTextTags: Set<String> = [
        "iframe", "noembed", "noframes", "noscript", "plaintext", "script", "style", "textarea",
        "title", "xmp",
    ]

    private let chars: [Character]
    private var position = 0
    private var rawTag: String?
    private var pendingToken: HTMLToken?

    init(_ input: String) {
        chars = Array(input)
    }

    /// Reads the next token, or nothing at the end of the input, which is where the reference
    /// reports the end of the reader.
    func next() -> HTMLToken? {
        if let token = pendingToken {
            pendingToken = nil
            return token
        }
        if let rawTag {
            return readRawToken(rawTag)
        }
        return readDataOrTag()
    }

    // MARK: - Data state

    private func readDataOrTag() -> HTMLToken? {
        let textStart = position
        while position < chars.count {
            if chars[position] != "<" {
                position += 1
                continue
            }

            let tagStart = position
            position += 1
            guard position < chars.count else { break }

            guard let kind = tagKind(after: chars[position], at: position) else {
                // The `<` does not begin a tag, so it stays in the text and the scan resumes after
                // it, which is the reconsumption `Next` does.
                continue
            }

            let token = parseTag(startedAt: tagStart, kind: kind)
            // A non-text token can have text accumulated before it, and the reference returns that
            // text first and the token on the next call.
            if textStart < tagStart {
                pendingToken = token
                return HTMLToken(kind: .text, data: normalize(String(chars[textStart..<tagStart]),
                    decoded: true, attribute: false, nulToReplacement: false))
            }
            return token
        }

        if textStart < position {
            return HTMLToken(kind: .text, data: normalize(String(chars[textStart..<position]),
                decoded: true, attribute: false, nulToReplacement: false))
        }
        return nil
    }

    /// The three cases `Next` answers with: a tag, an end tag, or anything that starts with `!` or
    /// `?`, which the reference reports as a comment. `</>` generates no tag at all, so it is a
    /// comment too.
    private func tagKind(after char: Character, at index: Int) -> HTMLToken.Kind? {
        if isAsciiLetter(char) { return .startTag }
        if char == "!" || char == "?" { return .comment }
        if char != "/" { return nil }
        if index + 1 < chars.count && isAsciiLetter(chars[index + 1]) { return .endTag }
        return .comment
    }

    private func parseTag(startedAt: Int, kind: HTMLToken.Kind) -> HTMLToken {
        if kind == .comment {
            // The data starts after `<!`, which is where `readMarkupDeclaration` sets it.
            return HTMLToken(kind: .comment, data: readComment(from: startedAt + 2))
        }

        let name = readTagName(startedAt: startedAt, endTag: kind == .endTag)
        let attributes = readAttributes(endTag: kind == .endTag)
        var tokenKind = kind
        if kind == .startTag && isSelfClosingToken(attributes: attributes) {
            tokenKind = .selfClosingStartTag
        }
        if kind == .startTag && HTMLTokenizer.rawTextTags.contains(name) {
            rawTag = name
        }
        return HTMLToken(kind: tokenKind, name: name, attributes: attributes)
    }

    // MARK: - Tag states

    /// The tag name, read to its delimiter, which the attribute state then consumes. `TagName`
    /// replaces NUL with U+FFFD and lower-cases the name, but it converts no newline and decodes no
    /// character reference, which is the one name rule that is not the conversion the data states
    /// apply.
    private func readTagName(startedAt: Int, endTag: Bool) -> String {
        var index = startedAt + (endTag ? 2 : 1)
        let nameStart = index
        while index < chars.count, !isTagDelimiter(chars[index]) { index += 1 }
        position = index
        let name = String(chars[nameStart..<index])
            .replacingOccurrences(of: "\u{00}", with: "\u{FFFD}")
        return lower(name)
    }

    /// The attribute key and value states, read until the close angle, which is consumed here. A
    /// name that is empty or already seen is not saved, as `readTag` only saves the first of each
    /// name, and for an end tag nothing is saved at all: the states are still read, so the input is
    /// consumed the same way.
    private func readAttributes(endTag: Bool) -> [HTMLAttribute] {
        var attributes: [HTMLAttribute] = []
        var seen = Set<String>()
        skipWhiteSpace()

        while position < chars.count {
            guard chars[position] != ">" else { position += 1; break }

            let keyStart = position
            while position < chars.count {
                let char = chars[position]
                // An equals sign seen before the name begins is a character of the name.
                if char == "=" && position > keyStart { break }
                if isSpace(char) || char == "/" || char == ">" { break }
                position += 1
            }
            let key = lower(normalize(String(chars[keyStart..<position]), decoded: false, attribute: false,
                nulToReplacement: true))

            let value = readAttributeValue()
            if !endTag && !key.isEmpty && !seen.contains(key) {
                attributes.append(HTMLAttribute(name: key, value: value.value))
                seen.insert(key)
            }

            // `readStartTag` compares the last character before the close angle with the last
            // character of the last value read.
            if !key.isEmpty { lastValueEnd = value.endMinusOne }
            skipWhiteSpace()
        }

        return attributes
    }

    /// The value state: `=` starts it, a quote closes it, and whitespace or `>` ends an unquoted
    /// one. A solidus where a value would begin ends the tag instead. `endMinusOne` is
    /// `pendingAttr[1].end - 1`, the position of the last character of the value.
    private func readAttributeValue() -> (value: String, endMinusOne: Int) {
        guard position < chars.count else { return ("", position - 1) }
        let entry = position

        if chars[position] == "/" {
            position += 1
            return ("", entry - 1)
        }
        guard chars[position] == "=" else { return ("", entry - 1) }

        position += 1
        skipWhiteSpace()
        guard position < chars.count else { return ("", entry) }

        let quote = chars[position]
        if quote == "/" || quote == ">" { return ("", position - 1) }

        if quote == "\"" || quote == "'" {
            position += 1
            let start = position
            while position < chars.count, chars[position] != quote { position += 1 }
            let value = normalize(String(chars[start..<position]), decoded: true, attribute: true,
                nulToReplacement: true)
            let end = position
            if position < chars.count { position += 1 }
            return (value, end - 1)
        }

        let start = position
        while position < chars.count, !isSpace(chars[position]), chars[position] != ">" { position += 1 }
        let value = normalize(String(chars[start..<position]), decoded: true, attribute: true,
            nulToReplacement: true)
        return (value, position - 1)
    }

    /// The check `readStartTag` makes for `<br/>`, with the guard that an attribute value can end
    /// where the self-closing solidus would be, which is the `<p a=/>` case.
    private func isSelfClosingToken(attributes: [HTMLAttribute]) -> Bool {
        guard position >= 2, chars[position - 2] == "/" else { return false }
        return attributes.isEmpty || (position - 2) != lastValueEnd
    }

    private var lastValueEnd = -1

    // MARK: - Comment and raw text states

    /// The comment state. A `>` inside the data does not close the comment: the reference closes it
    /// only after two dashes, `-->` or `--!>`, which is the `dashCount` rule. `<!>` has no data,
    /// and at the end of the input the trailing dashes are not part of it, which is what
    /// `calculateAbruptCommentDataEnd` answers with.
    private func readComment(from index: Int) -> String {
        let dataStart = chars[index...].starts(with: "--") ? index + 2 : index
        var dashCount = 0
        var beginning = true
        var end = index

        while end < chars.count {
            let char = chars[end]
            if char == "-" {
                dashCount += 1
                end += 1
                continue
            }
            if dashCount >= 2 {
                if char == ">" {
                    position = end + 1
                    return commentData(from: dataStart, to: end - 2)
                }
                if char == "!", closedAt(end) {
                    return commentData(from: dataStart, to: end - 2)
                }
                if char == "!", end + 1 < chars.count, chars[end + 1] == "-" {
                    dashCount = 1
                    beginning = false
                    end += 1
                    continue
                }
            }
            if char == ">", beginning {
                position = end + 1
                return commentData(from: dataStart, to: dataStart)
            }
            dashCount = 0
            beginning = false
            end += 1
        }

        position = chars.count
        return commentData(from: dataStart, to: abruptDataEnd(from: dataStart))
    }

    /// `--!>` closes the comment: the position is left past the `>`, and the answer says whether
    /// the bang really closes it or is data.
    private func closedAt(_ bang: Int) -> Bool {
        guard bang + 1 < chars.count, chars[bang + 1] == ">" else { return false }
        position = bang + 2
        return true
    }

    /// `calculateAbruptCommentDataEnd`: at the end of the input the trailing dashes are not data.
    private func abruptDataEnd(from dataStart: Int) -> Int {
        func trailing(_ pattern: String) -> Bool {
            chars.count >= pattern.count
                && String(chars[(chars.count - pattern.count)..<chars.count]) == pattern
        }
        return chars.count - (trailing("--!") ? 3 : trailing("--") ? 2 : trailing("-") ? 1 : 0)
    }

    private func commentData(from start: Int, to end: Int) -> String {
        normalize(String(chars[start..<max(start, end)]), decoded: false, attribute: false,
            nulToReplacement: true)
    }

    private func readRawToken(_ tag: String) -> HTMLToken? {
        let start = position
        if tag == "plaintext" {
            while position < chars.count { position += 1 }
            return HTMLToken(kind: .text, data: normalize(String(chars[start..<position]),
                decoded: false, attribute: false, nulToReplacement: true))
        }

        while position < chars.count {
            if chars[position] == "<", position + 1 < chars.count, chars[position + 1] == "/",
                readRawEndTag(tag, nameAt: position + 2) {
                break
            }
            position += 1
        }
        rawTag = nil
        // A raw text element with no content produces no text token, but the end tag at the current
        // position is still a token, which `Next` reads by falling through. At the end of the input
        // there is nothing left to read.
        if start == position {
            guard position < chars.count else { return nil }
            return parseTag(startedAt: position, kind: .endTag)
        }
        // `textarea` and `title` are the two raw states whose content is still decoded.
        return HTMLToken(kind: .text, data: normalize(String(chars[start..<position]),
            decoded: tag == "textarea" || tag == "title", attribute: false, nulToReplacement: true))
    }

    private func readRawEndTag(_ tag: String, nameAt index: Int) -> Bool {
        var cursor = index
        for char in tag {
            guard cursor < chars.count else { return false }
            // `rawTag` is lower-cased, so the reference accepts the upper-case form of each byte
            // too.
            if !sameAsciiLetter(chars[cursor], char) { return false }
            cursor += 1
        }
        guard cursor < chars.count,
            isSpace(chars[cursor]) || chars[cursor] == "/" || chars[cursor] == ">" else { return false }
        position = index - 2
        return true
    }

    private func sameAsciiLetter(_ read: Character, _ expected: Character) -> Bool {
        guard let a = read.unicodeScalars.first, let b = expected.unicodeScalars.first else {
            return read == expected
        }
        // `rawTag` is lower-cased, so the upper-case form of the byte is accepted too.
        return a == b || (b.value >= 97 && b.value <= 122 && a.value == b.value - 32)
    }

    // MARK: - Character conversion

    /// The conversion `Text` and `TagAttr` apply: newlines normalized, NUL replaced in the states
    /// the reference flags as converting (raw text, comment, doctype) and in an attribute key or
    /// value, which `TagAttr` replaces whatever the state, and character references decoded in the
    /// states that decode them, through the mode the state reads them with. The tag name has its
    /// own rule, which replaces NUL and lower-cases but converts no newline; it is read through
    /// `readTagName`.
    private func normalize(_ value: String, decoded: Bool, attribute: Bool, nulToReplacement: Bool) -> String {
        var out = convertNewlines(value)
        if nulToReplacement { out = out.replacingOccurrences(of: "\u{00}", with: "\u{FFFD}") }
        if decoded { out = HTMLEntities.decode(out, attribute: attribute) }
        return out
    }

    private func convertNewlines(_ value: String) -> String {
        guard value.contains("\r") else { return value }
        return value.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    private func lower(_ value: String) -> String { value.lowercased() }

    private func skipWhiteSpace() {
        while position < chars.count, isSpace(chars[position]) { position += 1 }
    }

    private func isSpace(_ char: Character) -> Bool {
        char == " " || char == "\n" || char == "\r" || char == "\t" || char == "\u{0C}"
    }

    private func isAsciiLetter(_ char: Character) -> Bool { char.isASCII && char.isLetter }

    private func isTagDelimiter(_ char: Character) -> Bool {
        isSpace(char) || char == "/" || char == ">"
    }
}
