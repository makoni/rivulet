import FluentKit
import SQLKit

/// The single access path to the SQLite database.
///
/// The wrapped `Database` never leaves this type: all application data access goes
/// through ``withConnection(_:)``, which guarantees that the required per-connection
/// pragmas are applied before the closure runs. `journal_mode=WAL` is persistent per
/// database file and is enabled once by ``prepare()``.
public struct SQLiteStorage: Sendable {
    /// Path of the SQLite database file.
    public let path: String

    private let database: any Database

    /// Creates a storage wrapper around a Fluent database.
    public init(database: any Database, path: String) {
        self.database = database
        self.path = path
    }

    /// Runs `body` on a pooled connection with the session pragmas applied.
    ///
    /// - Important: The connection is checked out for the duration of the closure and must
    ///   not escape it. Do not call `withConnection` again from inside the closure: the
    ///   SQLite driver keeps a single pooled connection per event loop, so a nested
    ///   checkout would wait for the pool and fail with a connection-pool timeout. Compose
    ///   by passing the connection to repositories instead.
    public func withConnection<T: Sendable>(
        _ body: @escaping @Sendable (any Database) async throws -> T
    ) async throws -> T {
        try await database.withConnection { connection in
            try await Self.applySessionPragmas(on: connection)
            return try await body(connection)
        }
    }

    /// Runs `body` inside a write transaction on a pooled connection.
    ///
    /// The transaction starts with `BEGIN IMMEDIATE`, so the write lock is taken
    /// before the first statement and a batch cannot fail halfway on a concurrent
    /// writer. Every write inside the closure commits together; any thrown error
    /// rolls the whole batch back and is rethrown. Session pragmas are applied
    /// before the transaction starts.
    ///
    /// - Important: As with ``withConnection(_:)``, do not open another connection
    ///   from inside the closure: a nested checkout would wait for the pooled
    ///   connection and time out. Compose by passing the connection to repositories
    ///   instead.
    public func withTransaction<T: Sendable>(
        _ body: @escaping @Sendable (any Database) async throws -> T
    ) async throws -> T {
        try await withConnection { connection in
            try await RawSQL.run("BEGIN IMMEDIATE", on: connection)
            do {
                let result = try await body(connection)
                try await RawSQL.run("COMMIT", on: connection)
                return result
            } catch {
                // SQLite rolls the transaction back itself after most fatal statement
                // errors, in which case ROLLBACK reports "no transaction is active".
                // Its failure must not mask the body error; a connection that is left
                // with an open transaction fails on its next checkout, the same trade-off
                // the driver's own `transaction` implementation makes.
                try? await RawSQL.run("ROLLBACK", on: connection)
                throw error
            }
        }
    }

    /// Enables WAL journaling and verifies that SQLite accepted it.
    ///
    /// Run once at startup, before migrations. WAL is a property of the database file; on
    /// filesystems that cannot support it SQLite reports the previous mode instead of
    /// failing, which surfaces as ``StorageError/walUnavailable(reported:)``.
    public func prepare() async throws {
        try await withConnection { connection in
            let row = try await RawSQL.first("PRAGMA journal_mode = WAL", on: connection)
            let mode = try row?.decode(column: "journal_mode", as: String.self)
            guard mode?.lowercased() == "wal" else {
                throw StorageError.walUnavailable(reported: mode ?? "unknown")
            }
        }
    }

    /// Upper bound for the WAL file in bytes (64 MiB).
    ///
    /// SQLite applies the limit when it resets the WAL after a checkpoint:
    /// the file is truncated to this size, but between checkpoints it can
    /// grow past the limit. The setting is per connection, hence part of the
    /// session pragmas.
    static let journalSizeLimit = 64 * 1024 * 1024

    /// Milliseconds a pooled connection waits for a held lock before failing.
    static let busyTimeoutMilliseconds = 5000

    /// Pragmas that must hold on every pooled connection.
    ///
    /// sqlite-kit applies only `foreign_keys` itself, so the wrapper enforces the full
    /// set on each checkout.
    static let sessionPragmas = [
        /// Wait up to five seconds instead of failing immediately on a held lock.
        "PRAGMA busy_timeout = \(busyTimeoutMilliseconds)",
        /// Durable enough with WAL: no fsync per commit, safe against process crashes.
        "PRAGMA synchronous = NORMAL",
        /// Explicit for clarity; also enabled by the driver at connection creation.
        "PRAGMA foreign_keys = ON",
        /// Keep the WAL file bounded; applied per connection, see `journalSizeLimit`.
        "PRAGMA journal_size_limit = \(journalSizeLimit)",
    ]

