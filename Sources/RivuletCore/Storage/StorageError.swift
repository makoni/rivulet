/// Storage-layer errors.
public enum StorageError: Error, Sendable, Equatable {
    /// The backing database does not speak SQL.
    case notSQLDatabase

    /// SQLite did not accept `journal_mode=WAL`.
    ///
    /// Some filesystems (network mounts, for example) cannot support WAL; SQLite then
    /// keeps the previous mode instead of failing.
    case walUnavailable(reported: String)

    /// A bookkeeping call referenced a feed that does not exist.
    case feedNotFound(id: Int)

    /// A user-state call referenced an entry that does not exist for the user.
    case entryNotFound(id: Int)

    /// The startup integrity check failed: `PRAGMA quick_check` reported a problem,
    /// or the check could not run because the file cannot be read.
    ///
    /// A database in this state must not be served. `details` carries what SQLite
    /// reported, or the error that prevented the check, so page damage can be told
    /// apart from a lock or disk failure before restoring from a backup.
    case databaseCorrupt(details: [String])

    /// A truncating WAL checkpoint was blocked by another connection.
    ///
    /// The WAL still holds committed transactions; the checkpoint can be
    /// retried once the reader is gone.
    case checkpointBusy

    /// A seeding request cannot produce the requested corpus shape: `feeds`
    /// must be positive and `entries` cannot be negative.
    case invalidSeeding(feeds: Int, entries: Int)
}

extension StorageError: CustomStringConvertible {
    /// Human-readable message used by the CLI error path.
    public var description: String {
        switch self {
        case .notSQLDatabase:
            return "the database does not support SQL"
        case .walUnavailable(let reported):
            return "could not enable WAL journal mode (SQLite reported: \(reported)); "
                + "check that the database lives on a local filesystem"
        case .feedNotFound(let id):
            return "feed #\(id) does not exist"
        case .entryNotFound(let id):
            return "entry #\(id) does not exist"
        case .databaseCorrupt(let details):
            return "the database failed the integrity check: "
                + details.joined(separator: " | ")
        case .checkpointBusy:
            return "the WAL checkpoint is blocked by another connection; retry when it is idle"
        case .invalidSeeding(let feeds, let entries):
            return "invalid corpus size: \(feeds) feed(s), \(entries) entry/entries"
        }
    }
}
