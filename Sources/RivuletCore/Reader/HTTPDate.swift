import Foundation

/// Parses an HTTP-date (RFC 1123, the format `Expires` and `Retry-After` use) into Unix seconds.
///
/// The weekday is part of the format, as in the reference's `time.RFC1123` layout, so the comma
/// after it is required. The zone must be GMT/UTC or a numeric offset; Go reads any zone name and
/// applies its zone table, so a named zone other than GMT/UTC is not read here — a recorded
/// deviation in `docs/reference-notes.md`. A value that does not parse yields nil, which the
/// reference also treats as "no delay".
enum HTTPDate {
    /// Returns Unix seconds, or nil when `value` is not an HTTP-date.
    static func parse(_ value: String) -> Int? {
        let parts = value.split(separator: " ", omittingEmptySubsequences: true)
        // "Wed, 21 Oct 2015 07:28:00 GMT" → weekday with its comma, day, month, year, time, zone. The
        // reference's layout looks the weekday up in its day-name table, reads the day as two digits and
        // the year as four, and range-checks the fields — so a made-up weekday or an out-of-range clock
        // is not an HTTP-date either.
        guard parts.count == 6,
            parts[0].hasSuffix(","),
            dayNames.contains(String(parts[0].dropLast().lowercased().prefix(3))),
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
            (1...31).contains(day),
            clock.count == 3,
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

    /// Go's `shortDayNames`. Its parser matches the weekday as a case-insensitive prefix, so "Monday"
    /// is read as "Mon".
    private static let dayNames: Set<String> = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]

    /// Zone name or numeric offset, in minutes; nil for a name that is not an offset.
    private static func parseZoneOffset(_ value: String) -> Int? {
        guard value.hasPrefix("+") || value.hasPrefix("-") else {
            return nil
        }
        let sign = value.hasPrefix("-") ? -1 : 1
        let digits = value.dropFirst()
        guard digits.count == 4, let hours = Int(digits.prefix(2)), let minutes = Int(digits.suffix(2)) else {
            return nil
        }
        return sign * (hours * 60 + minutes)
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
