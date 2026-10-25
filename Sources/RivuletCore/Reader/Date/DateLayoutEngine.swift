// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Go's standard library `time/format.go` (`parse`);
// adapted for Swift.

import Foundation

/// Reads one value through one layout, the way Go's `parse` does.
///
/// Go's `Parse` has a fast path for `RFC3339` that this engine does not, which changes nothing:
/// `Parse` falls back to the general `parse` when the fast path fails, so an unpadded field is
/// accepted either way. Recorded in `docs/parity.md`.
///
/// A failed layout is not an error here: the reference only cares whether a layout matched, so a
/// failure is the absence of a match, and Go's per-layout `ParseError` text is not reproduced.
///
/// The zone is resolved through ``DateZoneTable`` instead of through the machine's local zone,
/// which is the deviation recorded in `docs/parity.md`, and the name reported is the name as read,
/// where Go would name the machine's zone when it was in effect at the parsed instant. The default
/// location is UTC, as it is for Go's `Parse`. The clamp `checkTimezoneRange` belongs to the entry
/// point, so this engine reports what the layout read even when the offset is outside the range the
/// entry point accepts.
struct DateLayoutEngine {
    /// Reads `value` through `layout`, or returns `nil` when the layout does not match it.
    static func parse(layout: String, value: String) -> ParsedDate? {
        var engine = DateLayoutEngine()
        return engine.read(layout: Array(layout.utf8), value: value)
    }

    private var reader = DateInputReader(value: "")
    private var fields = DateFields()
    private var amSet = false
    private var pmSet = false
    private var resolvedToUtc = false

    /// Go's `zoneOffset` starts at -1, and that value means "no offset was read", so an offset of
    /// exactly one second is read as no offset at all. The sentinel is kept to reproduce that.
    private var zoneOffset = -1
    private var zoneName = ""

    private mutating func read(layout: [UInt8], value: String) -> ParsedDate? {
        reader = DateInputReader(value: value)
        var remaining = layout
        while true {
            let chunk = DateChunkScanner.nextChunk(in: remaining)
            guard reader.skip(prefix: chunk.prefix) else {
                return nil
            }
            if chunk.kind == .none {
                // Text left over after the last chunk is not consumed, which is a failure in Go
                // too.
                guard reader.isAtEnd else {
                    return nil
                }
                break
            }
            remaining = chunk.suffix
            guard read(chunk, remaining: remaining) else {
                return nil
            }
        }
        return build()
    }

    private mutating func read(_ chunk: DateChunk, remaining: [UInt8]) -> Bool {
        switch chunk.kind {
        case .longMonth, .month, .numberMonth, .zeroMonth:
            return readMonth(chunk.kind)
        case .longWeekDay, .weekDay:
            // The weekday is read for error checking only, never used.
            let table = chunk.kind == .longWeekDay ? DateNameTables.longDayNames
                : DateNameTables.shortDayNames
            return reader.lookup(table: table) != nil
        case .day, .underDay, .zeroDay:
            return readDay(chunk.kind)
        case .underYearDay, .zeroYearDay:
            return readYearDay(chunk.kind)
        case .year, .longYear:
            return readYear(chunk.kind)
        case .hour, .hour12, .zeroHour12:
            return readHour(chunk.kind)
        case .minute, .zeroMinute:
            return readMinute(chunk.kind)
        case .second, .zeroSecond:
            return readSecond(chunk.kind, remaining: remaining)
        case .pm, .pmLowercase:
            return readAmPm(chunk.kind)
        case .zoneName:
            return readZoneName()
        case .fractionalSeconds0, .fractionalSeconds9:
            return readFractional(chunk.kind)
        default: // The patterns that read a numeric offset.
            return readOffsetChunk(chunk.kind)
        }
    }

    private mutating func readMonth(_ kind: DateChunkKind) -> Bool {
        if kind == .longMonth || kind == .month {
            let table = kind == .longMonth ? DateNameTables.longMonthNames
                : DateNameTables.shortMonthNames
            guard let index = reader.lookup(table: table) else {
                return false
            }
            fields.month = index + 1
            return true
        }
        guard let month = reader.readNumber(fixed: kind == .zeroMonth) else {
            return false
        }
        if month <= 0 || month > 12 {
            return false
        }
        fields.month = month
        return true
    }

    private mutating func readDay(_ kind: DateChunkKind) -> Bool {
        // `_2` is a day with an optional leading space. The underscore is not part of the prefix
        // `skip` matches, so the space is consumed here.
        if kind == .underDay, reader.startsWithSpace {
            reader.consume(1)
        }
        guard let day = reader.readNumber(fixed: kind == .zeroDay) else {
            return false
        }
        fields.day = day
        return true
    }

    private mutating func readYearDay(_ kind: DateChunkKind) -> Bool {
        // `__2` allows two optional spaces, one for each underscore.
        if kind == .underYearDay {
            for _ in 0..<2 {
                guard reader.startsWithSpace else {
                    break
                }
                reader.consume(1)
            }
        }
        guard let yearDay = reader.readNumber3(fixed: kind == .zeroYearDay) else {
            return false
        }
        fields.yearDay = yearDay
        return true
    }

