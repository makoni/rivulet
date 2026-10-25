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

    /// A percent escape must be well formed; a malformed one is the error the caller reports, named
    /// as Go names it — at most the first three bytes of the offending escape. A value with nothing
    /// to decode is returned as it was read, which is what the reference's fast path does.
    static func unescape(_ value: String, mode: Mode) throws -> String {
        let bytes = Array(value.utf8)
        guard bytes.contains(UInt8(ascii: "%")) ||
            (mode.plusIsSpace && bytes.contains(UInt8(ascii: "+"))) else { return value }

        var result = [UInt8]()
        var index = 0
        while index < bytes.count {
            switch bytes[index] {
            case UInt8(ascii: "%"):
                guard index + 2 < bytes.count, isHexDigit(bytes[index + 1]),
                    isHexDigit(bytes[index + 2]) else {
                    let reported = bytes[index..<min(index + 3, bytes.count)]
                    throw URLParseError.invalidEscape(String(decoding: reported, as: UTF8.self))
                }
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
