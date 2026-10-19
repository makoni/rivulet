import Foundation
import FluentKit

/// A downloaded feed icon, deduplicated by content hash.
///
/// `hash` is the SHA-256 of the icon content; icons with the same hash are
/// stored once and shared by every feed that uses them. `externalID` is a
/// random, stable identifier for the public feed-icon URL.
///
/// `@unchecked Sendable` is safe: an instance is created, populated and used
/// inside a single `SQLiteStorage.withConnection` checkout and is never
/// shared between tasks (the FluentKit property wrappers it holds are
/// `@unchecked Sendable` as well).
public final class Icon: Model, @unchecked Sendable {
    /// The `icons` table; this FluentKit version has no schema-name default.
    public static let schema = "icons"

    /// Primary key, database-generated on create.
    @ID(custom: .id) public var id: Int?

    /// SHA-256 of the content, unique.
    @Field(key: "hash") public var hash: String

    /// Content type of the icon, normalized by ``IconRepository/insert(hash:mimeType:content:)``.
    @Field(key: "mime_type") public var mimeType: String

    /// Raw icon bytes.
    @Field(key: "content") public var content: Data

    /// Random identifier for the public feed-icon URL.
    @Field(key: "external_id") public var externalID: String

    /// Unix seconds; creation time.
    @Field(key: "created_at") public var createdAt: Int

    /// Creates an unfilled icon; the repositories populate and persist it.
    ///
    /// Fields must be set before the instance is used with a query.
    public init() {}
}
