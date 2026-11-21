import FluentKit
import Foundation
import SQLKit
import Testing
@testable import RivuletApp
@testable import RivuletCore

/// The two halves of the read every request of this path runs through before it reaches a route:
/// `validateAPIKeyAuth` and `validateBasicAuth` from `internal/api/middleware.go` at commit
/// `c4d54f87` (Apache-2.0), pinned as the decision each half answers. The storage read the token
/// half runs is pinned by `ApiKeyRepositoryTests`, the name lookup by `UserRepositoryTests`, and
/// the header block by `RestV1HeadersTests`; what the transport writes for these answers — the
/// status each one gets, the JSON error document, and the `WWW-Authenticate` value the basic half
/// writes before its guards — is the route half.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the guard that an
/// empty header value is not read against the storage layer at all, which a patch that read the
/// value fails on the input that stores an empty token; that the token half runs before the basic
/// half, which a patch that swapped the order fails on a request that carries both; the rule the
/// key half answers when its read finds no row, which a patch that answered the rule naming the
/// account row fails on; the guard that an empty name or an empty password ends the read before the
/// compare, which a patch that removed it fails on a stored row whose name is empty; the compare
/// running on the account column rather than on the Google Reader column, which a patch that read
/// the other column fails on; the name being read lowercase, as the account lookup reads it, which
/// a patch that compared it as given fails on; and the two branches the failure rules name, which a
/// patch that answered one rule for both inputs fails on. The guard patch for the token value fires
/// every pin that reads the basic half, because with the guard away the request is read against the
/// key table whatever it carries; the order patch fires the pin that reads the failure rule for a
/// request that carries no key row, because that pin's request reaches only the basic half; the
/// patch for the name reaches `UserRepositoryTests`, whose own pin pins the lookup itself; each
/// other patch fires only the pin it names.
///
/// What they cannot fail on: the answer a client would tell apart for the two branches that share
/// one status upstream — a name with no row and a name whose stored hash does not match are both
/// the same 401 there, so what these pins read is which branch fired, and the names are the port's
/// own; the order between the compare and the row read, because one read serves both here where
/// upstream reads the hash and then the row, so no input can tell the two orders apart; the
/// constant-time form of the compare, which is upstream's timing half and which no test reads; the
/// dummy comparison upstream runs for a name with no row, which has no piece here; the single-row
/// limit of the key read; the storage failure the middleware answers with the 500 shape, which this
/// suite cannot trigger; and the `SetLastLogin` and `SetAPIKeyUsedTimestamp` writes the reference
/// makes after its read passes, which have no column here, so there is nothing to pin.
@Suite struct RestV1AuthTests {
    @Test func anEmptyTokenValueIsNotReadAgainstTheStorageLayer() async throws {
        try await withMigratedStorage { _, storage in
            // A stored key with an empty token is what makes this falsifiable: with the guard taken
            // away the read would reach that row, and the request would be authenticated.
            try await storage.withConnection { connection in
                let alice = try await insertUser(connection, username: "alice", passwordHash: "seed")
                try await insertKey(connection, userID: alice, token: "", description: "phone app")
            }

            let outcome = try await authenticate(storage, headers: [])
            #expect(outcome == .unauthorized(rule: .noAuthorizationValue),
                "the basic half answered, because the token half read nothing")
        }
    }

    @Test func theTokenHalfRunsBeforeTheBasicHalf() async throws {
        try await withMigratedStorage { _, storage in
            let alice = try await storage.withConnection { connection in
                let id = try await insertUser(connection, username: "alice", passwordHash: "seed")
                try await insertKey(connection, userID: id, token: "key-value",
                    description: "phone app")
                return id
            }

            // A request that carries both: upstream's basic half sees the request as already
            // authenticated, so the basic half runs nothing.
            let outcome = try await authenticate(storage, headers: [
                ("X-Auth-Token", "key-value"),
                ("Authorization", "Basic not-base64"),
            ])
            #expect(outcome == .authenticated(userID: alice))
        }
    }

    @Test func theKeyReadAnsweringNothingAnswersTheFailureRule() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                _ = try await insertUser(connection, username: "alice", passwordHash: "seed")
            }

            let outcome = try await authenticate(storage, headers: [("X-Auth-Token", "no-such-key")])
            #expect(outcome == .unauthorized(rule: .noApiKeyRow))
        }
    }

    @Test func anEmptyNameOrPasswordEndsTheReadBeforeTheCompare() async throws {
        try await withMigratedStorage { _, storage in
            // A stored row whose name is empty: without the guard the read reaches this row and the
            // compare answers the mismatch rule, which is the half the pin can tell apart.
            try await storage.withConnection { connection in
                _ = try await insertUser(connection, username: "", passwordHash: hash("pw"))
            }

            let outcome = try await authenticate(storage, headers: [("Authorization", "Basic Og==")])
            #expect(outcome == .unauthorized(rule: .emptyNameOrPassword),
                "the guard answered, not the compare")
        }
    }

    @Test func theCompareRunsOnTheAccountColumn() async throws {
        try await withMigratedStorage { _, storage in
            let alice = try await storage.withConnection { connection in
                try await insertUser(connection, username: "alice", passwordHash: hash("pw"),
                    googleReaderPasswordHash: hash("other"))
            }

            // The password is the one the Google Reader column was created from, so the account
            // column is what the compare has to read for this pin to see a failure.
            let mismatch = try await authenticate(storage,
                headers: [("Authorization", "Basic YWxpY2U6b3RoZXI=")])
            #expect(mismatch == .unauthorized(rule: .passwordMismatch))

            // The control: the value the account column was created from answers as a match.
            let matched = try await authenticate(storage,
                headers: [("Authorization", "Basic YWxpY2U6cHc=")])
            #expect(matched == .authenticated(userID: alice),
                "the stored hash of the account column is what the compare reads")
        }
    }

    @Test func theNameIsReadLowercaseLikeTheAccountLookup() async throws {
        try await withMigratedStorage { _, storage in
            // The row is stored lowercase, as the create writes it, and the request carries the
            // name in the other case, which is what the pin can fail on.
            let alice = try await storage.withConnection { connection in
                try await insertUser(connection, username: "alice", passwordHash: hash("pw"))
            }

            let outcome = try await authenticate(storage,
                headers: [("Authorization", "Basic QWxpY2U6cHc=")])
            #expect(outcome == .authenticated(userID: alice),
                "the name is read as the account lookup reads it, lowercase")
        }
    }

    @Test func theTwoFailureBranchesNameTheirOwnRules() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                _ = try await insertUser(connection, username: "alice", passwordHash: hash("pw"))
            }

            #expect(try await authenticate(storage,
                headers: [("Authorization", "Basic YWxpY2U6cGFzcw==")])
                == .unauthorized(rule: .passwordMismatch))
            #expect(try await authenticate(storage, headers: [("Authorization", "Basic Ym9iOnB3")])
                == .unauthorized(rule: .noUserRow))
        }
    }

    // MARK: - Setup

    /// The read as the route half runs it, on its own checkout, so the pin that seeds the rows and
    /// the pin that reads the outcome do not hold the connection at the same time.
    private func authenticate(_ storage: SQLiteStorage,
        headers: [(name: String, value: String)]) async throws -> RestV1AuthOutcome {
        try await RestV1Auth(storage: storage, hasher: BcryptHasher())
            .authenticate(headers: RestV1Headers(lines: headers))
    }

    private func hash(_ password: String) throws -> String { try BcryptHasher().hash(password) }

    /// A row put in through SQL, so the two hash columns can hold two different values and the name
    /// can be a value the port would not write itself, which is what these pins need.
    private func insertUser(_ connection: any Database, username: String, passwordHash: String,
        googleReaderPasswordHash: String? = nil) async throws -> Int {
        let row = try await sqlDatabase(connection).raw("""
            INSERT INTO users (username, password_hash, is_admin, google_reader_password_hash,
                created_at, updated_at)
            VALUES (\(bind: username), \(bind: passwordHash), \(bind: 0),
                \(bind: googleReaderPasswordHash), \(bind: 1_000_000_000), \(bind: 1_000_000_000))
            RETURNING id
            """).first()
        return try #require(row).decode(column: "id", as: Int.self)
    }

    private func insertKey(_ connection: any Database, userID: Int, token: String,
        description: String) async throws {
        try await sqlDatabase(connection).raw("""
            INSERT INTO api_keys (user_id, token, description, created_at)
            VALUES (\(bind: userID), \(bind: token), \(bind: description), \(bind: 1_000_000_000))
            """).run()
    }
}
