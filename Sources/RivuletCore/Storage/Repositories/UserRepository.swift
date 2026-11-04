// Ported from Miniflux internal/storage/user.go (Apache-2.0); adapted for Swift/SQLite.
import Foundation
import FluentKit

/// Creates and reads users.
///
/// - See: ``SQLiteStorage/withConnection(_:)`` — the repository takes the
///   checked-out connection and lives inside that checkout.
public struct UserRepository {
    private let database: any Database

    /// Creates the repository around a checked-out connection.
    public init(_ database: any Database) {
        self.database = database
    }

    /// Creates a user with the integration credentials unset, together with
    /// the default "All" category (upstream parity: `CreateUser` creates both
    /// in one transaction). They are two statements here: wrap the call in
    /// ``SQLiteStorage/withTransaction(_:)`` when the pair must be atomic; a
    /// repository must not open a nested connection itself.
    public func create(username: String, passwordHash: String, isAdmin: Bool) async throws -> User {
        let now = Int(Date.now.timeIntervalSince1970)
        let user = User()
        user.username = username.lowercased()
        user.passwordHash = passwordHash
        user.isAdmin = isAdmin
        user.createdAt = now
        user.updatedAt = now
        try await user.create(on: database)
        let categories = CategoryRepository(database)
        _ = try await categories.create(userID: try user.requireID(), title: "All")
        return user
    }

    /// Returns the user with `id`, or `nil`.
    public func fetch(id: Int) async throws -> User? {
        try await User.query(on: database).filter(\User.$id == id).first()
    }

    /// Returns the user with `username`, or `nil`.
    ///
    /// The lookup is case-insensitive (upstream parity): usernames are
    /// stored lowercase.
    public func fetch(username: String) async throws -> User? {
        try await User.query(on: database).filter(\User.$username == username.lowercased()).first()
    }

    /// Returns whether a user with `username` has a row (upstream parity: `UserExists`, which reads
    /// `SELECT true FROM users WHERE username=LOWER($1) LIMIT 1`).
    ///
    /// The lookup is case-insensitive because usernames are stored lowercase. The single row is
    /// what the reference reads; a pin cannot tell a single-row read from one that read every
    /// match, so the limit is stated here and `UserRepositoryTests` pins the case-insensitive read.
    public func userExists(username: String) async throws -> Bool {
        try await User.query(on: database).filter(\User.$username == username.lowercased()).first() != nil
    }

    /// Returns every user, ordered by username (upstream parity:
    /// `ORDER BY username ASC`).
    public func list() async throws -> [User] {
        try await User.query(on: database).sort(\User.$username).all()
    }

    /// Writes the integration credential fields of `user` and returns the row (upstream parity:
    /// `UpdateIntegration`, which writes the integration columns for one user).
    ///
    /// The names are written as they are given: upstream writes `fever_username=$9` as submitted,
    /// without the `LOWER` the account name gets, and `UserRepositoryTests` pins that. The values
    /// themselves are what the caller derived — the rules that choose them are pinned by
    /// `IntegrationValidationTests` and `IntegrationCredentialsTests`. `updated_at` is the port's
    /// own column, so it is stamped here; the reference's `integrations` table has no such column,
    /// and no pin can read a clock value, so the stamp is stated rather than pinned.
    public func updateIntegration(_ user: User, feverUsername: String?, feverToken: String?,
        googleReaderUsername: String?, googleReaderPasswordHash: String?) async throws -> User {
        user.feverUsername = feverUsername
        user.feverToken = feverToken
        user.googleReaderUsername = googleReaderUsername
        user.googleReaderPasswordHash = googleReaderPasswordHash
        user.updatedAt = Int(Date.now.timeIntervalSince1970)
        try await user.save(on: database)
        return user
    }

    /// `HasDuplicateFeverUsername`: another row holds this Fever name.
    ///
    /// The reference reads `SELECT true FROM integrations WHERE user_id != $1 AND fever_username=$2
    /// LIMIT 1` — the row the value is being checked for is excluded, and the value is compared as
    /// read, with no `LOWER`. `UserRepositoryTests` pins both, and the single-row limit is stated
    /// here because no pin can tell a single-row read from one that read every match.
    public func hasDuplicateFeverUsername(userID: Int, feverUsername: String) async throws -> Bool {
        try await User.query(on: database)
            .filter(\User.$id != userID)
            .filter(\User.$feverUsername == feverUsername)
            .first() != nil
    }

    /// `HasDuplicateGoogleReaderUsername`: another row holds this Google Reader name.
    ///
    /// The same two rules as the Fever read — the caller's own row excluded, the value compared as
    /// read — and each check reads its own column, which `UserRepositoryTests` pins. The single-row
    /// limit is stated here for the same reason as above.
    public func hasDuplicateGoogleReaderUsername(userID: Int,
        googleReaderUsername: String) async throws -> Bool {
        try await User.query(on: database)
            .filter(\User.$id != userID)
            .filter(\User.$googleReaderUsername == googleReaderUsername)
            .first() != nil
    }

    /// `UserByFeverToken`: the row whose Fever token matches, with both sides compared lowercase,
    /// as the reference's `lower(integrations.fever_token)=lower($1)` does. `ClientAuthTests` pins
    /// each side and that this read looks at the token column. The reference gates the read on
    /// `fever_enabled`, which this port has no column for, so that branch has nothing to pin here.
    /// For "no row" the port answers `nil`, which is what the reference does too. A row that stores
    /// nothing is not a match for an empty input, because `NULL` is not the empty value; upstream's
    /// `fever_token text default ''` on the integration row created for every user matches an empty
    /// input, so that half is a divergence and no pin here can show it. The single row is what the
    /// reference reads; no pin can tell a single-row read from one that read every match, so the
    /// limit is stated here, and it describes the statement that picks the row.
    public func userByFeverToken(_ token: String) async throws -> User? {
        let row = try await RawSQL.sql(on: database).raw("""
            SELECT id FROM users
            WHERE LOWER(fever_token) = LOWER(\(bind: token))
            LIMIT 1
            """).first()
        guard let row else { return nil }
        return try await fetch(id: try row.decode(column: "id", as: Int.self))
    }

    /// The read `GoogleReaderUserCheckPassword` is built on: the stored hash for one row. The name
    /// is compared as read, with no `LOWER`, unlike the account-name lookup, which
    /// `ClientAuthTests` pins through the control pin. The reference gates this read on
    /// `googlereader_enabled`, which this port has no column for, and reports an error both when no
    /// row matches and when the stored value is not a hash; this port answers `nil` for both, and
    /// the compare itself belongs to the application layer, through `BcryptHasher`, because
    /// `RivuletCore` must not depend on Vapor. The single row is what the reference reads, which no
    /// pin can tell from a read that fetched every match, so the limit is stated here. A row that
    /// stores nothing is `NULL` here where upstream's column defaults to an empty string, which
    /// `ClientAuthTests` reads on the port's side only.
    public func googleReaderPasswordHash(username: String) async throws -> String? {
        let row = try await User.query(on: database)
            .filter(\User.$googleReaderUsername == username)
            .first()
        return row?.googleReaderPasswordHash
    }

    /// The same row the hash read finds, with its id, for the handler that reads the user back from
    /// the id the transport found. The name is compared as read, like the hash read.
    public func googleReaderUser(username: String) async throws -> User? {
        try await User.query(on: database)
            .filter(\User.$googleReaderUsername == username)
            .first()
    }
}
