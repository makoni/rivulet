import RivuletCore
import Vapor

/// A fully configured Rivulet application.
///
/// Built by ``ApplicationFactory``: the Vapor server with its HTTP routes and the SQLite
/// storage wrapper. The caller owns the lifecycle — prepare the storage, migrate, then
/// serve — and calls ``shutdown()`` exactly once.
public struct RivuletApplication: Sendable {
    /// The Vapor application (server, database, routes).
    public let application: Application

    /// The storage wrapper; the raw Fluent database stays private to it.
    public let storage: SQLiteStorage

    /// Shuts down the server, the database pools and the lifecycle handlers.
    ///
    /// Runs a best-effort truncating WAL checkpoint before teardown so the main
    /// database file holds every committed transaction and the `-wal` file does not
    /// linger. A failing checkpoint — a busy reader or a damaged database — is
    /// logged and never prevents the teardown itself.
    public func shutdown() async throws {
        do {
            try await storage.checkpoint()
        } catch {
            application.logger.warning("WAL checkpoint on shutdown failed: \(error)")
        }
        try await application.asyncShutdown()
    }
}
