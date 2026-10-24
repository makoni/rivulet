// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Go's standard library `time/format.go`
// (`nextStdChunk`); adapted for Swift.

import Foundation

/// Splits a layout at its first recognized pattern, the way `nextStdChunk` does.
///
/// The patterns are Go's reference time, so every one of them is ASCII. The layout is scanned as
/// UTF-8 bytes because that is what Go scans: a multi-byte character can never match a pattern.
enum DateChunkScanner {
    static func nextChunk(in layout: [UInt8]) -> DateChunk {
        var position = 0
        while position < layout.count {
            switch layout[position] {
            case letterJ: // January, Jan
                if has(layout, at: position, "Jan") {
                    if has(layout, at: position, "January") {
                        return chunk(layout, prefixEnd: position, kind: .longMonth,
                            suffixStart: position + 7)
                    }
                    if !startsWithLowerCase(layout, at: position + 3) {
                        return chunk(layout, prefixEnd: position, kind: .month, suffixStart: position + 3)
                    }
                }
            case letterM: // Monday, Mon, MST
                if has(layout, at: position, "Mon") {
                    if has(layout, at: position, "Monday") {
                        return chunk(layout, prefixEnd: position, kind: .longWeekDay,
                            suffixStart: position + 6)
                    }
                    if !startsWithLowerCase(layout, at: position + 3) {
                        return chunk(layout, prefixEnd: position, kind: .weekDay, suffixStart: position + 3)
                    }
                }
                if has(layout, at: position, "MST") {
                    return chunk(layout, prefixEnd: position, kind: .zoneName, suffixStart: position + 3)
                }
            case digitZero: // 01, 02, 03, 04, 05, 06, 002
                if position + 2 <= layout.count, isDigit(layout, at: position + 1),
                    digitValue(layout[position + 1]) >= 1, digitValue(layout[position + 1]) <= 6 {
                    return chunk(layout, prefixEnd: position,
                        kind: zeroPattern(digitValue(layout[position + 1])), suffixStart: position + 2)
                }
                if has(layout, at: position, "002") {
                    return chunk(layout, prefixEnd: position, kind: .zeroYearDay, suffixStart: position + 3)
                }
            case digitOne: // 15, 1
                if has(layout, at: position, "15") {
                    return chunk(layout, prefixEnd: position, kind: .hour, suffixStart: position + 2)
                }
                return chunk(layout, prefixEnd: position, kind: .numberMonth, suffixStart: position + 1)
            case digitTwo: // 2006, 2
                if has(layout, at: position, "2006") {
                    return chunk(layout, prefixEnd: position, kind: .longYear, suffixStart: position + 4)
                }
                return chunk(layout, prefixEnd: position, kind: .day, suffixStart: position + 1)
            case underscore: // _2, _2006, __2
                if has(layout, at: position, "_2") {
                    // `_2006` is a literal underscore followed by the long-year pattern, so the
                    // underscore stays in the prefix, which is what Go returns here.
                    if has(layout, at: position, "_2006") {
                        return chunk(layout, prefixEnd: position + 1, kind: .longYear,
                            suffixStart: position + 5)
                    }
                    return chunk(layout, prefixEnd: position, kind: .underDay, suffixStart: position + 2)
                }
                if has(layout, at: position, "__2") {
                    return chunk(layout, prefixEnd: position, kind: .underYearDay, suffixStart: position + 3)
                }
            case digitThree:
                return chunk(layout, prefixEnd: position, kind: .hour12, suffixStart: position + 1)
            case digitFour:
                return chunk(layout, prefixEnd: position, kind: .minute, suffixStart: position + 1)
            case digitFive:
                return chunk(layout, prefixEnd: position, kind: .second, suffixStart: position + 1)
            case letterP: // PM
                if has(layout, at: position, "PM") {
                    return chunk(layout, prefixEnd: position, kind: .pm, suffixStart: position + 2)
                }
            case lowercaseP: // pm
                if has(layout, at: position, "pm") {
                    return chunk(layout, prefixEnd: position, kind: .pmLowercase, suffixStart: position + 2)
                }
            case minusSign: // -070000, -07:00:00, -0700, -07:00, -07
                if let match = firstMatch(layout, at: position, offsetPatterns(for: "-")) {
                    return chunk(layout, prefixEnd: position, kind: match.kind,
                        suffixStart: position + match.pattern.count)
                }
            case letterZ: // Z070000, Z07:00:00, Z0700, Z07:00, Z07
                if let match = firstMatch(layout, at: position, offsetPatterns(for: "Z")) {
                    return chunk(layout, prefixEnd: position, kind: match.kind,
                        suffixStart: position + match.pattern.count)
                }
            case period, comma: // .000 or .999, a run of digits for fractional seconds
                if position + 1 < layout.count,
                    digitValue(layout[position + 1]) == 0 || digitValue(layout[position + 1]) == 9 {
                    let digit = layout[position + 1]
                    var end = position + 1
                    while end < layout.count, layout[end] == digit {
                        end += 1
                    }
                    // A run of digits only counts as fractional seconds when it ends here, which is
                    // what Go checks before it takes the run as a pattern.
                    if !isDigit(layout, at: end) {
                        let digits = end - (position + 1)
                        let kind = digit == digitNine
                            ? DateChunkKind.fractionalSeconds9(digits: digits)
                            : DateChunkKind.fractionalSeconds0(digits: digits)
                        return chunk(layout, prefixEnd: position, kind: kind, suffixStart: end)
                    }
                }
            default:
                break
            }
            position += 1
        }
        return DateChunk(prefix: layout, kind: .none, suffix: [])
    }

