// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/encoding/encoding.go (Apache-2.0); adapted for
// Swift/SQLite. The detection order follows golang.org/x/net/html/charset, and the tag scanner
// follows the HTML tokenizer rules that its `prescan` relies on.

import Foundation

/// Detection of a document's encoding, ported from the reference's two paths through
/// `golang.org/x/net/html/charset`.
enum CharsetDetection {
    /// Port of `charset.DetermineEncoding` over the first 1024 bytes of a document.
    ///
    /// The order of the steps is the reference's: a byte-order mark, then the `charset`
    /// parameter of the content type, then a `<meta>` prescan, then a "looks like UTF-8"
    /// heuristic, then the `windows-1252` default.
    ///
    /// - Returns: The encoding to decode with, or `nil` when the reference uses `encoding.Nop`
    ///   and the document passes through unchanged.
    static func detectedEncoding(preview: Data, contentType: String?) -> CharsetEncoding? {
        if preview.starts(with: [0xFE, 0xFF]) { return .utf16be }
        if preview.starts(with: [0xFF, 0xFE]) { return .utf16le }
        if preview.starts(with: [0xEF, 0xBB, 0xBF]) { return .utf8 }

        if let charset = contentTypeCharset(contentType), let encoding = CharsetEncoding.named(charset) {
            return encoding
        }

        if let encoding = metaPrescan(preview) {
            // `prescan` maps a utf-16 declaration to `encoding.Nop`, so those bytes are not
            // decoded; `nil` here means the same thing.
            if encoding.rawValue.hasPrefix("utf-16") { return nil }
            return encoding
        }

        // The reference returns `encoding.Nop` when the preview looks like UTF-8, so those bytes
        // pass through unchanged even when the whole document is not valid UTF-8.
        if looksLikeUTF8(preview) { return nil }
        return .windows1252
    }

