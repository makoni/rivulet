/// Read state of an entry (upstream `model.EntryStatusUnread` / `EntryStatusRead`).
///
/// The reference deliberately has only these two states: "unread" and "read".
/// Removal is expressed by deleting the row and writing a tombstone, not by a
/// third status.
public enum EntryStatus: String, Codable, Sendable {
    /// Not read yet; counts as unread in every client view.
    case unread
    /// Read; the retention cleanup deletes old read entries first.
    case read
}
