// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/sanitizer (`srcset.go`) (Apache-2.0); adapted for
// Swift/SQLite.

import Foundation

/// The srcset attribute parser, the rule `ParseSrcSetAttribute` implements, which follows the
/// WebKit `HTMLSrcsetParser` behaviour and the WHATWG "parse a srcset attribute" algorithm.
///
/// A candidate is the URL up to the first ASCII whitespace, then its descriptors. A candidate whose
/// descriptors do not parse is not a candidate at all. The sanitizer resolves each candidate
/// through the URL layer and drops the ones the scheme allowlist or the blocked resources reject.
enum SrcSetParser {
    /// The candidates of an attribute value, in the order they are read.
    static func parse(_ attributeValue: String) -> [ImageCandidate] {
        if attributeValue.isEmpty { return [] }

        let chars = Array(attributeValue)
        var candidates: [ImageCandidate] = []
        var position = 0

        while position < chars.count {
            position = skipWhileSpaceOrComma(chars, position)
            if position >= chars.count { break }

            let urlStart = position
            position = skipUntilWhitespace(chars, position)
            let imageURL = String(chars[urlStart..<position])
            if imageURL.isEmpty { continue }

            var result = DescriptorResult()
            if imageURL.hasSuffix(",") {
                var trimmed = imageURL
                while trimmed.hasSuffix(",") { trimmed.removeLast() }
                if trimmed.isEmpty { continue }
                candidates.append(ImageCandidate(imageURL: trimmed, descriptor: ""))
                continue
            }

            position = skipWhileWhitespace(chars, position)
            let tokens = tokenizeDescriptors(chars, from: position)
            position = tokens.position
            guard parseDescriptors(tokens.tokens, into: &result) else { continue }
            candidates.append(ImageCandidate(imageURL: imageURL, descriptor: serialize(result)))
        }

        return candidates
    }

    /// The value the sanitizer writes back for an attribute: every candidate that resolves to an
    /// allowed URL, joined the way the reference joins them.
    static func sanitized(base: ParsedURL?, value: String) -> String {
        let candidates = parse(value)
        if candidates.isEmpty { return "" }

        var kept: [ImageCandidate] = []
        for candidate in candidates {
            guard let absolute = try? URLResolution.resolveToAbsolute(parsedBase: base, relative: candidate.imageURL)
            else { continue }
            if !URISchemeAllowlist.hasValidScheme(absolute) || SanitizerAllowlists.isBlockedResource(absolute) {
                continue
            }
            kept.append(ImageCandidate(imageURL: absolute, descriptor: candidate.descriptor))
        }

        return kept.map { $0.description }.joined(separator: ", ")
    }

    // MARK: - Descriptors

    private struct DescriptorResult {
        var density = 0.0
        var resourceWidth = 0
        var resourceHeight = 0
        var hasDensity = false
        var hasWidth = false
        var hasHeight = false
    }

    private static func serialize(_ result: DescriptorResult) -> String {
        if result.hasDensity { return formatFloat(result.density) + "x" }
        if result.hasWidth { return String(result.resourceWidth) + "w" }
        return ""
    }

    private static func parseDescriptors(_ descriptors: [String], into result: inout DescriptorResult) -> Bool {
        for descriptor in descriptors {
            if descriptor.isEmpty { continue }
            let marker = descriptor.last!
            let value = String(descriptor.dropLast())

            switch marker {
            case "x":
                if result.hasDensity || result.hasHeight || result.hasWidth { return false }
                guard let density = parseFloat(value), density >= 0 else { return false }
                result.density = density
                result.hasDensity = true
            case "w":
                if result.hasDensity || result.hasWidth { return false }
                guard let width = parseNonNegativeInteger(value), width > 0 else { return false }
                result.resourceWidth = width
                result.hasWidth = true
            case "h":
                if result.hasDensity || result.hasHeight { return false }
                guard let height = parseNonNegativeInteger(value), height > 0 else { return false }
                result.resourceHeight = height
                result.hasHeight = true
            default:
                return false
            }
        }

        return !result.hasHeight || result.hasWidth
    }

    /// The descriptor tokenizer, the state machine `tokenizeDescriptors` implements: tokens are
    /// split by whitespace, a comma ends the descriptor list, and a pair of parentheses keeps what
    /// is inside it together, which is the `calc(1x, 2x)` case.
    private static func tokenizeDescriptors(_ chars: [Character], from start: Int) -> (tokens: [String], position: Int) {
        var tokens: [String] = []
        var state = DescriptorState.initial
        var tokenStart = start
        var hasToken = true
        var position = start

        func append(through end: Int) {
            if hasToken && end > tokenStart { tokens.append(String(chars[tokenStart..<end])) }
            hasToken = false
        }

        while position < chars.count {
            let char = chars[position]
            switch state {
            case .initial:
                if char == "," {
                    append(through: position)
                    return (tokens, position + 1)
                }
                if isWhitespace(char) {
                    append(through: position)
                    tokenStart = position + 1
                    hasToken = true
                    state = .afterToken
                } else if char == "(" {
                    state = .inParenthesis
                }
            case .inParenthesis:
                if char == ")" { state = .initial }
            case .afterToken:
                if !isWhitespace(char) {
                    state = .initial
                    tokenStart = position
                    hasToken = true
                    position -= 1
                }
            }
            position += 1
        }

        if state != .afterToken { append(through: position) }
        return (tokens, position)
    }

    private enum DescriptorState {
        case initial
        case inParenthesis
        case afterToken
    }

    private static func parseNonNegativeInteger(_ value: String) -> Int? {
        if value.isEmpty { return nil }
        guard value.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return nil }
        return Int(value)
    }

    /// The valid HTML floating point number rule: a leading `+` or a trailing `.` is not one, and
    /// neither is a value that is not finite.
    private static func parseFloat(_ value: String) -> Double? {
        if value.isEmpty { return nil }
        if value.first == "+" || value.last == "." { return nil }
        guard let parsed = Double(value), parsed.isFinite else { return nil }
        return parsed
    }

    /// The reference formats the density with `strconv.FormatFloat(value, 'g', -1, 64)`, the
    /// shortest form that round-trips; an integral value is written without the fractional part.
    private static func formatFloat(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e16 { return String(Int64(value)) }
        return String(value)
    }

    // MARK: - Positions

    private static func skipWhileSpaceOrComma(_ chars: [Character], _ position: Int) -> Int {
        var cursor = position
        while cursor < chars.count, isWhitespace(chars[cursor]) || chars[cursor] == "," { cursor += 1 }
        return cursor
    }

    private static func skipWhileWhitespace(_ chars: [Character], _ position: Int) -> Int {
        var cursor = position
        while cursor < chars.count, isWhitespace(chars[cursor]) { cursor += 1 }
        return cursor
    }

    private static func skipUntilWhitespace(_ chars: [Character], _ position: Int) -> Int {
        var cursor = position
        while cursor < chars.count, !isWhitespace(chars[cursor]) { cursor += 1 }
        return cursor
    }

    private static func isWhitespace(_ char: Character) -> Bool {
        char == "\t" || char == "\n" || char == "\u{0C}" || char == "\r" || char == " "
    }
}
