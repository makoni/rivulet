// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Go's standard library `time/format.go` (`skip`,
// `getnum`, `getnum3`, `lookup`, `atoi`, `parseTimeZone`, `parseGMT`, `parseSignedOffset`,
// `parseNanoseconds`); adapted for Swift.

import Foundation

/// The value cursor with Go's reading primitives. The value is read as UTF-8 bytes because that is
/// what Go scans: every pattern the scanner recognizes is ASCII, so a multi-byte character can
/// never match one, and a run of digits or upper-case letters ends at the same place in either
/// reading.
struct DateInputReader {
    private(set) var bytes: [UInt8]

    init(value: String) {
        bytes = Array(value.utf8)
    }

    var isAtEnd: Bool { bytes.isEmpty }

    var remainingCount: Int { bytes.count }

    var startsWithSpace: Bool { !bytes.isEmpty && bytes[0] == Self.space }

    /// `skip`: matches a literal run of the layout, treating a space in the layout as equivalent to
    /// a run of spaces in the value.
    mutating func skip(prefix: [UInt8]) -> Bool {
        var prefixPosition = 0
        var valuePosition = 0
        while prefixPosition < prefix.count {
            if prefix[prefixPosition] == Self.space {
                if valuePosition < bytes.count && bytes[valuePosition] != Self.space {
                    return false
                }
                while prefixPosition < prefix.count && prefix[prefixPosition] == Self.space {
                    prefixPosition += 1
                }
                while valuePosition < bytes.count && bytes[valuePosition] == Self.space {
                    valuePosition += 1
                }
                continue
            }
            if valuePosition >= bytes.count || bytes[valuePosition] != prefix[prefixPosition] {
                return false
            }
            prefixPosition += 1
            valuePosition += 1
        }
        bytes = Array(bytes[valuePosition...])
        return true
    }

    /// `getnum`: one or two digits, or exactly two when the layout fixes the width.
    mutating func readNumber(fixed: Bool) -> Int? {
        guard isDigit(at: 0) else {
            return nil
        }
        if !isDigit(at: 1) {
            if fixed {
                return nil
            }
            let number = digitValue(at: 0)
            consume(1)
            return number
        }
        let number = digitValue(at: 0) * 10 + digitValue(at: 1)
        consume(2)
        return number
    }

    /// `getnum3`: one, two or three digits, or exactly three when the layout fixes the width.
    mutating func readNumber3(fixed: Bool) -> Int? {
        var number = 0
        var position = 0
        while position < 3 && isDigit(at: position) {
            number = number * 10 + digitValue(at: position)
            position += 1
        }
        if position == 0 || (fixed && position != 3) {
            return nil
        }
        consume(position)
        return number
    }

    /// Exactly `width` digits, which is what the four-digit year reads: Go checks a digit at
    /// position zero before it runs `atoi`, so a sign there is not a match.
    mutating func readDigits(width: Int) -> Int? {
        guard remainingCount >= width else {
            return nil
        }
        var number = 0
        for position in 0..<width {
            guard isDigit(at: position) else {
                return nil
            }
            number = number * 10 + digitValue(at: position)
        }
        consume(width)
        return number
    }

    /// `atoi` over exactly `width` bytes, for the fields Go reads with `atoi` rather than `getnum`:
    /// the two characters of the two-digit year, which may begin with a sign.
    mutating func readSignedNumber(width: Int) -> Int? {
        guard remainingCount >= width else {
            return nil
        }
        guard let number = Self.atoi(Array(bytes[0..<width])) else {
            return nil
        }
        consume(width)
        return number
    }

    /// `lookup`: a day or month name read case-insensitively, matched as a prefix of the value.
    mutating func lookup(table: [String]) -> Int? {
        for (index, name) in table.enumerated() {
            let nameBytes = Array(name.utf8)
            guard remainingCount >= nameBytes.count,
                Self.matchesIgnoringCase(Array(bytes[0..<nameBytes.count]), nameBytes) else {
                continue
            }
            consume(nameBytes.count)
            return index
        }
        return nil
    }

