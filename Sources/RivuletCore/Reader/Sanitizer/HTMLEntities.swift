// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/sanitizer, which reads through golang.org/x/net/html
// (Apache-2.0 / BSD-3-Clause); adapted for Swift/SQLite.

import Foundation

/// The character references the HTML tokenizer decodes, the rule `unescape` and `unescapeEntity`
/// implement.
///
/// The two modes are the two the reference calls it through: a text token is decoded with
/// `attribute = false` and an attribute value with `attribute = true`. The difference is what a
/// named reference without its semicolon is allowed to be: the data state accepts the short names
/// the table lists without one, while an attribute value leaves the reference alone when the
/// character after it is `=`, so that `a&b=c` is not read as a reference.
enum HTMLEntities {
    /// The positions 0x80–0x9F of the Windows-1252 legacy forms, which `replacementTable` maps to
    /// the UTF-8 equivalents the HTML5 rule uses.
    private static let windows1252: [UInt32] = [
        0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030,
        0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F, 0x0090, 0x2018, 0x2019, 0x201C,
        0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D,
        0x017E, 0x0178,
    ]

    /// The longest named reference the table holds without a semicolon.
    private static let longestNameWithoutSemicolon = 6

    /// Decodes every character reference in a value. A reference that does not resolve stays as the
    /// ampersand it started with.
    static func decode(_ value: String, attribute: Bool) -> String {
        let chars = Array(value)
        guard chars.contains("&") else { return value }

        var out = ""
        var position = 0
        while position < chars.count {
            if chars[position] != "&" {
                out.append(chars[position])
                position += 1
                continue
            }
            let resolved = resolveRun(chars: chars, ampersand: position, attribute: attribute)
            if resolved.length == 1 {
                out.append("&")
                position += 1
                continue
            }
            for scalar in resolved.scalars {
                out.append(Character(scalar))
            }
            position += resolved.length
        }
        return out
    }

    /// The rule `unescapeEntity` applies to one run that starts with the ampersand.
    private static func resolveRun(chars: [Character], ampersand: Int, attribute: Bool)
        -> (scalars: [Unicode.Scalar], length: Int) {
        guard ampersand + 1 < chars.count else { return (["&"], 1) }
        if chars[ampersand + 1] == "#" {
            guard ampersand + 2 < chars.count else { return (["&"], 1) }
            return resolveNumeric(chars: chars, ampersand: ampersand, digitsFrom: ampersand + 2)
        }

        var position = ampersand + 1
        while position < chars.count {
            let char = chars[position]
            if char.isASCII && (char.isLetter || char.isNumber) {
                position += 1
                continue
            }
            // The reader is already past the character it stopped on, so a semicolon stays part of
            // the name and any other character is put back.
            if char == ";" { position += 1 }
            break
        }

        let name = String(chars[(ampersand + 1)..<position])
        if name.isEmpty { return (["&"], 1) }
        if attribute && !name.hasSuffix(";") && position < chars.count && chars[position] == "=" {
            return (["&"], 1)
        }
        if let scalar = HTMLEntityTable.resolve(name) {
            return ([scalar], position - ampersand)
        }
        if let pair = HTMLEntityTable.resolvePair(name) {
            return ([pair.0, pair.1], position - ampersand)
        }
        if !attribute {
            let limit = min(name.count - 1, longestNameWithoutSemicolon)
            for length in stride(from: limit, through: 2, by: -1) {
                if let scalar = HTMLEntityTable.resolve(String(name.prefix(length))) {
                    return ([scalar], length + 1)
                }
            }
        }
        return (["&"], 1)
    }

    /// The numeric form: decimal, or hex after `x` or `X`. The semicolon is consumed when it is
    /// there, but it is not required.
    private static func resolveNumeric(chars: [Character], ampersand: Int, digitsFrom: Int)
        -> (scalars: [Unicode.Scalar], length: Int) {
        let hex = chars[digitsFrom] == "x" || chars[digitsFrom] == "X"
        var position = digitsFrom
        if hex { position += 1 }
        let digitsStart = position

        var value: UInt32 = 0
        while position < chars.count, let digit = digitValue(chars[position], hex: hex) {
            if value <= 0x10FFFF { value = (hex ? 16 : 10) * value + digit }
            position += 1
        }
        if position == digitsStart { return (["&"], 1) }

        if position < chars.count && chars[position] == ";" { position += 1 }

        if value >= 0x80 && value <= 0x9F {
            value = windows1252[Int(value) - 0x80]
        } else if value == 0 || (value >= 0xD800 && value <= 0xDFFF) || value > 0x10FFFF {
            value = 0xFFFD
        }
        return ([Unicode.Scalar(value)!], position - ampersand)
    }

    private static func digitValue(_ char: Character, hex: Bool) -> UInt32? {
        guard let scalar = char.unicodeScalars.first, scalar.isASCII else { return nil }
        if scalar.value >= 48 && scalar.value <= 57 { return scalar.value - 48 }
        guard hex else { return nil }
        if scalar.value >= 97 && scalar.value <= 102 { return scalar.value - 97 + 10 }
        if scalar.value >= 65 && scalar.value <= 70 { return scalar.value - 65 + 10 }
        return nil
    }
}
