import Foundation
import Fluent
import FluentSQLiteDriver
import Vapor
@testable import RivuletCore

/// A file-backed SQLite database in a fresh temporary directory, plus the Vapor
/// application wired to it.
///
/// Used by integration tests; the schema migration is registered but **not** applied —
/// tests call `autoMigrate()` when they need the schema. The directory is removed in
/// ``shutdown()``.
final class TestDatabase {
    let directory: URL
    let path: String
    let app: Application

    private init(directory: URL, path: String, app: Application) {
        self.directory = directory
        self.path = path
        self.app = app
    }

    /// Creates the temp directory and configures an application with the SQLite file
    /// and the Rivulet schema migration.
    ///
    /// - Parameter poolTimeoutMilliseconds: overrides the driver's connection-pool timeout
    ///   (10 seconds by default); used by tests that pin the storage contract without waiting.
    static func make(poolTimeoutMilliseconds: Int? = nil) async throws -> TestDatabase {
        TestLogging.bootstrapOnce()

        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("rivulet-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let path = directory.appendingPathComponent("rivulet.db").path

        let app = try await Application.make(.testing)
        if let poolTimeoutMilliseconds {
            app.databases.use(
                .sqlite(
                    .file(path),
                    connectionPoolTimeout: .milliseconds(Int64(poolTimeoutMilliseconds))
                ),
                as: .sqlite
            )
        } else {
            app.databases.use(.sqlite(.file(path)), as: .sqlite)
        }
        app.migrations.add(SchemaV1())

        return TestDatabase(directory: directory, path: path, app: app)
    }

    /// Shuts the application down and removes the temporary directory.
    func shutdown() async {
        try? await app.asyncShutdown()
        try? FileManager.default.removeItem(at: directory)
    }

    /// Registers a second SQLite driver for `path` under `id`, so a test can
    /// open another database file (a backup copy) or a second handle on the
    /// same file with the same wiring as the main driver.
    func registerDriver(at path: String, as id: DatabaseID) {
        app.databases.use(.sqlite(.file(path)), as: id)
    }
}
