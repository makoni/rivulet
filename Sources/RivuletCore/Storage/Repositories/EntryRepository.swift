// Ported from Miniflux internal/storage/entry.go and internal/storage/enclosure.go
// (Apache-2.0); adapted for Swift/SQLite.
import Foundation
import FluentKit
import SQLKit

/// Stores entries, their user state, enclosures and tombstones.
///
/// The write path mirrors the reference refresh loop: a new entry is inserted
/// behind an atomic tombstone guard, an existing entry only has its feed-side
/// fields refreshed, and the user's state (`status`, `starred`) is never
/// overwritten by a refresh (`publishedAt` is feed data and is equally left
/// alone: the reference does not rewrite it). Deletion is a real `DELETE` that
/// records a tombstone for every non-empty hash, so a refreshed feed cannot
/// bring a cleaned-up entry back.
///
/// Ported semantics: `createEntry`, `updateEntry`, `updateEnclosures`,
/// `entryExists`, `IsNewEntry`, `GetEntries`, `GetEntryIDs`, `CountEntries`,
/// `EnclosuresByEntryIDs`, `SetEntriesStatus`, `SetEntriesStarredState`,
/// `ToggleStarred`, `MarkAllAsRead`, `MarkAllAsReadBeforeDate`,
/// `MarkFeedAsRead`, `MarkCategoryAsRead` and `ArchiveEntries`.
///
/// - Important: ``upsert(userID:feedID:input:updateExisting:)`` and
///   ``archive(status:createdBefore:limit:)`` span several statements and must
///   run inside ``SQLiteStorage/withTransaction(_:)``, so the batch is atomic
///   and serializes with the retention cleanup.
public struct EntryRepository {
    /// The checked-out connection; the listings extension in
    /// `EntryRepository+Queries.swift` shares it.
    let database: any Database

    /// Creates the repository around a checked-out connection.
    public init(_ database: any Database) {
        self.database = database
    }

    // MARK: - Reads

    /// Returns the entry with `id`, or `nil`.
    public func fetch(id: Int) async throws -> Entry? {
        try await Entry.query(on: database).filter(\Entry.$id == id).first()
    }

    /// Returns the enclosures of `entryID`, ordered by id.
    public func fetchEnclosures(entryID: Int) async throws -> [Enclosure] {
        try await Enclosure.query(on: database)
            .filter(\Enclosure.$entryID == entryID)
            .sort(\Enclosure.$id)
            .all()
    }

    /// Returns `true` when `(feedID, hash)` is neither stored nor tombstoned
    /// (upstream `IsNewEntry`).
    public func isNewEntry(feedID: Int, hash: String) async throws -> Bool {
        let row = try await RawSQL.sql(on: database).raw("""
            SELECT (
                EXISTS (
                    SELECT 1 FROM entries WHERE feed_id = \(bind: feedID) AND hash = \(bind: hash)
                ) OR EXISTS (
                    SELECT 1 FROM entry_tombstones WHERE feed_id = \(bind: feedID) AND hash = \(bind: hash)
                )
            ) AS known
            """).first()
        let known = try row?.decode(column: "known", as: Int.self) ?? 0
        return known == 0
    }

    // MARK: - Refresh

    /// Inserts `input` as a new entry, or refreshes the stored entry with the
    /// same `(feedID, hash)`.
    ///
    /// A refresh overwrites only the feed-side fields (title, url, author,
    /// content, plain text): `status` and `starred` are the user's state, and
    /// `publishedAt` is feed data the reference also leaves alone (upstream
    /// `updateEntry`). Enclosures are reconciled: a URL that is still declared
    /// keeps its stored row and metadata, a disappeared URL is deleted and a
    /// new URL is inserted (upstream `updateEnclosures`). A tombstoned
    /// `(feedID, hash)` is never re-inserted; the insert and the tombstone
    /// check are one statement, so a concurrent cleanup cannot be undone.
    ///
    /// - Parameters:
    ///   - userID: Owner of the entry.
    ///   - feedID: Feed the entry was parsed from.
    ///   - input: Parsed fields; `content` must already be sanitized HTML.
    ///   - updateExisting: When `true`, an existing entry is refreshed; when
    ///     `false`, it is left untouched (upstream `RefreshFeedEntries`).
    /// - Returns: What happened to the entry.
    @discardableResult
    public func upsert(
        userID: Int,
        feedID: Int,
        input: EntryInput,
        updateExisting: Bool
    ) async throws -> EntryUpsertOutcome {
        let sql = try RawSQL.sql(on: database)

        if !updateExisting, try await storedEntryID(feedID: feedID, hash: input.hash) != nil {
            return .existing
        }
        let contentText = EntryText.plainText(fromHTML: input.content)

        if updateExisting {
            if let row = try await sql.raw("""
                UPDATE entries
                SET
                    title = \(bind: input.title),
                    url = \(bind: input.url),
                    author = \(bind: input.author),
                    content = \(bind: input.content),
                    content_text = \(bind: contentText)
                WHERE user_id = \(bind: userID)
                    AND feed_id = \(bind: feedID)
                    AND hash = \(bind: input.hash)
                RETURNING id
                """).first() {
                let entryID = try row.decode(column: "id", as: Int.self)
                try await replaceEnclosures(entryID: entryID, with: input.enclosures)
                return .updated
            }
        }

        let now = Self.now()
        guard let row = try await sql.raw("""
            INSERT INTO entries (
                user_id, feed_id, hash, title, url, author,
                content, content_text, published_at, created_at, updated_at
            )
            SELECT
                \(bind: userID), \(bind: feedID), \(bind: input.hash),
                \(bind: input.title), \(bind: input.url), \(bind: input.author),
                \(bind: input.content), \(bind: contentText),
                \(bind: input.publishedAt), \(bind: now), \(bind: now)
            WHERE NOT EXISTS (
                SELECT 1 FROM entry_tombstones
                WHERE feed_id = \(bind: feedID) AND hash = \(bind: input.hash)
            )
            RETURNING id
            """).first() else {
            return .tombstoned
        }

        let entry = Entry()
        let entryID = try row.decode(column: "id", as: Int.self)
        entry.id = entryID
        entry.userID = userID
        entry.feedID = feedID
        entry.hash = input.hash
        entry.title = input.title
        entry.url = input.url
        entry.author = input.author
        entry.content = input.content
        entry.contentText = contentText
        entry.status = .unread
        entry.starred = false
        entry.publishedAt = input.publishedAt
        entry.createdAt = now
        entry.updatedAt = now
        // The row is stored: mark the identity as persisted, so the returned value
        // behaves like a fetched model (FluentKit precondition for update/save).
        entry._$idExists = true
        try await insertEnclosures(entryID: entryID, from: input.enclosures)
        return .created(entry)
    }