    /// Extracts the `charset` parameter of a content type, if it has a usable one.
    ///
    /// The reference parses the header with `mime.ParseMediaType`; this is the same parameter
    /// lookup for the shapes HTTP headers actually have, tolerating parameter order and both
    /// quoted and unquoted values.
    static func contentTypeCharset(_ contentType: String?) -> String? {
        guard let contentType else { return nil }
        for parameter in contentType.split(separator: ";").dropFirst() {
            let pieces = parameter.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pieces.count == 2, pieces[0].trimmingCharacters(in: .whitespaces).lowercased() == "charset" else {
                continue
            }
            var value = pieces[1].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// Port of `xml.getEncoding`: the value of the first `encoding=` assignment in the data.
    ///
    /// Like the reference, this scans the whole document rather than only the prolog, and
    /// returns `nil` unless the value is quoted.
    static func declaredEncoding(in data: Data) -> String? {
        let bytes = [UInt8](data)
        guard let start = find(bytes, of: Array("encoding=".utf8), from: 0) else { return nil }
        let quoteIndex = start + 9
        guard quoteIndex < bytes.count else { return nil }
        let quote = bytes[quoteIndex]
        guard quote == UInt8(ascii: "'") || quote == UInt8(ascii: "\"") else { return nil }
        guard let end = find(bytes, of: [quote], from: quoteIndex + 1) else { return nil }
        return String(decoding: bytes[(quoteIndex + 1)..<end], as: UTF8.self)
    }

    // MARK: - UTF-8 heuristic

    /// Port of the trailing "try to detect UTF-8" step of `DetermineEncoding`.
    private static func looksLikeUTF8(_ preview: Data) -> Bool {
        var bytes = [UInt8](preview)
        for offset in 0..<min(3, bytes.count) {
            let byte = bytes[bytes.count - 1 - offset]
            if byte < 0x80 { break }
            if byte & 0xC0 != 0x80 { // a rune start, so everything after it may be truncated
                bytes.removeLast(offset + 1)
                break
            }
        }
        guard bytes.contains(where: { $0 >= 0x80 }) else { return false }
        return String(data: Data(bytes), encoding: .utf8) != nil
    }

    // MARK: - Meta element prescan

    /// Port of `charset.prescan`: the encoding declared by the first usable `<meta>` element.
    ///
    /// This is a tag scanner rather than a full HTML tokenizer, so malformed markup that the
    /// reference's tokenizer would recover from can end the scan; the shapes real documents
    /// use — comments, both declaration styles, quoting — are all handled.
    static func metaPrescan(_ preview: Data) -> CharsetEncoding? {
        let bytes = [UInt8](preview)
        var index = 0
        while index < bytes.count {
            guard bytes[index] == UInt8(ascii: "<") else {
                index += 1
                continue
            }
            if matches(bytes, at: index, of: Array("<!--".utf8)) {
                guard let end = find(bytes, of: Array("-->".utf8), from: index + 4) else { return nil }
                index = end + 3
                continue
            }
            let next = index + 1
            guard next < bytes.count else { return nil }
            if bytes[next] == UInt8(ascii: "!") || bytes[next] == UInt8(ascii: "?") || bytes[next] == UInt8(ascii: "/") {
                guard let end = tagEnd(bytes, from: next) else { return nil }
                index = end
                continue
            }
            guard isASCIILetter(bytes[next]) else {
                index += 1
                continue
            }
            guard let tag = parseTag(bytes, from: index) else { return nil }
            index = tag.end
            if tag.name == "meta", let encoding = metaEncoding(tag.attributes) {
                return encoding
            }
        }
        return nil
    }

    private struct Tag {
        let name: String
        let attributes: [(String, String)]
        let end: Int
    }

    /// Parses a start tag at `start`, returning `nil` when the preview ends inside the tag.
    private static func parseTag(_ bytes: [UInt8], from start: Int) -> Tag? {
        var index = start + 1
        let nameStart = index
        while index < bytes.count, isNameByte(bytes[index]) { index += 1 }
        let name = lowercaseASCII(bytes[nameStart..<index])
        var attributes: [(String, String)] = []
        while true {
            while index < bytes.count, isHTMLWhitespace(bytes[index]) { index += 1 }
            guard index < bytes.count else { return nil }
            if bytes[index] == UInt8(ascii: ">") || bytes[index] == UInt8(ascii: "/") {
                if bytes[index] == UInt8(ascii: "/") {
                    index += 1
                    guard index < bytes.count, bytes[index] == UInt8(ascii: ">") else { continue }
                }
                return Tag(name: name, attributes: attributes, end: index + 1)
            }
            let attributeName = nameUpToDelimiter(bytes, from: &index)
            while index < bytes.count, isHTMLWhitespace(bytes[index]) { index += 1 }
            guard index < bytes.count, bytes[index] == UInt8(ascii: "=") else {
                attributes.append((attributeName, ""))
                continue
            }
            index += 1
            while index < bytes.count, isHTMLWhitespace(bytes[index]) { index += 1 }
            guard index < bytes.count else { return nil }
            let value = valueUpToDelimiter(bytes, from: &index)
            attributes.append((attributeName, value))
        }
    }

    /// Reads an attribute name, stopping at the delimiters the tokenizer recognizes.
    private static func nameUpToDelimiter(_ bytes: [UInt8], from index: inout Int) -> String {
        let start = index
        while index < bytes.count, !isHTMLWhitespace(bytes[index]),
              bytes[index] != UInt8(ascii: "="), bytes[index] != UInt8(ascii: ">"),
              bytes[index] != UInt8(ascii: "/") {
            index += 1
        }
        return lowercaseASCII(bytes[start..<index])
    }

    /// Reads an attribute value, quoted or unquoted, exactly as `Tokenizer.TagAttr` does,
    /// returning the lowercase form the reference compares against.
    private static func valueUpToDelimiter(_ bytes: [UInt8], from index: inout Int) -> String {
        let quote = bytes[index]
        if quote != UInt8(ascii: "\"") && quote != UInt8(ascii: "'") {
            let start = index
            while index < bytes.count, !isHTMLWhitespace(bytes[index]), bytes[index] != UInt8(ascii: ">") {
                index += 1
            }
            return lowercaseASCII(bytes[start..<index])
        }
        index += 1
        let start = index
        while index < bytes.count, bytes[index] != quote { index += 1 }
        let value = lowercaseASCII(bytes[start..<index])
        index = min(index + 1, bytes.count)
        return value
    }

    private enum PragmaNeed {
        case unknown
        case needed
        case notNeeded
    }

    /// Port of the meta handler of `charset.prescan`.
    ///
    /// - Returns: The declared encoding, or `nil` when this element does not declare a usable
    ///   one and the scan has to continue.
    private static func metaEncoding(_ attributes: [(String, String)]) -> CharsetEncoding? {
        var encoding: CharsetEncoding?
        var gotPragma = false
        var needPragma = PragmaNeed.unknown
        var seen = Set<String>()
        for (name, value) in attributes {
            if seen.contains(name) { continue }
            seen.insert(name)
            switch name {
            case "http-equiv":
                if value == "content-type" { gotPragma = true }
            case "content":
                if encoding == nil {
                    let label = fromMetaContent(value)
                    if !label.isEmpty {
                        encoding = CharsetEncoding.named(label)
                        if encoding != nil { needPragma = .needed }
                    }
                }
            case "charset":
                encoding = CharsetEncoding.named(value)
                needPragma = .notNeeded
            default:
                break
            }
        }
        if needPragma == .unknown || (needPragma == .needed && !gotPragma) { return nil }
        return encoding
    }

    /// Port of `charset.fromMetaElement`: extracts `charset=…` from a `content` attribute.
    private static func fromMetaContent(_ value: String) -> String {
        let whitespace = " \t\n\u{0C}\r"
        var text = Substring(value)
        while !text.isEmpty {
            guard let range = text.range(of: "charset") else { return "" }
            text = text[range.upperBound...]
            text = text.drop(while: { whitespace.contains($0) })
            guard text.first == "=" else { continue }
            text = text.dropFirst()
            text = text.drop(while: { whitespace.contains($0) })
            guard let first = text.first else { return "" }
            if first == "\"" || first == "'" {
                text = text.dropFirst()
                guard let closing = text.firstIndex(of: first) else { return "" }
                return String(text[text.startIndex..<closing])
            }
            if let end = text.firstIndex(where: { whitespace.contains($0) || $0 == ";" }) {
                return String(text[text.startIndex..<end])
            }
            return String(text)
        }
        return ""
    }

    // MARK: - Byte helpers

    /// Finds the first occurrence of `pattern` at or after `from`.
    private static func find(_ bytes: [UInt8], of pattern: [UInt8], from: Int) -> Int? {
        guard !pattern.isEmpty, bytes.count >= pattern.count, from <= bytes.count - pattern.count else {
            return nil
        }
        for start in from...(bytes.count - pattern.count) where matches(bytes, at: start, of: pattern) {
            return start
        }
        return nil
    }

    private static func matches(_ bytes: [UInt8], at index: Int, of pattern: [UInt8]) -> Bool {
        guard index + pattern.count <= bytes.count else { return false }
        for offset in 0..<pattern.count where bytes[index + offset] != pattern[offset] {
            return false
        }
        return true
    }

    /// Skips a markup declaration or processing instruction, returning the index after `>`.
    private static func tagEnd(_ bytes: [UInt8], from start: Int) -> Int? {
        var index = start
        var quote: UInt8?
        while index < bytes.count {
            let byte = bytes[index]
            if let openQuote = quote {
                if byte == openQuote { quote = nil }
            } else if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
                quote = byte
            } else if byte == UInt8(ascii: ">") {
                return index + 1
            }
            index += 1
        }
        return nil
    }

    private static func isASCIILetter(_ byte: UInt8) -> Bool {
        (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z"))
            || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
    }

    private static func isNameByte(_ byte: UInt8) -> Bool {
        isASCIILetter(byte) || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
            || byte == UInt8(ascii: "-") || byte == UInt8(ascii: "_") || byte == UInt8(ascii: ":")
    }

    private static func isHTMLWhitespace(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || byte == UInt8(ascii: "\n")
            || byte == UInt8(ascii: "\r") || byte == 0x0C
    }

    private static func lowercaseASCII(_ bytes: ArraySlice<UInt8>) -> String {
        String(decoding: bytes.map { byte in
            (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z")) ? byte + 0x20 : byte
        }, as: UTF8.self)
    }
}
