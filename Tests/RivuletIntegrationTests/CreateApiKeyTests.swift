import ConsoleKit
import FluentKit
import Foundation
import SQLKit
import Testing
import RivuletApp
@testable import RivuletCore

/// The command as a run, over the in-process console: the account it resolves, the rules it applies
/// in the reference's order, the row it writes, and the line it prints. The rules are the
/// `ApiKeyValidation` pair pinned by `ApiKeyValidationTests`, the write is the one pinned by
/// `ApiKeyRepositoryTests`, and the account is the lookup pinned by `UserRepositoryTests`; what
/// this suite reads is what the run does with those answers.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the row as the run
/// derived it, which the two write patches named in `ApiKeyRepositoryTests` — the description and
/// the last use — reach here as well, while the fixed-token patch cannot, because this pin reads
/// the token as the shape the generator writes and a fixed value of that shape answers it; the line
/// printing the value it stored rather than the description; that a description failing a rule ends
/// the run writing nothing, which a patch that wrote before the rules fails on — that patch fires
/// the row, the printed value and the account pins too, because the runs those pins make write a
/// row whatever the description is and then report the duplicate rule; the account the run
/// resolves, which a patch that wrote for another account fails on; and the flag gating the
/// migrations, which a patch that migrated whatever the flag says fails on — that pin reads the
/// schema each run leaves behind, on a file the run itself opens. The character-class patch named
/// in `ApiKeyValidationTests` fires the row, the printed value and the account pins here too,
/// because the run applies the rules through that same function.
///
/// What they cannot fail on: the shape of the command line and the wording of what the run prints,
/// which are the port's own path, recorded in `docs/parity.md`; the reference trimming the
/// description in its form, which no input here reads; the console seam itself, which the harness
/// pins; the ids the run assigns, which the pins read through SQL because the pool does not fix the
/// order the writes land in; and the wordings of the storage failures this suite cannot trigger.
///
@Suite struct CreateApiKeyTests {
    init() {
        TestLogging.bootstrapOnce()
    }

