// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Go's standard library `time/format.go`
// (`nextStdChunk`); adapted for Swift.

/// One literal run of a layout and the pattern after it, as `nextStdChunk` splits the layout. The
/// text is kept as UTF-8 bytes, because that is what Go scans and what makes the run-of-spaces rule
/// deterministic.
struct DateChunk: Equatable, Sendable {
    var prefix: [UInt8]
    var kind: DateChunkKind
    var suffix: [UInt8]

    init(prefix: [UInt8] = [], kind: DateChunkKind, suffix: [UInt8] = []) {
        self.prefix = prefix
        self.kind = kind
        self.suffix = suffix
    }
}

/// The layout patterns the reference recognizes, named after the Go constants `nextStdChunk`
/// returns.
enum DateChunkKind: Equatable, Sendable {
    /// No pattern was found, so the whole remaining layout is literal text.
    case none

    case longMonth, month, numberMonth, zeroMonth
    case longWeekDay, weekDay
    case day, underDay, zeroDay, underYearDay, zeroYearDay
    case hour, hour12, zeroHour12, minute, zeroMinute, second, zeroSecond
    case longYear, year, pm, pmLowercase

    case zoneName
    case iso8601Offset, iso8601SecondsOffset, iso8601ShortOffset, iso8601ColonOffset,
        iso8601ColonSecondsOffset
    case numericOffset, numericSecondsOffset, numericShortOffset, numericColonOffset,
        numericColonSecondsOffset

    /// A run of `0` or `9` standing for fractional seconds. Go keeps the length of the run in the
    /// high bits of the code; here it is the associated value. The separator is not kept, because
    /// parsing accepts either `.` or `,` regardless of which one the layout writes.
    case fractionalSeconds0(digits: Int)
    case fractionalSeconds9(digits: Int)

    /// The three patterns that accept a literal `Z` for UTC, as Go's `stdISO8601TZ`,
    /// `stdISO8601ShortTZ` and `stdISO8601ColonTZ` do.
    var acceptsLiteralZ: Bool {
        switch self {
        case .iso8601Offset, .iso8601ShortOffset, .iso8601ColonOffset:
            return true
        default:
            return false
        }
    }

    var isFractional: Bool {
        switch self {
        case .fractionalSeconds0, .fractionalSeconds9:
            return true
        default:
            return false
        }
    }
}
