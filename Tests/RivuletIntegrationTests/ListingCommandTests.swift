import ConsoleKit
import Fluent
import Foundation
import SQLKit
import Testing
import RivuletApp
@testable import RivuletCore

/// `rivulet list --categories` and `rivulet list --users` as runs through the in-process console
/// over a temp database: which read the flag names, which account the run applies, and what the
/// lines carry.
///
/// The command surface is the port's own: Miniflux has no `list`, so its flags, its lines and the
/// fields they carry are recorded in `docs/parity.md`. What is ported is the order the reference's
/// two reads answer in — `internal/storage/category.go` `Categories` orders by title,
/// `internal/storage/user.go` `Users` orders by username. Those orders are pinned as reads by
/// `CategoryRepositoryTests` and `UserRepositoryTests`, so what these pins read is the command's
/// own choice: the read the flag names, the account the run applies to the categories and not to
/// the accounts, the rule the run reports when two listing flags are given at once, and the values
/// on the line read as the stored rows rather than as the schema defaults. The `list` of feeds and
/// its order are pinned by `FeedCommandTests`; here only the default dispatch is read, so the same
/// rule is not pinned twice.
///
/// What these pins can fail on, each checked by patching the rule and reverting: that
/// `--categories` runs the title read and `--users` the username read, on data where the position
/// read, the title read and the feed read answer differently — the position read puts Tech first,
/// the title read puts News first, and the feed row carries a title no category has; that no flag
/// still lists the feeds; that two listing flags are reported as the rule the port names rather
/// than answered as a listing; that the account the command resolved applies to the categories and
/// not to the accounts, read on two accounts with their own categories; that the values on the line
/// are the stored rows and not the defaults the schema would answer; that one line carries one row;
/// that the run writes nothing; and that the title order is the byte order, on the pair that
/// separates it from the lowercased reading.
///
/// What these pins cannot fail on: the wording of the lines and of the reported failures, apart
/// from the values the pins read off a line and the rule name the run writes; a flag the command
/// does not know, which the command-signature parser rejects before the command runs, so the pins
/// cannot reach it; which fields the line carries and in what order on the line, which is the
/// port's choice; the header line, which is read here only as the one line that is not a row; the
/// `position` column, which is the port's own and has no reference counterpart, and the
/// `hide_globally` column the reference's read selects and this port's schema does not have; the
/// single-row limit of the reads; the account resolution itself, which `FeedCommandTests` pin, so
/// what is new here is only that the resolution reaches these reads; the flag that gates the
/// migrations, pinned for the same command there; that these commands fetch nothing and sleep
/// nothing; the two guards that read what the pin built before the run — the three row ids in the
/// dispatch pin and the row id in the position pin, which the default category the user create
/// writes makes always the second row — which bite only on the storage rules; and the collation the
/// reference's Postgres answers `ORDER BY title` with, which this port cannot have — recorded in
/// `docs/parity.md`, so the pins read the port's byte order only.
@Suite struct ListingCommandTests {
    init() {
        TestLogging.bootstrapOnce()
    }

    // MARK: - Pins

