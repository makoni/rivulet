// Ported from Miniflux internal/storage/feed.go `WeeklyFeedEntryCount` (Apache-2.0); adapted for
// Swift/SQLite.

import SQLKit

extension FeedRepository {
    /// The weekly entry count the entry-frequency mode divides the week by.
    ///
    /// The rule is the reference's (`WeeklyFeedEntryCount` at commit `c4d54f87`): the average gap
    /// between the entries of one feed inside one week, and the week rounded up over that gap —
    /// `CEIL(week / (span / (count - 1)))`. The reference's inner division is a real one, because
    /// PostgreSQL divides an interval by a scalar, so the gap keeps its fraction; the port computes
    /// the same value with whole arithmetic, `(week × (count - 1) + span - 1) / span`, which is the
    /// ceiling of a real division written as integers, and writes it that way because this SQLite
    /// driver has no `CEIL` at runtime.
    ///
    /// The average is undefined for a single entry, because `count - 1` is 0, so the reference
    /// guards it with `NULLIF` and `COALESCE` turns the no-value into 0; an empty feed
    /// answers 0 the same way. The count is read for the rows of one user, which is what
    /// the reference's `WHERE` clause keeps, and the week window is the instant the caller
    /// passes, the injected clock, which is the half a pin can read: the reference compares
    /// SQL `now()`, recorded in `docs/parity.md`. - Parameters:   - userID: The user the
    /// entries belong to; the reference scopes the count to it.   - feedID: The feed the
    /// entries belong to.   - now: The instant the week window is read from, which is the
    /// injected clock's value. - Returns: The weekly count, 0 when the average gap is
    /// undefined or the feed has no entries   inside the window.
    public func weeklyEntryCount(userID: Int, feedID: Int, now: Int) async throws -> Int {
        let sql = try RawSQL.sql(on: database)
        let row = try await sql.raw("""
            SELECT COALESCE((604800 * (n - 1) + span - 1) / span, 0) AS weekly_count
            FROM (
                SELECT COUNT(*) AS n, MAX(published_at) - MIN(published_at) AS span
                FROM entries
                WHERE entries.user_id = \(bind: userID)
                    AND entries.feed_id = \(bind: feedID)
                    AND entries.published_at >= \(bind: now - 604800)
            )
            """).first()

        return try row.flatMap { try $0.decode(column: "weekly_count", as: Int.self) } ?? 0
    }
}
