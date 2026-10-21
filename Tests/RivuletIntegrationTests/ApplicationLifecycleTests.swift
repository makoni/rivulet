import Fluent
import Foundation
import Testing
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

        // Mirrors `serve`: prepare, migrate, boot — then shut down like the server does.
        let rivulet = try await ApplicationFactory.make(config: config)
        do {
            try await rivulet.storage.prepare()
            try await rivulet.application.autoMigrate().get()
            try await rivulet.application.asyncBoot()
            try await rivulet.storage.withConnection { connection in
                _ = try await seedUser(connection)
            }

            let wal = path + "-wal"
            #expect(Self.fileSize(wal) > 0)

            try await rivulet.shutdown()
            #expect(Self.fileSize(wal) == 0)
        } catch {
            try? await rivulet.shutdown()
            throw error
        }
    }

    /// `serve` must reject a damaged file before it binds a port or migrates it.
    @Test(.timeLimit(.minutes(1)))
    func serveRefusesACorruptDatabase() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let path = directory.path("rivulet.db")

        // Build a real schema with a user, checkpoint it into the main file, damage
        // page 2 and copy the result out: `serve` starts on a fresh process view.
        try await withMigratedStorage { database, storage in
            try await storage.withConnection { connection in
                _ = try await seedUser(connection)
            }
            try await storage.checkpoint()
            DatabaseCorruption.page2CellCount(at: database.path)
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
