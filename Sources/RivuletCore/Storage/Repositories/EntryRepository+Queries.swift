// Ported from Miniflux internal/storage/entry.go, internal/storage/entry_query_builder.go
// and internal/storage/enclosure.go (Apache-2.0); adapted for Swift/SQLite.
import FluentKit
import SQLKit

/// Entry listings: filters, pagination, counts and full-text search.
///
/// Kept in a separate file from the write path: this extension only reads, and
/// it holds the SQL builder that mirrors the reference's `EntryQueryBuilder`.
extension EntryRepository {
    /// Returns the enclosures of `entryIDs`, grouped by entry and ordered by
    /// id.
    ///
    /// The reference fetches the enclosures of a whole listing in one query
    /// (upstream `EnclosuresByEntryIDs`), which is what the client APIs need
    /// for `stream/items/contents`. Enclosures carry no user id, so callers
    /// pass ids from a user-scoped listing.
    public func fetchEnclosures(entryIDs: [Int]) async throws -> [Int: [Enclosure]] {
        guard !entryIDs.isEmpty else { return [:] }
        let enclosures = try await Enclosure.query(on: database)
            .filter(\Enclosure.$entryID ~~ entryIDs)
            .sort(\Enclosure.$id)
            .all()
        return Dictionary(grouping: enclosures, by: \.entryID)
    }

    // MARK: - Listings

    /// Returns the entries matching `query`, in query order.
    ///
    /// Search results are ordered by relevance first and by
    /// ``EntryQuery/sort`` afterwards. An unbounded query loads every matching
    /// row, so callers pass a limit for pages and reserve `nil` for explicit id
    /// sets (`stream/items/contents`).
    public func list(_ query: EntryQuery) async throws -> [Entry] {
        let rows = try await RawSQL.sql(on: database)
            .raw(Self.selectSQL(query, columns: Self.entryColumns, paginate: true))
            .all()
        return try rows.map(Self.entry(from:))
    }

    /// Returns the ids of the entries matching `query`, in query order.
    ///
    /// The reference uses the same builder for id lists, which is how the
    /// Fever API returns every unread or saved id without loading the rows.
    public func listIDs(_ query: EntryQuery) async throws -> [Int] {
        let rows = try await RawSQL.sql(on: database)
            .raw(Self.selectSQL(query, columns: "e.id", paginate: true))
            .all()
        return try rows.map { try $0.decode(column: "id", as: Int.self) }
    }

    /// Returns how many entries match `query`, ignoring ``EntryQuery/limit``
    /// and ``EntryQuery/offset`` (upstream `CountEntries`).
    public func count(_ query: EntryQuery) async throws -> Int {
        let row = try await RawSQL.sql(on: database)
            .raw(Self.selectSQL(query, columns: "COUNT(*) AS count", paginate: false))
            .first()
        return try row?.decode(column: "count", as: Int.self) ?? 0
    }

    // MARK: - Query helpers

    /// Columns decoded by ``entry(from:)``.
    private static let entryColumns: SQLQueryString = """
        e.id, e.user_id, e.feed_id, e.hash, e.title, e.url, e.author,
        e.content, e.content_text, e.status, e.starred,
        e.published_at, e.created_at, e.updated_at
        """

    /// What ``EntryQuery/search`` asks the listing to do.
    private enum SearchFilter {
        /// No search filter.
        case none
        /// A MATCH expression built from the user's terms.
        case matching(String)
        /// The input contains no searchable term (for example only quotes).
        case noTerms

        /// Classifies the raw search text.
        init(_ search: String?) {
            guard let text = search, !text.isEmpty else {
                self = .none
                return
            }
            if let expression = EntryQuery.ftsExpression(for: text) {
                self = .matching(expression)
            } else {
                self = .noTerms
            }
        }

        /// Whether the listing joins and ranks the FTS index.
        var isMatching: Bool {
            if case .matching = self { return true }
            return false
        }
    }

    /// Builds a `SELECT` over entries joined with their feeds.
    ///
    /// The reference always joins `feeds` for the category filter and adds the
    /// FTS relation for search (`internal/storage/entry_query_builder.go`);
    /// the same shape works in SQLite. `paginate` adds the ordering, `LIMIT`
    /// and `OFFSET`; `count` leaves them out.
    private static func selectSQL(
        _ query: EntryQuery,
        columns: SQLQueryString,
        paginate: Bool
    ) -> SQLQueryString {
        let search = SearchFilter(query.search)
        var sql: SQLQueryString = "SELECT \(columns) FROM entries e JOIN feeds f ON f.id = e.feed_id"
        if search.isMatching {
            sql += " JOIN entries_fts ON entries_fts.rowid = e.id"
        }

        var conditions = filterConditions(for: query)
        switch search {
        case .none:
            break
        case .matching(let expression):
            conditions.append("entries_fts MATCH \(bind: expression)")
        case .noTerms:
            // Match nothing instead of silently dropping the filter.
            conditions.append("1 = 0")
        }
        sql += " WHERE " + conditions.joined(separator: SQLRaw(" AND "))

        if paginate {
            sql += orderClause(for: query, ranked: search.isMatching)
            sql += paginationClause(for: query)
        }
        return sql
    }