    // MARK: - Retention

    /// Deletes up to `limit` entries with `status` created before
    /// `createdBefore` (Unix seconds), oldest first, and records a tombstone
    /// for every deleted non-empty hash (upstream `ArchiveEntries`).
    ///
    /// Starred entries are kept. A non-positive `limit` deletes nothing. The
    /// delete and the tombstone insert are one atomic step only inside
    /// ``SQLiteStorage/withTransaction(_:)``, which callers must provide.
    ///
    /// - Returns: the number of deleted entries. The reference returns the number of
    ///   rows it inserted into `entry_tombstones`, which changes with skipped empty
    ///   hashes and with `(feed_id, hash)` conflicts; a live entry can never have a
    ///   tombstone, so in practice the two counts agree.
    @discardableResult
    public func archive(status: EntryStatus, createdBefore: Int, limit: Int) async throws -> Int {
        guard limit > 0 else { return 0 }
        let sql = try RawSQL.sql(on: database)
        let deleted = try await sql.raw("""
            DELETE FROM entries
            WHERE id IN (
                SELECT id FROM entries
                WHERE status = \(bind: status.rawValue)
                    AND starred = 0
                    AND created_at < \(bind: createdBefore)
                ORDER BY created_at ASC
                LIMIT \(bind: limit)
            )
            RETURNING feed_id, hash
            """).all()
        let tombstones = try deleted.compactMap { row -> (feedID: Int, hash: String)? in
            let hash = try row.decode(column: "hash", as: String.self)
            guard !hash.isEmpty else { return nil }
            return (try row.decode(column: "feed_id", as: Int.self), hash)
        }
        if !tombstones.isEmpty {
            let now = Self.now()
            let insert = sql.insert(into: "entry_tombstones")
                .columns("feed_id", "hash", "deleted_at")
                .ignoringConflicts(with: ["feed_id", "hash"])
            for tombstone in tombstones {
                insert.values(tombstone.feedID, tombstone.hash, now)
            }
            try await insert.run()
        }
        return deleted.count
    }

    // MARK: - Helpers

    /// Returns the id of the stored entry with `(feedID, hash)`, or `nil`.
    private func storedEntryID(feedID: Int, hash: String) async throws -> Int? {
        let row = try await RawSQL.sql(on: database).raw(
            "SELECT id FROM entries WHERE feed_id = \(bind: feedID) AND hash = \(bind: hash) LIMIT 1"
        ).first()
        return try row?.decode(column: "id", as: Int.self)
    }

    /// Inserts the attachments of a new entry.
    private func insertEnclosures(entryID: Int, from enclosures: [EntryInput.Enclosure]) async throws {
        for input in Self.uniqueEnclosures(enclosures) {
            let enclosure = Enclosure()
            enclosure.entryID = entryID
            enclosure.url = input.url
            enclosure.mimeType = input.mimeType
            enclosure.size = input.size
            try await enclosure.create(on: database)
        }
    }

    /// Refreshes the attachments of a refreshed entry (upstream `updateEnclosures`).
    ///
    /// A URL that is still declared keeps its stored row and metadata; rows
    /// whose URL disappeared are deleted and only new URLs are inserted. The
    /// reference deduplicates inserts on `(entry_id, sha256(url))`, so a
    /// conflicting URL also keeps the stored metadata.
    private func replaceEnclosures(entryID: Int, with enclosures: [EntryInput.Enclosure]) async throws {
        let incoming = Self.uniqueEnclosures(enclosures)
        let stored = try await fetchEnclosures(entryID: entryID)
        let incomingURLs = Set(incoming.map(\.url))
        let staleIDs = stored.filter { !incomingURLs.contains($0.url) }.compactMap(\.id)
        if !staleIDs.isEmpty {
            try await Enclosure.query(on: database)
                .filter(\Enclosure.$id ~~ staleIDs)
                .delete()
        }
        let storedURLs = Set(stored.map(\.url))
        try await insertEnclosures(
            entryID: entryID,
            from: incoming.filter { !storedURLs.contains($0.url) }
        )
    }

    /// Trims URLs, drops empty ones and keeps the first row per URL.
    ///
    /// The reference deduplicates on `(entry_id, sha256(url))`; the schema has
    /// no unique constraint, so the same rule is applied before inserting.
    static func uniqueEnclosures(_ enclosures: [EntryInput.Enclosure]) -> [EntryInput.Enclosure] {
        var seen: Set<String> = []
        return enclosures.compactMap { input in
            let url = input.url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty, seen.insert(url).inserted else {
                return nil
            }
            var unique = input
            unique.url = url
            return unique
        }
    }

    /// Unix seconds, the storage clock; shared with the state extension.
    static func now() -> Int {
        Int(Date.now.timeIntervalSince1970)
    }
}
