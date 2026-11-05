// The port's own command: Miniflux has no `add`, so the wording of its lines and the shape of its
// flags are recorded in `docs/parity.md`; what is ported is what the reference's feed validator
// does with the values it is given.

import ConsoleKit
import Foundation
import RivuletCore

extension RivuletCLI {
    /// `rivulet add` — one feed row, then exit.
    ///
    /// This is the insert only: the row is written with the reference's defaults, so
    /// `next_check_at` is the time the command ran at and the next pass over the batch takes the
    /// feed. The command fetches nothing and discovers nothing — discovery and the first fetch are
    /// the reader's path, and the rules that guard them landed with stage 5.
    ///
    /// The url is stored as the command read it, including a tracked parameter the URL cleaner
    /// would drop, because the reference's create path writes `feed_url` as submitted. The title
    /// and the site url stay empty until the first fetch. The category is the row the named title
    /// resolves to, or the account's default "All" category when no title is named, and the
    /// category is resolved before the rules run, because the rules read the id the resolution
    /// answers; the reference resolves it from the id the request carries, so a title the account
    /// has no row for answers `0`, which is what the guard fails on, and an input that fails a rule
    /// reaches no write. The rules run in the reference's order, which `FeedValidationTests` pins,
    /// and the message a failing run writes is the rule name, as the write handlers of this port
    /// write it. The migrations run when `RUN_MIGRATIONS` is on, as the other commands have them
    /// gated.
    struct Add: AsyncCommand {
        struct Signature: CommandSignature {
            /// The feed url, read as given. Kept optional so the mandatory rule can be reached,
            /// which is what its pin reads.
            @Argument(name: "url", help: "Feed url")
            var url: String

            @Option(name: "user", help: "Account to write the row for")
            var user: String?

            @Option(name: "category", help: "Category title; the default category when not given")
            var category: String?

            init() {}
        }

        /// What one run resolved: the account, the url as it was read, and the row it wrote.
        private struct Outcome: Sendable {
            let accountName: String
            let url: String
            let feedID: Int?
        }

        /// The title of the category the storage layer writes with a new account.
        private static let defaultCategoryTitle = "All"

        let environment: [String: String]

        var help: String { "Adds one feed row and exits; it does not fetch." }

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

            // The name reported is the stored one, not the text the flag carried, because the row
            // is written for the account the lookup found.
            let id = outcome.feedID.map(String.init) ?? "-"
            context.console.print("Added feed \(id) for \(outcome.accountName): \(outcome.url)")

            try await rivulet.shutdown()
        }

        /// Resolves the account and the category, applies the rules in the reference's order and
        /// writes the row. The reads and the write run on one checkout.
        private func resolve(_ signature: Signature, on storage: SQLiteStorage) async throws
            -> Outcome {
            let url = signature.url
            let userName = signature.user ?? ""
            let categoryTitle = signature.category ?? ""

            return try await storage.withConnection { connection in
                let users = UserRepository(connection)
                let categories = CategoryRepository(connection)
                let feeds = FeedRepository(connection)

                let (userID, accountName, rule) = try await FeedCommandAccount.resolve(
                    name: userName, users: users)
                if let rule { throw CLIError(rule.rawValue) }

                let title = categoryTitle.isEmpty ? Self.defaultCategoryTitle : categoryTitle
                let category = try await categories.byTitle(userID: userID, title: title)
                let categoryID = category?.id ?? 0

                let failed = FeedValidation.validate(url: url, categoryID: categoryID,
                    urlIsAbsolute: URLRules.isAbsoluteURL(url),
                    feedURLExists: try await feeds.feedURLExists(userID: userID, url: url),
                    categoryExists: try await categories.categoryExists(userID: userID,
                        categoryID: categoryID))
                if let failed { throw CLIError(failed.rawValue) }

                let feed = try await feeds.create(userID: userID, categoryID: categoryID, url: url)
                return Outcome(accountName: accountName, url: url, feedID: feed.id)
            }
        }
    }
}
