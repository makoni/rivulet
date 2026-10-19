/// Storage-layer errors.
public enum StorageError: Error, Sendable {
    /// The backing database does not speak SQL.
    case notSQLDatabase
}
