import Fluent
import FluentSQLiteDriver
@testable import RivuletCore

/// Creates a database with the schema migrated and runs `body` with the storage.
///
/// The application is shut down (which removes the temporary directory) on both success and
/// failure, keeping the per-test teardown rule of `docs/testing.md` in one place.
func withMigratedStorage(
    _ body: (TestDatabase, SQLiteStorage) async throws -> Void
) async throws {
    let database = try await TestDatabase.make()
    do {
        let storage = SQLiteStorage(database: database.app.db(.sqlite), path: database.path)
        try await storage.prepare()
        try await database.app.autoMigrate()
        try await body(database, storage)
    } catch {
        await database.shutdown()
        throw error
    }
    await database.shutdown()
}
