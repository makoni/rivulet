/// What ``EntryRepository/upsert(userID:feedID:input:updateExisting:)`` did.
///
/// Mirrors the branches of the reference refresh loop: a new item is inserted,
/// a known item is refreshed or left alone, and a tombstoned item is skipped
/// so a cleanup cannot be undone by the next fetch.
public enum EntryUpsertOutcome: Sendable {
    /// A new entry was inserted; the value carries the stored row.
    case created(Entry)
    /// The stored entry was refreshed (title, url, author, content, enclosures).
    case updated
    /// The entry already existed and was left untouched (`updateExisting == false`).
    case existing
    /// The `(feedID, hash)` pair is tombstoned; nothing was written.
    case tombstoned
}