    @Test func theRowIsWrittenAsTheCommandDerivedIt() async throws {
        try await withRun(arguments: ["create-api-key", "Phone App"],
            seed: [SeedRow(username: "bob")]) { outcome, stored in
            #expect(!outcome.failed, "the run: \(outcome.output)")
            #expect(stored.count == 1, "one row for the account the run resolved")

            let key = try #require(stored.first)
            #expect(key.description == "Phone App", "the description as the run read it")
            #expect(key.token.count == 64 && key.token.allSatisfy { Self.hexCharacters.contains($0) },
                "the token is the generator's answer, read as the shape it writes")
            #expect(key.userID == 1, "the account the run resolved")
            #expect(key.lastUseIsNull == 1, "the write stamps nothing for the last use")
        }
    }

    @Test func theRunPrintsTheValueItStored() async throws {
        try await withRun(arguments: ["create-api-key", "phone app"],
            seed: [SeedRow(username: "bob")]) { outcome, stored in
            #expect(!outcome.failed, "the run: \(outcome.output)")
            let token = try #require(stored.first?.token)
            #expect(outcome.output.contains(token),
                "the value printed is the value the row holds, which is what the user needs")
        }
    }

    @Test func aDescriptionThatFailsTheRuleEndsTheRunWritingNothing() async throws {
        try await withRun(arguments: ["create-api-key", ""], seed: [SeedRow(username: "bob")]) {
            outcome, stored in
            #expect(outcome.failed, "the run reports the rule it failed on")
            #expect(stored.isEmpty, "nothing is written for a description that fails the rule")
        }

        // The duplicate half: a description the account already has ends the run the same way, with
        // the row that was there still the only one.
        try await withRun(arguments: ["create-api-key", "phone app"],
            seed: [SeedRow(username: "bob", description: "phone app")]) { outcome, stored in
            #expect(outcome.failed, "the duplicate rule")
            #expect(stored.count == 1, "the seeded row is still the only one")
            #expect(stored.first?.token == "seed-token", "the run wrote nothing")
        }
    }

    @Test func theAccountIsTheOneTheRunResolves() async throws {
        // No name with several accounts is the port's rule, pinned by `FeedCommandTests`; what this
        // pin reads is which row the run wrote for the name it was given.
        try await withRun(arguments: ["create-api-key", "phone app", "--user", "carol"],
            seed: [SeedRow(username: "bob"), SeedRow(username: "carol")]) { outcome, stored in
            #expect(!outcome.failed, "the run: \(outcome.output)")
            #expect(stored.count == 1)
            #expect(stored.first?.userID == 2, "the account the run resolved")
        }

        // The single account when no name is given.
        try await withRun(arguments: ["create-api-key", "phone app"],
            seed: [SeedRow(username: "bob")]) { outcome, stored in
            #expect(!outcome.failed, "the run: \(outcome.output)")
            #expect(stored.first?.userID == 1)
        }
    }

    @Test func theMigrationFlagGatesThisCommand() async throws {
        // The flag on: the run builds the schema, so the pin reads the tables the run made rather
        // than a schema the test built.
        let migrated = try TemporaryDirectory()
        defer { migrated.remove() }
        _ = try await runCommand(databasePath: migrated.path("on.db"),
            arguments: ["create-api-key", "phone app"])
        let created = try await tables(at: migrated.path("on.db"))
        #expect(created.contains("api_keys"), "the flag on migrates: \(created)")

        // The flag off: the command creates no schema, so what the pin reads is the absence, on a
        // file the run itself opened. A patch that migrated whatever the flag said leaves
        // `api_keys` there.
        let unmigrated = try TemporaryDirectory()
        defer { unmigrated.remove() }
        _ = try await runCommand(databasePath: unmigrated.path("off.db"),
            arguments: ["create-api-key", "phone app"],
            environment: ["RUN_MIGRATIONS": "false"])
        let absent = try await tables(at: unmigrated.path("off.db"))
        #expect(!absent.contains("api_keys"), "the flag off does not migrate: \(absent)")
    }

    // MARK: - Setup

    private static let hexCharacters: Set<Character> = [
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f",
    ]

    private struct SeedRow: Sendable {
        let username: String
        let description: String?

        init(username: String, description: String? = nil) {
            self.username = username
            self.description = description
        }
    }

    private struct StoredKey: Sendable {
        let userID: Int
        let token: String
        let description: String
        let lastUseIsNull: Int
    }

    /// Seeds the rows, runs the command against the migrated file, and hands the pins the outcome
    /// read back after the run.
    ///
    /// The setup connection is not held across the run: the command builds its own application,
    /// which the single pooled connection of the test storage cannot serve from inside a checkout
    /// of its own.
    private func withRun(arguments: [String], seed: [SeedRow],
        _ body: (RunOutcome, [StoredKey]) async throws -> Void) async throws {
        try await withMigratedStorage { database, storage in
            try await storage.withConnection { connection in
                let sql = try sqlDatabase(connection)
                for row in seed {
                    let user = try await sql.raw("""
                        INSERT INTO users (username, password_hash, is_admin, created_at, updated_at)
                        VALUES (\(bind: row.username), \(bind: "seed-hash"), \(bind: 0),
                            \(bind: 1_000_000_000), \(bind: 1_000_000_000))
                        RETURNING id
                        """).first()
                    let userID = try #require(user).decode(column: "id", as: Int.self)
                    if let description = row.description {
                        try await sql.raw("""
                            INSERT INTO api_keys (user_id, token, description, created_at)
                            VALUES (\(bind: userID), \(bind: "seed-token"), \(bind: description),
                                \(bind: 1_000_000_000))
                            """).run()
                    }
                }
            }

            let outcome = try await runCommand(databasePath: database.path, arguments: arguments)
            let stored = try await storage.withConnection { connection in
                try await sqlDatabase(connection).raw("""
                    SELECT user_id, token, description, last_used_at IS NULL AS last_use_is_null
                    FROM api_keys ORDER BY id
                    """).all().map { row in
                    StoredKey(userID: try row.decode(column: "user_id", as: Int.self),
                        token: try row.decode(column: "token", as: String.self),
                        description: try row.decode(column: "description", as: String.self),
                        lastUseIsNull: try row.decode(column: "last_use_is_null", as: Int.self))
                }
            }
            try await body(outcome, stored)
        }
    }
}
