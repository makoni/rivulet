// Ported from Miniflux internal/storage/entry_query_builder.go (Apache-2.0);
// adapted for Swift/SQLite.
import Foundation

/// Filters, ordering and pagination for entry listings.
///
/// Ported from the reference's `EntryQueryBuilder`
/// (`internal/storage/entry_query_builder.go`); this value type carries the same
/// knobs for ``EntryRepository/list(_:)``, ``EntryRepository/listIDs(_:)`` and
/// ``EntryRepository/count(_:)``. Every query is scoped to ``userID``.
///
/// Unlike the reference builder, an identifier that is set is always applied:
/// `feedID: 0` selects nothing instead of meaning "unset". Use `nil` for
/// "unset"; callers translating request parameters where zero means absent
/// must map zero to `nil` first.
public struct EntryQuery: Sendable, Equatable {
    /// The largest limit a query may request (upstream `MaxEntryLimit`).
    public static let maximumLimit = 1_000

    /// Owner whose entries are listed.
    public var userID: Int

    /// When set, only entries of this feed (upstream `WithFeedID`).
    public var feedID: Int?

    /// When set, only entries of feeds in this category (upstream
    /// `WithCategoryID`).
    public var categoryID: Int?

    /// When non-empty, only entries with one of these ids (upstream
    /// `WithEntryIDs`); an empty list means "any entry", as in the reference.
    public var entryIDs: [Int]

    /// When non-empty, only entries with one of these statuses (upstream
    /// `WithStatuses`); an empty list means "any status".
    public var statuses: [EntryStatus]

    /// When set, only entries whose starred flag has this value (upstream
    /// `WithStarred`).
    public var starred: Bool?

    /// Only entries published strictly after this Unix second (upstream
    /// `AfterPublishedDate`).
    public var publishedAfter: Int?

    /// Only entries published strictly before this Unix second (upstream
    /// `BeforePublishedDate`).
    public var publishedBefore: Int?

    /// Only entries with a strictly greater id (upstream `AfterEntryID`);
    /// powers the Fever `since_id` cursor.
    public var afterID: Int?

    /// Only entries with a strictly smaller id (upstream `BeforeEntryID`);
    /// powers the Fever `max_id` cursor.
    public var beforeID: Int?

    /// Full-text search over titles and the plain text extracted at write time.
    ///
    /// Bare words must all match and double quotes group a phrase (the common
    /// subset of the reference's `websearch_to_tsquery`); every term is
    /// re-quoted, so FTS5 operators in user input are searched as text. `nil`
    /// and the empty string mean "do not search" (the reference only skips the
    /// empty string); any other input is translated, so whitespace-only input
    /// or a lone quote has no searchable term and matches nothing.
    public var search: String?

    /// Ordering; search results are ranked by relevance first (see
    /// ``EntrySort``).
    public var sort: EntrySort

    /// Maximum number of rows to return. `nil` means unbounded, which is how
    /// the reference lists every matching id (Fever's unread/saved ids).
    /// Non-positive values and values above ``maximumLimit`` are clamped to
    /// ``maximumLimit`` (upstream `WithLimit`).
    public var limit: Int?

    /// Number of rows to skip (upstream `WithOffset`); negative values mean no
    /// offset.
    public var offset: Int

    /// Creates a query for the entries of `userID`.
    ///
    /// - Parameters:
    ///   - userID: Owner whose entries are listed.
    ///   - feedID: When set, restrict to this feed.
    ///   - categoryID: When set, restrict to the feeds of this category.
    ///   - entryIDs: When non-empty, restrict to these ids.
    ///   - statuses: When non-empty, restrict to these statuses.
    ///   - starred: When set, restrict to this starred flag.
    ///   - publishedAfter: Strict lower bound on `published_at` (Unix seconds).
    ///   - publishedBefore: Strict upper bound on `published_at` (Unix seconds).
    ///   - afterID: Strict lower bound on the entry id.
    ///   - beforeID: Strict upper bound on the entry id.
    ///   - search: Full-text query; `nil` for no search.
    ///   - sort: Ordering of the result.
    ///   - limit: Maximum rows; `nil` for unbounded.
    ///   - offset: Rows to skip.
    public init(
        userID: Int,
        feedID: Int? = nil,
        categoryID: Int? = nil,
        entryIDs: [Int] = [],
        statuses: [EntryStatus] = [],
        starred: Bool? = nil,
        publishedAfter: Int? = nil,
        publishedBefore: Int? = nil,
        afterID: Int? = nil,
        beforeID: Int? = nil,
        search: String? = nil,
        sort: EntrySort = .defaultOrder,
        limit: Int? = nil,
        offset: Int = 0
    ) {
        self.userID = userID
        self.feedID = feedID
        self.categoryID = categoryID
        self.entryIDs = entryIDs
        self.statuses = statuses
        self.starred = starred
        self.publishedAfter = publishedAfter
        self.publishedBefore = publishedBefore
        self.afterID = afterID
        self.beforeID = beforeID
        self.search = search
        self.sort = sort
        self.limit = limit
        self.offset = offset
    }

    /// The limit the SQL layer applies: `nil` for unbounded, otherwise
    /// `1...maximumLimit`.
    var effectiveLimit: Int? {
        guard let limit else { return nil }
        return limit <= 0 || limit > Self.maximumLimit ? Self.maximumLimit : limit
    }

    /// The offset the SQL layer applies; negative values mean zero.
    var effectiveOffset: Int {
        max(offset, 0)
    }
}

extension EntryQuery {
    /// Translates `search` into an FTS5 `MATCH` expression, or `nil` when the
    /// input has no searchable term.
    ///
    /// Bare words are joined with `AND` and double quotes group a phrase, which
    /// covers the common `websearch_to_tsquery` behaviour of the reference.
    /// Each term is quoted again, so FTS5 syntax (`AND`, `OR`, `NEAR`, `-`,
    /// `*`, unbalanced quotes) is searched as text and a malformed query can
    /// never make SQLite fail.
    static func ftsExpression(for search: String) -> String? {
        var terms: [String] = []
        var current = ""
        var inQuotes = false

        func finishTerm() {
            let term = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !term.isEmpty {
                terms.append(term)
            }
            current = ""
        }

        for character in search {
            if character == "\"" {
                inQuotes.toggle()
            } else if character.isWhitespace && !inQuotes {
                finishTerm()
            } else {
                current.append(character)
            }
        }
        finishTerm()

        guard !terms.isEmpty else { return nil }
        return terms.map { "\"\($0)\"" }.joined(separator: " AND ")
    }
}

/// Ordering of an entry listing (upstream `WithSorting`).
public struct EntrySort: Sendable, Equatable {
    /// Column used for ordering.
    public enum Field: Sendable, Equatable {
        /// Publication time (`published_at`).
        case publishedAt
        /// Entry id.
        case id
    }

    /// Direction of the order.
    public enum Direction: Sendable, Equatable {
        /// Ascending.
        case ascending
        /// Descending.
        case descending
    }

    /// Column to order by.
    public var field: Field

    /// Direction of the order.
    public var direction: Direction

    /// Creates a sort order.
    ///
    /// - Parameters:
    ///   - field: Column to order by.
    ///   - direction: Direction of the order.
    public init(field: Field, direction: Direction) {
        self.field = field
        self.direction = direction
    }

    /// The reference default: publication time, oldest first.
    public static let defaultOrder = EntrySort(field: .publishedAt, direction: .ascending)
}
