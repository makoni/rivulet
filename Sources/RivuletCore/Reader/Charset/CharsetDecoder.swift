// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/encoding/encoding.go (Apache-2.0); adapted for
// Swift/SQLite. The UTF-8 rule follows golang.org/x/text encoding/unicode.

import Foundation

/// Byte-level decoding of ``CharsetEncoding`` values into UTF-8.
///
/// Ported from the decoders the reference reaches through `golang.org/x/text`, which are all
/// lossy: bytes and sequences that cannot be decoded become U+FFFD instead of failing the
/// document. Every primitive below keeps that property, because a feed with a few corrupt
/// bytes should still parse, and the output is always valid UTF-8.
enum CharsetDecoder {
    /// Decodes `data` with `strategy` and returns UTF-8 bytes.
    static func decode(_ data: Data, using strategy: CharsetDecoderStrategy, canonicalName: String) -> Data {
        switch strategy {
        case .utf8:
            return decodeUTF8(data)
        case .singleByte(let encoding):
            return Data(decodeSingleByte(data, encoding: encoding).utf8)
        case .multiByte(let encoding):
            return decodeMultiByte(data, encoding: encoding, canonicalName: canonicalName)
        case .utf16LittleEndian:
            return Data(decodeUTF16(data, littleEndian: true).utf8)
        case .utf16BigEndian:
            return Data(decodeUTF16(data, littleEndian: false).utf8)
        case .userDefined:
            return Data(decodeUserDefined(data).utf8)
        case .replacement:
            // The reference replacement decoder emits one U+FFFD for a non-empty document.
            return data.isEmpty ? Data() : Data("\u{FFFD}".utf8)
        }
    }

    /// Decodes UTF-8 the way the reference does: valid sequences are copied, and every maximal
    /// subpart of an ill-formed subsequence becomes one U+FFFD.
    ///
    /// The boundaries come from the W3C table that `x/text` implements on purpose, in place of
    /// Go's own `utf8.DecodeRune`, so the byte count consumed by an error is part of the
    /// behavior — two invalid bytes inside one subpart give one U+FFFD, not two.
    private static func decodeUTF8(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte < 0x80 {
                output.append(byte)
                index += 1
                continue
            }
            guard let rule = utf8Rule(forByte: byte) else {
                output.append(contentsOf: Array("\u{FFFD}".utf8))
                index += 1
                continue
            }
            let subpart = maximalSubpart(of: bytes, at: index, rule: rule)
            if subpart == rule.size {
                output.append(contentsOf: bytes[index ..< index + subpart])
            } else {
                output.append(contentsOf: Array("\u{FFFD}".utf8))
            }
            index += subpart
        }
        return Data(output)
    }

    /// The size of a UTF-8 sequence and the range its second byte must be in.
    ///
    /// `nil` means the byte cannot start a sequence: the overlong forms `C0` and `C1`, the
    /// forms above `U+10FFFF`, and continuation bytes standing alone.
    private static func utf8Rule(forByte byte: UInt8) -> (size: Int, secondLower: UInt8, secondUpper: UInt8)? {
        switch byte {
        case 0xC2...0xDF: return (2, 0x80, 0xBF)
        case 0xE0: return (3, 0xA0, 0xBF)   // overlong forms are excluded
        case 0xE1...0xEC, 0xEE...0xEF: return (3, 0x80, 0xBF)
        case 0xED: return (3, 0x80, 0x9F)   // surrogates are excluded
        case 0xF0: return (4, 0x90, 0xBF)   // the first byte above U+10FFFF is excluded
        case 0xF1...0xF3: return (4, 0x80, 0xBF)
        case 0xF4: return (4, 0x80, 0x8F)
        default: return nil
        }
    }

    /// How many bytes the maximal subpart of the subsequence starting at `start` covers.
    ///
    /// Equal to the rule size when the whole sequence is valid. Otherwise it is the longest
    /// valid prefix, which is what the reference consumes before emitting U+FFFD, including a
    /// sequence cut short by the end of the document.
    private static func maximalSubpart(of bytes: [UInt8], at start: Int, rule: (size: Int, secondLower: UInt8, secondUpper: UInt8)) -> Int {
        guard let second = byte(bytes, at: start + 1), second >= rule.secondLower, second <= rule.secondUpper else {
            return 1
        }
        guard rule.size > 2 else { return 2 }
        guard let third = byte(bytes, at: start + 2), isContinuation(third) else { return 2 }
        guard rule.size > 3 else { return 3 }
        guard let fourth = byte(bytes, at: start + 3), isContinuation(fourth) else { return 3 }
        return 4
    }

    /// Decodes a single-byte encoding byte by byte.
    ///
    /// The platform converter doubles as the WHATWG index: a byte it cannot decode is exactly a
    /// byte the WHATWG index leaves undefined, and both become U+FFFD.
    private static func decodeSingleByte(_ data: Data, encoding: String.Encoding) -> String {
        let table: [String?] = (0...255).map { byte in
            String(data: Data([UInt8(byte)]), encoding: encoding)
        }
        var result = ""
        for byte in data {
            result += table[Int(byte)] ?? "\u{FFFD}"
        }
        return result
    }

    /// Decodes a multi-byte encoding, falling back to the platform `iconv`.
    ///
    /// When neither the platform converter nor `iconv` can decode the name, the bytes are treated
    /// as UTF-8 with the reference's replacement rule, which keeps the output valid UTF-8; the
    /// reference decodes such a document with its own table instead, so the result for a legacy
    /// encoding can differ. This is the documented platform gap recorded in `docs/parity.md`.
    private static func decodeMultiByte(_ data: Data, encoding: String.Encoding, canonicalName: String) -> Data {
        if let text = String(data: data, encoding: encoding) {
            return Data(text.utf8)
        }
        #if canImport(Glibc)
        if let text = IconvDecoder.decode(data, from: canonicalName) {
            return Data(text.utf8)
        }
        #endif
        return decodeUTF8(data)
    }

    /// Decodes UTF-16 by hand, so that the platform can neither drop nor normalize a BOM.
    ///
    /// The reference decodes UTF-16 with its `IgnoreBOM` policy, which keeps a leading BOM in
    /// the output; an odd trailing byte or a lone surrogate becomes U+FFFD.
    private static func decodeUTF16(_ data: Data, littleEndian: Bool) -> String {
        var units: [UInt16] = []
        units.reserveCapacity(data.count / 2)
        var index = data.startIndex
        while index < data.endIndex {
            let next = data.index(after: index)
            guard next < data.endIndex else {
                units.append(0xFFFD)
                break
            }
            let first = UInt16(data[index])
            let second = UInt16(data[next])
            units.append(littleEndian ? first | (second << 8) : (first << 8) | second)
            index = data.index(after: next)
        }
        return String(decoding: units, as: UTF16.self)
    }

    /// Decodes the WHATWG `x-user-defined` encoding: bytes 0x80-0xFF map to U+F780-U+F7FF.
    private static func decodeUserDefined(_ data: Data) -> String {
        var scalars = String.UnicodeScalarView()
        for byte in data {
            if byte < 0x80 {
                scalars.append(Unicode.Scalar(byte))
            } else {
                // 0xF780...0xF7FF is a valid scalar range, so the failable initializer cannot
                // fail here.
                scalars.append(Unicode.Scalar(0xF780 + UInt32(byte) - 0x80)!)
            }
        }
        return String(scalars)
    }

    private static func byte(_ bytes: [UInt8], at index: Int) -> UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private static func isContinuation(_ byte: UInt8) -> Bool {
        byte >= 0x80 && byte <= 0xBF
    }
}
