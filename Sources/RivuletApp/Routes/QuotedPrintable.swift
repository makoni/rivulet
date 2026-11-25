// Ported from Go's `mime/quotedprintable` package, which `mime/multipart` reads through
// `newPart` (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The decoder that stands in front of a part declaring
/// `Content-Transfer-Encoding: quoted-printable`: `ReadForm` reaches it through `NextPart`, not
/// through `NextRawPart`.
///
/// The four deviations from RFC 2045 that the reference's reader lists are the rules here: `=\n` is a
/// soft line break as well as `=\r\n`; a `\r` or `\n` that is not after an `=` survives; an `=` as the
/// last byte of the part is the break at the end of the read and is dropped; and an `=` that is not a
/// hex pair and not at the end of the line is the literal character. Hex digits are accepted in either
/// case, and a byte at or above `0x80` passes through. An invalid byte is the error the decoder
/// reports, and `ReadForm` returns it for the whole body read rather than for this part alone.
enum QuotedPrintable {
    private static let lf: UInt8 = 10
    private static let cr: UInt8 = 13
    private static let space: UInt8 = 32
    private static let tab: UInt8 = 9
    private static let equals: UInt8 = 61

    /// The decoded bytes, or nothing for a part the decoder reports an error on.
    static func decode(_ content: String) -> String? {
        var rest = Array(content.utf8)
        var decoded: [UInt8] = []

        // `ReadSlice('\n')`: the line with its line ending, or the run that ends without one, which is
        // the end of the read.
        while !rest.isEmpty {
            let whole: [UInt8]
            let atEnd: Bool
            if let found = rest.firstIndex(of: lf) {
                whole = Array(rest[...found])
                rest = Array(rest[(found + 1)...])
                atEnd = false
            } else {
                whole = rest
                rest = []
                atEnd = true
            }
            guard let part = decodeLine(whole, atEnd: atEnd) else { return nil }
            decoded += part
        }

        return String(decoding: decoded, as: UTF8.self)
    }

    /// One line as the decoder reads it. `isQPDiscardWhitespace` is the set the right trim takes,
    /// which is not the set the break check reads: the line ending survives when it is not the break.
    private static func decodeLine(_ whole: [UInt8], atEnd: Bool) -> [UInt8]? {
        var line = whole
        while let last = line.last, last == lf || last == cr || last == space || last == tab {
            line.removeLast()
        }

        if line.last == equals {
            // `rightStripped`: the whitespace the right trim took off, read without its own leading
            // spaces and tabs. Only the line ending, or the end of the read with something before the
            // break, may follow the break.
            let after = Array(whole[line.count...]).drop { $0 == space || $0 == tab }
            line.removeLast()
            let endsTheLine = after.first == lf ||
                (after.first == cr && after.count > 1 && after.dropFirst().first == lf)
            if !endsTheLine && !(after.isEmpty && !line.isEmpty && atEnd) { return nil }
        } else if whole.last == lf {
            // The line ending survives, which is the second deviation.
            line.append(contentsOf: whole.count > 1 && whole[whole.count - 2] == cr ? [cr, lf] : [lf])
        }

        var out: [UInt8] = []
        var i = 0
        while i < line.count {
            let byte = line[i]
            switch byte {
            case equals:
                if i + 2 < line.count, let high = hex(line[i + 1]), let low = hex(line[i + 2]) {
                    out.append(high << 4 | low)
                    i += 3
                    continue
                }
                // `readHexByte` answers fewer than two bytes as the error, and the fourth deviation
                // takes the `=` as the literal character when it is not at the end of the line.
                if i + 1 >= line.count || line[i + 1] == cr || line[i + 1] == lf { return nil }
                out.append(equals)
            case tab, cr, lf:
                out.append(byte)
            default:
                if byte < 0x20 || byte == 0x7F { return nil }
                out.append(byte)
            }
            i += 1
        }
        return out
    }

    /// `fromHex`, which accepts the lowercase form as a badly encoded byte rather than as the error.
    private static func hex(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39: return byte - 0x30
        case 0x41...0x46: return byte - 0x41 + 10
        case 0x61...0x66: return byte - 0x61 + 10
        default: return nil
        }
    }
}
