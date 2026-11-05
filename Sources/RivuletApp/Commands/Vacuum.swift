// The port's own command: Miniflux's CLI dispatches by flags and has no vacuum command, so the
// shape of its line is recorded in `docs/parity.md`; what is ported is the storage helper stage 1
// landed.

import ConsoleKit
import Foundation
import RivuletCore

extension RivuletCLI {
    /// `rivulet vacuum` — the file rebuilt, then exit.
    ///
    /// The run is the storage helper's rebuild: the free pages the rows left behind go back to the
    /// filesystem, and the rows themselves are untouched. Nothing is fetched and nothing is
    /// deleted — the retention pass is what leaves free pages, and this command only releases
    /// them. The rebuild ends with a truncating WAL checkpoint, so the file holds the whole
    /// database when the run returns, and a reader that prevents the checkpoint is reported rather
    /// than answered as a run that shrank nothing. The migrations run when `RUN_MIGRATIONS` is on,
    /// as the other commands have them gated.
    struct Vacuum: AsyncCommand {
        struct Signature: CommandSignature {
            init() {}
        }

        let environment: [String: String]

        var help: String { "Rebuilds the database file, releasing the free pages, then exits." }

        func run(using context: CommandContext, signature: Signature) async throws {
            let config = try Config.load(environment: environment)
            LoggingSetup.bootstrap(logLevel: config.logLevel, format: config.logFormat)

            let rivulet = try await ApplicationFactory.make(config: config)
            try await rivulet.storage.prepare()
            if config.runMigrations {
                try await rivulet.application.autoMigrate()
            }

            // A reader that blocks the checkpoint leaves through the gate, so the app the command
            // opened is shut down before the error does.
            do {
                try await rivulet.storage.vacuum()
            } catch {
                try? await rivulet.shutdown()
                throw error
            }

            context.console.print("Vacuumed \(config.databasePath)")
            try await rivulet.shutdown()
        }
    }
}
