import RivuletCore
import Vapor

/// A fully configured Rivulet application.
///
/// Built by ``ApplicationFactory``: the Vapor server with its HTTP routes, the SQLite
/// storage wrapper and the configuration they were built from. The caller owns the
/// lifecycle — prepare the storage, migrate, then serve — and calls ``shutdown()``
/// exactly once.
public struct RivuletApplication: Sendable {
    /// The Vapor application (server, database, routes).
    public let application: Application

    /// The storage wrapper; the raw Fluent database stays private to it.
    public let storage: SQLiteStorage

    /// The configuration this application was built from.
    public let config: Config

    /// Shuts down the server, the database pools and the lifecycle handlers.
    public func shutdown() async throws {
        try await application.asyncShutdown()
    }
}
