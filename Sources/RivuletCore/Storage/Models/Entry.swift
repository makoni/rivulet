import FluentKit

/// One feed item: the unit clients list, read, mark and star.
///
/// Identity is `(feedID, hash)`: a refresh matches parsed items against stored
/// entries by the hash the parser derives (see `docs/reference-notes.md`), so a
/// re-imported GUID updates the stored row instead of duplicating it.
///
/// `content` holds sanitized HTML; `contentText` is the plain text extracted
/// from it at write time and indexed by FTS5. `status` and `starred` are the
/// user's state: a feed refresh never overwrites them, while the user-state
/// mutations stamp `updatedAt` (upstream `changed_at`). `publishedAt` is feed
/// data that the reference likewise leaves alone on refresh.
///
/// `@unchecked Sendable` is safe: an instance is created, populated and used
/// inside a single `SQLiteStorage.withTransaction` checkout and is never
/// shared between tasks (the FluentKit property wrappers it holds are
/// `@unchecked Sendable` as well).
public final class Entry: Model, @unchecked Sendable {
    /// The `entries` table; this FluentKit version has no schema-name default.
    public static let schema = "entries"

    /// Primary key, database-generated on create.
    @ID(custom: .id) public var id: Int?

    /// Owner of the entry.
    @Field(key: "user_id") public var userID: Int

    /// Feed the entry was parsed from.
    @Field(key: "feed_id") public var feedID: Int

    /// Parser-derived identity, unique per feed.
    @Field(key: "hash") public var hash: String

    /// Entry title; empty when the feed has none.
    @Field(key: "title") public var title: String

    /// Link to the original item; empty when the feed has none.
    @Field(key: "url") public var url: String

    /// Author, as the feed declared it; empty when absent.
    @Field(key: "author") public var author: String

    /// Sanitized HTML content.
    @Field(key: "content") public var content: String

    /// Plain text extracted from ``content`` at write time, indexed by FTS5.
    @Field(key: "content_text") public var contentText: String

    /// Read state of the owner.
    @Enum(key: "status") public var status: EntryStatus

    /// Whether the owner starred the entry; starred entries are never purged.
    @Field(key: "starred") public var starred: Bool

    /// Publication time supplied by the feed, or the parse time when absent;
    /// preserved across refreshes.
    @Field(key: "published_at") public var publishedAt: Int

    /// Unix seconds; creation time.
    @Field(key: "created_at") public var createdAt: Int

    /// Unix seconds; stamped by user-state mutations, untouched by refreshes.
    @Field(key: "updated_at") public var updatedAt: Int

    /// Creates an unfilled entry; the repositories populate and persist it.
    ///
    /// Fields must be set before the instance is used with a query.
    public init() {}
}
