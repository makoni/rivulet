// Ported from Miniflux internal/storage/batch.go (Apache-2.0); adapted for Swift/SQLite.

import SQLKit

extension FeedRepository {
    /// The due batch the tick reads, with the reference builder's rules.
    ///
    /// Each rule is the builder's (`internal/storage/batch.go` at commit `c4d54f87`): the due
    /// comparison is strict (`next_check_at < now()`); the error condition is appended only when
    /// the limit is positive, so the default zero means "no filter" rather than "cap at zero"; the
    /// disabled gate excludes a disabled feed; the rows are ordered by `next_check_at` ascending;
    /// the `LIMIT` clause is added only for a positive batch size; and the per-host limit applies
    /// while the rows are iterated — after the `LIMIT`, so it caps the rows read, not the jobs
    /// kept, and a smaller per-host count cannot pull in a row the `LIMIT` had already cut. The
    /// host is `urllib.Domain`: the parsed host with its port, the string as written when Go's
    /// parse fails, and no `www.` strip. The builder can also scope the batch to a user or a
    /// category; `feedScheduler` calls neither, so the batch is not user-scoped and each job
    /// carries the user of its own row.
    ///
    /// What this cannot show: `IS false` and `= 0` are equal on this schema because the column is
    /// NOT NULL; the order of rows that share one `next_check_at` is undefined in SQL; the log
    /// lines the builder emits have no place here, as `RivuletCore` has no logging layer.
    /// - Parameters:
    ///   - now: The instant the due rule reads. The reference calls SQL `now()`; here the caller
    ///     passes the injected clock's value, which is what a pin can tell from the process clock.
    ///   - options: The values the builder reads, as ``SchedulerOptions``.
    /// - Returns: The jobs, in the order the rows were read.
    public func dueBatch(now: Int, options: SchedulerOptions) async throws -> [RefreshJob] {
        let sql = try RawSQL.sql(on: database)

        // Conditions in the order `feedScheduler` appends them.
        var conditions: [SQLQueryString] = []
        if options.parsingErrorLimit > 0 {
            conditions.append("parsing_error_count < \(bind: options.parsingErrorLimit)")
        }
        conditions.append("disabled IS false")
        conditions.append("next_check_at < \(bind: now)")

        var query: SQLQueryString = "SELECT id, user_id, url FROM feeds"
        if !conditions.isEmpty {
            query += " WHERE " + conditions.joined(separator: SQLRaw(" AND "))
        }
        query += " ORDER BY next_check_at ASC"
        if options.batchSize > 0 {
            query += " LIMIT \(bind: options.batchSize)"
        }

        var jobs: [RefreshJob] = []
        var hosts: [String: Int] = [:]
        for row in try await sql.raw(query).all() {
            let feedURL = try row.decode(column: "url", as: String.self)
            if options.limitPerHost > 0 {
                let host = domain(feedURL)
                if hosts[host, default: 0] >= options.limitPerHost { continue }
                hosts[host] = hosts[host, default: 0] + 1
            }
            jobs.append(RefreshJob(feedID: try row.decode(column: "id", as: Int.self),
                userID: try row.decode(column: "user_id", as: Int.self), feedURL: feedURL))
        }
        return jobs
    }

    /// `urllib.Domain`: the parsed host with its port, or the string as written when the parse
    /// fails. The `www.` prefix is not part of this rule, and the port-less `Hostname` is not.
    private func domain(_ feedURL: String) -> String {
        guard let parsed = try? ParsedURL.parse(feedURL) else {
            return feedURL
        }
        return parsed.host
    }
}