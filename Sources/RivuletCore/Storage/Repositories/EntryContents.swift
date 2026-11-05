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

    /// The entry's own fields.
    public var title: String
    public var url: String
    public var author: String
    public var content: String
    public var status: EntryStatus
    public var starred: Bool

    /// The three time columns the item document is built from, as whole seconds.
    public var publishedAt: Int
    public var createdAt: Int
    public var updatedAt: Int

    /// The attachments of this row, in the order the second statement reads them.
    public var attachments: [Enclosure]

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
