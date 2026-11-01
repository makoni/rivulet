import ConsoleKit
import Foundation
import SQLKit
import Testing
import RivuletApp
@testable import RivuletCore

/// The minimal machine-readable contract the stage-4 soak reads: `rivulet status --json`. The
/// reference has no status command, so the document shape is the port's own, recorded in
/// `docs/parity.md`; the values are the rows and the batch rules, which `StatusSnapshotTests` pins.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the `--json` flag
/// selects the document, so a patch that always prints JSON fails the pin that runs the command
/// without the flag; the whole output is the document, which a patch printing anything beside
/// it fails because the output then is not one document; the document carries the documented
/// keys, so a patch renaming one fails the pin that reads them; an absent stamp stays `null`,
/// which a patch that drops the key or reports it as `0` fails; the values are the stored rows
/// rather than the schema defaults, which a patch reading a default fails; the human form
/// carries the row's values as the numbers on its line, which a patch printing the default
/// counter fails; the environment values reach the totals through the command, which a patch
/// keeping the reference defaults fails; the due total is read against the process clock, which
/// a patch passing a fixed instant fails; and the migration flag gates this command, which a
/// patch that migrates regardless of it fails.
///
/// What they cannot fail on: that the command makes no network request or does not sleep; which
/// clock the command is built with, since a pin can only read the instant that clock answers, which
/// is what the process-clock pin does through the rows it seeds; the order of the JSON keys, which
/// a machine-readable contract does not promise; the wording of the human form, which is the port's
/// own, so the pins read the values on the line and not the words, and which number on that line
/// belongs to which field, since the pin reads them as a set; the totals of the human form, which
/// the document pins; and the closing of the storage the command opened, which no pin can assert
/// because a shutdown that itself fails would hide the failure the test reports. Nothing here
/// sleeps or polls.
@Suite struct StatusCommandTests {
    init() {
        TestLogging.bootstrapOnce()
    }

    // MARK: - Pins

