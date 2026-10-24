// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/date/parser.go
// (`Parse`); adapted for Swift/SQLite.

import Foundation

/// Date parsing as the reference does it: an integer Unix timestamp wins over every layout, then
/// the local-time group, then the layout list over the normalized input, and finally the offset
/// clamp. The reference's zone workaround for the local-time group — Los Angeles for `PST` and
/// `PDT`, New York for `EST` and `EDT` — is the fixed table in ``DateZoneTable``, so the two groups
/// read the same way here and only the order of the layouts is kept separate. Falling back to the
/// current time when nothing matched is the adapters' job, not this entry point's, because it needs
/// a clock; this point only reports the failure the reference would have produced.
enum FeedDateParser {
    static func parse(_ input: String) throws -> ParsedDate {
        let trimmed = asciiTrimmed(input)
        guard !trimmed.isEmpty else {
            throw DateParseError.empty
        }

        if let seconds = Int64(trimmed) {
            return ParsedDate(epochSeconds: seconds, nanoseconds: 0, zoneName: "UTC",
                zoneOffsetSeconds: 0)
        }

        let normalized = DateInputNormalizer.normalized(trimmed)
        for layout in DateLayoutCatalog.localTimeOnlyLayouts + DateLayoutCatalog.layouts {
            if let parsed = DateLayoutEngine.parse(layout: layout, value: normalized) {
                return clamped(parsed)
            }
        }

        // The reference reports the trimmed input, not the normalized one.
        throw DateParseError.failedToParse(input: trimmed)
    }

    /// `checkTimezoneRange`: an offset outside −12:00 to +14:00 is reported as UTC, and the instant
    /// stays as it was read.
    private static func clamped(_ parsed: ParsedDate) -> ParsedDate {
        guard parsed.zoneOffsetSeconds > 14 * 3_600 || parsed.zoneOffsetSeconds < -12 * 3_600 else {
            return parsed
        }
        return ParsedDate(epochSeconds: parsed.epochSeconds, nanoseconds: parsed.nanoseconds,
            zoneName: "UTC", zoneOffsetSeconds: 0)
    }

    /// Go's `TrimSpace` also trims Unicode whitespace, which this port does not; that is recorded
    /// in `docs/parity.md`. The two sets differ only for characters a feed date would not carry.
    private static func asciiTrimmed(_ input: String) -> String {
        let bytes = Array(input.utf8)
        var start = 0
        var end = bytes.count
        while start < end && asciiSpace.contains(bytes[start]) {
            start += 1
        }
        while end > start && asciiSpace.contains(bytes[end - 1]) {
            end -= 1
        }
        return String(decoding: bytes[start..<end], as: UTF8.self)
    }

    /// Go's `asciiSpace` table.
    private static let asciiSpace: Set<UInt8> = [9, 10, 11, 12, 13, 32]
}
