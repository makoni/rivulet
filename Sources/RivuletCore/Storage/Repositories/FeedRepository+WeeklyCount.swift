// Ported from Miniflux internal/storage/feed.go `WeeklyFeedEntryCount` (Apache-2.0); adapted for
// Swift/SQLite.

import SQLKit

extension FeedRepository {
    /// The weekly entry count the entry-frequency mode divides the week by.
    ///
    /// The rule is the reference's (`WeeklyFeedEntryCount` at commit `c4d54f87`): the average gap
    /// between the entries of one feed inside one week, taken as whole division of the span by
    /// `count - 1`, and the week rounded up over that gap — `CEIL(week / (span / (count -
    /// 1)))`. The average is undefined for a single entry, because `count - 1` is 0, so the
    /// reference guards it with `NULLIF` and `COALESCE` turns the no-value into 0; an empty
    /// feed answers 0 the same way. The count is read for the rows of one user, which is
    /// what the reference's `WHERE` clause keeps, and the week window is the instant the
    /// caller passes, the injected clock, which is the half a pin can read: the reference
    /// compares SQL `now()`, recorded in `docs/parity.md`.
    ///
    /// The ceiling is written as whole arithmetic, `(week + gap - 1) / gap`, because the
    /// SQLite this port runs on does not answer `CEIL` for these builds; for a whole gap
    /// the two are the same number. What that shape cannot show is the case the reference's
    /// own division refuses: a span of 0 with more than one entry, which PostgreSQL raises
    /// and SQLite answers as null, and `COALESCE` turns into the same 0 — no case here can
    /// pin it, and `docs/parity.md` records it. The same is true of the error wrapping the
    /// reference's storage layer adds, because RivuletCore has no locale layer. -
    /// Parameters:   - userID: The user the entries belong to; the reference scopes the
    /// count to it.   - feedID: The feed the entries belong to.   - now: The instant the
    /// week window is read from, which is the injected clock's value. - Returns: The weekly
    /// count, 0 when the average gap is undefined or the feed has no entries   inside the
    /// window.
    public func weeklyEntryCount(userID: Int, feedID: Int, now: Int) async throws -> Int {
        let sql = try RawSQL.sql(on: database)
        let row = try await sql.raw("""
            SELECT COALESCE((604800 + gap - 1) / gap, 0) AS weekly_count
            FROM (
                SELECT (MAX(published_at) - MIN(published_at)) / NULLIF(COUNT(*) - 1, 0) AS gap
                FROM entries
                WHERE entries.user_id = \(bind: userID)
                    AND entries.feed_id = \(bind: feedID)
                    AND entries.published_at >= \(bind: now - 604800)
            )
            """).first()

        return try row.flatMap { try $0.decode(column: "weekly_count", as: Int.self) } ?? 0
    }
}