    private mutating func readYear(_ kind: DateChunkKind) -> Bool {
        // Go reads the two characters of a two-digit year with `atoi`, which accepts a sign, and
        // the four-digit year checks a digit at position zero first, so a sign there is not a
        // match.
        guard let number = kind == .year ? reader.readSignedNumber(width: 2)
            : reader.readDigits(width: 4) else {
            return false
        }
        // Go splits the two-digit year at 69, because the Unix time starts on 31 December 1969 in
        // some zones.
        fields.year = kind == .year ? (number >= 69 ? 1900 + number : 2000 + number) : number
        return true
    }

    private mutating func readHour(_ kind: DateChunkKind) -> Bool {
        guard let hour = reader.readNumber(fixed: kind == .zeroHour12) else {
            return false
        }
        // Twelve is allowed for the twelve-hour patterns, because twelve is noon or midnight; the
        // twenty-four-hour pattern stops at twenty-three.
        if hour < 0 || hour > (kind == .hour ? 23 : 12) {
            return false
        }
        fields.hour = hour
        return true
    }

    private mutating func readMinute(_ kind: DateChunkKind) -> Bool {
        guard let minute = reader.readNumber(fixed: kind == .zeroMinute) else {
            return false
        }
        if minute < 0 || minute >= 60 {
            return false
        }
        fields.minute = minute
        return true
    }

    private mutating func readSecond(_ kind: DateChunkKind, remaining: [UInt8]) -> Bool {
        guard let second = reader.readNumber(fixed: kind == .zeroSecond) else {
            return false
        }
        if second < 0 || second >= 60 {
            return false
        }
        fields.second = second

        // Go's special case: a fraction in the value with no fractional chunk in the layout.
        guard reader.remainingCount >= 2, reader.isSeparator(at: 0), reader.isDigit(at: 1) else {
            return true
        }
        if DateChunkScanner.nextChunk(in: remaining).kind.isFractional {
            return true
        }
        var digits = 2
        while digits < reader.remainingCount && reader.isDigit(at: digits) {
            digits += 1
        }
        guard let nanoseconds = reader.readNanoseconds(length: digits) else {
            return false
        }
        fields.nanoseconds = nanoseconds
        return true
    }

    private mutating func readAmPm(_ kind: DateChunkKind) -> Bool {
        guard reader.remainingCount >= 2 else {
            return false
        }
        switch reader.take(2) {
        case kind == .pm ? "PM" : "pm":
            pmSet = true
        case kind == .pm ? "AM" : "am":
            amSet = true
        default:
            return false
        }
        return true
    }

    private mutating func readZoneName() -> Bool {
        if reader.has("UTC") {
            resolvedToUtc = true
            reader.consume(3)
            return true
        }
        guard let name = reader.readZoneName() else {
            return false
        }
        zoneName = name
        return true
    }

    private mutating func readOffsetChunk(_ kind: DateChunkKind) -> Bool {
        // Only the three patterns without seconds accept a literal `Z` for UTC.
        if kind.acceptsLiteralZ, reader.has("Z") {
            resolvedToUtc = true
            reader.consume(1)
            return true
        }
        guard let offset = reader.readOffset(kind: kind) else {
            return false
        }
        zoneOffset = offset
        return true
    }

    private mutating func readFractional(_ kind: DateChunkKind) -> Bool {
        switch kind {
        case .fractionalSeconds0(let digits):
            // The exact number of digits the layout asks for.
            guard let nanoseconds = reader.readNanoseconds(length: 1 + digits) else {
                return false
            }
            fields.nanoseconds = nanoseconds
            return true
        case .fractionalSeconds9:
            guard reader.remainingCount >= 2, reader.isSeparator(at: 0), reader.isDigit(at: 1) else {
                return true // The fraction may be omitted.
            }
            // Any number of digits is taken, even more than the layout asks for.
            var digits = 1
            while digits + 1 < reader.remainingCount && reader.isDigit(at: digits + 1) {
                digits += 1
            }
            guard let nanoseconds = reader.readNanoseconds(length: 1 + digits) else {
                return false
            }
            fields.nanoseconds = nanoseconds
            return true
        default:
            return false
        }
    }

    private mutating func build() -> ParsedDate? {
        if pmSet && fields.hour < 12 {
            fields.hour += 12
        } else if amSet && fields.hour == 12 {
            fields.hour = 0
        }

        guard let wallSeconds = fields.wallSeconds() else {
            return nil
        }
        let offset = resolvedOffset
        return ParsedDate(epochSeconds: wallSeconds - Int64(offset),
            nanoseconds: Int64(fields.nanoseconds), zoneName: resolvedName,
            zoneOffsetSeconds: offset)
    }

    /// Go's order: an explicit UTC wins, then an offset the layout read, then the name, and finally
    /// the default location, which is UTC for this port and for Go's `Parse` alike.
    private var resolvedOffset: Int {
        if resolvedToUtc {
            return 0
        }
        if zoneOffset != -1 {
            return zoneOffset
        }
        return zoneName.isEmpty ? 0 : DateZoneTable.offset(forName: zoneName)
    }

    private var resolvedName: String {
        if resolvedToUtc {
            return "UTC"
        }
        if !zoneName.isEmpty || zoneOffset != -1 {
            // The name is reported as it was parsed, which for a bare numeric offset is empty.
            return zoneName
        }
        return "UTC"
    }
}
