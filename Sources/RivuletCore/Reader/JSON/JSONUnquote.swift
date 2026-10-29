// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Rivulet's own reader over the bytes; the literal is written out by `unquoteBytes` in `decode.go`,
// read through `utf8.DecodeRune` and `utf16.DecodeRune` as the reference uses them. `JSONScanner`
// names the source the rules are traced against.

/// Writes a string literal out: the escapes are written, a surrogate pair is combined, and a
/// surrogate that is not paired becomes the replacement character. The bytes are made well-formed,
/// which is where the reference's documented rule for invalid UTF-8 inside a string comes from.
enum JSONUnquote {
    static let replacement: Unicode.Scalar = Unicode.Scalar(0xFFFD)!

    /// What `unquoteBytes` writes for each escape `stateInStringEsc` accepts. The letters Go's
    /// `unquote` would write for a byte outside the set are not accepted by the machine, so they
    /// never reach here.
    private static let writes: [UInt8: Unicode.Scalar] = [
        JSONByte.lowercaseB: Unicode.Scalar(0x08)!,
        JSONByte.lowercaseF: Unicode.Scalar(0x0C)!,
        JSONByte.lowercaseN: Unicode.Scalar(0x0A)!,
        JSONByte.lowercaseR: Unicode.Scalar(0x0D)!,
        JSONByte.lowercaseT: Unicode.Scalar(0x09)!,
    ]

    /// `stateInStringEsc`: the byte the escape state accepts, which is the set `unquoteBytes` has a
    /// branch for. `u` is the one the machine reads as the four hex digits rather than as a
    /// character.
    static func acceptsEscape(_ byte: UInt8) -> Bool {
        writes[byte] != nil || byte == JSONByte.doubleQuote || byte == JSONByte.backslash
            || byte == JSONByte.slash
    }

    /// The bytes `stateInStringEscU` accepts as a hex digit, which the machine validates one byte
    /// at a time before `unquote` reads the four as one value, as `getu4` does.
    static func hexDigit(_ byte: UInt8) -> UInt32? {
        if JSONByte.zero <= byte && byte <= JSONByte.nine { return UInt32(byte - JSONByte.zero) }
        if JSONByte.lowercaseA <= byte && byte <= JSONByte.lowercaseF {
            return UInt32(byte - JSONByte.lowercaseA + 10)
        }
        if JSONByte.uppercaseA <= byte && byte <= JSONByte.uppercaseF {
            return UInt32(byte - JSONByte.uppercaseA + 10)
        }
        return nil
    }

    /// `unquoteBytes`, on the literal as the machine read it, without the quotes it validated.
    static func unquote(_ literal: [UInt8]) -> String {
        var text = ""
        var index = 0

        while index < literal.count {
            let written = literal[index] == JSONByte.backslash ? writeEscape(literal, at: index)
                : decodeRune(literal, at: index)
            text.unicodeScalars.append(written.scalar)
            index += written.length
        }

        return text
    }

    /// `getu4` and the branches of `unquoteBytes` that write one character: the escape as the
    /// machine read it, and the length of the bytes it consumed, which is longer for a combined
    /// surrogate pair.
    private static func writeEscape(_ literal: [UInt8], at index: Int) -> (scalar: Unicode.Scalar, length: Int) {
        let escaped = literal[index + 1]
        guard escaped == JSONByte.lowercaseU else {
            return (writes[escaped] ?? Unicode.Scalar(UInt32(escaped))!, 2)
        }

        let value = getu4(literal, at: index)!
        guard value >= 0xD800 && value <= 0xDFFF else { return (Unicode.Scalar(value)!, 6) }

        if let pair = getu4(literal, at: index + 6), let combined = decodeSurrogatePair(value, pair) {
            return (combined, 12)
        }
        return (replacement, 6)
    }

    /// `utf8.DecodeRune`: a valid encoding is the rune it writes, and anything else is the
    /// replacement character with one byte consumed, which is what makes an invalid multi-byte
    /// encoding one failure per byte. The checks are the ones Go makes: an encoding of a surrogate
    /// and an overlong encoding are not valid encodings, and neither is a form above U+10FFFF.
    private static func decodeRune(_ literal: [UInt8], at index: Int) -> (scalar: Unicode.Scalar, length: Int) {
        let lead = literal[index]
        guard lead >= 0x80 else { return (Unicode.Scalar(UInt32(lead))!, 1) }
        guard lead >= 0xC0 else { return (replacement, 1) }

        let length = lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : 2
        guard index + length <= literal.count else { return (replacement, 1) }

        var value = UInt32(lead & (0xFF >> (length + 1)))
        for offset in 1 ..< length {
            let continuation = literal[index + offset]
            guard continuation & 0xC0 == 0x80 else { return (replacement, 1) }
            value = (value << 6) | UInt32(continuation & 0x3F)
        }

        let smallest = length == 2 ? 0x80 : length == 3 ? 0x800 : 0x10000
        if value < smallest || value > 0x10FFFF || (value >= 0xD800 && value <= 0xDFFF) {
            return (replacement, 1)
        }

        return (Unicode.Scalar(value)!, length)
    }

    /// `getu4`: the escape as the four hex digits, or nothing where the bytes are not an escape.
    /// `unquote` looks for a second escape with the same function, which is why a surrogate is only
    /// paired by a following escape that is itself a `\u` escape.
    private static func getu4(_ literal: [UInt8], at start: Int) -> UInt32? {
        guard start + 6 <= literal.count, literal[start] == JSONByte.backslash,
            literal[start + 1] == JSONByte.lowercaseU else { return nil }

        var value: UInt32 = 0
        for position in start + 2 ..< start + 6 {
            guard let digit = hexDigit(literal[position]) else { return nil }
            value = (value << 4) | digit
        }

        return value
    }

    /// `utf16.DecodeRune`: a high surrogate followed by a low one is the pair, and anything else is
    /// what `unquote` writes as the replacement character.
    private static func decodeSurrogatePair(_ first: UInt32, _ second: UInt32) -> Unicode.Scalar? {
        guard first >= 0xD800 && first <= 0xDBFF, second >= 0xDC00 && second <= 0xDFFF else { return nil }
        return Unicode.Scalar(0x10000 + (first - 0xD800) * 0x400 + (second - 0xDC00))
    }
}
