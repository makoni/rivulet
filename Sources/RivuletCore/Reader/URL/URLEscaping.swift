// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Go's standard library `net/url` (`shouldEscape`, `escape`, `unescape`,
// `validEncoded`), the modes the reader reaches; adapted for Swift/SQLite.

import Foundation

/// Percent-encoding as Go's `net/url` applies it, for the modes the reader reaches: the path, a
/// query component, a fragment, a host and the user part of an authority. The character classes are
/// Go's, as `gen_encoding_table.go` defines them: alphanumerics and the four marks are never
/// escaped, the sub-delimiters are escaped outside the host, and each mode decides what its
/// reserved set allows.
///
/// The work is byte-level, as Go's is, so a decoded value is rebuilt from UTF-8 bytes. Bytes that
/// are not valid UTF-8 become the replacement character, which is the deviation recorded in
/// `docs/parity.md`.
enum URLEscaping {
    enum Mode {
        case path, queryComponent, fragment, host, userPassword

        /// In Go, `unescape` turns a `+` into a space only for a query component.
        var plusIsSpace: Bool { self == .queryComponent }
    }

    static func shouldEscape(_ byte: UInt8, mode: Mode) -> Bool {
        if isAlphanumeric(byte) { return false }

        if mode == .host && hostClass.contains(byte) { return false }

        if marks.contains(byte) { return false }

        if reserved.contains(byte) {
            switch mode {
            case .path: return byte == UInt8(ascii: "?")
            case .queryComponent: return true
            case .fragment: return false
            case .userPassword:
                return byte == UInt8(ascii: "@") || byte == UInt8(ascii: "/") ||
                    byte == UInt8(ascii: "?") || byte == UInt8(ascii: ":")
            case .host: return true
            }
        }

        // Go always escapes sub-delimiters outside the host, and always escapes a single quote in a
        // fragment, so that callers that assumed it was escaped keep working.
        if mode == .fragment && fragmentSubDelimiters.contains(byte) { return false }

        return true
    }

    static func escape(_ value: String, mode: Mode) -> String {
        var result = [UInt8]()
        for byte in Array(value.utf8) {
            if !shouldEscape(byte, mode: mode) {
                result.append(byte)
            } else if byte == UInt8(ascii: " ") && mode == .queryComponent {
                result.append(UInt8(ascii: "+"))
            } else {
                result.append(contentsOf: percentEncoding(byte))
            }
        }
        return String(decoding: result, as: UTF8.self)
    }

    /// Go's `unescape`, in its two passes: the value is checked over the whole string before
    /// anything is decoded, which is why a host is refused for a character it must escape even when
    /// there is nothing to decode. A value with nothing to decode is then returned as it was read,
    /// which is what the reference's fast path does.
    static func unescape(_ value: String, mode: Mode) throws -> String {
        let bytes = Array(value.utf8)
        let checked = try check(bytes, mode: mode)
        if checked.escapes == 0 && !checked.hasPlus { return value }

        var result = [UInt8]()
        var index = 0
        while index < bytes.count {
            switch bytes[index] {
            case UInt8(ascii: "%"):
                result.append(UInt8(hexValue(bytes[index + 1]) * 16 + hexValue(bytes[index + 2])))
                index += 3
            case UInt8(ascii: "+"):
                result.append(mode.plusIsSpace ? UInt8(ascii: " ") : bytes[index])
                index += 1
            default:
                result.append(bytes[index])
                index += 1
            }
        }
        return String(decoding: result, as: UTF8.self)
    }

    /// Go's first pass: every escape is checked for being well formed, and in the host component
    /// for carrying a byte that is not ASCII, except `%25`, which carries the percent sign of a
    /// zone identifier. A character the host mode would escape is the error Go reports for the
    /// host.
    private static func check(_ bytes: [UInt8], mode: Mode) throws -> (escapes: Int, hasPlus: Bool) {
        var escapes = 0
        var hasPlus = false
        var index = 0
        while index < bytes.count {
            switch bytes[index] {
            case UInt8(ascii: "%"):
                guard index + 2 < bytes.count, isHexDigit(bytes[index + 1]),
                    isHexDigit(bytes[index + 2]) else {
                    throw URLParseError.invalidEscape(reportedEscape(bytes, at: index))
                }
                if mode == .host && hexValue(bytes[index + 1]) < 8 && !isEscapedPercent(bytes, at: index) {
                    throw URLParseError.invalidEscape(reportedEscape(bytes, at: index))
                }
                escapes += 1
                index += 3
            case UInt8(ascii: "+"):
                hasPlus = mode.plusIsSpace
                index += 1
            default:
                if mode == .host && bytes[index] < 0x80 && shouldEscape(bytes[index], mode: mode) {
                    throw URLParseError.invalidHost(character: Character(Unicode.Scalar(bytes[index])))
                }
                index += 1
            }
        }
        return (escapes, hasPlus)
    }

