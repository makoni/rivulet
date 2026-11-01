// Ported from Miniflux internal/storage/icon.go (Apache-2.0); adapted for Swift/SQLite.
import Foundation
import FluentKit

/// Stores and looks up icons, deduplicated by content hash.
///
/// - See: ``SQLiteStorage/withConnection(_:)`` — the repository takes the
///   checked-out connection and lives inside that checkout.
public struct IconRepository {
    private let database: any Database

    /// Creates the repository around a checked-out connection.
    public init(_ database: any Database) {
        self.database = database
    }

    /// Inserts the icon unless one with the same `hash` is already stored, in
    /// which case the existing icon is returned (icons are deduplicated by
    /// content hash, upstream parity).
    ///
    /// `mimeType` is normalized like the reference: lowercased, and coerced
    /// to `image/x-icon` unless it names a known icon type.
    public func insert(hash: String, mimeType: String, content: Data) async throws -> Icon {
        if let existing = try await fetch(hash: hash) {
            return existing
        }
        let icon = Icon()
        icon.hash = hash
        icon.mimeType = Self.normalizeMimeType(mimeType)
        icon.content = content
        icon.externalID = Self.randomExternalID()
        icon.createdAt = Int(Date.now.timeIntervalSince1970)
        try await icon.create(on: database)
        return icon
    }

    /// Returns the icon with `id`, or `nil`.
    public func fetch(id: Int) async throws -> Icon? {
        try await Icon.query(on: database).filter(\Icon.$id == id).first()
    }

    /// Returns the icon with `hash`, or `nil`.
    public func fetch(hash: String) async throws -> Icon? {
        try await Icon.query(on: database).filter(\Icon.$hash == hash).first()
    }

    /// Returns the icon with `externalID` (the public feed-icon URL), or `nil`.
    public func fetch(externalID: String) async throws -> Icon? {
        try await Icon.query(on: database).filter(\Icon.$externalID == externalID).first()
    }

    /// Points the feed row at `iconID`, replacing the icon it had.
    ///
    /// The reference's `StoreFeedIcon` (`internal/storage/icon.go`) deletes the feed's row
    /// in the `feed_icons` table and inserts the new one in the same transaction; this port
    /// keeps the mapping as `feeds.icon_id`, so the replace is one statement — the same
    /// decision, recorded in `docs/parity.md`.
    public func link(feedID: Int, iconID: Int) async throws {
        try await RawSQL.sql(on: database).raw("""
            UPDATE feeds SET icon_id = \(bind: iconID) WHERE id = \(bind: feedID)
        """).run()
    }

    /// Removes the icons no feed points at and returns the number of rows deleted, which is
    /// the reference's `CleanupOrphanIcons`: a deduplicated icon row survives its mapping
    /// being replaced and survives the feed being deleted, so this pass is what stops those
    /// rows accumulating.
    public func cleanupOrphans() async throws -> Int {
        try await RawSQL.run("""
            DELETE FROM icons
            WHERE NOT EXISTS (
                SELECT 1 FROM feeds WHERE feeds.icon_id = icons.id
            )
        """, on: database)

        // This SQLKit version gives no row count for a statement run through `RawSQL`, so the
        // number is read from the connection immediately after the statement, which is what
        // `RowsAffected` reports upstream: the repository holds one checked-out connection, so
        // this read sees this statement and no other's.
        let row = try await RawSQL.first("SELECT changes()", on: database)
        return try row?.decode(column: "changes()", as: Int.self) ?? 0
    }

    /// A random external id: 20 random bytes as 40 lowercase hex characters,
    /// the same shape as the reference's `crypto.GenerateRandomStringHex(20)`.
    private static func randomExternalID() -> String {
        let bytes = (0..<20).map { _ in UInt8.random(in: .min ... .max) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Normalizes a MIME type the way the reference does (upstream
    /// `normalizeMimeType`): lowercased, and coerced to `image/x-icon` unless
    /// it is one of the known icon types.
    private static func normalizeMimeType(_ mimeType: String) -> String {
        let normalized = mimeType.lowercased()
        switch normalized {
        case "image/png", "image/jpeg", "image/jpg", "image/webp",
             "image/svg+xml", "image/x-icon", "image/gif":
            return normalized
        default:
            return "image/x-icon"
        }
    }
}
