// The port's own command: Miniflux has no `remove`, so the wording of its lines and the shape of
// its flags are recorded in `docs/parity.md`; what is ported is the storage rule the reference
// reads — the delete applies the pair `(id, user_id)`, and the rows below the feed go with it.

import ConsoleKit
import Foundation
import RivuletCore

extension RivuletCLI {
    /// `rivulet remove` — one feed row away, then exit.
    ///
    /// The row is the one the account has with that url: the same url on another account is a
    /// different row, and the delete applies the pair, as `RemoveFeed` does. A url the account has
    /// no row for is reported as the port's rule rather than answered as an empty run, because a
    /// command line that deletes nothing must say so. The rows below the feed — the entries, the
    /// attachments, the tombstones and the search rows — go with it, which is the schema's rule and
    /// is pinned by `FeedManagementReadsTests`. The migrations run when `RUN_MIGRATIONS` is on, as
    /// the other commands have them gated.
    struct Remove: AsyncCommand {
        struct Signature: CommandSignature {
            @Argument(name: "url", help: "Feed url to remove")
            var url: String

            @Option(name: "user", help: "Account the row belongs to")
            var user: String?

            init() {}
        }

        /// What one run resolved: the account and the url the row carried.
        private struct Outcome: Sendable {
            let accountName: String
            let url: String
        }

        let environment: [String: String]

        var help: String { "Removes one feed row and the rows below it, then exits." }

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

            context.console.print("Removed feed \(outcome.accountName): \(outcome.url)")

            try await rivulet.shutdown()
        }

        /// Resolves the account, reads the row it has with that url and deletes that row. The reads
        /// and the delete run on one checkout.
        private func resolve(_ signature: Signature, on storage: SQLiteStorage) async throws
            -> Outcome {
            let url = signature.url
            let userName = signature.user ?? ""

            return try await storage.withConnection { connection in
                let users = UserRepository(connection)
                let feeds = FeedRepository(connection)

                let (userID, accountName, rule) = try await FeedCommandAccount.resolve(
                    name: userName, users: users)
                if let rule { throw CLIError(rule.rawValue) }

                // The row is read through the account, so the row the delete applies is the row the
                // account has; a patch that read the url alone answered the row it found first.
                guard let feed = try await feeds.fetch(userID: userID, url: url),
                    let feedID = feed.id else {
                    throw CLIError(FeedValidationRule.feedNotFound.rawValue)
                }

                try await feeds.delete(id: feedID, userID: userID)
                return Outcome(accountName: accountName, url: url)
            }
        }
    }
}