    /// Go reports at most the first three bytes of the offending escape.
    private static func reportedEscape(_ bytes: [UInt8], at index: Int) -> String {
        String(decoding: bytes[index..<min(index + 3, bytes.count)], as: UTF8.self)
    }

    private static func isEscapedPercent(_ bytes: [UInt8], at index: Int) -> Bool {
        bytes[index] == UInt8(ascii: "%") && bytes[index + 1] == UInt8(ascii: "2")
            && bytes[index + 2] == UInt8(ascii: "5")
    }

    /// Go's `validEncoded`: whether the value can be used as the recorded raw form of the section
    /// the mode describes.
    static func isValidEncoded(_ value: String, mode: Mode) -> Bool {
        for byte in Array(value.utf8) {
            if validEncodedClass.contains(byte) { continue }
            if shouldEscape(byte, mode: mode) { return false }
        }
        return true
    }

    private static let marks: [UInt8] = [UInt8(ascii: "-"), UInt8(ascii: "_"), UInt8(ascii: "."),
        UInt8(ascii: "~")]

    private static let reserved: [UInt8] = [UInt8(ascii: "$"), UInt8(ascii: "&"), UInt8(ascii: "+"),
        UInt8(ascii: ","), UInt8(ascii: "/"), UInt8(ascii: ":"), UInt8(ascii: ";"), UInt8(ascii: "="),
        UInt8(ascii: "?"), UInt8(ascii: "@")]

    /// The sub-delimiters Go allows in a host, plus the brackets and the colon that carries the
    /// port. Go also allows `<` `>` `"`, the only characters left it could allow, because Parse
    /// would reject them if it escaped them.
    private static let hostClass: [UInt8] = [UInt8(ascii: "!"), UInt8(ascii: "$"), UInt8(ascii: "&"),
        UInt8(ascii: "'"), UInt8(ascii: "("), UInt8(ascii: ")"), UInt8(ascii: "*"), UInt8(ascii: "+"),
        UInt8(ascii: ","), UInt8(ascii: ";"), UInt8(ascii: "="), UInt8(ascii: ":"), UInt8(ascii: "["),
        UInt8(ascii: "]"), UInt8(ascii: "<"), UInt8(ascii: ">"), UInt8(ascii: "\"")]

    /// `validEncoded` checks the sub-delimiters itself, because `shouldEscape` is not quite RFC
    /// 3986 compliant.
    private static let validEncodedClass: [UInt8] = [UInt8(ascii: "!"), UInt8(ascii: "$"),
        UInt8(ascii: "&"), UInt8(ascii: "'"), UInt8(ascii: "("), UInt8(ascii: ")"), UInt8(ascii: "*"),
        UInt8(ascii: "+"), UInt8(ascii: ","), UInt8(ascii: ";"), UInt8(ascii: "="), UInt8(ascii: ":"),
        UInt8(ascii: "@"), UInt8(ascii: "["), UInt8(ascii: "]"), UInt8(ascii: "%")]

    private static let fragmentSubDelimiters: [UInt8] = [UInt8(ascii: "!"), UInt8(ascii: "("),
        UInt8(ascii: ")"), UInt8(ascii: "*")]

    private static let hexDigits: [UInt8] = Array("0123456789ABCDEF".utf8)

    private static func isAlphanumeric(_ byte: UInt8) -> Bool {
        isDigit(byte) || isLetter(byte)
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }

    private static func isLetter(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
            || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        isDigit(byte) || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
            || (UInt8(ascii: "A")...UInt8(ascii: "F")).contains(byte)
    }

    private static func hexValue(_ byte: UInt8) -> Int {
        if isDigit(byte) { return Int(byte) - Int(UInt8(ascii: "0")) }
        if (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte) {
            return Int(byte) - Int(UInt8(ascii: "a")) + 10
        }
        return Int(byte) - Int(UInt8(ascii: "A")) + 10
    }

    private static func percentEncoding(_ byte: UInt8) -> [UInt8] {
        [UInt8(ascii: "%"), hexDigits[Int(byte) / 16], hexDigits[Int(byte) % 16]]
    }
}