    /// The offset patterns share one switch case in Go, so they are tried in the same order here:
    /// the forms with seconds first, then the plain ones, then the short one.
    private static func offsetPatterns(for first: String) -> [(String, DateChunkKind)] {
        first == "Z"
            ? [(first + "070000", .iso8601SecondsOffset), (first + "07:00:00", .iso8601ColonSecondsOffset),
                (first + "0700", .iso8601Offset), (first + "07:00", .iso8601ColonOffset),
                (first + "07", .iso8601ShortOffset)]
            : [(first + "070000", .numericSecondsOffset), (first + "07:00:00", .numericColonSecondsOffset),
                (first + "0700", .numericOffset), (first + "07:00", .numericColonOffset),
                (first + "07", .numericShortOffset)]
    }

    private static func firstMatch(_ layout: [UInt8], at position: Int,
        _ patterns: [(String, DateChunkKind)]) -> (pattern: String, kind: DateChunkKind)? {
        for (pattern, kind) in patterns where has(layout, at: position, pattern) {
            return (pattern, kind)
        }
        return nil
    }

    private static func chunk(_ layout: [UInt8], prefixEnd: Int, kind: DateChunkKind,
        suffixStart: Int) -> DateChunk {
        DateChunk(prefix: Array(layout[0..<prefixEnd]), kind: kind, suffix: Array(layout[suffixStart...]))
    }

    private static func has(_ layout: [UInt8], at position: Int, _ pattern: String) -> Bool {
        let patternBytes = Array(pattern.utf8)
        guard position + patternBytes.count <= layout.count else {
            return false
        }
        return Array(layout[position..<position + patternBytes.count]) == patternBytes
    }

    private static func isDigit(_ layout: [UInt8], at position: Int) -> Bool {
        position < layout.count && digitValue(layout[position]) >= 0 && digitValue(layout[position]) <= 9
    }

    private static func digitValue(_ byte: UInt8) -> Int {
        Int(byte) - Int(digitZero)
    }

    private static func startsWithLowerCase(_ layout: [UInt8], at position: Int) -> Bool {
        position < layout.count && 97 <= layout[position] && layout[position] <= 122
    }

    /// `std0x`: the pattern a `0` followed by a digit names.
    private static func zeroPattern(_ digit: Int) -> DateChunkKind {
        switch digit {
        case 1: return .zeroMonth
        case 2: return .zeroDay
        case 3: return .zeroHour12
        case 4: return .zeroMinute
        case 5: return .zeroSecond
        default: return .year
        }
    }

    private static let letterJ = UInt8(ascii: "J")
    private static let letterM = UInt8(ascii: "M")
    private static let letterP = UInt8(ascii: "P")
    private static let letterZ = UInt8(ascii: "Z")
    private static let lowercaseP = UInt8(ascii: "p")
    private static let minusSign = UInt8(ascii: "-")
    private static let underscore = UInt8(ascii: "_")
    private static let period = UInt8(ascii: ".")
    private static let comma = UInt8(ascii: ",")
    private static let digitZero = UInt8(ascii: "0")
    private static let digitOne = UInt8(ascii: "1")
    private static let digitTwo = UInt8(ascii: "2")
    private static let digitThree = UInt8(ascii: "3")
    private static let digitFour = UInt8(ascii: "4")
    private static let digitFive = UInt8(ascii: "5")
    private static let digitNine = UInt8(ascii: "9")
}
