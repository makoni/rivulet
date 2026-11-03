import ConsoleKit
import Foundation
import SQLKit
import Testing
import RivuletApp
@testable import RivuletCore

/// `rivulet create-admin` (`internal/cli/create_admin.go` at commit `c4d54f87`): read the name and
/// the password from the console, skip when the name already has a row, otherwise write the admin
/// row with the "All" category the storage layer creates with it, and report what it wrote. The
/// rules themselves are pinned by `UserValidationTests`, the hash by `BcryptHasherTests`, and the
/// lowercase write and the default category by `UserRepositoryTests`; these pins are the command —
/// the order its own reads happen in, which path each input takes, and what ends up in the
/// database.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the row is written
/// as the command read it — the name in the form the storage layer writes it, the admin flag the
/// command sets, the stored value is the hash of the password read and not the plaintext — which a
/// patch that stores the input text as the hash, or passes the admin flag as false, or skips the
/// normalization, fails; the skip runs before the rules, which a patch that validates first fails,
/// because the pin seeds a name the character class rejects and only the skip path ends that run
/// without a failure; the existence read finds the stored name whatever case the input has, which a
/// patch that compares the input as read fails; a rule failure writes nothing, which a patch that
/// writes the row before checking the rules fails; the password is read as the secure input and the
/// name as the plain one, which a patch that reads both plainly fails, because the console records
/// the flag of each read; the input is trimmed before it is used, which a patch that skips the trim
/// fails on the name stored and on the password hashed; and the migration flag gates this command,
/// which a patch that migrates regardless of it fails.
///
/// What they cannot fail on: the wording of what the command prints, which is the port's own — the
/// reference's locale strings are not ported, so a failing run is read as a failure and an empty
/// database, and which rule a failing input fails on is pinned by `UserValidationTests`; which of
/// the two reports the command writes (the skip line or the created line), since both pins read the
/// outcome and the name carried on the line rather than the sentence; the prompts themselves; the
/// interactive-terminal check the reference makes before reading (`term.IsTerminal`), which this
/// port does not have because it reads through the console seam and a captured console has no
/// terminal to test; the environment path the reference's `create-admin` also has
/// (`ADMIN_USERNAME`, `ADMIN_PASSWORD` with `CREATE_ADMIN`), which belongs to the daemon branch and
/// arrives with `serve`; and the bcrypt cost, which `BcryptHasherTests` pins. Nothing here sleeps
/// or polls.
@Suite struct CreateAdminTests {
    init() {
        TestLogging.bootstrapOnce()
    }

    // MARK: - Pins

