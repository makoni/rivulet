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
/// lowercases the input fails; and both reads answer nothing when no row matches. What they cannot
/// fail on: the reference's `*_enabled` flags, which this port has no column for, so the branch
/// those flags select has nothing to pin here; the single-row limit of these reads, which a lookup
/// that fetched every matching row answers the same way, so the code states it; the bcrypt compare,
/// which `BcryptHasherTests` pins, and which sits in the application layer because `RivuletCore`
/// must not depend on Vapor; and the reference's two failure wordings, which this port answers with
/// `nil` for "no row". The pin for the empty input covers a row that has nothing stored, where a
/// patch that read an empty stored value as a match would answer that row. The control that shows
/// the name read against the account lookup fails on a patch that made the account lookup
/// case-sensitive.
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

                // The account name is stored lowercase and the integration name as read, so the two
                // reads answer differently for the same mixed-case input.
                try await insert(sql, username: "grname", feverUsername: "F1", feverToken: "t",
                    googleReaderUsername: "GrName", googleReaderPasswordHash: "stored-hash")

                let asRead = try await users.googleReaderPasswordHash(username: "GrName")
                #expect(asRead == "stored-hash", "the value as read: \(asRead)")
                let lowercased = try await users.googleReaderPasswordHash(username: "grname")
                #expect(lowercased == nil, "the input is not lowercased first: \(lowercased)")

                // The control that names the difference: this read compares the name as read, while
                // the account-name lookup lowercases what it is given.
                let accountRow = try await users.fetch(username: "GRNAME")
                #expect(accountRow != nil,
                    "the account-name lookup is case-insensitive: \(accountRow)")
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

                // A row with nothing stored is not a match for an empty input either, which a patch
                // that read an empty stored value as a match fails on.
                try await insert(sql, username: "carol")
                let emptyToken = try await users.userByFeverToken("")
                #expect(emptyToken == nil, "the stored value is NULL, not empty: \(emptyToken)")
                let noHash = try await users.googleReaderPasswordHash(username: "carol")
                #expect(noHash == nil, "the row has no stored hash: \(noHash)")
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
