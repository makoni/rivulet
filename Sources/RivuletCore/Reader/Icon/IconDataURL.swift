// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/icon/finder.go (`parseImageDataURL`) (Apache-2.0);
// adapted for Swift/SQLite.

import Foundation

/// The error the data-URL reader answers with. The reference reports these as messages; this
/// port keeps them typed, so a test compares the branch rather than the wording.
enum IconDataURLError: Error, Equatable {
    /// The value does not have the shape `data:<mediatype>[;encoding],<data>` with an image
    /// mediatype and a non-empty data part.
    case malformed(String)

    /// The shape is right and the encoding is `base64`, but the data is not standard-
    /// alphabet base64.
    case invalidBase64(String)

    /// The shape is right and the encoding is the empty one, and the data has a truncated escape.
    case invalidEscape(String)
}

/// A `data:` URL read as an icon: the mediatype, the bytes the encoding branch produces, and
/// the hash the storage layer deduplicates by.
///
/// The reference builds this with one regexp whose productions are `image/[^;,]+` for the
/// mediatype, `base64|utf8` for the optional encoding and `.+` for the data, so a value fails
/// on the shape before anything is decoded: the mediatype cannot cross the `;` or the `,`, an
/// unknown encoding is not the optional group, and the data part must not be empty. Go's `.`
/// does not match a newline, so a data part containing `\n` is not a match either. The three
/// encodings then do three different things, and Go's `QueryUnescape` for the empty one is not
/// a plain percent-decode: it turns a `+` into a space and refuses a truncated escape.
///
/// The checksum is the port's SHA-256 over the decoded bytes. The reference hashes the same
/// bytes with `crypto.HashFromBytes`, which is FNV-128a, so the stored hash value differs from
/// the reference's; the difference is recorded in `docs/parity.md` and cannot be pinned from
/// this side of the boundary.
enum IconDataURL {
    struct Value: Equatable {
        var mimeType: String
        var content: Data
        var hash: String
    }

    /// Reads `value` the way the reference's regexp and the encoding switch do.
    static func parse(_ value: String) throws -> Value {
        let (mimeType, encoding, data) = try readShape(value)
        let bytes = try readEncoding(encoding: encoding, data: data, value: value)
        return Value(mimeType: mimeType, content: bytes, hash: Hashes.sha256(bytes))
    }

    /// The four productions, read in the order the regexp reads them.
    private static func readShape(_ value: String) throws -> (String, String, String) {
        guard value.hasPrefix("data:") else { throw IconDataURLError.malformed(value) }

        var rest = value.dropFirst("data:".count)
        guard rest.hasPrefix("image/") else { throw IconDataURLError.malformed(value) }
        rest = rest.dropFirst("image/".count)

        guard !rest.isEmpty, let delimiter = rest.firstIndex(where: { $0 == ";" || $0 == "," }),
            delimiter != rest.startIndex else {
            throw IconDataURLError.malformed(value)
        }
        // The named group is the whole mediatype production, prefix included.
        let mimeType = "image/" + String(rest[rest.startIndex..<delimiter])

        var encoding = ""
        var data = ""
        if rest[delimiter] == ";" {
            guard let comma = rest.firstIndex(of: ",") else {
                throw IconDataURLError.malformed(value)
            }
            encoding = String(rest[rest.index(after: delimiter)..<comma])
            data = String(rest[rest.index(after: comma)...])
            guard encoding == "base64" || encoding == "utf8" else {
                throw IconDataURLError.malformed(value)
            }
        } else {
            data = String(rest[rest.index(after: delimiter)...])
        }

        guard !data.isEmpty, !data.contains("\n") else {
            throw IconDataURLError.malformed(value)
        }
        return (mimeType, encoding, data)
    }

    /// What the three encodings do with the data part.
    private static func readEncoding(encoding: String, data: String, value: String) throws -> Data {
        switch encoding {
        case "base64":
            // Go's decoder accepts a value whose last quantum is not padded; this
            // port's does not, which no case here reads.
            guard let decoded = Data(base64Encoded: data) else {
                throw IconDataURLError.invalidBase64(data)
            }
            return decoded
        case "utf8":
            return Data(data.utf8)
        default:
            return try unescape(data)
        }
    }

    /// Go's `QueryUnescape`: a `+` is a space, a percent escape needs two hex digits after it, and
    /// everything else is written as the byte it was read as.
    private static func unescape(_ value: String) throws -> Data {
        let bytes = Array(value.utf8)
        var out: [UInt8] = []
        var index = 0

        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "+") {
                out.append(UInt8(ascii: " "))
            } else if byte == UInt8(ascii: "%") {
                guard index + 2 < bytes.count, isHexDigit(bytes[index + 1]),
                    isHexDigit(bytes[index + 2]) else {
                    throw IconDataURLError.invalidEscape(value)
                }
                out.append(UInt8(hexValue(bytes[index + 1]) * 16 + hexValue(bytes[index + 2])))
                index += 2
            } else {
                out.append(byte)
            }
            index += 1
        }

        return Data(out)
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool { hexValue(byte) >= 0 }

    /// Go's `ishex`, which answers -1 for a byte that is not a hex digit.
    private static func hexValue(_ byte: UInt8) -> Int {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return Int(byte - UInt8(ascii: "0"))
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return Int(byte - UInt8(ascii: "a")) + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return Int(byte - UInt8(ascii: "A")) + 10
        default: return -1
        }
    }
}
