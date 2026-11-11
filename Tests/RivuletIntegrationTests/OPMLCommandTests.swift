import ConsoleKit
import Foundation
import Fluent
import SQLKit
import Testing
import RivuletApp
@testable import RivuletCore

/// `rivulet import` and `rivulet export` as runs through the in-process console, against the file
/// the pin names, on a temp database. The command surface is the port's own: the reference has no
/// `import` command at all — its import reaches the rows through the API handler — and its CLI
/// export takes the username as a flag argument and prints the document to stdout. The stdout half
/// is the port shape that matches the reference answer; writing a file is the port's own half,
/// named as an option because `@Argument` has no default and cannot name an optional path, and the
/// `docs/parity.md` row names the divergence. The pins read the values carried on the line, not the
/// sentences, and the account rules the runs reach are pinned by `FeedCommandAccount` where they
/// live. What these pins can fail on, each checked by patching the rule and reverting: that the
/// import run reads the bytes of the file the argument names, so a run that reads another path
/// reports it, and hands them to the import path for the account the run resolves; that a path the
/// run cannot read is reported and reaches no write; that the export run prints the document to
/// stdout, which is where the reference prints it and writes nothing on the filesystem; and that
/// the export run writes the file when the option names one and prints only the line that names the
/// path it wrote, which is the port's own half. The documents are read as fragments without the
/// leading indent, so the serializer rules pinned on the serialize suite — the header constant, the
/// indent, the layout, the field order, the escape set and the grouping — cannot reach these pins;
/// the parsed inputs carry `type="rss"` on every record with a url, so a patch that reads the
/// subscription branch through `type` answers the same records here; and the import pin's record
/// carries its title as its url, so the pin that names which field the create path is given stays
/// on the import suite. The fields the rows carry are the handler mapping, pinned there. What these
/// pins cannot fail on: the wordings of the lines and of the reported failures; the rules the runs
/// only reach, which `FeedCommandAccount` and the storage suite pin; the time the export run stamps
/// in the date field, which is the time the run happens at and not something a pin can name; and
/// the migrations gate, which the command pins have read since stage 6.
@Suite struct OPMLCommandTests {
    init() {
        TestLogging.bootstrapOnce()
    }

    @Test func theImportRunReadsTheFileItNamesAndWritesForTheAccountItResolves() async throws {
        try await withMigratedStorage { database, storage in
            let userID = try await storage.withConnection { connection in
                try await seedUser(connection, username: "alice")
            }

            // The record's title is its url, so the pin reads only that the run reaches the import
            // path: a patch to the field the create path is given answers the same row here, and
            // that rule is pinned on the import suite.
            let file = try writeOPML("""
                <opml version="2.0"><head><title>x</title></head><body>
                <outline text="Tech" title="https://imported.example/feed" text="https://imported.example/feed" \
                xmlUrl="https://imported.example/feed" htmlUrl="https://imported.example/feed" type="rss"/>
                </body></opml>
                """, in: database.directory.path)
            let databasePath = database.path

            let outcome = try await runCommand(databasePath: databasePath,
                arguments: ["import", file, "--user", "alice"])
            #expect(!outcome.failed, "the run: \(outcome.output)")

            try await storage.withConnection { connection in
                let written = try await feedRows(connection)
                #expect(written.count == 1, "the run reaches the import path: \(written)")
                let row = try #require(written.first)
                #expect(row.userID == userID, "the account the run resolved: \(row)")

                // The run resolves the account through the lookup: `--user` names the row, and when
                // none is named the single account is used, which is the rule `FeedCommandAccount`
                // pins; here the run reaches it, so the control names the single-account answer.
                // The fields the rows carry are the handler mapping, pinned on the import suite.
                let second = try await runCommand(databasePath: databasePath,
                    arguments: ["import", file], environment: ["RUN_MIGRATIONS": "false"])
                #expect(!second.failed, "the single-account answer: \(second.output)")
                let rows = try await feedRows(connection)
                #expect(rows.count == 1, "the duplicate answer stops the second run from writing: \(rows)")
            }
        }
    }

