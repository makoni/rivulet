import Fluent
import FluentSQLiteDriver
import Foundation
import SQLKit
import XCTest
import RivuletApp
import RivuletCore

final class CommandLineTests: XCTestCase {
    override func setUp() {
        TestLogging.bootstrapOnce()
    }

    func testHelpListsEveryCommandWithoutConfiguration() async throws {
        let console = TestConsole()

        try await RivuletCLI.run(console: console, environment: [:], arguments: ["rivulet", "--help"])

        let expected = [
            "serve", "migrate", "version",
            "create-admin", "add", "remove", "list",
            "import", "export", "refresh", "status",
            "integration-credentials", "backup", "vacuum",
        ]
        // The group help lists one command per line, starting with its name.
        let listed = Set(
            console.output
                .split(separator: "\n")
                .compactMap { $0.split(separator: " ").first.map(String.init) }
        )
        for name in expected {
            XCTAssertTrue(listed.contains(name), "`\(name)` is missing from --help:\n\(console.output)")
        }
    }

    func testVersionPrintsTheVersionWithoutConfiguration() async throws {
        let console = TestConsole()

        try await RivuletCLI.run(console: console, environment: [:], arguments: ["rivulet", "version"])

        XCTAssertTrue(console.output.contains("rivulet \(RivuletCore.version)"), console.output)
    }

    func testServeHelpMentionsTheServerOptions() async throws {
        let console = TestConsole()

        try await RivuletCLI.run(console: console, environment: [:], arguments: ["rivulet", "serve", "--help"])

        XCTAssertTrue(console.output.contains("--port"), console.output)
    }

    func testBareInvocationPrintsHelpAndFails() async throws {
        let console = TestConsole()

        do {
            try await RivuletCLI.run(console: console, environment: [:], arguments: ["rivulet"])
            XCTFail("a bare invocation must not succeed")
        } catch {
            XCTAssertTrue(String(describing: error).contains("Missing command"), "\(error)")
        }
        XCTAssertTrue(console.output.contains("Usage:"), console.output)
    }

    func testUnknownCommandIsRejected() async throws {
        let console = TestConsole()

        do {
            try await RivuletCLI.run(console: console, environment: [:], arguments: ["rivulet", "frobnicate"])
            XCTFail("an unknown command must not succeed")
        } catch {
            XCTAssertTrue(String(describing: error).contains("Unknown command"), "\(error)")
        }
    }

    func testPlannedCommandsReportTheStageThatImplementsThem() async throws {
        let planned: [(name: String, stage: Int)] = [
            ("create-admin", 5),
            ("add", 6),
            ("remove", 6),
            ("list", 6),
            ("import", 5),
            ("export", 5),
            ("refresh", 4),
            ("status", 4),
            ("integration-credentials", 5),
            ("backup", 6),
            ("vacuum", 6),
        ]

        for (name, stage) in planned {
            let console = TestConsole()
            do {
                try await RivuletCLI.run(console: console, environment: [:], arguments: ["rivulet", name])
                XCTFail("`\(name)` must not succeed before stage \(stage)")
            } catch let error as CLIError {
                XCTAssertTrue(error.message.contains("not implemented yet"), error.message)
                XCTAssertTrue(error.message.contains("stage \(stage)"), error.message)
            } catch {
                XCTFail("unexpected error for `\(name)`: \(error)")
            }
        }
    }

    func testMigrateCreatesTheSchema() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        // `RUN_MIGRATIONS` only gates what `serve` does: `migrate` always migrates.
        let environment = ["DATABASE_URL": directory.path("rivulet.db"), "RUN_MIGRATIONS": "false"]

        let first = TestConsole()
        try await RivuletCLI.run(console: first, environment: environment, arguments: ["rivulet", "migrate"])
        XCTAssertTrue(first.output.contains("Applied 1 migration(s): SchemaV1."), first.output)

        // A second run is a no-op and says so.
        let second = TestConsole()
        try await RivuletCLI.run(console: second, environment: environment, arguments: ["rivulet", "migrate"])
        XCTAssertTrue(second.output.contains("up to date"), second.output)

        // The schema really exists: open the same file through the application factory.
        let config = try Config.load(environment: environment)
        let rivulet = try await ApplicationFactory.make(config: config)
        do {
            let sql = try XCTUnwrap(rivulet.application.db(.sqlite) as? any SQLDatabase)
            let rows = try await sql.raw("SELECT name FROM sqlite_master WHERE type = 'table'").all()
            let tables = try rows.map { try $0.decode(column: "name", as: String.self) }
            XCTAssertTrue(tables.contains("users"), "\(tables)")
            XCTAssertTrue(tables.contains("entries_fts"), "\(tables)")

            let countRow = try await sql.raw("SELECT COUNT(*) AS count FROM _fluent_migrations").first()
            XCTAssertEqual(try countRow?.decode(column: "count", as: Int.self), 1)
        } catch {
            try? await rivulet.shutdown()
            throw error
        }
        try await rivulet.shutdown()
    }

    func testPlannedCommandsReportTheStageEvenWithArguments() async throws {
        let invocations: [(arguments: [String], stage: Int)] = [
            (["add", "https://example.com/feed"], 6),
            (["import", "feeds.opml"], 5),
            (["status", "--json"], 4),
        ]

        for (arguments, stage) in invocations {
            let console = TestConsole()
            do {
                try await RivuletCLI.run(
                    console: console,
                    environment: [:],
                    arguments: ["rivulet"] + arguments
                )
                XCTFail("`\(arguments.joined(separator: " "))` must not succeed before stage \(stage)")
            } catch let error as CLIError {
                XCTAssertTrue(error.message.contains("not implemented yet"), error.message)
                XCTAssertTrue(error.message.contains("stage \(stage)"), error.message)
            } catch {
                XCTFail("unexpected error for `\(arguments.joined(separator: " "))`: \(error)")
            }
        }
    }

    func testServeRejectsUnsupportedArgumentsBeforeCreatingTheDatabase() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let databasePath = directory.path("rivulet.db")
        let environment = ["DATABASE_URL": databasePath]

        let cases: [(arguments: [String], expected: String)] = [
            (["serve", "--bogus"], "Input not recognized: --bogus"),
            (["serve", "--port", "abc"], "Could not convert option for `port`"),
        ]
        for (arguments, expected) in cases {
            let console = TestConsole()
            do {
                try await RivuletCLI.run(
                    console: console,
                    environment: environment,
                    arguments: ["rivulet"] + arguments
                )
                XCTFail("`\(arguments.joined(separator: " "))` must not succeed")
            } catch {
                XCTAssertTrue(String(describing: error).contains(expected), "\(arguments): \(error)")
            }
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: databasePath),
                "`\(arguments.joined(separator: " "))` must fail before the database is created"
            )
        }
    }

    func testMigrateRequiresTheDatabasePath() async throws {
        let console = TestConsole()

        do {
            try await RivuletCLI.run(console: console, environment: [:], arguments: ["rivulet", "migrate"])
            XCTFail("migrate without DATABASE_URL must not succeed")
        } catch {
            XCTAssertTrue(String(describing: error).contains("DATABASE_URL"), "\(error)")
        }
    }
}
