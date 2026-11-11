// The port's own command: Miniflux has no `import`, so the shape of its flags and the wording of
// its lines are recorded in `docs/parity.md`; what is ported is what the reference's OPML handler
// does with the records it reads.

import ConsoleKit
import Foundation
import RivuletCore

extension RivuletCLI {
    /// `rivulet import` — the rows an OPML file names, then exit.
    ///
    /// The file is the path the argument names, read as the bytes the read gets. The rows are the
    /// records the import path answers, in the order it answers them, and the steps it applies are
    /// the reference's: the duplicate answer, the category resolution, the rules, the row. A record
    /// that fails a rule stops the run with the earlier rows standing, because the reference
    /// applies the steps per record. The account is the one `--user` names, read as the account
    /// lookup reads a name, or the single account when none is named; both are the rule
    /// `FeedCommandAccount` pins. The migrations run when `RUN_MIGRATIONS` is on, as the other
    /// commands have them gated.
    struct Import: AsyncCommand {
        struct Signature: CommandSignature {
            @Argument(name: "file", help: "OPML file to read")
            var file: String

            @Option(name: "user", help: "Account to write the rows for")
            var user: String?

            init() {}
        }

        /// What one run resolved: the account and the path the file was read from.
        private struct Outcome: Sendable {
            let accountName: String
            let path: String
        }

        let environment: [String: String]

        var help: String { "Imports the feed rows an OPML file names and exits." }

        func run(using context: CommandContext, signature: Signature) async throws {
            let config = try Config.load(environment: environment)
            LoggingSetup.bootstrap(logLevel: config.logLevel, format: config.logFormat)

            let rivulet = try await ApplicationFactory.make(config: config)
            try await rivulet.storage.prepare()
            if config.runMigrations {
                try await rivulet.application.autoMigrate()
            }

            let outcome: Outcome
            do {
                outcome = try await resolve(signature, on: rivulet.storage)
            } catch {
                try? await rivulet.shutdown()
                throw error
            }

            // The name reported is the stored one, not the text the flag carried, because the rows
            // are written for the account the lookup found.
            context.console.print("Imported \(outcome.path) for \(outcome.accountName)")

            try await rivulet.shutdown()
        }

        /// Reads the bytes the file carries, resolves the account and runs the import path for it.
        /// The read is the run's own one-shot file read: the reference reads the request body as a
        /// stream, so there is no stream rule here to mirror, and the file the argument names is
        /// what the read gets. The account is resolved on its own checkout and the import path
        /// takes the checkout it names, so the run does not hold two at once.
        private func resolve(_ signature: Signature, on storage: SQLiteStorage) async throws
            -> Outcome {
            let path = signature.file
            let data = try Data(contentsOf: URL(fileURLWithPath: path))

            let account = try await storage.withConnection { connection in
                let resolved = try await FeedCommandAccount.resolve(
                    name: signature.user ?? "", users: UserRepository(connection))
                if let rule = resolved.rule { throw CLIError(rule.rawValue) }
                return (userID: resolved.userID, accountName: resolved.accountName)
            }

            try await OPMLHandler(storage).importFeeds(userID: account.userID, data: data)
            return Outcome(accountName: account.accountName, path: path)
        }
    }
}
