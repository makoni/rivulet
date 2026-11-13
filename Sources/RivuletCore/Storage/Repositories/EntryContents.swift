// Ported from Miniflux internal/storage/entry_query_builder.go's listing row (Apache-2.0); adapted
// for Swift/SQLite.

/// One row of the listing `stream/items/contents` reads: the entry fields with the values the join
/// adds, and the attachments of that entry.
///
/// The reference reads the two titles from two different rows — `f.title as feed_title` and
/// `c.title as category_title` — so the origin document and the categories list are built from two
/// values that a patch reading one for the other cannot answer the same for. The attachments come
/// from the second statement of the read, so a row with none carries the empty list rather than
/// nothing, which is what `docs/reference-notes.md` records as `make` writing `[]`.
public struct EntryContents: Sendable {
    /// Entry row id, which the item id is built from.
    public var entryID: Int

    /// Entry's feed row id, which the origin stream id is built from.
    public var feedID: Int

    /// The feed row's title, which the origin document is built from.
    public var feedTitle: String

    /// The feed row's site url, which the origin document is built from.
    public var siteURL: String

    /// The category row's title, which the categories list is built from.
    public var categoryTitle: String

    /// The entry's title, read from the `title` column of the same row.
    public var title: String

    /// The entry's url, read from the `url` column.
    public var url: String

    /// The entry's author, read from the `author` column.
    public var author: String

    /// The body, read from the `content` column, which is the sanitized HTML the parser left.
    public var content: String

    /// The state the row is in, read from the `status` column.
    public var status: EntryStatus

    /// The starred flag, read from the `starred` column.
    public var starred: Bool

    /// The publication time, read from the `published_at` column as a whole second.
    public var publishedAt: Int

    /// The instant the row was written, read from the `created_at` column as a whole second.
    public var createdAt: Int

    /// The instant the row last changed, read from the `updated_at` column as a whole second.
    public var updatedAt: Int

    /// The attachments of this row, in the order the second statement reads them.
    public var attachments: [Enclosure]

    /// A row as the read answered it, one field per column the statement names.
    public init(entryID: Int, feedID: Int, feedTitle: String, siteURL: String, categoryTitle: String,
        title: String, url: String, author: String, content: String, status: EntryStatus,
        starred: Bool, publishedAt: Int, createdAt: Int, updatedAt: Int, attachments: [Enclosure]) {
        self.entryID = entryID
        self.feedID = feedID
        self.feedTitle = feedTitle
        self.siteURL = siteURL
        self.categoryTitle = categoryTitle
        self.title = title
        self.url = url
        self.author = author
        self.content = content
        self.status = status
        self.starred = starred
        self.publishedAt = publishedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.attachments = attachments
    }
}
