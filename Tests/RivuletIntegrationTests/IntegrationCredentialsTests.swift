import ConsoleKit
import Foundation
import SQLKit
import Testing
import RivuletApp
@testable import RivuletCore

/// `rivulet integration-credentials`: read the account name and the two credential pairs from the
/// console, check each name against the other users, write what the run derived, and print the
/// Fever `api_key`. The reference has this path only as its web form
/// (`internal/ui/integration_update.go` at `c4d54f87`), so the console prompts are the port's own;
/// what is ported is what that handler does with the values it is given.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the stored Fever
/// value is the digest of the pair the command read, which a patch that stores the password itself
/// fails; the stored Google Reader value is the hash of the password read and not the plaintext,
/// which a patch that stores the plaintext fails; the names are stored as read, which a patch that
/// lowercases them before writing fails — the reference writes `fever_username=$9` as submitted;
/// the input is trimmed before it is used, which a patch that skips the trim fails on the stored
/// name and on the value derived from it; a read that comes back empty keeps what the row already
/// holds, which a patch that writes the empty read fails; the rule order, read here as the answer
/// of the rule function pinned by `IntegrationValidationTests`, ends the run before anything is
/// written, which a patch that writes first fails; the run prints the value it stored, which a
/// patch that prints the password instead fails; the passwords are read as the secure input and the
/// names as the plain one, which a patch that reads everything plainly fails, because the console
/// records the flag of each read; the account must have a row, which a patch that creates one
/// fails; and the migration flag gates this command, which a patch that migrates regardless of it
/// fails — that pin reads the schema each run leaves behind, because the run itself ends at the
/// account read.
///
/// What they cannot fail on: the wording of what the command prints, which is the port's own — the
/// reference has no CLI path here, so a failing run is read as a failure and an unchanged row, and
/// the pins read the stored values and the value printed rather than the sentences; the order of
/// the prompts, which is the port's own; the per-user exclusion and the column each duplicate check
/// reads, which are the storage layer's rules and are pinned by `UserRepositoryTests`; the
/// reference's stored Fever password, which this port has no column for, so the pair is stored as
/// the digest alone; and the unique index on `fever_token`, which no patch can reach because the
/// rule is the schema, so it is stated in the schema comment and in `docs/parity.md`.
@Suite struct IntegrationCredentialsTests {
    init() {
        TestLogging.bootstrapOnce()
    }

    // MARK: - Pins

