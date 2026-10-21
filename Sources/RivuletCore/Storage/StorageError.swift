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

    /// `PRAGMA quick_check` reported a structural problem with the database file.
    ///
    /// The database must not be served in this state; restore from a backup
    /// (see `docs/backup-restore.md`) instead of trying to repair it.
    case databaseCorrupt(details: [String])
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
        }
    }
}
