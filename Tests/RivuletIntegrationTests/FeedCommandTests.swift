import ConsoleKit
import Fluent
import Foundation
import SQLKit
import Testing
import RivuletApp
@testable import RivuletCore

/// `rivulet add`, `rivulet remove` and `rivulet list` over a temp database through the in-process
/// command entry point: what each run leaves in the database and what it reports.
///
/// The command surface is the port's own: Miniflux has no `add`, `remove` or `list`, so the pins
/// read the values carried on the line rather than the sentence, and a failing run is read as the
/// rule name the command writes, as the write handlers of this port write it.
///
/// What these pins can fail on, each checked by patching the rule and reverting: that `add` stores
/// the url as the command read it, with the tracked parameter the URL cleaner would drop, and that
/// the title and the site url stay empty until the first fetch; that the default category is used
/// only when no title is named; that the first rule the input fails on is the one the run reports,
/// on the inputs that fail two rules at once; that the guard reads the category as a positive
/// number, on the name that resolves to nothing; that the duplicate answer is this account's row;
/// that the account is the named one read through the lookup, or the only one when none is named;
/// that a named account with no row is reported rather than answered as another account; that the
/// delete applies the account it is given, on the url both accounts have; that a url this account
/// has no row for is reported rather than answered as an empty run; that `list` prints in the order
/// the read answers and prints only the rows of the account it is given; and that the flag gates
/// the migrations this command runs.
///
/// What these pins cannot fail on: the order between the duplicate read and the category read,
/// because at the command level a category name the command cannot resolve answers `0`, so the
/// guard runs first and no input reaches both — that order is pinned as pure logic in
/// `FeedValidationTests`; the lowercasing of the account lookup as a storage rule, which
/// `ClientAuthTests` pin, where these pins can fail only on the patch that compares the name as
/// read instead of reading it through the lookup; the rows below the feed, which
/// `FeedManagementReadsTests` pin for the same delete; the wording of the lines and of the reported
/// failures; the fetch these commands do not make; and the rules the port names rather than the
/// reference.
@Suite struct FeedCommandTests {
    init() {
        TestLogging.bootstrapOnce()
    }

    // MARK: - Pins

