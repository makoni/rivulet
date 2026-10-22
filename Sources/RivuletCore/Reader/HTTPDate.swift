import Foundation

/// Parses an HTTP-date (RFC 1123, the format `Expires` and `Retry-After` use) into Unix seconds.
///
/// The value is read the way Go's `time.Parse` reads `time.RFC1123`: the three-letter weekday with its
/// comma, a two-digit day, the month name, a four-digit year, a clock whose minute and second are two
/// digits while the hour is not, and the zone. A value that does not parse yields nil, which the
/// reference also treats as "no delay".
///
/// Deviation: Go reads any zone name and looks it up in the local zone table, so `EST` shifts the time
/// when that table defines it (otherwise the name is kept with no offset). Go also accepts a signed hour
/// here (`+03`), but a bare `+03` is taken as a zone name with no offset — only `GMT+3` shifts the time —
/// while Rivulet reads only the four-digit `+hhmm` form and shifts for it. The value is split on spaces,
/// so a padded value is read: Go rejects a leading space before the weekday and text left after the zone,
/// though a run of spaces in the middle counts as one separator. Both are recorded in
/// `docs/reference-notes.md`.
enum HTTPDate {
    /// Returns Unix seconds, or nil when `value` is not an HTTP-date.
    static func parse(_ value: String) -> Int? {
        let parts = value.split(separator: " ", omittingEmptySubsequences: true)
        // "Wed, 21 Oct 2015 07:28:00 GMT" → weekday with its comma, day, month, year, time, zone. Go
        // consumes exactly three characters for the weekday, reads the day as two digits and the year as
        // four, fixes the minute and second at two digits while leaving the hour unfixed, and
        // range-checks the fields.
        guard parts.count == 6,
            parts[0].hasSuffix(","),
            parts[0].count == 4,
            dayNames.contains(String(parts[0].dropLast().lowercased())),
            parts[1].count == 2,
            parts[3].count == 4
        else {
            return nil
        }

        let month = months[parts[2].lowercased()]
        let day = Int(parts[1])
        let year = Int(parts[3])
        let clock = parts[4].split(separator: ":")
        guard
            let month, let day, let year,
            (1...31).contains(day), day <= daysIn(month: month, year: year),
            clock.count == 3,
            clock[0].count <= 2,
            clock[1].count == 2,
            clock[2].count == 2,
            let hour = Int(clock[0]), (0...23).contains(hour),
            let minute = Int(clock[1]), (0...59).contains(minute),
            let second = Int(clock[2]), (0...59).contains(second)
        else {
            return nil
        }

        var zoneOffset = 0
        if let offset = parseZoneOffset(String(parts[5])) {
            zoneOffset = offset
        } else if parts[5].lowercased() != "gmt", parts[5].lowercased() != "utc" {
            return nil
        }

        let days = daysFromCivil(year: year, month: month, day: day)
        return (days * 86_400 + hour * 3_600 + minute * 60 + second) - zoneOffset
    }

    private static let months: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
    ]

    /// Go's `shortDayNames`. Its parser consumes exactly three characters for the weekday, so the
    /// three-letter form is what this layout reads and `Monday` does not parse.
    private static let dayNames: Set<String> = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]

    /// Go validates the day against the month after parsing, so `31 Feb` is not a date.
    private static func daysIn(month: Int, year: Int) -> Int {
        let lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        if month == 2, (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) {
            return 29
        }
        return lengths[month - 1]
    }

    /// Zone name or numeric offset, in seconds — the unit the instant is computed in; nil for a name
    /// that is not an offset.
    ///
    /// Rivulet is stricter than Go at the boundary, and the two Go paths differ. Its numeric-zone path
    /// (`RFC1123Z`) reads fixed-width two-digit fields and allows an hour of 24 and a minute of 60
    /// (`hr > 24`, `mm > 60`), so `+2400` and `+0360` parse there. Its name path
    /// (`parseSignedOffset`, which is what `RFC1123` reaches) rejects anything above 23, so `+0730` fails
    /// there while `+03` and `GMT+3` parse. Rivulet reads only the four-digit form, with an hour of 0...23
    /// and a minute of 0...59, and it reads neither the short `+03` form nor a named zone other than
    /// GMT/UTC. Recorded in `docs/reference-notes.md`.
    private static func parseZoneOffset(_ value: String) -> Int? {
        guard value.hasPrefix("+") || value.hasPrefix("-") else {
            return nil
        }
        let sign = value.hasPrefix("-") ? -1 : 1
        let digits = value.dropFirst()
        guard digits.count == 4,
            let hours = Int(digits.prefix(2)), (0...23).contains(hours),
            let minutes = Int(digits.suffix(2)), (0...59).contains(minutes)
        else {
            return nil
        }
        return sign * (hours * 3_600 + minutes * 60)
    }

    /// Days from the Unix epoch to a proleptic Gregorian date (Howard Hinnant's algorithm).
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let monthIndex = (month + (month > 2 ? -3 : 9)) % 12
        let dayOfYear = (153 * monthIndex + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + yearOfEra / 400 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}
