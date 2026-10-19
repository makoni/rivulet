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
    /// the default "All" category (upstream parity: `CreateUser` creates the
    /// user and the category in one transaction; here they are two statements
    /// because the storage wrapper does not offer a multi-statement
    /// transaction yet, and a repository must not open a nested connection).
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

    /// Returns every user, ordered by username (upstream parity:
    /// `ORDER BY username ASC`).
    public func list() async throws -> [User] {
        try await User.query(on: database).sort(\User.$username).all()
    }
}
