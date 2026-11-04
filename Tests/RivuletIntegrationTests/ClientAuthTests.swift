import Foundation
import Fluent
import FluentSQLiteDriver
import SQLKit
import Testing
@testable import RivuletCore

/// The storage reads the client-API auth path is built on: the Fever token lookup and the Google
/// Reader password read (`internal/storage/integration.go` at `c4d54f87`). What these pins can fail
/// on, each checked by patching the rule and reverting: the Fever lookup lowercases both sides,
/// which a patch that compares the stored value as read fails on the mixed-case row and a patch
/// that compares the input as read fails on the mixed-case input; the lookup reads the token
/// column, which a patch that read the name column for this rule answers on a different row; the
/// Google Reader read compares the name as read, unlike the account-name lookup, which a patch that
/// lowercases the input fails; and both reads answer nothing when no row matches. The pin that
/// reads a row with nothing stored is the divergent half: the reference's integration columns
/// default to an empty string, so its side of that rule has nothing to pin here. What these pins
/// cannot fail on: the reference's `*_enabled` flags, which this port has no column for, so the
/// branch those flags select has nothing to pin here; the single-row limit, which a lookup that
/// fetched every matching row answers the same way, so the code states it; the bcrypt compare,
/// which `BcryptHasherTests` pins, and which sits in the application layer because `RivuletCore`
/// must not depend on Vapor; the reference's wording for the Google read, which reports an error
/// for no row and for a stored value that is not a hash, where this port answers `nil`; the control
/// pin, which cannot tell "lowercase the input" from "lowercase both sides", because the reference
/// lowercases only the input for the account lookup; and `LOWER` on SQLite, which is ASCII-only
/// where the reference's Postgres `lower()` is Unicode-aware, so no fixture here can show that.
@Suite struct ClientAuthTests {
    @Test func theFeverLookupLowercasesBothSides() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let users = UserRepository(connection)
                let sql = try sqlDatabase(connection)

                // The stored side is mixed case, so a patch that compares it as read answers
                // nothing for the lowercase input.
                try await insert(sql, username: "alice", feverUsername: "FeverA",
                    feverToken: "71E9D7C8FD7D2B3DC94C3DE389826BD8")
                // The input side is mixed case, so a patch that lowercases only the column answers
                // nothing for this input.
                try await insert(sql, username: "bob", feverUsername: "FeverB",
                    feverToken: "ca3c9f9982d0ecbb019392085546ad93")

                let byStoredCase = try #require(try await users.userByFeverToken(
                    "71e9d7c8fd7d2b3dc94c3de389826bd8"), "the stored side is compared lowercase")
                #expect(byStoredCase.username == "alice",
                    "the row that holds that token: \(byStoredCase)")

                let byInputCase = try #require(try await users.userByFeverToken(
                    "CA3C9F9982D0ECBB019392085546AD93"), "the input is compared lowercase too")
                #expect(byInputCase.username == "bob",
                    "the row that holds that token: \(byInputCase)")
            }
        }
    }

    @Test func theFeverLookupReadsTheTokenColumn() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let users = UserRepository(connection)
                let sql = try sqlDatabase(connection)

                // One row holds the string in the name column, the other in the token column, so
                // the answer names which column this read looks at.
                try await insert(sql, username: "alice", feverUsername: "TOKENX", feverToken: "t1")
                try await insert(sql, username: "bob", feverUsername: "y", feverToken: "TOKENX")

                let found = try #require(try await users.userByFeverToken("TOKENX"),
                    "the token column is what this read compares")
                #expect(found.username == "bob", "the row that holds it as the token: \(found)")
            }
        }
    }

    @Test func theGoogleReaderReadComparesTheNameAsRead() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let users = UserRepository(connection)
                let sql = try sqlDatabase(connection)

                // The account name is stored lowercase, as the repository writes it, and the
                // integration name as the value was given.
                try await insert(sql, username: "grname", feverUsername: "F1", feverToken: "t",
                    googleReaderUsername: "GrName", googleReaderPasswordHash: "stored-hash")

                // The row is matched by the name as read, so a patch that lowercases the input
                // stops answering it.
                let asRead = try await users.googleReaderPasswordHash(username: "GrName")
                #expect(asRead == "stored-hash", "the row matched by the name as read: \(asRead)")

                // The control that names the difference between the two reads for one input: this
                // read compares the name as read, while the account-name lookup lowercases what it
                // is given.
                let nameRead = try await users.googleReaderPasswordHash(username: "GRNAME")
                #expect(nameRead == nil, "the input is not lowercased first: \(nameRead)")
                let accountRow = try await users.fetch(username: "GRNAME")
                #expect(accountRow != nil,
                    "the account-name lookup lowercases the same input: \(accountRow)")
            }
        }
    }

    @Test func theAuthReadsAnswerNothingWhenNoRowMatches() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let users = UserRepository(connection)
                let sql = try sqlDatabase(connection)
                try await insert(sql, username: "alice", feverUsername: "F1", feverToken: "t1",
                    googleReaderUsername: "Gr1", googleReaderPasswordHash: "h1")

                let noToken = try await users.userByFeverToken("no-token-stored")
                #expect(noToken == nil, "no row holds this token: \(noToken)")
                let noName = try await users.googleReaderPasswordHash(username: "Nobody")
                #expect(noName == nil, "no row holds this name: \(noName)")

                // A row that stores nothing is not a match either, which is where this port
                // diverges from the reference: its integration columns default to an empty string,
                // so an empty input matches there. Each assertion names one side of the stored
                // value.
                try await insert(sql, username: "carol", googleReaderUsername: "carol")
                let emptyToken = try await users.userByFeverToken("")
                #expect(emptyToken == nil,
                    "the stored token is NULL, not the empty value: \(emptyToken)")
                let noHash = try await users.googleReaderPasswordHash(username: "carol")
                #expect(noHash == nil, "the row is matched but stores no hash: \(noHash)")
            }
        }
    }

    // MARK: - Setup

    /// Seeds a row through SQL, so a stored value can be one this port would not write itself: the
    /// integration columns are written as they are given, and the account name is stored lowercase,
    /// as the repository writes it.
    private func insert(_ sql: any SQLDatabase, username: String, feverUsername: String? = nil,
        feverToken: String? = nil, googleReaderUsername: String? = nil,
        googleReaderPasswordHash: String? = nil) async throws {
        try await sql.raw("""
            INSERT INTO users (username, password_hash, is_admin, fever_username, fever_token,
                google_reader_username, google_reader_password_hash,
                created_at, updated_at)
            VALUES (\(bind: username.lowercased()), \(bind: "seed-hash"), \(bind: 0),
                \(bind: feverUsername), \(bind: feverToken),
                \(bind: googleReaderUsername), \(bind: googleReaderPasswordHash),
                \(bind: 1_000_000_000), \(bind: 1_000_000_000))
            """).run()
    }
}
