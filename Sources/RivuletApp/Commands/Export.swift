// The port's own shape for the reference's export: the reference's CLI prints the document to
// stdout with the account named as its flag argument, and the port prints to stdout the same way.
// Writing a file is the port's own half, named as an option because `@Argument` has no default and
// cannot name an optional path. The divergence is recorded in `docs/parity.md`.

import ConsoleKit
import Foundation
import RivuletCore

extension RivuletCLI {
    /// `rivulet export` — the document for one account, then exit.
    ///
    /// The document is the listing order the reference's query builder answers, with the category
    /// title read through the join, and the bytes the serializer writes. The date field is the time
    /// the run happens at. The document goes to stdout when no path is named, which is where the
    /// reference prints it; when `--file` names one, the run writes the file and prints only what
    /// it wrote. The account is the one `--user` names, read as the account lookup reads a name, or
    /// the single account when none is named; both are the rule `FeedCommandAccount` pins. The
    /// migrations run when `RUN_MIGRATIONS` is on, as the other commands have them gated.
    struct Export: AsyncCommand {
        struct Signature: CommandSignature {
            @Option(name: "file", help: "Path the document is written to; stdout when none is named")
            var file: String?

            @Option(name: "user", help: "Account the document is read for")
            var user: String?

            init() {}
        }

        /// What one run produced: the account, the document, and the path it was written to, when
        /// one was named.
        private struct Outcome: Sendable {
            let accountName: String
            let document: String
            let path: String?
        }

        let environment: [String: String]

        var help: String { "Writes the OPML document for one account to stdout or to a file." }

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

            if let path = outcome.path {
                try write(document: outcome.document, to: path)
                context.console.print("Wrote the document for \(outcome.accountName) to \(path)")
            } else {
                context.console.print(outcome.document)
            }

            try await rivulet.shutdown()
        }

        /// Resolves the account and builds the document for it.
        private func resolve(_ signature: Signature, on storage: SQLiteStorage) async throws
            -> Outcome {
            let userName = signature.user ?? ""

            let account = try await storage.withConnection { connection in
                let resolved = try await FeedCommandAccount.resolve(
                    name: userName, users: UserRepository(connection))
                if let rule = resolved.rule { throw CLIError(rule.rawValue) }
                return (userID: resolved.userID, accountName: resolved.accountName)
            }

            let document = try await OPMLHandler(storage).exportFeeds(userID: account.userID,
                now: Date.now)
            return Outcome(accountName: account.accountName, document: document, path: signature.file)
        }

        /// The port's own half: one-shot file write of the bytes the document holds. The reference
        /// has no file half at all — it prints the document, which is the branch the run takes when
        /// no path is named.
        private func write(document: String, to path: String) throws {
            try document.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
        }
    }
}
