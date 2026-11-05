import Foundation
import FluentKit
import SQLKit

extension FeedRepository {
    /// The feeds of `userID` in the order `rivulet list` prints them.
    ///
    /// The order is the reference's feed query builder (`internal/storage/feed_query_builder.go` at
    /// commit `c4d54f87`): the default sort expression is the parsing-error count descending, and
    /// the lowercased title is appended as the tiebreaker after whatever sort expressions the
    /// builder has. The pins show both halves against the orders the storage would otherwise give:
    /// they seed rows where the error count and the title order differ, and rows with equal counts
    /// whose titles separate only under the lowercased reading.
    ///
    /// The lowercasing is SQLite's `LOWER`, which is ASCII-only; the reference's `lower()` on
    /// PostgreSQL folds non-ASCII letters too. Recorded in `docs/reference-notes.md`, and not
    /// reachable by a pin that compares ASCII titles.
    ///
    /// - Parameter userID: The account the listing is read for.
    /// - Returns: The rows of this user, in the reference's order.
    public func listSortedByErrorCountThenTitle(userID: Int) async throws -> [Feed] {
        let sql = try RawSQL.sql(on: database)
        let rows = try await sql.raw("""
            SELECT id FROM feeds WHERE user_id = \(bind: userID)
            ORDER BY parsing_error_count DESC, LOWER(title) ASC
            """).all()

        var feeds: [Feed] = []
        for row in rows {
            let feedID = try row.decode(column: "id", as: Int.self)
            let feed = try await Feed.query(on: database).filter(\Feed.$id == feedID).first()
            if let feed { feeds.append(feed) }
        }
        return feeds
    }
}