    @Test func theRowIsWrittenAsTheCommandReadIt() async throws {
        try await withRun(username: " Alice ", password: " secret ") { outcome in
            #expect(!outcome.failed, "the run: \(outcome.output)")
            let user = try #require(outcome.users.first, "the row the command wrote")
            #expect(user.username == "alice", "the name as the storage layer writes it: \(user)")
            #expect(user.isAdmin, "the admin flag the command sets: \(user)")
            #expect(user.passwordHash != "secret", "the stored value is the hash: \(user)")
            #expect(try BcryptHasher().verify("secret", hash: user.passwordHash),
                "the stored hash is the hash of the password the command read: \(user)")
            // Both sides of the trim: the value hashed is the trimmed input, not the line as read.
            #expect(!(try BcryptHasher().verify(" secret ", hash: user.passwordHash)),
                "the trimmed password is what was hashed: \(user)")
            #expect(outcome.categories == [StoredCategory(userID: user.id, title: "All")],
                "the default category written with the row: \(outcome.categories)")

            // The report carries the name as it was stored, not the text it read. The words around
            // it are the port's own, so this is the part of the report a pin can read.
            #expect(outcome.output.contains("alice") && !outcome.output.contains("Alice"),
                "the run reports the name it stored: \(outcome.output)")
        }
    }

    @Test func thePasswordIsReadThroughTheSecureInputAndTheNameThroughThePlainOne() async throws {
        try await withRun(username: "alice", password: "secret") { outcome in
            #expect(!outcome.failed, "the run: \(outcome.output)")
            #expect(outcome.secureReads == [false, true],
                "the flag of each read, in the order the command made them: \(outcome.secureReads)")
        }
    }

    @Test func anExistingUserIsSkippedBeforeTheRulesAreApplied() async throws {
        // A name the character class would reject, put in the database through SQL so that it is a
        // stored row. Only the skip path can end this run without a failure, so the run completing
        // is what shows the existence read comes before the rules; a patch that validates first
        // turns this pin's run into a failure.
        try await withRun(username: "bad name", password: "secret", seedUsername: "bad name") { outcome in
            #expect(!outcome.failed, "the skip path, not a rule failure: \(outcome.output)")
            #expect(outcome.users.count == 1, "nothing was written: \(outcome.users)")
            let user = try #require(outcome.users.first)
            #expect(user.passwordHash == "seed-hash", "the stored row was not rewritten: \(user)")
            #expect(!user.isAdmin, "the stored row was not changed: \(user)")
            #expect(outcome.output.contains("bad name"),
                "the run reports the name it skipped: \(outcome.output)")
        }
    }

    @Test func theExistenceReadFindsTheStoredNameWhateverCaseTheInputHas() async throws {
        try await withRun(username: "ALICE", password: "secret", seedUsername: "alice") { outcome in
            #expect(!outcome.failed, "the stored name is found: \(outcome.output)")
            #expect(outcome.users.count == 1,
                "the run skipped rather than writing a second row: \(outcome.users)")
        }
    }

    @Test func eachRuleFailureWritesNothing() async throws {
        // Each input fails one rule. The control case at the end, which fails none and writes, is
        // what keeps these pins from being satisfied by a command that writes nothing at all.
        let failures: [(username: String, password: String)] = [
            ("", "secret"),          // the mandatory rule
            ("bad name", "secret"),  // the character class
            ("alice", "short"),      // the length rule
        ]
        for input in failures {
            try await withRun(username: input.username, password: input.password) { outcome in
                #expect(outcome.failed,
                    "a run that fails a rule must report the failure: \(outcome.output)")
                #expect(outcome.users.isEmpty, "no row for \(input.username): \(outcome.users)")
                #expect(outcome.categories.isEmpty,
                    "no category for a user that was never written: \(outcome.categories)")
            }
        }

        try await withRun(username: "carol", password: "secret") { outcome in
            #expect(!outcome.failed, "the control run: \(outcome.output)")
            #expect(outcome.users.count == 1, "the control writes the row: \(outcome.users)")
            #expect(outcome.categories.count == 1, "the control writes the category: \(outcome.categories)")
        }
    }

    @Test func theMigrationFlagGatesThisCommand() async throws {
        // The flag on: the command builds the schema and writes through it.
        let migrated = try TemporaryDirectory()
        defer { migrated.remove() }
        let on = TestConsole()
        on.pushInput("alice")
        on.pushInput("secret")
        try await RivuletCLI.run(console: on, environment: ["DATABASE_URL": migrated.path("on.db")],
            arguments: ["rivulet", "create-admin"])
        let created = try await tables(at: migrated.path("on.db"))
        #expect(created.contains("users"), "the flag on migrates: \(created)")

        // The flag off: the command does not create the schema, so it has no table to write to and
        // fails rather than writing nothing.
        let unmigrated = try TemporaryDirectory()
        defer { unmigrated.remove() }
        let off = TestConsole()
        off.pushInput("alice")
        off.pushInput("secret")
        var failed = false
        do {
            try await RivuletCLI.run(console: off,
                environment: ["DATABASE_URL": unmigrated.path("off.db"), "RUN_MIGRATIONS": "false"],
                arguments: ["rivulet", "create-admin"])
            Issue.record("a command that does not migrate must fail on a fresh database")
        } catch {
            // The pin reads that the run failed, not the words of the error, which are the port's
            // own.
            failed = true
        }
        #expect(failed, "the flag off leaves the command no schema to write to")
        let absent = try await tables(at: unmigrated.path("off.db"))
        #expect(!absent.contains("users"), "the flag off does not migrate: \(absent)")
    }

    // MARK: - Setup

    private struct StoredUser: Sendable {
        let id: Int
        let username: String
        let passwordHash: String
        let isAdmin: Bool
    }

    private struct StoredCategory: Sendable, Equatable {
        let userID: Int
        let title: String
    }

    /// What a run left behind: the console output, whether the run failed, the flag of each input
    /// read, and the rows the file holds afterwards.
    private struct RunOutcome: Sendable {
        let output: String
        let failed: Bool
        let secureReads: [Bool]
        let users: [StoredUser]
        let categories: [StoredCategory]
    }

    /// Seeds `seedUsername` through SQL — so a name the rules would reject can be a stored row,
    /// which the skip pin needs — runs `rivulet create-admin` with the inputs the pin names against
    /// the migrated file, and hands the pins the outcome read back after the run.
    ///
    /// The setup connection is not held across the run: the command builds its own application,
    /// which the single pooled connection of the test storage cannot serve from inside a checkout
    /// of its own.
    private func withRun(username: String, password: String, seedUsername: String? = nil,
        environment: [String: String] = [:],
        _ body: (RunOutcome) async throws -> Void) async throws {
        try await withMigratedStorage { database, storage in
            if let seedUsername {
                try await storage.withConnection { connection in
                    try await sqlDatabase(connection).raw("""
                        INSERT INTO users (username, password_hash, is_admin, created_at, updated_at)
                        VALUES (\(bind: seedUsername), \(bind: "seed-hash"), \(bind: 0),
                            \(bind: 1_000_000_000), \(bind: 1_000_000_000))
                        """).run()
                }
            }

            let console = TestConsole()
            console.pushInput(username)
            console.pushInput(password)
            var values = environment
            values["DATABASE_URL"] = database.path
            var failed = false
            do {
                try await RivuletCLI.run(console: console, environment: values,
                    arguments: ["rivulet", "create-admin"])
            } catch {
                failed = true
            }

            let rows = try await storage.withConnection { connection in
                let sql = try sqlDatabase(connection)
                let users = try await sql.raw("""
                    SELECT id, username, password_hash, is_admin FROM users ORDER BY id
                    """).all().map {
                    try StoredUser(id: $0.decode(column: "id", as: Int.self),
                        username: $0.decode(column: "username", as: String.self),
                        passwordHash: $0.decode(column: "password_hash", as: String.self),
                        isAdmin: $0.decode(column: "is_admin", as: Int.self) == 1)
                }
                let categories = try await sql.raw("""
                    SELECT user_id, title FROM categories ORDER BY id
                    """).all().map {
                    try StoredCategory(userID: $0.decode(column: "user_id", as: Int.self),
                        title: $0.decode(column: "title", as: String.self))
                }
                return (users: users, categories: categories)
            }
            try await body(RunOutcome(output: console.output, failed: failed,
                secureReads: console.secureReads, users: rows.users, categories: rows.categories))
        }
    }
}