    @Test func theWholeOutputIsTheDocumentWithTheDocumentedKeys() async throws {
        try await withRun(feeds: [spec(id: 1, url: "http://host.test/due", errors: 2,
            message: "parse failed"), spec(id: 2, url: "http://host.test/off", disabled: true)]) {
            document, output in
            // The whole output read as a document: anything printed beside it makes this fail,
            // because then the output as a whole is not one document.
            let parsed = try #require(document, "the whole output is the document: \(output)")
            #expect(Set(parsed.keys) == ["feeds", "totals"], "the top-level keys: \(parsed)")
            let feeds = try #require(parsed["feeds"] as? [[String: Any]], "feeds reads as an array")
            let totals = try #require(parsed["totals"] as? [String: Any], "totals reads as an object")
            #expect(Set(totals.keys) == ["feeds", "enabled", "disabled", "due", "at_error_limit"],
                "the documented totals keys: \(totals)")
            for feed in feeds {
                #expect(Set(feed.keys) == ["id", "user_id", "title", "url", "site_url", "enabled",
                    "fetched_at", "next_check_at", "parsing_error_count", "parsing_error_message"],
                    "the documented feed keys: \(feed)")
            }

            // The values are the rows the storage holds, not the schema defaults.
            let first = try #require(row(parsed, id: 1))
            #expect(first["url"] as? String == "http://host.test/due", "\(first)")
            #expect(first["parsing_error_count"] as? Int == 2, "\(first)")
            #expect(first["parsing_error_message"] as? String == "parse failed", "\(first)")
            let second = try #require(row(parsed, id: 2))
            #expect(second["enabled"] as? Bool == false, "\(second)")
            #expect(totals["feeds"] as? Int == 2, "\(totals)")
            #expect(totals["enabled"] as? Int == 1, "\(totals)")
            #expect(totals["disabled"] as? Int == 1, "\(totals)")
        }
    }

    @Test func anAbsentStampStaysNullInTheDocument() async throws {
        // A row written without a schedule or a fetch: the create path stamps `next_check_at` with
        // the instant the reference reads, so this pin inserts the row the way the storage layer
        // would see a NULL column, which the contract must report as null rather than as zero.
        try await withRun(feeds: [spec(id: 1, url: "http://host.test/fresh", due: nil,
            fetched: nil)]) { document, _ in
            let parsed = try #require(document)
            let feed = try #require(row(parsed, id: 1))
            #expect(feed["fetched_at"] is NSNull, "an absent stamp is not a zero: \(feed)")
            #expect(feed["next_check_at"] is NSNull, "an absent stamp is not a zero: \(feed)")
            #expect(feed["title"] as? String == "", "the empty value the row holds: \(feed)")
            #expect(feed["site_url"] as? String == "", "the empty value the row holds: \(feed)")
        }
    }

    @Test func withoutTheFlagTheConsoleGetsTheHumanFormNotJSON() async throws {
        let row = spec(id: 7, url: "http://host.test/human", errors: 2)
        let fetched = try #require(row.fetchedAt)
        let next = try #require(row.dueAt)
        try await withRun(feeds: [row], json: false) { document, output in
            #expect(document == nil, "the default form is not a JSON document: \(output)")
            let line = try #require(output.split(separator: "\n")
                .first { $0.contains("http://host.test/human") }, "the line for the row: \(output)")
            // The numbers the line carries are the row's values. The wording around them is the
            // port's own, so the pin reads the numbers as numbers: a patch printing the default
            // counter, or the clock instead of the stored instant, changes this set.
            let numbers = Set(String(line).components(separatedBy: CharacterSet.decimalDigits.inverted)
                .compactMap(Int.init))
            #expect(numbers == [7, 2, fetched, next], "the numbers on the line are the values: \(line)")
        }
    }

    @Test func theEnvironmentValuesReachTheTotalsThroughTheCommand() async throws {
        // A batch size of one caps the pick the totals read, while the document lists every row.
        try await withRun(environment: ["BATCH_SIZE": "1"],
            feeds: [spec(id: 1, url: "http://host.test/first"),
                    spec(id: 2, url: "http://host.test/second")]) { document, _ in
            let parsed = try #require(document)
            let totals = try #require(parsed["totals"] as? [String: Any])
            #expect(totals["feeds"] as? Int == 2, "\(totals)")
            #expect(totals["due"] as? Int == 1, "the batch size comes from the environment: \(totals)")
        }

        // A limit of zero is the switch that reads no filter, so the row at three is due
        // and nothing is at the limit.
        try await withRun(environment: ["POLLING_PARSING_ERROR_LIMIT": "0"],
            feeds: [spec(id: 3, url: "http://host.test/at-limit", errors: 3)]) { document, _ in
            let parsed = try #require(document)
            let totals = try #require(parsed["totals"] as? [String: Any])
            #expect(totals["due"] as? Int == 1, "\(totals)")
            #expect(totals["at_error_limit"] as? Int == 0, "zero reads no filter: \(totals)")
        }
    }

    @Test func theDueTotalIsReadAgainstTheProcessClock() async throws {
        let past = spec(id: 1, url: "http://host.test/past", due: -3600)
        let future = spec(id: 2, url: "http://host.test/future", due: 3600)
        try await withRun(feeds: [past, future]) { document, _ in
            let parsed = try #require(document)
            let totals = try #require(parsed["totals"] as? [String: Any])
            #expect(totals["feeds"] as? Int == 2, "\(totals)")
            #expect(totals["due"] as? Int == 1, "only the row that is due now: \(totals)")

            // The document reports the stored instants, not the one the process answered.
            let feed = try #require(row(parsed, id: 1))
            #expect(feed["next_check_at"] as? Int == past.dueAt, "\(feed)")
        }
    }

    @Test func theMigrationFlagGatesThisCommand() async throws {
        // The flag on: the command builds the schema and reads the rows through it.
        let migrated = try TemporaryDirectory()
        defer { migrated.remove() }
        let on = TestConsole()
        try await RivuletCLI.run(console: on, environment: ["DATABASE_URL": migrated.path("on.db")],
            arguments: ["rivulet", "status", "--json"])
        let document = try #require(jsonDocument(on.output))
        let totals = try #require(document["totals"] as? [String: Any])
        #expect(totals["feeds"] as? Int == 0, "the flag on reads the migrated schema: \(on.output)")
        let created = try await tables(at: migrated.path("on.db"))
        #expect(created.contains("feeds"), "the flag on migrates: \(created)")

        // The flag off: the command does not create the schema, so it cannot read the rows and
        // fails rather than reporting an empty snapshot.
        let unmigrated = try TemporaryDirectory()
        defer { unmigrated.remove() }
        let off = TestConsole()
        var failed = false
        do {
            try await RivuletCLI.run(console: off,
                environment: ["DATABASE_URL": unmigrated.path("off.db"), "RUN_MIGRATIONS": "false"],
                arguments: ["rivulet", "status", "--json"])
            Issue.record("a command that does not migrate must fail on a fresh database")
        } catch {
            // The pin reads that the run failed, not the words of the error, which are the port's.
            failed = true
        }
        #expect(failed, "the flag off leaves the command no schema to read")
        let absent = try await tables(at: unmigrated.path("off.db"))
        #expect(!absent.contains("feeds"), "the flag off does not migrate: \(absent)")
    }

    // MARK: - Setup

    /// A feed row as the command reads it: the id the pins name, the url, the instants relative to
    /// the process clock the command answers with, the error count and the disabled flag.
    private struct FeedSpec: Sendable {
        let id: Int
        let url: String
        let dueAt: Int?
        let fetchedAt: Int?
        let errors: Int
        let message: String
        let disabled: Bool
    }

    /// The instants are relative to the process clock the command answers with, so a pin
    /// can name the row it expects the due rule to pick; `nil` is the column the row has no
    /// value for.
    private func spec(id: Int, url: String, due: Int? = -3600, fetched: Int? = -7200,
        errors: Int = 0, message: String = "", disabled: Bool = false) -> FeedSpec {
        let now = Int(Date.now.timeIntervalSince1970)
        return FeedSpec(id: id, url: url, dueAt: due.map { now + $0 },
            fetchedAt: fetched.map { now + $0 }, errors: errors, message: message, disabled: disabled)
    }

    /// Seeds the rows, runs `rivulet status` against the same file with the values the pins
    /// name, and hands the pins the document — `nil` when the output is not one — and the
    /// console output.
    ///
    /// The setup connection is not held across the run: the command opens its own
    /// application and its own read, which the single pooled connection of the test storage
    /// cannot serve from inside a checkout of its own.
    private func withRun(environment: [String: String] = [:], feeds: [FeedSpec],
        json: Bool = true,
        _ body: @escaping @Sendable ([String: Any]?, String) async throws -> Void) async throws {
        try await withMigratedStorage { database, storage in
            try await storage.withConnection { connection in
                let userID = try await seedUser(connection)
                let categoryID = try await seedCategory(connection, userID: userID, title: "Tech")
                for feed in feeds {
                    try await sqlDatabase(connection).raw("""
                        INSERT INTO feeds (id, user_id, category_id, url, title, next_check_at,
                            fetched_at, parsing_error_count, parsing_error_message, disabled,
                            created_at, updated_at)
                        VALUES (\(bind: feed.id), \(bind: userID), \(bind: categoryID),
                            \(bind: feed.url), \(bind: ""), \(bind: feed.dueAt),
                            \(bind: feed.fetchedAt), \(bind: feed.errors), \(bind: feed.message),
                            \(bind: feed.disabled), \(bind: 1_000_000_000), \(bind: 1_000_000_000))
                        """).run()
                }
            }

            var env = environment
            env["DATABASE_URL"] = database.path
            let console = TestConsole()
            var arguments = ["rivulet", "status"]
            if json { arguments.append("--json") }
            try await RivuletCLI.run(console: console, environment: env, arguments: arguments)
            let output = console.output
            try await body(jsonDocument(output), output)
        }
    }

    /// The whole output read as one JSON document; `nil` when it is not one, which is what the pin
    /// that names the default form reads.
    private func jsonDocument(_ output: String) -> [String: Any]? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) else {
            return nil
        }
        return parsed as? [String: Any]
    }

    /// One row of the document, read by the id the pin names.
    private func row(_ document: [String: Any], id: Int) -> [String: Any]? {
        (document["feeds"] as? [[String: Any]])?.first { $0["id"] as? Int == id }
    }

    /// The tables the database file holds, read through a connection of its own.
    private func tables(at path: String) async throws -> [String] {
        let config = try Config.load(environment: ["DATABASE_URL": path])
        let rivulet = try await ApplicationFactory.make(config: config)
        do {
            let sql = try #require(rivulet.application.db(.sqlite) as? any SQLDatabase)
            let rows = try await sql.raw("SELECT name FROM sqlite_master WHERE type = 'table'").all()
            let names = try rows.map { try $0.decode(column: "name", as: String.self) }
            try await rivulet.shutdown()
            return names
        } catch {
            try? await rivulet.shutdown()
            throw error
        }
    }
}