    /// `parseTimeZone`, which reads a zone name, including the `GMT` and the signed-offset cases.
    mutating func readZoneName() -> String? {
        guard remainingCount >= 3 else {
            return nil
        }
        // Special case 1: ChST and MeST are the only names with a lower-case letter.
        if remainingCount >= 4 && (has("ChST") || has("MeST")) {
            return take(4)
        }
        // Special case 2: GMT may have an hour offset, which Go keeps as part of the name.
        if has("GMT") {
            return take(3 + Self.signedOffsetLength(Array(bytes[3...])))
        }
        // Special case 3: some zones are unnamed and written as a signed hour.
        if bytes[0] == Self.plus || bytes[0] == Self.minus {
            let length = Self.signedOffsetLength(bytes)
            return length > 0 ? take(length) : nil
        }
        var upper = 0
        while upper < 6 && upper < remainingCount && isUpperCaseLetter(at: upper) {
            upper += 1
        }
        switch upper {
        case 3:
            return take(3)
        case 4 where bytes[3] == Self.letterT || has("WITA"):
            // Four letters must end in T, except one special case.
            return take(4)
        case 5 where bytes[4] == Self.letterT:
            return take(5)
        default:
            return nil
        }
    }

    /// `parseNanoseconds` over `length` bytes, which include the separator. Go scales by the
    /// missing digits using the capped length, while the caller consumes the length it asked for.
    mutating func readNanoseconds(length: Int) -> Int? {
        guard length >= 1, remainingCount >= length, isSeparator(at: 0) else {
            return nil
        }
        let capped = min(length, 10)
        guard let number = Self.atoi(Array(bytes[1..<capped])) else {
            return nil
        }
        // Go reports `fractional second` for a negative result, so a run that `atoi` reads as
        // negative is not a match.
        if number < 0 {
            return nil
        }
        consume(length)
        return number * Self.powerOfTen(10 - capped)
    }

    /// Reads a numeric offset as Go's offset case does, and returns it in seconds.
    mutating func readOffset(kind: DateChunkKind) -> Int? {
        let zeros = Array("00".utf8)
        var sign: UInt8 = 0
        var hour = zeros
        var minute = zeros
        var second = zeros

        switch kind {
        case .iso8601ColonOffset, .numericColonOffset:
            guard remainingCount >= 6, bytes[3] == Self.colon else {
                return nil
            }
            sign = bytes[0]
            hour = Array(bytes[1..<3])
            minute = Array(bytes[4..<6])
            consume(6)
        case .numericShortOffset, .iso8601ShortOffset:
            guard remainingCount >= 3 else {
                return nil
            }
            sign = bytes[0]
            hour = Array(bytes[1..<3])
            consume(3)
        case .iso8601ColonSecondsOffset, .numericColonSecondsOffset:
            guard remainingCount >= 9, bytes[3] == Self.colon, bytes[6] == Self.colon else {
                return nil
            }
            sign = bytes[0]
            hour = Array(bytes[1..<3])
            minute = Array(bytes[4..<6])
            second = Array(bytes[7..<9])
            consume(9)
        case .iso8601SecondsOffset, .numericSecondsOffset:
            guard remainingCount >= 7 else {
                return nil
            }
            sign = bytes[0]
            hour = Array(bytes[1..<3])
            minute = Array(bytes[3..<5])
            second = Array(bytes[5..<7])
            consume(7)
        default:
            guard remainingCount >= 5 else {
                return nil
            }
            sign = bytes[0]
            hour = Array(bytes[1..<3])
            minute = Array(bytes[3..<5])
            consume(5)
        }

        // The offset fields go through `getnum`, not `atoi`, so a sign inside them is not a match.
        guard let hourValue = Self.digitPair(hour), let minuteValue = Self.digitPair(minute),
            let secondValue = Self.digitPair(second) else {
            return nil
        }
        var offset = (hourValue * 60 + minuteValue) * 60 + secondValue
        if sign == Self.minus {
            offset = -offset
        } else if sign != Self.plus {
            return nil
        }
        return offset
    }