    @Test func theFlagNamesTheReadTheCommandRuns() async throws {
        try await withMigratedStorage { database, storage in
            // Seeded so the readings answer differently: the position read puts Tech first, the
            // title read puts News first, and the feed row carries a title no category has. A patch
            // that ran the feed read for both flags answered this pin with the feed title and with
            // no username, and a patch that ran the position read answered Tech first.
            let graph = try await storage.withConnection { connection in
                let userID = try await seedUser(connection, username: "alice")
                let news = try await seedCategory(connection, userID: userID, title: "News")
                let tech = try await seedCategory(connection, userID: userID, title: "Tech")
                try await sqlDatabase(connection).raw("""
                    UPDATE categories SET position = 2 WHERE id = \(bind: news)
                    """).run()
                try await sqlDatabase(connection).raw("""
                    UPDATE categories SET position = 1 WHERE id = \(bind: tech)
                    """).run()
                let feedID = try await seedFeed(connection, userID: userID,
                    categoryID: news, url: "https://example.com/feed.xml")
                try await sqlDatabase(connection).raw("""
                    UPDATE feeds SET title = 'FeedTitle' WHERE id = \(bind: feedID)
                    """).run()
                return (newsID: news, techID: tech, feedID: feedID)
            }

            #expect(graph.newsID != graph.techID && graph.feedID != graph.newsID,
                "the three rows the pin seeded: \(graph)")

            let categories = try await run(database: database, arguments: ["list", "--categories"])
            #expect(!categories.failed, "the run: \(categories.output)")
            #expect(Self.position(categories.output, "News") < Self.position(categories.output, "Tech"),
                "the categories in the order the title read answers: \(categories.output)")
            #expect(!categories.output.contains("FeedTitle"),
                "the flag named the category read, not the feed read: \(categories.output)")

            let users = try await run(database: database, arguments: ["list", "--users"])
            #expect(!users.failed, "the run: \(users.output)")
            #expect(users.output.contains("alice"), "the usernames the user read answers: \(users.output)")
            #expect(!users.output.contains("News"),
                "the flag named the user read, not the category read: \(users.output)")
        }
    }

    @Test func noFlagStillListsTheFeeds() async throws {
        try await withMigratedStorage { database, storage in
            try await storage.withConnection { connection in
                let userID = try await seedUser(connection, username: "alice")
                let categoryID = try await seedCategory(connection, userID: userID, title: "Tech")
                let feedID = try await seedFeed(connection, userID: userID, categoryID: categoryID,
                    url: "https://example.com.feed.example/rss")
                try await sqlDatabase(connection).raw("""
                    UPDATE feeds SET title = 'FeedTitle' WHERE id = \(bind: feedID)
                    """).run()
            }

            // The title only the feed row has is what this pin reads, so a patch that made the
            // default the categories answered this pin with the category title instead.
            let outcome = try await run(database: database, arguments: ["list"])
            #expect(!outcome.failed, "the run: \(outcome.output)")
            #expect(outcome.output.contains("FeedTitle"), "the default is the feed listing: \(outcome.output)")
        }
    }

    @Test func twoListingFlagsAreReportedAsTheRuleThePortNames() async throws {
        try await withMigratedStorage { database, storage in
            try await storage.withConnection { connection in
                let userID = try await seedUser(connection, username: "alice")
                _ = try await seedCategory(connection, userID: userID, title: "Tech")
            }

            // A patch that picked one of the two flags answered this pin as a listing, which is
            // what the pin reads must not be: the rule name is what the run reports.
            let outcome = try await run(database: database, arguments: ["list", "--categories", "--users"])
            #expect(outcome.failed, "two listing flags are reported, not answered: \(outcome.output)")
            #expect(outcome.message.contains("multipleListings"),
                "the rule the run reports for two listing flags: \(outcome.message)")
            #expect(!outcome.output.contains("Tech"),
                "nothing was listed for the pair of flags: \(outcome.output)")
        }
    }

    @Test func theAccountAppliesToTheCategoriesAndNotToTheAccounts() async throws {
        try await withMigratedStorage { database, storage in
            // Two accounts with different titles: a patch that dropped the account condition
            // printed both, and a patch that applied it to the account read printed one, which
            // upstream does not do. The account listing has no condition upstream, so the run
            // resolves no account for it.
            try await storage.withConnection { connection in
                let alice = try await seedUser(connection, username: "alice")
                let bob = try await seedUser(connection, username: "bob")
                _ = try await seedCategory(connection, userID: alice, title: "AliceOnly")
                _ = try await seedCategory(connection, userID: bob, title: "BobOnly")
            }

            let categories = try await run(database: database,
                arguments: ["list", "--categories", "--user", "alice"])
            #expect(!categories.failed, "the run: \(categories.output)")
            #expect(categories.output.contains("AliceOnly"),
                "the rows of the account the run resolved: \(categories.output)")
            #expect(!categories.output.contains("BobOnly"),
                "the account the listing is for is the one the command resolved: \(categories.output)")

            let users = try await run(database: database, arguments: ["list", "--users"])
            #expect(!users.failed, "the run: \(users.output)")
            #expect(users.output.contains("alice") && users.output.contains("bob"),
                "the account listing is every account, whatever the run was given: \(users.output)")
        }
    }

    @Test func theCategoryLineCarriesTheStoredPositionNotTheDefault() async throws {
        try await withMigratedStorage { database, storage in
            let row = try await storage.withConnection { connection in
                let userID = try await seedUser(connection, username: "alice")
                let categoryID = try await seedCategory(connection, userID: userID, title: "Tech")
                try await sqlDatabase(connection).raw("""
                    UPDATE categories SET position = 7 WHERE id = \(bind: categoryID)
                    """).run()
                return categoryID
            }
            #expect(row != 7, "the row id must not read as the position the pin seeds: \(row)")

            // A patch that reported the default the create path writes answered 0 for this row.
            let outcome = try await run(database: database, arguments: ["list", "--categories"])
            #expect(!outcome.failed, "the run: \(outcome.output)")
            let lines = outcome.output.split(separator: "\n").filter { $0.contains("Tech") }
            #expect(lines.count == 1, "one line per row: \(outcome.output)")
            let line = try #require(lines.first)
            #expect(line.contains("7"), "the position as the row holds it: \(line)")
        }
    }

    @Test func theAccountLineCarriesTheStoredAdminFlagNotTheDefault() async throws {
        try await withMigratedStorage { database, storage in
            try await storage.withConnection { connection in
                _ = try await UserRepository(connection).create(username: "carol",
                    passwordHash: "hash", isAdmin: false)
                _ = try await UserRepository(connection).create(username: "root",
                    passwordHash: "hash", isAdmin: true)
            }

            // A patch that printed the schema default answered false for the account the pin made
            // admin.
            let outcome = try await run(database: database, arguments: ["list", "--users"])
            #expect(!outcome.failed, "the run: \(outcome.output)")
            let lines = outcome.output.split(separator: "\n").filter { $0.contains("root") }
            #expect(lines.count == 1, "one line per row: \(outcome.output)")
            let adminLine = try #require(lines.first)
            #expect(adminLine.contains("true"), "the flag as the row holds it: \(adminLine)")
            let other = outcome.output.split(separator: "\n").filter { $0.contains("carol") }
            #expect(other.count == 1, "the other row is one line: \(outcome.output)")
            let otherLine = try #require(other.first)
            #expect(!otherLine.contains("true"), "the other row keeps its own flag: \(otherLine)")
        }
    }

    @Test func oneLineCarriesOneRow() async throws {
        try await withMigratedStorage { database, storage in
            try await storage.withConnection { connection in
                let userID = try await seedUser(connection, username: "alice")
                for title in ["First", "Second", "Third"] {
                    _ = try await seedCategory(connection, userID: userID, title: title)
                }
            }

            // One line per row: a patch that printed a row twice, or folded two rows into one line,
            // fails here. The header is read as the one line that carries no row, so its wording is
            // not pinned.
            let outcome = try await run(database: database, arguments: ["list", "--categories"])
            #expect(!outcome.failed, "the run: \(outcome.output)")
            let rowLines = outcome.output.split(separator: "\n").filter { line in
                ["First", "Second", "Third"].contains { line.contains($0) }
            }
            #expect(rowLines.count == 3, "one line per row: \(outcome.output)")
            #expect(Set(rowLines.map { String($0) }).count == 3, "no row is printed twice: \(rowLines)")
        }
    }

    @Test func theListingRunWritesNothing() async throws {
        try await withMigratedStorage { database, storage in
            let before = try await storage.withConnection { connection in
                let userID = try await seedUser(connection, username: "alice")
                for title in ["Tech", "News"] {
                    _ = try await seedCategory(connection, userID: userID, title: title)
                }
                try await sqlDatabase(connection).raw("""
                    UPDATE categories SET position = 3 WHERE title = 'Tech'
                    """).run()
                return try await Self.positions(on: connection)
            }

            // A patch that wrote what it read — normalising the position for the listing — changed
            // the rows, so this pin reads them again after the run.
            let outcome = try await run(database: database, arguments: ["list", "--categories"])
            #expect(!outcome.failed, "the run: \(outcome.output)")
            let after = try await storage.withConnection { connection in
                try await Self.positions(on: connection)
            }
            #expect(after == before, "the run left the rows as it read them: \(after)")
        }
    }

    @Test func theTitleOrderIsTheByteOrderNotTheLowercasedOne() async throws {
        try await withMigratedStorage { database, storage in
            // The pair that separates the two readings: byte order puts `Zebra` first, the
            // lowercased reading puts `apple` first. The reference's Postgres collation answers the
            // lowercased form, which this port cannot have, so the pins read only the port's own
            // order.
            try await storage.withConnection { connection in
                let userID = try await seedUser(connection, username: "alice")
                _ = try await seedCategory(connection, userID: userID, title: "apple")
                _ = try await seedCategory(connection, userID: userID, title: "Zebra")
            }

            let outcome = try await run(database: database, arguments: ["list", "--categories"])
            #expect(!outcome.failed, "the run: \(outcome.output)")
            #expect(Self.position(outcome.output, "Zebra") < Self.position(outcome.output, "apple"),
                "the byte order the read answers: \(outcome.output)")
        }
    }

    // MARK: - Setup

    private struct RunOutcome: Sendable {
        let output: String
        let failed: Bool
        let message: String
    }

    /// Runs one command against the file the pin names, through the in-process console.
    private func run(database: TestDatabase, arguments: [String],
        environment: [String: String] = [:]) async throws -> RunOutcome {
        var values = environment
        values["DATABASE_URL"] = database.path
        let console = TestConsole()
        var failed = false
        var message = ""
        do {
            try await RivuletCLI.run(console: console, environment: values,
                arguments: ["rivulet"] + arguments)
        } catch {
            failed = true
            message = String(describing: error)
        }
        return RunOutcome(output: console.output, failed: failed, message: message)
    }

    /// The place `name` first appears in the output, or -1 when it does not, so the pins read the
    /// order of the rows rather than the sentence around them.
    private static func position(_ output: String, _ name: String) -> Int {
        let lines = output.split(separator: "\n")
        for (index, line) in lines.enumerated() where line.contains(name) {
            return index
        }
        return -1
    }

    private static func positions(on connection: any Database) async throws -> [String] {
        let sql = try sqlDatabase(connection)
        return try await sql.raw("""
            SELECT title || '|' || position AS shape FROM categories ORDER BY id
            """).all().map { try $0.decode(column: "shape", as: String.self) }
    }
}



