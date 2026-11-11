// Ported from Miniflux internal/http/response/builder.go (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The caching rules the reference's response builder applies for a cached asset, which the icon
/// route runs. They are kept apart from the route so each rule is read by one place:
/// `CachingRulesTests` pins them as pure logic, and `IconRouteTests` pins the answer the route
/// builds with them.
enum CachingRules {
    /// `normalizeETag`: the quoted shape is added only when the value does not carry it already.
    static func etag(_ value: String) -> String {
        let etag = trim(value)
        if etag.isEmpty {
            return ""
        }
        if etag.hasPrefix("\"") || etag.hasPrefix("W/\"") {
            return etag
        }
        return "\"\(etag)\""
    }

    /// `ifNoneMatch`, read against the value `normalizeETag` produced. The comparison is weak: the
    /// prefix is dropped, and the header is read as containing the tag rather than as being equal
    /// to it.
    static func matchesNoneMatch(headerValue: String, etag: String) -> Bool {
        if headerValue.isEmpty || etag.isEmpty {
            return false
        }
        if trim(headerValue) == "*" {
            return true
        }
        let tag = etag.hasPrefix("W/") ? String(etag.dropFirst(2)) : etag
        return headerValue.contains(tag)
    }

    /// `Cache-Control`, built from the whole seconds of the bound. The reference counts them with
    /// `int64(duration.Seconds())`, which truncates toward zero, so the same is done here.
    static func cacheControl(_ duration: TimeInterval) -> String {
        "public, max-age=\(wholeSeconds(duration)), immutable"
    }

    /// `Expires`: the instant plus the whole bound — the reference does not count the seconds
    /// before adding them, it truncates only when it writes the value — written in the
    /// `http.TimeFormat` shape, in UTC.
    static func expires(now: Date, duration: TimeInterval) -> String {
        formatter.string(from: now.addingTimeInterval(duration))
    }

    /// The whole seconds of the bound, as the reference counts them for `Cache-Control`.
    private static func wholeSeconds(_ duration: TimeInterval) -> Int64 {
        Int64(duration)
    }

    /// `strings.TrimSpace`: the class Go reads with is Unicode `White_Space`, which is wider than
    /// Swift's `.whitespaces` — a newline, a vertical tab or a NEL on either side of the value is
    /// trimmed by the reference and not by `.whitespaces`. Both reads use this one class.
    private static func isSpace(_ character: Character) -> Bool {
        character.isWhitespace
    }

    private static func trim(_ value: String) -> String {
        var part = Substring(value)
        while part.first.map(isSpace) == true { part = part.dropFirst() }
        while part.last.map(isSpace) == true { part = part.dropLast() }
        return String(part)
    }

    /// `http.TimeFormat`, which is RFC 1123 with the zone written as `GMT` rather than as an
    /// offset. The locale is fixed, because the shape names English weekday and month
    /// abbreviations: the machine's locale is not part of the rule.
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter
    }()
}
