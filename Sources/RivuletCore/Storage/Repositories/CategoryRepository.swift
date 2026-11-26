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

    /// Creates a category at position 0, with the value the request carries for the hide rule.
    public func create(userID: Int, title: String, hideGlobally: Bool = false) async throws -> Category {
        let now = Int(Date.now.timeIntervalSince1970)
        let category = Category()
        category.userID = userID
        category.title = title
        category.position = 0
        category.hideGlobally = hideGlobally
        category.createdAt = now
        category.updatedAt = now
        try await category.create(on: database)
        return category
    }

    /// Returns the category with `id`, or `nil`.
    public func fetch(id: Int) async throws -> Category? {
        try await Category.query(on: database).filter(\Category.$id == id).first()
    }

    /// `Category`: the row is read for the pair, so a row of another account with the same id is not
    /// this account's category, which `RestV1CategoryRouteTests` pins through the handler.
    public func fetch(userID: Int, id: Int) async throws -> Category? {
        try await Category.query(on: database)
            .filter(\Category.$userID == userID)
            .filter(\Category.$id == id)
            .first()
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

    /// `CategoriesWithFeedCount`: the two counts, read as the reference's two grouped subqueries,
    /// and the order the reference's default answers — the unread count first, then the title. The
    /// reference takes the order from the user row, which this port's schema has no column for, so
    /// the default is the order this read answers; `CategoryRepositoryTests` pins the order with an
    /// input where the title order and the count order disagree, and the account filter.
    public func listWithCounts(userID: Int) async throws -> [CategoryWithCounts] {
        let rows = try await RawSQL.sql(on: database).raw("""
            SELECT c.id, c.user_id, c.title, c.hide_globally,
                COALESCE(fc.feed_count, 0) AS feed_count,
                COALESCE(uc.unread_count, 0) AS total_unread
            FROM categories c
            LEFT JOIN (
                SELECT category_id, COUNT(*) AS feed_count
                FROM feeds WHERE user_id = \(bind: userID)
                GROUP BY category_id
            ) fc ON fc.category_id = c.id
            LEFT JOIN (
                SELECT f.category_id, COUNT(*) AS unread_count
                FROM entries e
                INNER JOIN feeds f ON f.id = e.feed_id
                WHERE e.user_id = \(bind: userID) AND e.status = 'unread'
                GROUP BY f.category_id
            ) uc ON uc.category_id = c.id
            WHERE c.user_id = \(bind: userID)
            ORDER BY COALESCE(uc.unread_count, 0) DESC, c.title ASC
            """).all()

        return try rows.map { row in
            let category = Category()
            category.id = try row.decode(column: "id", as: Int.self)
            category.userID = try row.decode(column: "user_id", as: Int.self)
            category.title = try row.decode(column: "title", as: String.self)
            category.hideGlobally = try row.decode(column: "hide_globally", as: Bool.self)
            return CategoryWithCounts(category: category, counts: CategoryCounts(
                feedCount: try row.decode(column: "feed_count", as: Int.self),
                totalUnread: try row.decode(column: "total_unread", as: Int.self)))
        }
    }

    /// `CategoryTitleExists`: the title is compared through `LOWER` on both sides, with no category
    /// excluded, because the creation path has no row to exclude. `CategoryValidationTests` pins the
    /// order the two rules of the block run in; this read is the one the block's second rule runs.
    public func titleExists(userID: Int, title: String) async throws -> Bool {
        let row = try await RawSQL.sql(on: database).raw("""
            SELECT 1 FROM categories WHERE user_id = \(bind: userID) AND LOWER(title) = LOWER(\(bind: title))
            LIMIT 1
            """).first()
        return row != nil
    }

    /// `CategoryByTitle`: the title is compared as it is given, with no `LOWER`, which is the
    /// difference from the duplicate read below.
    public func byTitle(userID: Int, title: String) async throws -> Category? {
        try await Category.query(on: database)
            .filter(\Category.$userID == userID)
            .filter(\Category.$title == title)
            .first()
    }

    /// `FirstCategory`: the row this account has with the smallest title, which is not the row that
    /// came first. `CategoryRepositoryTests` pins the order, the account filter and the answer for
    /// a row that is not there. The reference reads `hide_globally` on the same row, which this
    /// port's schema does not have.
    public func first(userID: Int) async throws -> Category? {
        try await Category.query(on: database)
            .filter(\Category.$userID == userID)
            .sort(\Category.$title)
            .first()
    }

    /// `CategoryIDExists`: the answer is read for the pair `(user_id, id)`, so a row of another
    /// user with the same id is not this user's category, which is what `FeedManagementReadsTests`
    /// pins. The single row is what the reference reads; a pin cannot tell a single-row read from
    /// one that read every match, because a user cannot have two rows with the same id.
    ///
    /// - Parameters:
    ///   - userID: The account the answer is read for.
    ///   - categoryID: The row the answer is read for.
    /// - Returns: Whether this account has `categoryID`.
    public func categoryExists(userID: Int, categoryID: Int) async throws -> Bool {
        let row = try await RawSQL.sql(on: database).raw("""
            SELECT 1 FROM categories WHERE user_id = \(bind: userID) AND id = \(bind: categoryID) LIMIT 1
            """).first()
        return row != nil
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

    /// `UpdateCategory`: writes both fields the reference's statement writes, for the row of the pair.
    /// The reference does not stamp `updated_at`; this port stamps it on every mutation, which
    /// `CategoryRepositoryTests` pins as the difference.
    public func update(userID: Int, id: Int, title: String, hideGlobally: Bool) async throws {
        try await Category.query(on: database)
            .filter(\Category.$userID == userID)
            .filter(\Category.$id == id)
            .set(\Category.$title, to: title)
            .set(\Category.$hideGlobally, to: hideGlobally)
            .set(\Category.$updatedAt, to: Int(Date.now.timeIntervalSince1970))
            .update()
    }

    /// Deletes the category; its feeds (and their entries) cascade away.
    public func delete(id: Int) async throws {
        try await Category.query(on: database).filter(\Category.$id == id).delete()
    }

    /// `RemoveCategory`: the statement is guarded by the pair, and the reference reports when it
    /// removed no row. The handler reads the pair before the write, so this answer is reached only by
    /// a row that went away between the two, which no pin can make happen; the pin reads the guard
    /// and the pair, and names this report as what it cannot show.
    public func delete(userID: Int, id: Int) async throws {
        try await RawSQL.sql(on: database).raw("""
            DELETE FROM categories WHERE id = \(bind: id) AND user_id = \(bind: userID)
            """).run()
        let row = try await RawSQL.first("SELECT changes() AS removed", on: database)
        if (try row?.decode(column: "removed", as: Int.self) ?? 0) == 0 {
            throw DeleteError.nothingRemoved
        }
    }

    /// What the delete path reports for an input that would leave no category, with the reference's
    /// wording.
    public enum DeleteError: Error, CustomStringConvertible, Sendable {
        case leavesNone

        /// `RemoveCategory`'s report for a statement that removed no row.
        case nothingRemoved

        /// The reference's wording for the rule, which the handler answers with the same string.
        public var description: String {
            switch self {
            case .leavesNone:
                return "store: at least 1 category must remain after deletion"
            case .nothingRemoved:
                return "store: no category has been removed"
            }
        }
    }
}
