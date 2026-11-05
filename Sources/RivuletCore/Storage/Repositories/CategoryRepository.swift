// Ported from Miniflux internal/storage/category.go (Apache-2.0); adapted for Swift/SQLite.
import Foundation
import FluentKit
import SQLKit

/// Creates, lists and deletes categories.
///
/// - See: ``SQLiteStorage/withConnection(_:)`` — the repository takes the checked-out connection
///   and lives inside that checkout.
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

    /// The read the Google Reader tag list builds from upstream `Categories`: title alone, not
    /// position.
    public func listByTitle(userID: Int) async throws -> [Category] {
        try await Category.query(on: database)
            .filter(\Category.$userID == userID)
            .sort(\Category.$title)
            .all()
    }

    /// `CategoryByTitle`: the title is compared as it is given, with no `LOWER`, which is the
    /// difference from the duplicate read below.
    public func byTitle(userID: Int, title: String) async throws -> Category? {
        try await Category.query(on: database)
            .filter(\Category.$userID == userID)
            .filter(\Category.$title == title)
            .first()
    }

    /// `AnotherCategoryExists`: both sides are read through `LOWER`, and the category being checked
    /// is excluded, so a rename to its own title is not a duplicate. The single row is what the
    /// reference reads, and `LOWER` on SQLite is ASCII-only, which `ClientAuthTests` names.
    public func anotherTitleExists(userID: Int, categoryID: Int, title: String)
        async throws -> Bool {
        let row = try await RawSQL.sql(on: database).raw("""
            SELECT 1 FROM categories
            WHERE user_id = \(bind: userID)
                AND id != \(bind: categoryID)
                AND LOWER(title) = LOWER(\(bind: title))
            LIMIT 1
            """).first()
        return row != nil
    }

    /// `UpdateCategory` for the rename path: writes the title the request carries. The reference's
    /// statement also writes `hide_globally`, which this port's schema does not have, and it does
    /// not stamp `updated_at`, which this port stamps on every mutation.
    public func setTitle(userID: Int, categoryID: Int, title: String) async throws {
        try await Category.query(on: database)
            .filter(\Category.$userID == userID)
            .filter(\Category.$id == categoryID)
            .set(\Category.$title, to: title)
            .set(\Category.$updatedAt, to: Int(Date.now.timeIntervalSince1970))
            .update()
    }

    /// `RemoveAndReplaceCategoriesByName`: the guard counts the categories that are not named, so
    /// an input that would leave the user with none is reported before anything is written; the
    /// feeds of the named rows go to the first remaining category by title, and the titles are
    /// compared as read. The reference reads the count and the pick as two statements; this port
    /// reads the rows and takes the smallest title, which answers the same for every input that
    /// reaches them, and its comparison is Swift's `<`, which is the reference's
    /// `ORDER BY title ASC` order for the titles pinned here and not for the non-ASCII ones. The
    /// reference runs its three statements in a transaction; this port's transaction boundary is
    /// the caller's, so the pins name the statements and not the boundary.
    public func removeAndReplaceNamed(userID: Int, titles: [String]) async throws {
        let named = try await Category.query(on: database)
            .filter(\Category.$userID == userID)
            .filter(\Category.$title ~~ titles)
            .all()
        let remaining = try await Category.query(on: database)
            .filter(\Category.$userID == userID)
            .filter(\Category.$title !~ titles)
            .all()
        guard let firstRemaining = remaining.min(by: { $0.title < $1.title }),
            let firstID = firstRemaining.id else {
            throw DeleteError.leavesNone
        }

        let namedIDs = named.compactMap(\.id)
        if !namedIDs.isEmpty {
            try await Feed.query(on: database)
                .filter(\Feed.$userID == userID)
                .filter(\Feed.$categoryID ~~ namedIDs)
                .set(\Feed.$categoryID, to: firstID)
                .update()
        }

        try await Category.query(on: database)
            .filter(\Category.$userID == userID)
            .filter(\Category.$title ~~ titles)
            .delete()
    }

    /// Deletes the category; its feeds (and their entries) cascade away.
    public func delete(id: Int) async throws {
        try await Category.query(on: database).filter(\Category.$id == id).delete()
    }

    /// What the delete path reports for an input that would leave no category, with the reference's
    /// wording.
    public enum DeleteError: Error, CustomStringConvertible, Sendable {
        case leavesNone

        public var description: String {
            "store: at least 1 category must remain after deletion"
        }
    }
}
