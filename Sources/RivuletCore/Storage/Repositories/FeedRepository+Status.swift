import Foundation
import SQLKit

extension FeedRepository {
    /// The feed-state snapshot `rivulet status` prints.
    ///
    /// The rows are read in id order, which is the order a script can compare between runs. SQL
    /// defines no order without the clause, so the pins show this one against the orders
    /// the storage would otherwise give: they seed rows whose url order and schedule order
    /// differ from the id order. The stamps are read as the row holds them, not as the
    /// schema's default, so a row that has never been fetched or scheduled answers `nil`
    /// rather than `0`. The counts are read from every row whatever its state, except
    /// `due`, which is the pick ``dueBatch(now:options:)`` makes at the instant the caller
    /// names — so the rules that read a zero as a switch show up in it, and
    /// `at_error_limit` is counted only for a positive limit, because for that switch there
    /// is no filter a row could be at. Like the batch, the snapshot is not scoped to a
    /// user. - Parameters:   - now: The instant the due rule reads; the reference calls SQL
    /// `now()`, here the caller     names the instant, which is what a pin can tell from
    /// the process clock.   - options: The values the batch rules read, as
    /// ``SchedulerOptions``. - Returns: The rows and the counts, as ``StatusSnapshot``.
    public func statusSnapshot(now: Int, options: SchedulerOptions) async throws -> StatusSnapshot {
        let sql = try RawSQL.sql(on: database)
        let rows = try await sql.raw("""
            SELECT id, user_id, url, site_url, title, disabled, fetched_at, next_check_at,
                parsing_error_count, parsing_error_message
            FROM feeds
            ORDER BY id ASC
            """).all()

        var feeds: [StatusSnapshot.Feed] = []
        var enabled = 0
        var disabled = 0
        var atErrorLimit = 0
        for row in rows {
            let errors = try row.decode(column: "parsing_error_count", as: Int.self)
            let isDisabled = try row.decode(column: "disabled", as: Int.self) != 0
            feeds.append(StatusSnapshot.Feed(
                id: try row.decode(column: "id", as: Int.self),
                userID: try row.decode(column: "user_id", as: Int.self),
                title: try row.decode(column: "title", as: String.self),
                url: try row.decode(column: "url", as: String.self),
                siteURL: try row.decode(column: "site_url", as: String.self),
                enabled: !isDisabled,
                fetchedAt: try row.decode(column: "fetched_at", as: (Int?).self),
                nextCheckAt: try row.decode(column: "next_check_at", as: (Int?).self),
                parsingErrorCount: errors,
                parsingErrorMessage: try row.decode(column: "parsing_error_message", as: String.self)
            ))
            if isDisabled {
                disabled += 1
            } else {
                enabled += 1
            }
            if options.parsingErrorLimit > 0 && errors >= options.parsingErrorLimit {
                atErrorLimit += 1
            }
        }

        // The due count is the batch's pick, so its rules are the ones `SchedulerBatchTests` pins.
        let due = try await dueBatch(now: now, options: options).count

        return StatusSnapshot(feeds: feeds,
            totals: StatusSnapshot.Totals(feeds: feeds.count, enabled: enabled, disabled: disabled,
                due: due, atErrorLimit: atErrorLimit))
    }
}
