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
            let framesBefore = try fileSize(wal)
            #expect(framesBefore > 0)

            try await rivulet.shutdown()
            let truncated = try fileSize(wal)
            #expect(truncated == 0)

            try await observerApp.asyncShutdown()
            observer = nil
        } catch {
            try? await observer?.asyncShutdown()
            try? await rivulet.shutdown()
            throw error
        }
    }

    /// `shutdown()` treats the checkpoint as best effort: a blocked one does not stop the
    /// teardown. The assertion is that shutdown completed while the WAL still holds the
    /// frames the failed checkpoint could not move — without the blocked reader the WAL
    /// would be empty, so the test cannot pass by accident.
    @Test func shutdownCompletesWhenTheCheckpointIsBlocked() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let path = directory.path("rivulet.db")
        let config = try Config.load(environment: ["DATABASE_URL": path])

        let rivulet = try await ApplicationFactory.make(config: config)
        try await rivulet.storage.prepare()
        try await rivulet.application.autoMigrate().get()

        // A second driver holds a read snapshot, so the truncating checkpoint reports busy.
        let observerApp = try await Application.make(.testing)
        observerApp.databases.use(.sqlite(.file(path)), as: .sqlite)
        let observer = SQLiteStorage(database: observerApp.db(.sqlite), path: path)
        do {
            try await observer.withConnection { connection in
                try await RawSQL.run("BEGIN", on: connection)
                _ = try await RawSQL.first("SELECT count(*) AS n FROM users", on: connection)
                try await rivulet.shutdown()
            }

            let frames = try fileSize(path + "-wal")
            #expect(frames > 0)

            try await observerApp.asyncShutdown()
        } catch {
            try? await observerApp.asyncShutdown()
            try? await rivulet.shutdown()
            throw error
        }
    }

    /// `serve` must refuse a damaged file instead of serving it.
    ///
    /// The assertion is the integrity error itself. `serve` runs the check before it
    /// migrates or listens, so no socket is created and `LISTEN_ADDR` stays at the
    /// configuration default; a regression would start listening and this test fails on
    /// the time limit instead of hanging forever.
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
                environment: ["DATABASE_URL": path],
                arguments: ["rivulet", "serve"]
            )
            Issue.record("serve must not start on a corrupt database")
        } catch {
            guard case StorageError.databaseCorrupt(let details) = error else {
                Issue.record("expected databaseCorrupt, got: \(error)")
                return
            }
            // The integrity check must actually see the damaged page.
            #expect(details.joined(separator: " ").contains("page 2"))
        }
    }
}
