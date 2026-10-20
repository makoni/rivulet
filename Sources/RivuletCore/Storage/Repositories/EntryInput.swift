/// The parsed fields of one entry, as the fetcher hands them to ``EntryRepository``.
///
/// This is the write-side value: the repository owns persistence concerns
/// (identity, defaults, timestamps, plain-text extraction, enclosures), so the
/// fetcher does not build Fluent models.
public struct EntryInput: Sendable {
    /// One attachment of an entry, stored as an `enclosures` row.
    public struct Enclosure: Sendable {
        /// Attachment URL; trimmed on write, empty values are dropped.
        public var url: String
        /// Content type declared by the feed.
        public var mimeType: String
        /// Size in bytes declared by the feed.
        public var size: Int

        /// Creates an attachment value.
        ///
        /// - Parameters:
        ///   - url: Attachment URL as parsed from the feed.
        ///   - mimeType: Content type declared by the feed; empty when absent.
        ///   - size: Size in bytes declared by the feed; zero when absent.
        public init(url: String, mimeType: String = "", size: Int = 0) {
            self.url = url
            self.mimeType = mimeType
            self.size = size
        }
    }

    /// Parser-derived identity, unique per feed.
    public var hash: String
    /// Entry title; empty when the feed has none.
    public var title: String
    /// Link to the original item; empty when the feed has none.
    public var url: String
    /// Author, as the feed declared it; empty when absent.
    public var author: String
    /// Sanitized HTML; the repository extracts the indexed plain text from it.
    public var content: String
    /// Publication time supplied by the feed, or the parse time when absent.
    public var publishedAt: Int
    /// Attachments declared by the feed.
    public var enclosures: [Enclosure]

    /// Creates an entry value.
    ///
    /// - Parameters:
    ///   - hash: Parser-derived identity, unique per feed.
    ///   - title: Entry title; empty when the feed has none.
    ///   - url: Link to the original item; empty when the feed has none.
    ///   - author: Author, as the feed declared it; empty when absent.
    ///   - content: Sanitized HTML content.
    ///   - publishedAt: Publication time supplied by the feed, or parse time.
    ///   - enclosures: Attachments declared by the feed.
    public init(
        hash: String,
        title: String = "",
        url: String = "",
        author: String = "",
        content: String = "",
        publishedAt: Int,
        enclosures: [Enclosure] = []
    ) {
        self.hash = hash
        self.title = title
        self.url = url
        self.author = author
        self.content = content
        self.publishedAt = publishedAt
        self.enclosures = enclosures
    }
}