    /// Creates a point-in-time copy of the database at `destination`.
    ///
    /// The copy is a self-contained database file with the source's exact
    /// content, produced by `VACUUM INTO` — a consistent snapshot even while
    /// the source stays writable. The destination's directory must exist, and
    /// SQLite refuses to overwrite an existing non-empty file (an empty file
    /// is reused). The copy needs roughly the source size in free disk space.
    public func backup(to destination: String) async throws {
        try await withConnection { connection in
            try await RawSQL.sql(on: connection).raw("VACUUM INTO \(bind: destination)").run()
        }
    }

    /// Rebuilds the database file, releasing free pages back to the filesystem.
    ///
    /// Run after large deletions (for example a retention pass) to reclaim
    /// disk space: `DELETE` marks pages free but never shrinks the file.
    /// The rebuild is followed by a truncating WAL checkpoint, so the
    /// reclaimed space is visible in the main file when the call returns.
    ///
    /// - Throws: ``StorageError/checkpointBusy`` when another connection
    ///   prevents the truncation. The rebuilt database is already committed
    ///   in that case; retry the checkpoint once the reader is gone.
    public func vacuum() async throws {
        try await withConnection { connection in
            try await RawSQL.run("VACUUM", on: connection)
            try await Self.truncateWAL(on: connection)
        }
    }

    /// Checkpoints the WAL into the main database file and truncates the WAL
    /// to zero length.
    ///
    /// Call on graceful shutdown so the main file is complete on disk when
    /// the process exits.
    ///
    /// - Throws: ``StorageError/checkpointBusy`` when a reader holds a
    ///   snapshot that prevents the truncation; the WAL keeps the committed
    ///   transactions and nothing is lost.
    public func checkpoint() async throws {
        try await withConnection { connection in
            try await Self.truncateWAL(on: connection)
        }
    }

    /// `PRAGMA wal_checkpoint(TRUNCATE)` reports a blocked checkpoint in a result row
    /// instead of failing. Observed in testing: the first truncating checkpoint right
    /// after a burst of writes reports `busy` even though every frame has been copied,
    /// and an immediate retry succeeds. So the loop retries a few times without waiting
    /// and then reports a genuinely blocked WAL instead of claiming success. The
    /// connection goes back to the pool with the documented session timeout restored,
    /// even when an attempt fails.
    private static func truncateWAL(on connection: any Database) async throws {
        try await RawSQL.run("PRAGMA busy_timeout = 0", on: connection)
        var busy = 1
        var failure: (any Error)?
        for _ in 0..<3 {
            do {
                let row = try await RawSQL.first("PRAGMA wal_checkpoint(TRUNCATE)", on: connection)
                busy = try row?.decode(column: "busy", as: Int.self) ?? 0
                if busy == 0 {
                    break
                }
            } catch {
                failure = error
                break
            }
        }
        try await RawSQL.run("PRAGMA busy_timeout = \(busyTimeoutMilliseconds)", on: connection)
        if let failure {
            throw failure
        }
        guard busy == 0 else {
            throw StorageError.checkpointBusy
        }
    }

    /// Runs `PRAGMA quick_check` and throws ``StorageError/databaseCorrupt(details:)``
    /// when SQLite reports a problem or the check cannot complete.
    ///
    /// The fast startup integrity check: it verifies page structure, not full
    /// content, so it stays cheap even on large databases. A file whose header is
    /// not a database fails as a statement rather than returning problem rows.
    /// A failure that prevents the check from running at all — a lock held by
    /// another connection, a full disk — is reported through the same case with the
    /// underlying error as the detail, so the message does not claim damage that
    /// SQLite did not see; either outcome means the database must not be served.
    /// A cancelled task is rethrown unchanged.
    public func quickCheck() async throws {
        do {
            try await withConnection { connection in
                let rows = try await RawSQL.sql(on: connection).raw("PRAGMA quick_check").all()
                var problems: [String] = []
                for row in rows {
                    let detail = try row.decode(column: "quick_check", as: String.self)
                    if detail != "ok" {
                        problems.append(detail)
                    }
                }
                if !problems.isEmpty {
                    throw StorageError.databaseCorrupt(details: problems)
                }
            }
        } catch let error as StorageError {
            throw error
        } catch {
            if error is CancellationError {
                throw error
            }
            // A file SQLite cannot even open (torn write, header damage) fails while the
            // session pragmas run or while the check statement runs; a cancelled task is
            // not a damaged database and is rethrown unchanged.
            throw StorageError.databaseCorrupt(details: [String(describing: error)])
        }
    }

    static func applySessionPragmas(on database: any Database) async throws {
        for statement in sessionPragmas {
            try await RawSQL.run(statement, on: database)
        }
    }
}
