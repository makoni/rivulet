// Ported from Miniflux internal/storage/api_key.go and the UserByAPIKey half of
// internal/storage/user.go (Apache-2.0); adapted for Swift/SQLite.

import Foundation
import FluentKit

/// Creates and reads api keys.
///
/// - See: ``SQLiteStorage/withConnection(_:)`` — the repository takes the checked-out connection
/// and lives inside that checkout.
public struct ApiKeyRepository {
    private let database: any Database

    /// Creates the repository around a checked-out connection.
    public init(_ database: any Database) {
        self.database = database
    }

    /// `CreateAPIKey`: the row written with the token the caller generated and the description as
    /// it was given — the reference writes `description` as submitted, with no `LOWER`, which
    /// `ApiKeyRepositoryTests` pins. The last-use column is stamped by nothing at write, which the
    /// same pin reads; the reference's `last_used_at` is updated by its request path, which this
    /// port has no piece for. The create instant is the port's own write time, so it is stated
    /// rather than pinned.
    public func create(userID: Int, token: String, description: String) async throws -> ApiKey {
        let key = ApiKey()
        key.userID = userID
        key.token = token
        key.description = description
        key.createdAt = Int(Date.now.timeIntervalSince1970)
        try await key.create(on: database)
        return key
    }

    /// `APIKeyExists`: the duplicate answer for one account, read as the reference's `SELECT true
    /// FROM api_keys WHERE user_id=$1 AND lower(description)=lower($2) LIMIT 1` reads it — both
    /// sides lowercase, which `ApiKeyRepositoryTests` pins, and the check is for the account it is
    /// given, which the same pin reads against a row of another user. `LOWER` on SQLite is
    /// ASCII-only, which the stage-5 auth header records. The single row is what the reference
    /// reads; no pin can tell a single-row read from one that read every match, so the limit is
    /// stated here.
    public func apiKeyExists(userID: Int, description: String) async throws -> Bool {
        let row = try await RawSQL.sql(on: database).raw("""
            SELECT true AS found FROM api_keys
            WHERE user_id = \(bind: userID) AND LOWER(description) = LOWER(\(bind: description))
            LIMIT 1
            """).first()
        guard let row else { return false }
        return try row.decode(column: "found", as: Int.self) == 1
    }

    /// `UserByAPIKey`: the account the key belongs to, reached through the join, with the token
    /// compared as read — the statement carries no `LOWER`, unlike the account-name lookup, which
    /// `UserRepositoryTests` pins through the control. Which row the join reaches is the rule
    /// `ApiKeyRepositoryTests` pins. For "no row" the port answers `nil`, which is what the
    /// reference answers too. The single row is what the reference reads through `QueryRow`, so the
    /// limit is stated here rather than pinned.
    public func userByAPIKey(_ token: String) async throws -> User? {
        let row = try await RawSQL.sql(on: database).raw("""
            SELECT u.id FROM users u
            INNER JOIN api_keys ON api_keys.user_id = u.id
            WHERE api_keys.token = \(bind: token)
            LIMIT 1
            """).first()
        guard let row else { return nil }
        return try await UserRepository(database).fetch(id: try row.decode(column: "id", as: Int.self))
    }
}
