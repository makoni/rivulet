import FluentKit
import SQLKit

/// The single access path to the SQLite database.
///
/// The wrapped `Database` never leaves this type: all application data access goes
/// through ``withConnection(_:)``, which guarantees that the required
/// per-connection pragmas are applied before the closure runs. `journal_mode=WAL`
/// is persistent per database file and is enabled once by ``prepare()``.
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
    public func withConnection<T: Sendable>(
        _ body: @escaping @Sendable (any Database) async throws -> T
    ) async throws -> T {
        try await database.withConnection { connection in
            try await Self.applySessionPragmas(on: connection)
            return try await body(connection)
        }
    }

    /// Enables WAL journaling. Runs once after opening the database file.
    public func prepare() async throws {
        try await withConnection { connection in
            try await RawSQL.run("PRAGMA journal_mode = WAL", on: connection)
        }
    }

    /// Pragmas that must hold on every pooled connection.
    ///
    /// sqlite-kit applies only `foreign_keys` itself, so the wrapper enforces the
    /// full set on each checkout.
    static let sessionPragmas = [
        /// Wait up to five seconds instead of failing immediately on a held lock.
        "PRAGMA busy_timeout = 5000",
        /// Durable enough with WAL: no fsync per commit, safe against process crashes.
        "PRAGMA synchronous = NORMAL",
        /// Explicit for clarity; also enabled by the driver at connection creation.
        "PRAGMA foreign_keys = ON",
    ]

    static func applySessionPragmas(on database: any Database) async throws {
        for statement in sessionPragmas {
            try await RawSQL.run(statement, on: database)
        }
    }
}
