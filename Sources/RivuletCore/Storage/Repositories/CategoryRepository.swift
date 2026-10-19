// Ported from Miniflux internal/storage/category.go (Apache-2.0); adapted for Swift/SQLite.
import Foundation
import FluentKit

/// Creates, lists and deletes categories.
///
/// - See: ``SQLiteStorage/withConnection(_:)`` — the repository takes the
///   checked-out connection and lives inside that checkout.
public struct CategoryRepository {
    private let database: any Database

    /// Creates the repository around a checked-out connection.
    public init(_ database: any Database) {
        self.database = database
    }

    /// Creates a category at position 0.
    public func create(userID: Int, title: String) async throws -> Category {
        let now = Int(Date.now.timeIntervalSince1970)
        let category = Category()
        category.userID = userID
        category.title = title
        category.position = 0
        category.createdAt = now
        category.updatedAt = now
        try await category.create(on: database)
        return category
    }

    /// Returns the category with `id`, or `nil`.
    public func fetch(id: Int) async throws -> Category? {
        try await Category.query(on: database).filter(\Category.$id == id).first()
    }

    /// Returns the categories of `userID`, ordered by position then title.
    public func list(userID: Int) async throws -> [Category] {
        try await Category.query(on: database)
            .filter(\Category.$userID == userID)
            .sort(\Category.$position)
            .sort(\Category.$title)
            .all()
    }

    /// Deletes the category; its feeds (and their entries) cascade away.
    public func delete(id: Int) async throws {
        try await Category.query(on: database).filter(\Category.$id == id).delete()
    }
}