    @Test func aPathTheRunCannotReadIsReportedAndWritesNothing() async throws {
        try await withMigratedStorage { database, storage in
            let userID = try await storage.withConnection { connection in
                try await seedUser(connection, username: "alice")
            }

            // The path is one the filesystem answers nothing for, so the pin reads the run's own
            // rule and a patch to the read of the document cannot reach it.
            let outcome = try await runCommand(databasePath: database.path,
                arguments: ["import", database.directory.path + "/not-there.opml", "--user", "alice"])
            #expect(outcome.failed, "a path the run cannot read must fail the run")

            try await storage.withConnection { connection in
                let written = try await feedRows(connection)
                #expect(written.isEmpty, "a run that fails writes nothing")
            }
            _ = userID
        }
    }

    @Test func theExportRunPrintsTheDocumentToStdoutWhereTheReferencePrintsIt() async throws {
        try await withMigratedStorage { database, storage in
            let userID = try await storage.withConnection { connection in
                let id = try await seedUser(connection, username: "alice")
                let tech = try await seedCategory(connection, userID: id, title: "Tech")
                _ = try await seedFeed(connection, userID: id, categoryID: tech,
                    url: "https://exported.example/feed")
                try await RawSQL.sql(on: connection).raw(
                    "UPDATE feeds SET title = 'Exported' WHERE url = 'https://exported.example/feed'").run()
                return id
            }

            let outcome = try await runCommand(databasePath: database.path,
                arguments: ["export", "--user", "alice"])
            #expect(!outcome.failed, "the run: \(outcome.output)")
            // The document is read as fragments without the indent, so the serializer rules pinned
            // on the serialize suite — the header constant, the indent, the layout, the field order
            // and the escape set — cannot reach this pin, which names where the document goes.
            #expect(outcome.output.contains("xmlUrl=\"https://exported.example/feed\""),
                "the record is on stdout, where the reference prints it: \(outcome.output)")
            #expect(outcome.output.contains("</opml>"), "the document is printed whole: \(outcome.output)")

            // The half the reference answers and the port keeps: the console line, not a file. The
            // run writes nothing to the filesystem when no file is named.
            #expect(!FileManager.default.fileExists(atPath: database.directory.path + "/feeds.opml"),
                "the run writes no file: \(outcome.output)")
            _ = userID
        }
    }

    @Test func theExportRunWritesTheFileWhenTheOptionNamesOne() async throws {
        try await withMigratedStorage { database, storage in
            let userID = try await storage.withConnection { connection in
                let id = try await seedUser(connection, username: "alice")
                let tech = try await seedCategory(connection, userID: id, title: "Tech")
                _ = try await seedFeed(connection, userID: id, categoryID: tech,
                    url: "https://written.example/feed")
                try await RawSQL.sql(on: connection).raw(
                    "UPDATE feeds SET title = 'Written' WHERE url = 'https://written.example/feed'").run()
                return id
            }

            let out = database.directory.path + "/feeds.opml"
            let outcome = try await runCommand(databasePath: database.path,
                arguments: ["export", "--file", out, "--user", "alice"])
            #expect(!outcome.failed, "the run: \(outcome.output)")

            let written = try String(contentsOfFile: out, encoding: .utf8)
            #expect(written.contains("xmlUrl=\"https://written.example/feed\""),
                "the file holds the document the serializer wrote: \(written)")

            // The run prints the line that names the path it wrote, which is the port's own half,
            // and it prints nothing of the document. Reading the line as the value it carries keeps
            // the escape, layout and field-order rules out of this pin.
            #expect(outcome.output.contains(out), "the line names the path the run wrote: \(outcome.output)")
            #expect(!outcome.output.contains("xmlUrl"),
                "the document goes to the file, not to stdout: \(outcome.output)")
            _ = userID
        }
    }

    private struct FeedRow: Sendable {
        let userID: Int
        let url: String
        let title: String
        let siteURL: String
    }

    private func feedRows(_ connection: any Database) async throws -> [FeedRow] {
        try await RawSQL.sql(on: connection).raw("""
            SELECT user_id, url, title, site_url FROM feeds ORDER BY id
            """).all().map { row in
            FeedRow(userID: try row.decode(column: "user_id", as: Int.self),
                url: try row.decode(column: "url", as: String.self),
                title: try row.decode(column: "title", as: String.self),
                siteURL: try row.decode(column: "site_url", as: String.self))
        }
    }

    private func writeOPML(_ content: String, in directory: String) throws -> String {
        let path = directory + "/feeds.opml"
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }
}