    /// The `WHERE` conditions of `query`, in a fixed order.
    private static func filterConditions(for query: EntryQuery) -> [SQLQueryString] {
        var conditions: [SQLQueryString] = ["e.user_id = \(bind: query.userID)"]
        if let feedID = query.feedID {
            conditions.append("e.feed_id = \(bind: feedID)")
        }
        if let categoryID = query.categoryID {
            conditions.append("f.category_id = \(bind: categoryID)")
        }
        if !query.entryIDs.isEmpty {
            conditions.append("e.id IN (\(binds: query.entryIDs))")
        }
        if !query.statuses.isEmpty {
            conditions.append("e.status IN (\(binds: query.statuses.map(\.rawValue)))")
        }
        if let starred = query.starred {
            conditions.append("e.starred = \(bind: starred)")
        }
        if let publishedAfter = query.publishedAfter {
            conditions.append("e.published_at > \(bind: publishedAfter)")
        }
        if let publishedBefore = query.publishedBefore {
            conditions.append("e.published_at < \(bind: publishedBefore)")
        }
        if let afterID = query.afterID {
            conditions.append("e.id > \(bind: afterID)")
        }
        if let beforeID = query.beforeID {
            conditions.append("e.id < \(bind: beforeID)")
        }
        return conditions
    }

    /// `ORDER BY` for a listing, with the relevance order first when searching.
    ///
    /// The reference appends its rank expression after an explicit sort in the
    /// REST API; Rivulet makes relevance primary and the requested sort the
    /// tiebreaker, because every query carries a sort and a date-first order
    /// would make search useless. The recency component of the reference rank
    /// is not ported: `ts_rank` and `bm25()` live on different scales, and a
    /// fixed age term either vanishes in `bm25()`'s noise or dominates it. The
    /// 2.5:1 column weights approximate PostgreSQL's title `A` (1.0) and
    /// content `B` (0.4) weights.
    private static func orderClause(for query: EntryQuery, ranked: Bool) -> SQLQueryString {
        var order: [SQLQueryString] = []
        if ranked {
            order.append("bm25(entries_fts, 2.5, 1.0) ASC")
        }
        let direction: SQLQueryString = query.sort.direction == .ascending ? "ASC" : "DESC"
        switch query.sort.field {
        case .publishedAt:
            // The id makes pagination deterministic when dates collide.
            order.append("e.published_at \(direction)")
            order.append("e.id \(direction)")
        case .id:
            order.append("e.id \(direction)")
        }
        return " ORDER BY " + order.joined(separator: SQLRaw(", "))
    }

    /// `LIMIT`/`OFFSET` for a listing.
    private static func paginationClause(for query: EntryQuery) -> SQLQueryString {
        var sql: SQLQueryString = ""
        if let limit = query.effectiveLimit {
            sql += " LIMIT \(bind: limit)"
        } else if query.effectiveOffset > 0 {
            // SQLite requires LIMIT before OFFSET; -1 means "no limit".
            sql += " LIMIT -1"
        }
        if query.effectiveOffset > 0 {
            sql += " OFFSET \(bind: query.effectiveOffset)"
        }
        return sql
    }

    /// Rebuilds an ``Entry`` from a row selected by ``selectSQL``.
    private static func entry(from row: any SQLRow) throws -> Entry {
        let entry = Entry()
        entry.id = try row.decode(column: "id", as: Int.self)
        entry.userID = try row.decode(column: "user_id", as: Int.self)
        entry.feedID = try row.decode(column: "feed_id", as: Int.self)
        entry.hash = try row.decode(column: "hash", as: String.self)
        entry.title = try row.decode(column: "title", as: String.self)
        entry.url = try row.decode(column: "url", as: String.self)
        entry.author = try row.decode(column: "author", as: String.self)
        entry.content = try row.decode(column: "content", as: String.self)
        entry.contentText = try row.decode(column: "content_text", as: String.self)
        entry.status = try row.decode(column: "status", as: EntryStatus.self)
        entry.starred = try row.decode(column: "starred", as: Bool.self)
        entry.publishedAt = try row.decode(column: "published_at", as: Int.self)
        entry.createdAt = try row.decode(column: "created_at", as: Int.self)
        entry.updatedAt = try row.decode(column: "updated_at", as: Int.self)
        // The row is stored: mark the identity as persisted, so the returned value
        // behaves like a fetched model (FluentKit precondition for update/save).
        entry._$idExists = true
        return entry
    }
}
