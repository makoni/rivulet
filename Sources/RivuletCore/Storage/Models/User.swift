import FluentKit

/// A Rivulet account.
///
/// A user owns categories and feeds; deleting a user cascades to everything
/// they own. `passwordHash` holds the bcrypt hash of the account password;
/// the integration credential pairs (Google Reader, Fever) start unset and
/// are assigned by the credential management commands.
public final class User: Model, @unchecked Sendable {
    public static let schema = "users"

    @ID(custom: .id) public var id: Int?

    /// Login name, unique across all users.
    @Field(key: "username") public var username: String

    /// Bcrypt hash of the account password.
    @Field(key: "password_hash") public var passwordHash: String

    /// Admin flag: admin users see every entry of every user.
    @Field(key: "is_admin") public var isAdmin: Bool

    /// Google Reader API login name, `nil` until the integration is enabled.
    @OptionalField(key: "google_reader_username") public var googleReaderUsername: String?

    /// Bcrypt hash of the Google Reader API password.
    @OptionalField(key: "google_reader_password_hash") public var googleReaderPasswordHash: String?

    /// Fever API login name, `nil` until the integration is enabled.
    @OptionalField(key: "fever_username") public var feverUsername: String?

    /// MD5 token used as the Fever `api_key`.
    @OptionalField(key: "fever_token") public var feverToken: String?

    /// Unix seconds; creation time.
    @Field(key: "created_at") public var createdAt: Int

    /// Unix seconds; updated on every mutation.
    @Field(key: "updated_at") public var updatedAt: Int

    /// Creates an unfilled user; the repositories populate and persist it.
    ///
    /// Fields must be set before the instance is used with a query.
    public init() {}
}
