// The port's own command: Miniflux's CLI dispatches by flags and has no backup command, so the
// shape of its argument and the wording of its line are recorded in `docs/parity.md`; what is
// ported is the storage helper stage 1 landed.

import ConsoleKit
import Foundation
import RivuletCore

extension RivuletCLI {
    /// `rivulet backup <destination>` — a point-in-time copy, then exit.
    ///
    /// The copy is the snapshot `VACUUM INTO` writes: a self-contained database carrying the
    /// content the source had at the run, compacted, while the source stays writable. The
    /// destination is used as it was given, so a relative value means the process's working
    /// directory rather than the data directory; the command does not build the directory the
    /// storage layer needs, because a run that wrote nothing has to say so rather than build a
    /// path around itself. A destination that already holds something is refused and left as it
    /// was — the port does not overwrite a previous backup, and SQLite's refusal is reported as
    /// the run failing. The migrations run when `RUN_MIGRATIONS` is on, as the other commands have
    /// them gated.
    ///
    /// The run checks the room at its start, before it writes: the estimate is the bytes the
    /// source holds as the filesystem reads them, times the factor
    /// `docs/plan/stage-1-storage.md` documents for `VACUUM INTO`, and the room is read at the
    /// directory the destination is in. A run that cannot hold the copy reports it and writes
    /// nothing, which is the failure the CLI reads as the exit code. The rule is the port's own,
    /// recorded in `docs/parity.md`; `vacuum` is not checked, because it rebuilds the file it
    /// already holds rather than writing a copy beside it.
    struct Backup: AsyncCommand {
        struct Signature: CommandSignature {
            @Argument(name: "destination", help: "Path the copy is written to")
            var destination: String

            init() {}
        }

        let environment: [String: String]
        let space: any FileSystemSpace

        var help: String { "Writes a point-in-time copy of the database to `destination`, then exits." }

        func run(using context: CommandContext, signature: Signature) async throws {
            let config = try Config.load(environment: environment)
            LoggingSetup.bootstrap(logLevel: config.logLevel, format: config.logFormat)

            // The check is the start of the run: it reads before anything is written, so a run
            // that cannot hold the copy reports it and leaves nothing behind rather than writing
            // and failing.
            if let refusal = FreeSpaceCheck(space: space)
                .refusal(sourcePath: config.databasePath, destinationPath: signature.destination) {
                throw refusal
            }

            let rivulet = try await ApplicationFactory.make(config: config)
            try await rivulet.storage.prepare()
            if config.runMigrations {
                try await rivulet.application.autoMigrate()
            }

            // The storage error leaves through the gate, so the app the command opened is shut
            // down before it does: a refused destination is a run that failed, not a run that
            // wrote nothing.
            do {
                try await rivulet.storage.backup(to: signature.destination)
            } catch {
                try? await rivulet.shutdown()
                throw error
            }

            context.console.print("Backup written: \(signature.destination)")
            try await rivulet.shutdown()
        }
    }
}
