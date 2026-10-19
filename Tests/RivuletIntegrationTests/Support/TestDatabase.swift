import Foundation
import Fluent
import FluentSQLiteDriver
import Logging
import Vapor
@testable import RivuletCore

/// A file-backed SQLite database in a fresh temporary directory, plus the Vapor
/// application wired to it.
///
/// Used by integration tests; the directory is removed in ``shutdown()``.
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
    /// and the Rivulet schema migrations.
    static func make() async throws -> TestDatabase {
        bootstrapLoggingOnce()

        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("rivulet-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let path = directory.appendingPathComponent("rivulet.db").path

        let app = try await Application.make(.testing)
        app.databases.use(.sqlite(.file(path)), as: .sqlite)
        app.migrations.add(SchemaV1())

        return TestDatabase(directory: directory, path: path, app: app)
    }

    /// Shuts the application down and removes the temporary directory.
    func shutdown() async {
        try? await app.asyncShutdown()
        try? FileManager.default.removeItem(at: directory)
    }

    private static let loggingBootstrap: Void = {
        LoggingSystem.bootstrap { _ in SwiftLogNoOpLogHandler() }
    }()

    private static func bootstrapLoggingOnce() {
        _ = loggingBootstrap
    }
}
