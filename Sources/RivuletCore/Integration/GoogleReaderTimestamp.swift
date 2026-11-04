// Ported from Miniflux internal/googlereader/handler.go's `ts` read in `markAllAsReadHandler`
// (Apache-2.0); adapted for Swift/SQLite.

/// The time the mark-as-read pass is bounded by.
///
/// The reference reads `ts` from the merged form, reports the error the integer read gives, and
/// then decides the unit by the length of the value as read: sixteen characters or more are
/// microseconds, fewer are seconds. A value that is not positive leaves the zero time, which the
/// handler replaces with the time it is running at, so the default is not a time the read answers.
///
/// What the pins cannot show: the part below a second, because this port's entry column holds whole
/// seconds; `GoogleReaderTimestampTests` names that, and the second boundary itself is pinned by
/// the storage read, which compares with `<`.
public enum GoogleReaderTimestamp {
    /// The `before` the pass is bounded by, in Unix seconds.
    ///
    /// - Parameters:
    ///   - value: the value as the form read answered it, or `nil` when the name is not carried.
    ///   - now: the time the caller is running at, which is what the reference uses for the zero
    ///     time.
    /// - Throws: ``GoParseInt/ParseError`` for a value the integer read cannot read.
    public static func before(value: String?, now: Int) throws -> Int {
        guard let value, !value.isEmpty else { return now }

        let parsed = try GoParseInt.parse(value)
        guard parsed > 0 else { return now }

        // The length is the length of the value as read, in bytes, which is what Go's `len()`
        // counts.
        if value.utf8.count >= 16 {
            return Int(parsed / 1_000_000)
        }
        return Int(parsed)
    }
}
