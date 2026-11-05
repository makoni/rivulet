// The port's own command: Miniflux has no `list`, so the shape of its lines and its flags are
// recorded in `docs/parity.md`; what is ported is the order its feed query builder answers in.

import ConsoleKit
import Foundation
import RivuletCore

extension RivuletCLI {
    /// `rivulet list` — the feeds of one account, then exit.
    ///
    /// The rows are printed in the order the reference's feed query builder answers: the
    /// parsing-error count descending, then the lowercased title as the tiebreaker, which
    /// `FeedManagementReadsTests` pins for the read this command calls. Only the rows of the
    /// account are printed. The wording of the lines is the port's own, so the pins read the values
    /// on the line rather than the sentence. The migrations run when `RUN_MIGRATIONS` is on, as the
    /// other commands have them gated.
    struct List: AsyncCommand {
        struct Signature: CommandSignature {
            @Option(name: "user", help: "Account whose feeds are listed")
            var user: String?

            init() {}
        }

        /// One printed row: the values the order and the report read.
        struct Row: Sendable {
            let id: Int?
            let title: String
            let url: String
            let errorCount: Int
        }

        /// What one run resolved: the account and the rows in the order the read answered.
        private struct Outcome: Sendable {
            let accountName: String
            let rows: [Row]
        }

        let environment: [String: String]

        var help: String { "Lists the feeds of one account, in the reference's order, and exits." }

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

            let console = context.console
            console.print("Feeds of \(outcome.accountName):")
            for row in outcome.rows {
                let title = row.title.isEmpty ? "-" : row.title
                let id = row.id.map(String.init) ?? "-"
                console.print("\(id) \(title) \(row.url) (\(row.errorCount))")
            }

            try await rivulet.shutdown()
        }

        /// Resolves the account and reads its rows in the order the rule answers.
        private func resolve(_ signature: Signature, on storage: SQLiteStorage) async throws
            -> Outcome {
            let userName = signature.user ?? ""

            return try await storage.withConnection { connection in
                let (userID, accountName, rule) = try await FeedCommandAccount.resolve(
                    name: userName, users: UserRepository(connection))
                if let rule { throw CLIError(rule.rawValue) }

                let feeds = try await FeedRepository(connection)
                    .listSortedByErrorCountThenTitle(userID: userID)
                return Outcome(accountName: accountName, rows: feeds.map {
                    Row(id: $0.id, title: $0.title, url: $0.url, errorCount: $0.parsingErrorCount)
                })
            }
        }
    }
}
