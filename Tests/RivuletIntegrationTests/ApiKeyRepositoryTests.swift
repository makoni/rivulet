import FluentKit
import Foundation
import SQLKit
import Testing
@testable import RivuletCore

/// The storage reads the api-key path is built on: `ApiKeyExists`, `CreateAPIKey` and
/// `UserByAPIKey`, ported from Miniflux `internal/storage/api_key.go` and
/// `internal/storage/user.go` at commit `c4d54f87` (Apache-2.0), pinned against a real SQLite file.
///
/// What these pins can fail on, each checked by patching the rule and reverting: which account the
/// key read answers, which a patch that answered the first account for any token fails on; that the
/// key read compares the token as read, which a patch that lowercased the value it was given fails
/// on, and that it looks at the token column, which a patch that read the description column fails
/// on; that the duplicate read lowercases both sides — the pin has one input for each side, so the
/// patch that dropped the stored side fires only the stored-side line and the one that dropped the
/// given side fires only the given-side line — that it is per user, which a patch that counted a
/// row of another user fails on, and that it looks at the description column, which a patch that
/// read the token column fails on; that `create` writes the description as it is given, which a
/// patch that lowercased it before writing fails on, writes nothing for the last use, which a patch
/// that stamped the write instant fails on, and writes the token the caller gave it, which a patch
/// that wrote a fixed value fails on.
///
/// Five patches reach more than one pin, because pins share a read or a write: the patch for the
/// key read's column fires the three pins that read that read plus `RestV1AuthTests`' pin for the
/// request that reaches the key half, whose token matches no row once the read looks at the other
/// column; the patch that drops the match condition fires the pins that read which account the read
/// answers and which column the compare uses; the write patches for the description and for the
/// last use fire `CreateApiKeyTests`' row pin too, because the command writes through the same
/// rule; and the fixed-token patch fires this suite's pin for no key row as well, because that
/// pin's control row is written through the create, while it cannot fire the command's row pin,
/// which reads the value the run printed against the row the run wrote.
/// What they cannot fail on: the join as a join, which this schema makes the same answer — `ON
/// DELETE CASCADE` with foreign keys enforced, so the patch that read `api_keys.user_id` instead
/// answers the same account, and the pin is falsifiable only on which account the read answers; the
/// pin for no key row, whose line reads the absence before its control row is written, so the patch
/// that drops the match condition has no row there to answer and fires only the control line
/// through the patches named above; the single-row limit of the read, which no patch can tell from
/// a read that fetched every match; the order two keys of one account answer, which SQL does not
/// fix; the clock fields, read as the shape they hold; and the `timestamp with time zone` type,
/// which this port writes as Unix seconds.
///
@Suite struct ApiKeyRepositoryTests {
    @Test func theKeyReadAnswersTheAccountTheKeyBelongsTo() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let keys = ApiKeyRepository(connection)
                let alice = try await UserRepository(connection).create(username: "alice",
                    passwordHash: "seed-hash", isAdmin: true)
                let bob = try await UserRepository(connection).create(username: "bob",
                    passwordHash: "seed-hash", isAdmin: false)
                let aliceID = try alice.requireID()
                let bobID = try bob.requireID()

                // Two accounts with a key each, so the row the read answers is the one the token
                // belongs to, which is what this pin can fail on: a patch that answered the first
                // account for any token reads alice's row here.
                try await insertKey(connection, userID: aliceID, token: "token-for-alice",
                    description: "phone app")
                try await insertKey(connection, userID: bobID, token: "token-for-bob",
                    description: "phone app")