    @Test func addWritesTheRowAsTheCommandReadIt() async throws {
        let before = nowInSeconds()
        try await withRun(accounts: ["alice", "bob"], arguments: ["add",
            "https://example.com/feed.xml?utm_source=x", "--user", "alice", "--category", "Tech"]) {
            outcome, seed, _, written in
            #expect(!outcome.failed, "the run: \(outcome.output)")
            #expect(written.count == 1, "the row the command wrote: \(written)")
            let row = try #require(written.first)

            #expect(row.url == "https://example.com/feed.xml?utm_source=x",
                "the url as the command read it, with the parameter the cleaner would drop: \(row)")
            #expect(row.title == "" && row.siteURL == "",
                "the title and the site url stay empty until the first fetch: \(row)")
            #expect(row.categoryTitle == "Tech", "the category the name resolved to: \(row)")
            #expect(row.userID == seed.userIDs["alice"], "the row is for the account named: \(row)")
            #expect(row.nextCheckAt >= before && row.nextCheckAt <= nowInSeconds(),
                "the next check is the time the command ran at: \(row)")

            // The report carries the url as it was stored, which is the part of the line a pin can
            // read; the sentence around it is the command's own wording.
            #expect(outcome.output.contains("utm_source=x"),
                "the run reports the row it wrote: \(outcome.output)")
        }
    }

    @Test func addUsesTheDefaultCategoryOnlyWhenNoTitleIsNamed() async throws {
        try await withRun(accounts: ["alice"], arguments: ["add", "https://default.example/feed",
            "--user", "alice"]) { outcome, _, _, written in
            #expect(!outcome.failed, "the run: \(outcome.output)")
            let row = try #require(written.first, "the row the command wrote: \(written)")
            #expect(row.categoryTitle == "All", "the default category, when the pin named none: \(row)")

            // The control on the same account: a named title is the row it resolves to, so this pin
            // is not satisfied by a command that used the default for every run.
            try await withRun(accounts: ["alice"], arguments: ["add", "https://named.example/feed",
                "--user", "alice", "--category", "Tech"]) { _, _, _, named in
                let wrote = try #require(named.first, "the row the second run wrote: \(named)")
                #expect(wrote.categoryTitle == "Tech", "the named title, not the default: \(wrote)")
            }
        }
    }

    @Test func theFirstRuleTheInputFailsOnIsTheOneTheCommandReports() async throws {
        // Each input fails two rules, so the rule the run reports is the one that runs first.
        let order: [(url: String, rule: FeedValidationRule)] = [
            // The empty url fails the guard and the URL rule; the guard runs first.
            ("", .mandatoryFields),
            // Not absolute, and this account already has a row with it: the URL rule runs first.
            ("relative.example/feed", .invalidURL),
            // Passes the guard and the URL rule, and the account has the row: the duplicate read.
            ("https://alice.example/feed", .alreadyExists),
        ]
        for input in order {
            try await withRun(accounts: ["alice", "bob"],
                arguments: ["add", input.url, "--user", "alice", "--category", "Tech"]) {
                outcome, _, _, written in
                #expect(outcome.failed, "a run that fails a rule must report it: \(outcome.output)")
                #expect(outcome.message.contains(ruleName(input.rule)),
                    "the first rule the input \"\(input.url)\" fails on: \(outcome.message)")
                #expect(written.isEmpty, "nothing is written for an input that fails a rule: \(written)")
            }
        }

        // The control: the same command with an input that fails none writes the row.
        try await withRun(accounts: ["alice", "bob"], arguments: ["add", "https://ok.example/feed",
            "--user", "alice", "--category", "Tech"]) { outcome, _, _, written in
            #expect(!outcome.failed, "the control run: \(outcome.output)")
            #expect(written.count == 1, "the control writes the row: \(written)")
        }
    }

    @Test func theGuardReadsTheCategoryAsAPositiveNumberAtTheCommandLevel() async throws {
        // The name the pin gives resolves to nothing, so the id the guard reads is 0 while the url
        // passes every later rule. A patch that dropped the guard's category half would answer the
        // category read here, which is not the rule this pin names.
        try await withRun(accounts: ["alice"], arguments: ["add", "https://ok.example/feed",
            "--user", "alice", "--category", "Missing"]) { outcome, _, _, written in
            #expect(outcome.failed, "the run must report the rule: \(outcome.output)")
            #expect(outcome.message.contains(ruleName(FeedValidationRule.mandatoryFields)),
                "the guard's category half: \(outcome.message)")
            #expect(written.isEmpty, "a run that fails writes nothing: \(written)")
        }
    }

    @Test func theDuplicateAnswerIsThisAccountsRowAtTheCommandLevel() async throws {
        try await withRun(accounts: ["alice", "bob"], arguments: ["add", "https://bob.example/feed",
            "--user", "alice"]) { outcome, seed, _, written in
            #expect(!outcome.failed,
                "another account's row with the same url is not this account's duplicate: \(outcome.message)")
            let row = try #require(written.first, "the row the command wrote: \(written)")
            #expect(row.userID == seed.userIDs["alice"], "the row is written for the account named: \(row)")

            // The same url for its own account is the duplicate answer, so the pin is not satisfied
            // by a read that answered nothing for every account, or that read the url alone.
            try await withRun(accounts: ["alice", "bob"], arguments: ["add", "https://bob.example/feed",
                "--user", "bob"]) { second, _, _, _ in
                #expect(second.failed, "the row this account has is the duplicate: \(second.output)")
                #expect(second.message.contains(ruleName(FeedValidationRule.alreadyExists)),
                    "the message: \(second.message)")
            }
        }
    }

    @Test func theAccountIsTheNamedOneOrTheOnlyOne() async throws {
        // The named account is read as the account lookup, so the case the input has is not what
        // the row is matched against; the storage rule itself is pinned by `ClientAuthTests`.
        try await withRun(accounts: ["alice", "bob"], arguments: ["add", "https://case.example/feed",
            "--user", "ALICE"]) { outcome, seed, _, written in
            #expect(!outcome.failed, "the stored name is found: \(outcome.message)")
            #expect(written.first?.userID == seed.userIDs["alice"],
                "the row is for the stored row: \(written)")
        }

        // One account and no name: that account is the one the command uses.
        try await withRun(accounts: ["alice"], arguments: ["add", "https://single.example/feed"]) {
            outcome, seed, _, written in
            #expect(!outcome.failed, "the single account is used when none is named: \(outcome.message)")
            #expect(written.first?.userID == seed.userIDs["alice"],
                "the row is for the only account: \(written)")
        }

        // Several accounts and no name is the port's own rule, so the pin reads the rule name the
        // command writes; a patch that took the first account it found would answer no failure.
        try await withRun(accounts: ["alice", "bob"], arguments: ["add", "https://two.example/feed"]) {
            outcome, _, _, written in
            #expect(outcome.failed, "several accounts with none named: \(outcome.message)")
            #expect(outcome.message.contains(ruleName(FeedValidationRule.multipleAccounts)),
                "the message: \(outcome.message)")
            #expect(written.isEmpty, "nothing is written for a run that fails: \(written)")
        }

        // A named account with no row is reported, so the pin is not satisfied by a command that
        // fell back to the account it could read.
        try await withRun(accounts: ["bob"], arguments: ["add", "https://named.example/feed",
            "--user", "alice"]) { outcome, _, _, written in
            #expect(outcome.failed, "a named account with no row: \(outcome.message)")
            #expect(outcome.message.contains(ruleName(FeedValidationRule.accountNotFound)),
                "the message: \(outcome.message)")
            #expect(written.isEmpty, "nothing is written for a run that fails: \(written)")
        }
    }

    @Test func theRowTheDeleteAppliesIsTheRowTheAccountHas() async throws {
        try await withRun(accounts: ["alice", "bob"], arguments: ["remove", "https://shared.example/feed",
            "--user", "bob"]) { outcome, seed, all, written in
            #expect(!outcome.failed, "the run: \(outcome.output)")
            #expect(written.isEmpty, "a delete writes no row: \(written)")
            #expect(all.count == 8, "one row of the nine seeded is gone: \(all)")

            // Both accounts have the url, so a patch that read the row without the account
            // condition deleted the row it found first, which is the row this pin expects to stay.
            let remaining = all.filter { $0.url == "https://shared.example/feed" }
            #expect(remaining.count == 1, "the row with the same url is read once: \(all)")
            #expect(remaining.first?.userID == seed.userIDs["alice"],
                "the row of the other account with the same url is not deleted: \(all)")
            #expect(outcome.output.contains("https://shared.example/feed"),
                "the run reports the row it removed: \(outcome.output)")
        }
    }

    @Test func removeReportsWhenTheAccountHasNoRowWithThatUrl() async throws {
        try await withRun(accounts: ["alice", "bob"], arguments: ["remove", "https://bob.example/feed",
            "--user", "alice"]) { outcome, _, all, written in
            #expect(outcome.failed, "a url the account has no row for: \(outcome.output)")
            #expect(outcome.message.contains(ruleName(FeedValidationRule.feedNotFound)),
                "the message: \(outcome.message)")
            #expect(all.count == 9 && written.isEmpty, "nothing was deleted: \(all)")
        }
    }

    @Test func listPrintsTheRowsInTheOrderTheRuleAnswers() async throws {
        try await withRun(accounts: ["alice", "bob"], arguments: ["list", "--user", "alice"]) {
            outcome, seed, all, written in
            #expect(!outcome.failed, "the run: \(outcome.output)")
            #expect(all.count == 9 && written.isEmpty, "the listing writes nothing: \(all)")

            // The two halves of the order are read apart: the pair inside the equal counts is the
            // pair that separates only under the lowercased reading, and the row with one error is
            // last although its title would put it first.
            #expect(Self.position(outcome.output, "alpha") < Self.position(outcome.output, "Beta"),
                "the lowercased title: \(outcome.output)")
            #expect(Self.position(outcome.output, "Beta") < Self.position(outcome.output, "Zeta"),
                "the title order inside the equal counts: \(outcome.output)")
            #expect(Self.position(outcome.output, "Zeta") < Self.position(outcome.output, "Alpha"),
                "the error count before the title: \(outcome.output)")

            // Bob's row has the largest count, so a patch that read the order without the account
            // condition printed it first and named the account this pin expects not to appear.
            #expect(!outcome.output.contains("Bob"),
                "only the rows of the account the listing is given: \(outcome.output)")
            #expect(all.filter { $0.userID == seed.userIDs["alice"] }.count == 7 &&
                seed.userIDs.count == 2, "the data the pin seeded: \(all)")
        }
    }

    @Test func theMigrationFlagGatesTheFeedCommands() async throws {
        let unmigrated = try TemporaryDirectory()
        defer { unmigrated.remove() }
        let console = TestConsole()
        var failed = false
        do {
            try await RivuletCLI.run(console: console,
                environment: ["DATABASE_URL": unmigrated.path("off.db"), "RUN_MIGRATIONS": "false"],
                arguments: ["rivulet", "add", "https://example.com/feed", "--user", "alice"])
            Issue.record("a command that does not migrate must fail on a fresh database")
        } catch {
            failed = true
        }
        #expect(failed, "the flag off leaves the command no schema to write to")
        let tables = try await tables(at: unmigrated.path("off.db"))
        #expect(!tables.contains("feeds"), "the flag off does not migrate: \(tables)")
    }

    // MARK: - Setup

    private struct RunOutcome: Sendable {
        let output: String
        let failed: Bool
        let message: String
    }

    /// A feed row read back through SQL, with the category title the row points at.
    private struct FeedRow: Sendable {
        let id: Int
        let userID: Int
        let categoryTitle: String
        let url: String
        let title: String
        let siteURL: String
        let errorCount: Int
        let nextCheckAt: Int
    }

    private struct Seeded: Sendable {
        let userIDs: [String: Int]
        let seededIDs: Set<Int>
    }

    /// Seeds `accounts` and the rows each pin needs — a url both accounts have, the titles and the
    /// counts the listing pins read apart, and the rows below one feed — and hands the body the
    /// outcome of one run with the rows read back after it.
    ///
    /// The pins read the rows through SQL, so a pin is not satisfied by the read it is testing. The
    /// rows the run wrote are told apart from the seed by their ids rather than by a count, so a
    /// pin that says a failing run writes nothing can fail on a patch that wrote before the rule.
    private func withRun(accounts: [String], arguments: [String],
        _ body: (RunOutcome, Seeded, [FeedRow], [FeedRow]) async throws -> Void) async throws {
        try await withMigratedStorage { database, storage in
            let seeded = try await storage.withConnection { connection in
                try await Self.seed(connection, accounts: accounts)
            }

            let console = TestConsole()
            var failed = false
            var message = ""
            do {
                try await RivuletCLI.run(console: console, environment: ["DATABASE_URL": database.path],
                    arguments: ["rivulet"] + arguments)
            } catch {
                failed = true
                message = String(describing: error)
            }

            let rows = try await storage.withConnection { connection in
                try await Self.readFeeds(connection)
            }
            try await body(RunOutcome(output: console.output, failed: failed, message: message),
                seeded, rows, rows.filter { !seeded.seededIDs.contains($0.id) })
        }
    }

    private static func seed(_ connection: any Database, accounts: [String]) async throws -> Seeded {
        var userIDs: [String: Int] = [:]
        for name in accounts {
            userIDs[name] = try await seedUser(connection, username: name)
        }
        for name in accounts {
            _ = try await seedCategory(connection, userID: try #require(userIDs[name]), title: "Tech")
        }

        // A url both accounts have, so the delete pin sees which of the two rows it removed; the
        // titles and counts are the data the listing pin needs for the two orders to differ.
        let graph: [(owner: String, url: String, title: String, count: Int)] = [
            ("alice", "https://alice.example/feed", "", 0),
            ("alice", "https://shared.example/feed", "", 0),
            ("bob", "https://shared.example/feed", "", 0),
            ("alice", "https://alpha.example/feed", "Alpha", 1),
            ("alice", "https://zeta.example/feed", "Zeta", 2),
            ("alice", "https://lower.example/feed", "alpha", 2),
            ("alice", "https://upper.example/feed", "Beta", 2),
            ("alice", "relative.example/feed", "", 0),
            ("bob", "https://bob.example/feed", "Bob", 9),
        ]

        var seededIDs: Set<Int> = []
        for row in graph {
            guard let userID = userIDs[row.owner] else { continue }
            let categoryID = try await Self.categoryID(connection, userID: userID, title: "Tech")
            let feedID = try await seedFeed(connection, userID: userID, categoryID: categoryID, url: row.url)
            seededIDs.insert(feedID)
            if row.count > 0 {
                try await sqlDatabase(connection).raw("""
                    UPDATE feeds SET parsing_error_count = \(bind: row.count), title = \(bind: row.title)
                    WHERE id = \(bind: feedID)
                    """).run()
            }
            if row.url == "https://alice.example/feed" {
                try await Self.seedRowsBelow(connection, userID: userID, feedID: feedID)
            }
        }

        return Seeded(userIDs: userIDs, seededIDs: seededIDs)
    }

    /// The entry, the tombstone and the attachment below one feed, so the pin sees which of them a
    /// delete takes with the row, on the feed the command is given here.
    private static func seedRowsBelow(_ connection: any Database, userID: Int,
        feedID: Int) async throws {
        let entryID = try await seedEntry(connection, userID: userID, feedID: feedID, hash: "h1",
            content: "<p>Searchable content</p>")
        let sql = try sqlDatabase(connection)
        try await sql.raw("""
            INSERT INTO entry_tombstones (feed_id, hash, deleted_at)
            VALUES (\(bind: feedID), \(bind: "h1"), \(bind: 1_700_000_000))
            """).run()
        try await sql.raw("""
            INSERT INTO enclosures (entry_id, url, mime_type)
            VALUES (\(bind: entryID), \(bind: "https://example.com/a.mp3"), \(bind: "audio/mpeg"))
            """).run()
    }

    private static func categoryID(_ connection: any Database, userID: Int,
        title: String) async throws -> Int {
        let category = try await CategoryRepository(connection).byTitle(userID: userID, title: title)
        return try #require(category?.id)
    }

    private static func readFeeds(_ connection: any Database) async throws -> [FeedRow] {
        let sql = try sqlDatabase(connection)
        return try await sql.raw("""
            SELECT f.id, f.user_id, c.title AS category_title, f.url, f.title, f.site_url,
                f.parsing_error_count, f.next_check_at
            FROM feeds f JOIN categories c ON c.id = f.category_id
            ORDER BY f.id
            """).all().map {
            try FeedRow(id: $0.decode(column: "id", as: Int.self),
                userID: try $0.decode(column: "user_id", as: Int.self),
                categoryTitle: try $0.decode(column: "category_title", as: String.self),
                url: try $0.decode(column: "url", as: String.self),
                title: try $0.decode(column: "title", as: String.self),
                siteURL: try $0.decode(column: "site_url", as: String.self),
                errorCount: try $0.decode(column: "parsing_error_count", as: Int.self),
                nextCheckAt: try $0.decode(column: "next_check_at", as: Int.self))
        }
    }

    private static func position(_ text: String, _ value: String) -> Int {
        text.distance(from: text.startIndex, to: text.range(of: value)!.lowerBound)
    }

    /// The name the command writes for a rule, which is what the pins read.
    private func ruleName(_ rule: FeedValidationRule) -> String { rule.rawValue }
}
