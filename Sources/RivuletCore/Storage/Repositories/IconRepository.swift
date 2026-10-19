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
        icon.externalID = UUID().uuidString.lowercased()
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