                let found = try await keys.userByAPIKey("token-for-bob")
                #expect(found?.id == bobID, "the account the token belongs to")
                #expect(found?.username == "bob", "the row that account is")
            }
        }
    }

    @Test func theKeyReadComparesTheTokenAsReadAndLooksAtTheTokenColumn() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let keys = ApiKeyRepository(connection)
                let alice = try await UserRepository(connection).create(username: "alice",
                    passwordHash: "seed-hash", isAdmin: true)
                let aliceID = try alice.requireID()

                // The reference compares `api_keys.token = $1` with no `LOWER`, which is the rule
                // this line names, and the control is the same value read as it was stored.
                try await insertKey(connection, userID: aliceID, token: "MixedCase",
                    description: "MixedCase")
                #expect(try await keys.userByAPIKey("MixedCase")?.id == aliceID)
                #expect(try await keys.userByAPIKey("mixedcase") == nil, "the value is read as given")

                // The input is a value one row holds in its description and not in its token, so
                // the column the read looks at is what this line can fail on.
                try await insertKey(connection, userID: aliceID, token: "key-of-alice",
                    description: "token-a")
                #expect(try await keys.userByAPIKey("token-a") == nil,
                    "the read looks at the token column")
            }
        }
    }

    @Test func theKeyReadAnswersNothingForNoKeyRow() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let keys = ApiKeyRepository(connection)
                let alice = try await UserRepository(connection).create(username: "alice",
                    passwordHash: "seed-hash", isAdmin: true)

                #expect(try await keys.userByAPIKey("no-such-token") == nil, "no row matches")

                // The control: the same read answers when a row does match, so the line above reads
                // the absence of a match rather than a read that answers nothing whatever it is
                // given.
                _ = try await keys.create(userID: try alice.requireID(), token: "token-a",
                    description: "phone app")
                #expect(try await keys.userByAPIKey("token-a")?.id == alice.id,
                    "the control, a row that matches answers the row")
            }
        }
    }

    @Test func theDuplicateReadLowercasesBothSidesAndIsPerUser() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let keys = ApiKeyRepository(connection)
                let alice = try await UserRepository(connection).create(username: "alice",
                    passwordHash: "seed-hash", isAdmin: true)
                let bob = try await UserRepository(connection).create(username: "bob",
                    passwordHash: "seed-hash", isAdmin: false)
                let aliceID = try alice.requireID()
                let bobID = try bob.requireID()

                // One row per half, so each half is read on its own input: the two match halves put
                // the value in both columns, and the column half has a row whose token holds a
                // value the read is not given.
                try await insertKey(connection, userID: aliceID, token: "Reader",
                    description: "Reader")
                #expect(try await keys.apiKeyExists(userID: aliceID, description: "reader"),
                    "the stored side read as lowercase")

                try await insertKey(connection, userID: aliceID, token: "reader",
                    description: "reader")
                #expect(try await keys.apiKeyExists(userID: aliceID, description: "READER"),
                    "the value it is given read as lowercase")

                // The account half: bob has no row, so the answer is the absence, read against
                // alice's.
                #expect(!(try await keys.apiKeyExists(userID: bobID, description: "reader")),
                    "the check is for the account it is given")

                try await insertKey(connection, userID: aliceID, token: "key-of-alice",
                    description: "phone app")
                #expect(!(try await keys.apiKeyExists(userID: aliceID, description: "key-of-alice")),
                    "the read looks at the description column")
            }
        }
    }

    @Test func createWritesTheFieldsAsTheCallerGaveThem() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let keys = ApiKeyRepository(connection)
                let alice = try await UserRepository(connection).create(username: "alice",
                    passwordHash: "seed-hash", isAdmin: true)
                let aliceID = try alice.requireID()
                _ = try await keys.create(userID: aliceID, token: "MixedCase",
                    description: "Phone App")

                // Read back through SQL: the assertions prove the stored row, not the in-memory
                // object.
                let row = try await storedKey(connection, userID: aliceID)
                #expect(row?.description == "Phone App", "written as given, not lowercased")
                #expect(row?.token == "MixedCase")
                #expect(row?.lastUseIsNull == 1, "the write stamps nothing for the last use")
            }
        }
    }

    // MARK: - Setup

    private struct StoredKey: Sendable {
        let token: String
        let description: String
        let lastUseIsNull: Int
    }

    /// A key row put in through SQL, so a value the port would not write itself can be a stored
    /// row: a row seeded through the repository writes what it is given, so the case rules the pins
    /// read would not show.
    private func insertKey(_ connection: any Database, userID: Int, token: String,
        description: String) async throws {
        try await sqlDatabase(connection).raw("""
            INSERT INTO api_keys (user_id, token, description, created_at)
            VALUES (\(bind: userID), \(bind: token), \(bind: description), \(bind: 1_000_000_000))
            """).run()
    }

    private func storedKey(_ connection: any Database, userID: Int) async throws -> StoredKey? {
        let row = try await sqlDatabase(connection).raw("""
            SELECT token, description, last_used_at IS NULL AS last_use_is_null
            FROM api_keys WHERE user_id = \(bind: userID)
            """).first()
        guard let row else { return nil }
        return StoredKey(token: try row.decode(column: "token", as: String.self),
            description: try row.decode(column: "description", as: String.self),
            lastUseIsNull: try row.decode(column: "last_use_is_null", as: Int.self))
    }
}
