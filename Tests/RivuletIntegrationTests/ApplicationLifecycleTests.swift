import Fluent
import FluentSQLiteDriver
import Foundation
import Testing
import Vapor
import RivuletApp
@testable import RivuletCore

/// The serving lifecycle: the startup integrity check and the shutdown checkpoint.
@Suite struct ApplicationLifecycleTests {
    init() {
        TestLogging.bootstrapOnce()
    }

    @Test func shutdownCheckpointsTheWriteAheadLog() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let path = directory.path("rivulet.db")
        let config = try Config.load(environment: ["DATABASE_URL": path])

        // Mirrors `serve`: prepare, integrity check, migrate, boot — then shut down
        // like the server does.
        let rivulet = try await ApplicationFactory.make(config: config)
        var observer: Application?
        do {
            try await rivulet.storage.prepare()
            try await rivulet.storage.quickCheck()
            try await rivulet.application.autoMigrate().get()
            try await rivulet.application.asyncBoot()
            try await rivulet.storage.withConnection { connection in
                _ = try await seedUser(connection)
            }

            // An idle connection from a second application keeps the WAL file
            // alive when the app's own pool closes: with the explicit shutdown
            // checkpoint the file is truncated to zero, without it the frames
            // would remain (SQLite only deletes the WAL when the last
            // connection closes).
            let observerApp = try await Application.make(.testing)
            observer = observerApp
            observerApp.databases.use(.sqlite(.file(path)), as: .sqlite)
            let observerStorage = SQLiteStorage(database: observerApp.db(.sqlite), path: path)
            try await observerStorage.withConnection { connection in
                _ = try await RawSQL.first("SELECT count(*) AS n FROM users", on: connection)
            }

            let wal = path + "-wal"
            #expect(Self.fileSize(wal) > 0)
            try await rivulet.shutdown()
            #expect(Self.fileSize(wal) == 0)

            try await observerApp.asyncShutdown()
            observer = nil
        } catch {
            try? await observer?.asyncShutdown()
            try? await rivulet.shutdown()
            throw error
        }
    }

    /// `serve` must reject a damaged file before it binds a port or migrates it.
    ///
    /// A correct run never reaches the listener, so `LISTEN_ADDR` is not bound; a
    /// regression binds it and the test fails on the time limit instead of hanging.
    @Test(.timeLimit(.minutes(1)))
    func serveRefusesACorruptDatabase() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let path = directory.path("rivulet.db")

        // Build a real, migrated schema, checkpoint it into the main file, damage
        // page 2 and copy the result out: `serve` starts on a fresh process view.
        try await withMigratedStorage { database, storage in
            try await storage.checkpoint()
            try DatabaseCorruption.page2CellCount(at: database.path)
            try FileManager.default.copyItem(atPath: database.path, toPath: path)
        }

        let console = TestConsole()
        do {
            try await RivuletCLI.run(
                console: console,
                environment: ["DATABASE_URL": path, "LISTEN_ADDR": "127.0.0.1:8080"],
                arguments: ["rivulet", "serve"]
            )
            Issue.record("serve must not start on a corrupt database")
        } catch {
            guard case StorageError.databaseCorrupt = error else {
                Issue.record("expected databaseCorrupt, got: \(error)")
                return
            }
        }
    }

    private static func fileSize(_ path: String) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return (attributes?[.size] as? NSNumber)?.intValue ?? 0
    }
}
