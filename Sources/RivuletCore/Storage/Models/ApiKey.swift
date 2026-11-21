import FluentKit

/// An api key: the value the token read finds an account by.
///
/// `token` is unique across all users, as the reference's `token text not null unique` is.
/// `lastUsedAt` is the reference's `last_used_at` column, which its request path stamps after the
/// read passes; this port has no piece that writes it yet, so a new row is written with nothing
/// there, which `ApiKeyRepositoryTests` pins. The reference's columns are `timestamp with time
/// zone`; this port's schema writes Unix seconds, as the rest of the schema does.
///
/// `@unchecked Sendable` is safe: an instance is created, populated and used inside a single
/// `SQLiteStorage.withConnection` checkout and is never shared between tasks (the FluentKit
/// property wrappers it holds are `@unchecked Sendable` as well).
public final class ApiKey: Model, @unchecked Sendable {
    /// The `api_keys` table; this FluentKit version has no schema-name default.
    public static let schema = "api_keys"

    /// Primary key, database-generated on create.
    @ID(custom: .id) public var id: Int?

    /// The account the key belongs to.
    @Field(key: "user_id") public var userID: Int

    /// The value a request carries as `X-Auth-Token`, unique across all users.
    @Field(key: "token") public var token: String

    /// What the user named the key, unique within the account.
    @Field(key: "description") public var description: String

    /// Unix seconds; nothing until the reference's request path stamps it, which this port does
    /// not.
    @OptionalField(key: "last_used_at") public var lastUsedAt: Int?

    /// Unix seconds; creation time.
    @Field(key: "created_at") public var createdAt: Int

    /// Creates an unfilled key; the repository populates and persists it.
    ///
    /// Fields must be set before the instance is used with a query.
    public init() {}
}
