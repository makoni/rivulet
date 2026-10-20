// Ported from Miniflux internal/storage/entry.go (Apache-2.0); adapted for Swift/SQLite.
import FluentKit
import SQLKit

/// User-state mutations: read status, starring and bulk mark-as-read.
///
/// Split from the write path to keep ``EntryRepository`` within the file-size
/// budget; every method works on the checked-out connection the repository was
/// created with, and each call is a single statement.
extension EntryRepository {
    // MARK: - User state

    /// Sets the status of `entryIDs` owned by `userID` and stamps
    /// `updated_at` (upstream `SetEntriesStatus`). Entries of other users are
    /// left alone; an empty list is a no-op.
    public func setStatus(userID: Int, entryIDs: [Int], status: EntryStatus) async throws {
        guard !entryIDs.isEmpty else { return }
        try await Entry.query(on: database)
            .filter(\Entry.$userID == userID)
            .filter(\Entry.$id ~~ entryIDs)
            .set(\Entry.$status, to: status)
            .set(\Entry.$updatedAt, to: Self.now())
            .update()
    }

    /// Sets the starred flag of `entryIDs` owned by `userID` and stamps
    /// `updated_at` (upstream `SetEntriesStarredState`). Starred entries are
    /// never purged; an empty list is a no-op.
    public func setStarred(userID: Int, entryIDs: [Int], starred: Bool) async throws {
        guard !entryIDs.isEmpty else { return }
        try await Entry.query(on: database)
            .filter(\Entry.$userID == userID)
            .filter(\Entry.$id ~~ entryIDs)
            .set(\Entry.$starred, to: starred)
            .set(\Entry.$updatedAt, to: Self.now())
            .update()
    }

    /// Flips the starred flag of one entry and returns the new state
    /// (upstream `ToggleStarred`).
    ///
    /// - Throws: ``StorageError/entryNotFound(id:)`` when the entry does not
    ///   exist for `userID`.
    @discardableResult
    public func toggleStarred(userID: Int, entryID: Int) async throws -> Bool {
        let row = try await RawSQL.sql(on: database).raw("""
            UPDATE entries
            SET starred = NOT starred, updated_at = \(bind: Self.now())
            WHERE user_id = \(bind: userID) AND id = \(bind: entryID)
            RETURNING starred
            """).first()
        guard let row else {
            throw StorageError.entryNotFound(id: entryID)
        }
        return try row.decode(column: "starred", as: Bool.self)
    }

    /// Marks every unread entry of `userID` as read and stamps `updated_at`
    /// (upstream `MarkAllAsRead`).
    public func markAllAsRead(userID: Int) async throws {
        try await markUnreadAsRead(userID: userID, before: nil)
    }

    /// Marks unread entries of `userID` published before `before` (Unix
    /// seconds) as read (upstream `MarkAllAsReadBeforeDate`).
    public func markAllAsRead(userID: Int, before: Int) async throws {
        try await markUnreadAsRead(userID: userID, before: before)
    }

    /// Marks the unread entries of `userID` in `feedID` published before
    /// `before` (Unix seconds) as read and stamps `updated_at` (upstream
    /// `MarkFeedAsRead`). Starred entries are marked like any other unread
    /// entry; entries of other users are never touched.
    public func markFeedAsRead(userID: Int, feedID: Int, before: Int) async throws {
        try await RawSQL.sql(on: database).raw("""
            UPDATE entries
            SET status = \(bind: EntryStatus.read.rawValue), updated_at = \(bind: Self.now())
            WHERE user_id = \(bind: userID)
                AND feed_id = \(bind: feedID)
                AND status = \(bind: EntryStatus.unread.rawValue)
                AND published_at < \(bind: before)
            """).run()
    }

    /// Marks the unread entries of `userID` in the feeds of `categoryID`
    /// published before `before` (Unix seconds) as read and stamps `updated_at`
    /// (upstream `MarkCategoryAsRead`). The category is resolved through the
    /// feeds of the same user, so another user's category selects nothing.
    public func markCategoryAsRead(userID: Int, categoryID: Int, before: Int) async throws {
        try await RawSQL.sql(on: database).raw("""
            UPDATE entries
            SET status = \(bind: EntryStatus.read.rawValue), updated_at = \(bind: Self.now())
            WHERE user_id = \(bind: userID)
                AND status = \(bind: EntryStatus.unread.rawValue)
                AND published_at < \(bind: before)
                AND feed_id IN (
                    SELECT id FROM feeds
                    WHERE user_id = \(bind: userID) AND category_id = \(bind: categoryID)
                )
            """).run()
    }

    /// Marks unread entries of `userID` as read, optionally up to `before`.
    private func markUnreadAsRead(userID: Int, before: Int?) async throws {
        var query = Entry.query(on: database)
            .filter(\Entry.$userID == userID)
            .filter(\Entry.$status == .unread)
        if let before {
            query = query.filter(\Entry.$publishedAt < before)
        }
        try await query
            .set(\Entry.$status, to: .read)
            .set(\Entry.$updatedAt, to: Self.now())
            .update()
    }
}
