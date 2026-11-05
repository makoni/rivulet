// The port's own command: Miniflux has no `list`, so the shape of its lines and its flags are
// recorded in `docs/parity.md`; what is ported is the order its reads answer in.

import ConsoleKit
import Foundation
import RivuletCore

extension RivuletCLI {
    /// `rivulet list` — one listing, then exit.
    ///
    /// The flags name which listing the run answers, and no flag means the feeds. The feed rows are
    /// printed in the order the reference's feed query builder answers: the parsing-error count
    /// descending, then the lowercased title as the tiebreaker, which `FeedManagementReadsTests`
    /// pin for the read this command calls, and only the rows of the account are printed. The
    /// category rows are printed in the order `internal/storage/category.go` `Categories` answers,
    /// the title alone, which `CategoryRepositoryTests` pin as a read, so this command uses the
    /// title read rather than the position one. The account rows are printed in the order
    /// `internal/storage/user.go` `Users` answers, the username, and that read has no account
    /// condition upstream, so the run does not resolve an account for it. The wording of the lines
    /// is the port's own, so the pins read the values on the line rather than the sentence. The
    /// migrations run when `RUN_MIGRATIONS` is on, as the other commands have them gated.
    struct List: AsyncCommand {
        struct Signature: CommandSignature {
            @Option(name: "user", help: "Account whose feeds or categories are listed")
            var user: String?

            @Flag(name: "categories", help: "List the categories instead of the feeds")
            var categories: Bool

            @Flag(name: "users", help: "List every account instead of the feeds")
            var users: Bool

            init() {}
        }

        /// Which listing the flags name.
        enum Listing: Sendable {
            case feeds
            case categories
            case accounts

            /// Resolves the pair of flags into the one listing the run answers.
            ///
            /// - Throws: ``ListingRule/multipleListings`` when both flags are given, because the
            /// command answers one listing per run.
            static func select(categories: Bool, users: Bool) throws -> Listing {
                if categories {
                    if users { throw CLIError(ListingRule.multipleListings.rawValue) }
                    return .categories
                }
                if users { return .accounts }
                return .feeds
            }
        }

        /// The port's own rule for what the pair of flags answers, with no reference counterpart.
        ///
        /// The reference has no `list`, so there is no reference rule for a listing a command line
        /// asks for; the rule name is what the run reports, recorded in `docs/reference-notes.md`.
        enum ListingRule: String, Sendable {
            /// The port's own rule: the command answers one listing per run, so the pair is
            /// reported rather than picked.
            case multipleListings
        }

        /// One printed row: the values the pins read as the row holds them, for whichever listing
        /// the flags named.
        enum Row: Sendable {
            /// A feed row: the values the order and the report read.
            struct Feed: Sendable {
                let id: Int?
                let title: String
                let url: String
                let errorCount: Int
            }

            /// A category row: the title the read ordered by, and the position as the row holds it,
            /// which the create path defaults to zero.
            struct Category: Sendable {
                let id: Int?
                let title: String
                let position: Int
            }

            /// An account row: the username the read ordered by, and the admin flag as the row
            /// holds it, which the create path defaults to false.
            struct Account: Sendable {
                let id: Int?
                let username: String
                let isAdmin: Bool
            }

            case feed(Feed)
            case category(Category)
            case account(Account)
        }

        /// What one run resolved: the account the listing applies to, and the rows in the order the
        /// read answered.
        struct Outcome: Sendable {
            let accountName: String
            let rows: [Row]
        }

        let environment: [String: String]

        var help: String { "Lists one listing - the feeds, the categories or the accounts - and exits." }

        func run(using context: CommandContext, signature: Signature) async throws {
            let listing = try Listing.select(categories: signature.categories, users: signature.users)

            let config = try Config.load(environment: environment)
            LoggingSetup.bootstrap(logLevel: config.logLevel, format: config.logFormat)

            let rivulet = try await ApplicationFactory.make(config: config)
            try await rivulet.storage.prepare()
            if config.runMigrations {
                try await rivulet.application.autoMigrate()
            }

            let outcome: Outcome
            do {
                outcome = try await resolve(listing, signature, on: rivulet.storage)
            } catch {
                try? await rivulet.shutdown()
                throw error
            }

            let console = context.console
            switch listing {
            case .feeds:
                console.print("Feeds of \(outcome.accountName):")
            case .categories:
                console.print("Categories of \(outcome.accountName):")
            case .accounts:
                console.print("Accounts:")
            }

            for row in outcome.rows {
                switch row {
                case .feed(let feed):
                    let title = feed.title.isEmpty ? "-" : feed.title
                    console.print("\(idText(feed.id)) \(title) \(feed.url) (\(feed.errorCount))")
                case .category(let category):
                    console.print("\(idText(category.id)) \(category.title) \(category.position)")
                case .account(let account):
                    console.print("\(idText(account.id)) \(account.username) \(account.isAdmin)")
                }
            }

            try await rivulet.shutdown()
        }

        /// Resolves the account the listing applies to and reads the rows in the order the rule
        /// answers.
        ///
        /// The account condition belongs to the feeds and the categories, as the reference's reads
        /// have it. The account listing has no condition upstream, so the run does not resolve an
        /// account for it and prints every row the read answers.
        private func resolve(_ listing: Listing, _ signature: Signature, on storage: SQLiteStorage)
            async throws -> Outcome {
            let userName = signature.user ?? ""

            return try await storage.withConnection { connection in
                switch listing {
                case .feeds:
                    let (userID, accountName, rule) = try await FeedCommandAccount.resolve(
                        name: userName, users: UserRepository(connection))
                    if let rule { throw CLIError(rule.rawValue) }

                    let feeds = try await FeedRepository(connection)
                        .listSortedByErrorCountThenTitle(userID: userID)
                    return Outcome(accountName: accountName,
                        rows: feeds.map { Row.feed(.init(id: $0.id, title: $0.title, url: $0.url,
                            errorCount: $0.parsingErrorCount)) })
                case .categories:
                    let (userID, accountName, rule) = try await FeedCommandAccount.resolve(
                        name: userName, users: UserRepository(connection))
                    if let rule { throw CLIError(rule.rawValue) }

                    let categories = try await CategoryRepository(connection).listByTitle(userID: userID)
                    return Outcome(accountName: accountName,
                        rows: categories.map { Row.category(.init(id: $0.id, title: $0.title,
                            position: $0.position)) })
                case .accounts:
                    let accounts = try await UserRepository(connection).list()
                    return Outcome(accountName: userName,
                        rows: accounts.map { Row.account(.init(id: $0.id, username: $0.username,
                            isAdmin: $0.isAdmin)) })
                }
            }
        }

        /// The id as the line prints it, which is the value the pins read, or the placeholder the
        /// port uses when the row has none.
        private func idText(_ id: Int?) -> String {
            id.map(String.init) ?? "-"
        }
    }
}

