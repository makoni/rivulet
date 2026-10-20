import FluentKit

/// An attachment declared by an entry: a podcast episode, a PDF, an image.
///
/// Enclosures are written and replaced together with their entry by
/// ``EntryRepository``; the rows have no independent lifecycle.
///
/// `@unchecked Sendable` is safe: an instance is created, populated and used
/// inside a single `SQLiteStorage.withTransaction` checkout and is never
/// shared between tasks (the FluentKit property wrappers it holds are
/// `@unchecked Sendable` as well).
public final class Enclosure: Model, @unchecked Sendable {
    /// The `enclosures` table; this FluentKit version has no schema-name default.
    public static let schema = "enclosures"

    /// Primary key, database-generated on create.
    @ID(custom: .id) public var id: Int?

    /// Entry the attachment belongs to.
    @Field(key: "entry_id") public var entryID: Int

    /// Attachment URL; empty values are dropped on write.
    @Field(key: "url") public var url: String

    /// Content type declared by the feed, verbatim; empty when absent.
    @Field(key: "mime_type") public var mimeType: String

    /// Size in bytes as declared by the feed; zero when absent.
    @Field(key: "size") public var size: Int

    /// Creates an unfilled enclosure; the repositories populate and persist it.
    ///
    /// Fields must be set before the instance is used with a query.
    public init() {}
}