    @Test func theRowIsWrittenAsTheCommandDerivedIt() async throws {
        try await withRun(inputs: ["bob", "Fever1", "secret", "Gr1", "secret"],
            seed: [seedRow(username: "bob")]) { outcome in
            #expect(!outcome.failed, "the run: \(outcome.output)")
            let user = try #require(outcome.user(named: "bob"), "the row the command wrote")

            // The names as submitted, which is what the reference writes: unlike the account name,
            // an integration name is not stored lowercase.
            #expect(user.feverUsername == "Fever1", "the name as read: \(user)")
            #expect(user.googleReaderUsername == "Gr1", "the name as read: \(user)")

            // The Fever value is the digest of the pair, not the password the command read. The
            // golden is the reference's output for `Fever1:secret`.
            #expect(user.feverToken == "71e9d7c8fd7d2b3dc94c3de389826bd8",
                "the reference's value for the same pair: \(user)")
            #expect(user.feverToken != "secret", "the stored value is not the password: \(user)")

            // The Google Reader value is the hash of the password read.
            #expect(user.googleReaderPasswordHash != "secret", "the stored value is the hash: \(user)")
            #expect(try BcryptHasher().verify("secret",
                hash: try #require(user.googleReaderPasswordHash)),
                "the stored hash is the hash of the password the command read: \(user)")
        }
    }

    @Test func theInputIsTrimmedBeforeItIsUsed() async throws {
        try await withRun(inputs: ["bob", " Fever1 ", " secret ", " Gr1 ", " secret "],
            seed: [seedRow(username: "bob")]) { outcome in
            #expect(!outcome.failed, "the run: \(outcome.output)")
            let user = try #require(outcome.user(named: "bob"))
            #expect(user.feverUsername == "Fever1", "the name trimmed: \(user)")

            // Both sides of the trim: the value derived is from the trimmed pair, not from the
            // lines as read.
            #expect(user.feverToken == "71e9d7c8fd7d2b3dc94c3de389826bd8",
                "the digest of the trimmed pair: \(user)")
            #expect(try BcryptHasher().verify("secret",
                hash: try #require(user.googleReaderPasswordHash)),
                "the trimmed password is what was hashed: \(user)")
            #expect(!(try BcryptHasher().verify(" secret ",
                hash: try #require(user.googleReaderPasswordHash))),
                "the untrimmed password is not what was hashed: \(user)")
        }
    }

    @Test func anEmptyReadKeepsWhatTheRowAlreadyHolds() async throws {
        // Every read blank: the row is left as it was, which is the reference keeping the stored
        // value for a form field submitted blank. A patch that wrote the blank read would clear it.
        try await withRun(inputs: ["bob", "", "", "", ""], seed: [seedRow(
            username: "bob", feverUsername: "Fever1", feverToken: "71e9d7c8fd7d2b3dc94c3de389826bd8",
            googleReaderUsername: "Gr1", googleReaderPasswordHash: "stored-hash")]) { outcome in
            #expect(!outcome.failed, "the run: \(outcome.output)")
            let user = try #require(outcome.user(named: "bob"))
            #expect(user.feverUsername == "Fever1", "the stored name was not cleared: \(user)")
            #expect(user.feverToken == "71e9d7c8fd7d2b3dc94c3de389826bd8",
                "the stored value was not re-derived: \(user)")
            #expect(user.googleReaderUsername == "Gr1", "the stored name was not cleared: \(user)")
            #expect(user.googleReaderPasswordHash == "stored-hash",
                "the stored hash was not replaced: \(user)")
        }

        // One side supplied, the other read blank: the supplied one is written, the blank one
          // stays.
        try await withRun(inputs: ["bob", "Fever1", "newpass", "", ""], seed: [seedRow(
            username: "bob", feverUsername: "old", feverToken: "db76921119a86d54eaef38f9ffee7184",
            googleReaderUsername: "Gr1", googleReaderPasswordHash: "stored-hash")]) { outcome in
            #expect(!outcome.failed, "the run: \(outcome.output)")
            let user = try #require(outcome.user(named: "bob"))
            #expect(user.feverToken == "f6f824c34b91bfd788bd989a89a1981b",
                "the digest of the pair supplied, the name being the one read: \(user)")
            #expect(user.googleReaderPasswordHash == "stored-hash",
                "the blank read left the stored hash: \(user)")
        }
    }

    @Test func thePasswordsAreReadAsSecureInputAndTheNamesAsPlainInput() async throws {
        try await withRun(inputs: ["bob", "Fever1", "secret", "Gr1", "secret"],
            seed: [seedRow(username: "bob")]) { outcome in
            #expect(!outcome.failed, "the run: \(outcome.output)")
            #expect(outcome.secureReads == [false, false, true, false, true],
                "the flag of each read, in the order the command made them: \(outcome.secureReads)")
        }
    }

    @Test func aNameAnotherUserHoldsEndsTheRunAndWritesNothing() async throws {
        let other = seedRow(username: "carol", feverUsername: "Fever1", feverToken: "other-token",
            googleReaderUsername: "Gr1", googleReaderPasswordHash: "other-hash")

        // Only the Fever column holds the name, so the Fever check is the one that answers here: a
        // patch that read the Google Reader column for this rule would let the run through.
        try await withRun(inputs: ["bob", "Fever1", "secret", "other", "secret"],
            seed: [seedRow(username: "bob"), other]) { outcome in
            #expect(outcome.failed, "a name another user holds must end the run: \(outcome.output)")
            let user = try #require(outcome.user(named: "bob"))
            #expect(user.feverToken == nil, "nothing was written: \(user)")
        }

        // Only the Google Reader column holds the name, for the other rule.
        try await withRun(inputs: ["bob", "other", "secret", "Gr1", "secret"],
            seed: [seedRow(username: "bob"), other]) { outcome in
            #expect(outcome.failed, "a name another user holds must end the run: \(outcome.output)")
            let user = try #require(outcome.user(named: "bob"))
            #expect(user.googleReaderPasswordHash == nil, "nothing was written: \(user)")
        }
    }

    @Test func theRunPrintsTheValueItStored() async throws {
        try await withRun(inputs: ["bob", "Fever1", "secret", "Gr1", "secret"],
            seed: [seedRow(username: "bob")]) { outcome in
            #expect(!outcome.failed, "the run: \(outcome.output)")
            let user = try #require(outcome.user(named: "bob"))
            #expect(outcome.output.contains("71e9d7c8fd7d2b3dc94c3de389826bd8"),
                "the printed key is the value the row holds: \(outcome.output)")
            #expect(outcome.output.contains(try #require(user.feverToken)),
                "the printed value and the stored one are the same: \(outcome.output)")
            #expect(!outcome.output.contains("secret"),
                "the printed line carries the digest, not the password: \(outcome.output)")
        }
    }

    @Test func anAccountWithoutARowEndsTheRun() async throws {
        try await withRun(inputs: ["nobody", "Fever1", "secret", "Gr1", "secret"]) { outcome in
            #expect(outcome.failed, "the port must find the account it writes to: \(outcome.output)")
            #expect(outcome.users.isEmpty, "no row was created: \(outcome.users)")
        }
    }

    @Test func theMigrationFlagGatesThisCommand() async throws {
        // What this pin reads is the schema each run leaves behind, not what a run wrote: the
        // account the command reads has no row here, so both runs end at the account read. With the
        // flag on the command still builds the schema, and with the flag off it does not.
        let migrated = try TemporaryDirectory()
        defer { migrated.remove() }
        let on = TestConsole()
        for line in ["bob", "Fever1", "secret", "Gr1", "secret"] { on.pushInput(line) }
        do {
            try await RivuletCLI.run(console: on, environment: ["DATABASE_URL": migrated.path("on.db")],
                arguments: ["rivulet", "integration-credentials"])
        } catch {
            // The run ends at the account read; the pin reads the tables, not this error.
        }
        let created = try await tables(at: migrated.path("on.db"))
        #expect(created.contains("users"), "the flag on migrates: \(created)")

        let unmigrated = try TemporaryDirectory()
        defer { unmigrated.remove() }
        let off = TestConsole()
        for line in ["bob", "Fever1", "secret", "Gr1", "secret"] { off.pushInput(line) }
        do {
            try await RivuletCLI.run(console: off,
                environment: ["DATABASE_URL": unmigrated.path("off.db"), "RUN_MIGRATIONS": "false"],
                arguments: ["rivulet", "integration-credentials"])
        } catch {
            // The same account read, on a file with no schema: the run ends here too, and the pin
            // reads the tables.
        }
        let absent = try await tables(at: unmigrated.path("off.db"))
        #expect(!absent.contains("users"), "the flag off does not migrate: \(absent)")
    }

    // MARK: - Setup

    private struct SeedRow: Sendable {
        let username: String
        let feverUsername: String?
        let feverToken: String?
        let googleReaderUsername: String?
        let googleReaderPasswordHash: String?
    }

    /// A row put in the database through SQL, so a name the port would not write itself can be a
    /// stored row, which is what the pins for the duplicate checks need. A row seeded through the
    /// repository stores the name lowercase, which would hide the rule these pins read.
    private func seedRow(username: String, feverUsername: String? = nil, feverToken: String? = nil,
        googleReaderUsername: String? = nil,
        googleReaderPasswordHash: String? = nil) -> SeedRow {
        SeedRow(username: username, feverUsername: feverUsername, feverToken: feverToken,
            googleReaderUsername: googleReaderUsername,
            googleReaderPasswordHash: googleReaderPasswordHash)
    }

    private struct StoredUser: Sendable {
        let username: String
        let feverUsername: String?
        let feverToken: String?
        let googleReaderUsername: String?
        let googleReaderPasswordHash: String?
    }

    private struct RunOutcome: Sendable {
        let output: String
        let failed: Bool
        let secureReads: [Bool]
        let users: [StoredUser]

        func user(named username: String) -> StoredUser? {
            users.first { $0.username == username }
        }
    }

    /// Seeds the rows, runs `rivulet integration-credentials` with the five inputs the pin names
    /// against the migrated file, and hands the pins the outcome read back after the run.
    ///
    /// The setup connection is not held across the run: the command builds its own application,
    /// which the single pooled connection of the test storage cannot serve from inside a checkout
    /// of its own.
    private func withRun(inputs: [String], seed: [SeedRow] = [],
        _ body: (RunOutcome) async throws -> Void) async throws {
        try await withMigratedStorage { database, storage in
            try await storage.withConnection { connection in
                let sql = try sqlDatabase(connection)
                for row in seed {
                    try await sql.raw("""
                        INSERT INTO users (username, password_hash, is_admin, fever_username,
                            fever_token, google_reader_username, google_reader_password_hash,
                            created_at, updated_at)
                        VALUES (\(bind: row.username), \(bind: "seed-hash"), \(bind: 0),
                            \(bind: row.feverUsername), \(bind: row.feverToken),
                            \(bind: row.googleReaderUsername),
                            \(bind: row.googleReaderPasswordHash), \(bind: 1_000_000_000),
                            \(bind: 1_000_000_000))
                        """).run()
                }
            }

            let console = TestConsole()
            for input in inputs { console.pushInput(input) }
            var failed = false
            do {
                try await RivuletCLI.run(console: console,
                    environment: ["DATABASE_URL": database.path],
                    arguments: ["rivulet", "integration-credentials"])
            } catch {
                failed = true
            }

            let users = try await storage.withConnection { connection in
                try await sqlDatabase(connection).raw("""
                    SELECT username, fever_username, fever_token, google_reader_username,
                        google_reader_password_hash
                    FROM users ORDER BY id
                    """).all().map { row in
                    try StoredUser(username: row.decode(column: "username", as: String.self),
                        feverUsername: nullable(row, "fever_username"),
                        feverToken: nullable(row, "fever_token"),
                        googleReaderUsername: nullable(row, "google_reader_username"),
                        googleReaderPasswordHash: nullable(row, "google_reader_password_hash"))
                }
            }
            try await body(RunOutcome(output: console.output, failed: failed,
                secureReads: console.secureReads, users: users))
        }
    }

    /// A column that can hold `NULL`, which the pins read as "nothing stored there" rather than as
    /// an empty string.
    private func nullable(_ row: some SQLRow, _ column: String) throws -> String? {
        try row.decodeNil(column: column) ? nil : row.decode(column: column, as: String.self)
    }
}
