import FluentKit

/// A named group of feeds belonging to a user.
///
/// Titles are unique per user; deleting a category cascades to its feeds.
/// `position` orders the category in listings.
public final class Category: Model, @unchecked Sendable {
    public static let schema = "categories"

    @ID(custom: .id) public var id: Int?

    /// Owner of the category.
    @Field(key: "user_id") public var userID: Int

    /// Display name, unique per user.
    @Field(key: "title") public var title: String

    /// Ordering value; lower comes first.
    @Field(key: "position") public var position: Int

    /// Unix seconds; creation time.
    @Field(key: "created_at") public var createdAt: Int

    /// Unix seconds; updated on every mutation.
    @Field(key: "updated_at") public var updatedAt: Int

    /// Creates an unfilled category; the repositories populate and persist it.
    ///
    /// Fields must be set before the instance is used with a query.
    public init() {}
}