    /// `parseSignedOffset`: the length of a signed hour offset, which is zero for a bad one.
    static func signedOffsetLength(_ value: [UInt8]) -> Int {
        guard let sign = value.first, sign == plus || sign == minus else {
            return 0
        }
        var number = 0
        var digits = 0
        for byte in value.dropFirst() {
            guard digitValue(byte) >= 0 && digitValue(byte) <= 9 else {
                break
            }
            number = number * 10 + digitValue(byte)
            digits += 1
            if number > 23 {
                return 0
            }
        }
        return digits == 0 ? 0 : 1 + digits
    }

    mutating func consume(_ count: Int) {
        bytes = Array(bytes[count...])
    }

    /// Takes exactly `count` bytes as a value, for the patterns that read a fixed length.
    mutating func take(_ count: Int) -> String {
        let taken = String(decoding: bytes[0..<count], as: UTF8.self)
        consume(count)
        return taken
    }

    func has(_ pattern: String) -> Bool {
        let patternBytes = Array(pattern.utf8)
        return remainingCount >= patternBytes.count && Array(bytes[0..<patternBytes.count]) == patternBytes
    }

    func isDigit(at position: Int) -> Bool {
        position < remainingCount && Self.digitValue(bytes[position]) >= 0
            && Self.digitValue(bytes[position]) <= 9
    }

    func isSeparator(at position: Int) -> Bool {
        position < remainingCount && (bytes[position] == Self.period || bytes[position] == Self.comma)
    }

    private func isUpperCaseLetter(at position: Int) -> Bool {
        position < remainingCount && 65 <= bytes[position] && bytes[position] <= 90
    }

    private func digitValue(at position: Int) -> Int {
        position < remainingCount ? Self.digitValue(bytes[position]) : -1
    }

    /// `match`: equal bytes, or equal after folding ASCII letters to lower case.
    private static func matchesIgnoringCase(_ value: [UInt8], _ name: [UInt8]) -> Bool {
        for (left, right) in zip(value, name) {
            if left == right {
                continue
            }
            let foldedLeft = left | 32
            let foldedRight = right | 32
            if foldedLeft != foldedRight || foldedLeft < 97 || foldedLeft > 122 {
                return false
            }
        }
        return true
    }

    /// `atoi` over a run of bytes: a leading sign is allowed, and nothing may be left over. Go's
    /// `leadingInt` stops at the first non-digit, so a run that is not all digits is not read.
    /// `getnum` with the width fixed, over the two-byte slice Go takes for an offset field.
    private static func digitPair(_ value: [UInt8]) -> Int? {
        guard value.count == 2, digitValue(value[0]) >= 0, digitValue(value[0]) <= 9,
            digitValue(value[1]) >= 0, digitValue(value[1]) <= 9 else {
            return nil
        }
        return digitValue(value[0]) * 10 + digitValue(value[1])
    }

    private static func atoi(_ value: [UInt8]) -> Int? {
        var negative = false
        var digits = value[...]
        if let first = digits.first, first == plus || first == minus {
            negative = first == minus
            digits = digits.dropFirst()
        }
        guard digits.allSatisfy({ digitValue($0) >= 0 && digitValue($0) <= 9 }) else {
            return nil
        }
        let number = digits.reduce(0) { $0 * 10 + digitValue($1) }
        return negative ? -number : number
    }

    private static func powerOfTen(_ exponent: Int) -> Int {
        var result = 1
        for _ in 0..<exponent {
            result *= 10
        }
        return result
    }

    private static func digitValue(_ byte: UInt8) -> Int {
        Int(byte) - Int(digitZero)
    }

    private static let space = UInt8(ascii: " ")
    private static let colon = UInt8(ascii: ":")
    private static let period = UInt8(ascii: ".")
    private static let comma = UInt8(ascii: ",")
    private static let plus = UInt8(ascii: "+")
    private static let minus = UInt8(ascii: "-")
    private static let letterT = UInt8(ascii: "T")
    private static let digitZero = UInt8(ascii: "0")
}
