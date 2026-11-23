import FluentKit
import Foundation
import SQLKit
import Testing
import Vapor
@testable import RivuletApp
@testable import RivuletCore

///The route this stage registers, read over a real socket: what the port answers for the call Capy
///Reader's `minifluxclient` declares, `GET /v1/me`. 8 pins and 13 probes, every probe seen to fail
///on the rule it names and to revert the file byte-identically. What each pin can fail on, with the
///patch its probe names: - the path the pattern registers — a patch that renamed the path the
///registration line writes. This is the patch that reaches every pin here except the one for the
///method, because that pin reads an answer the router gives either way, and it reaches the pin for
///this prefix in `ClientSequenceReplayTests`, so it fires on 11 assertions; - the row the read
///hands the handler — a patch that read the first row of the table instead of the row the id names,
///which fires on both of this pin's assertions; - the status the guard answers — a patch that
///answered another status for the guard rule, which reaches the pin for this prefix and the pure
///status pin in `RestV1ResponseTests`; - the name written for every request and the name written
///for no request — two patches, one for each half of the rule, each firing on its own assertion
///here and on the pure pin that reads the same rule; - the three CORS names — one patch per name,
///each firing on its own assertion here and on the pure CORS pin, and the fourth assertion, the
///name the reference writes only on its OPTIONS branch, is shown by a patch that wrote it here; -
///the content type — a patch that wrote the framework's charset; - the key order the struct
///declares — a patch that swapped two of them, which reaches the row pin and the pure shape pin; -
///the method the pattern registers — a patch that registered the same path for another method,
///which fires on this pin alone. What these pins cannot show: the single-row limit of the key read;
///the constant-time form of the password compare; the wording of a storage failure this suite
///cannot trigger; the 404 the handler answers for a row its own read does not find, because the
///read that reaches the handler has already found the row; the `Vary` name the reference writes
///only above its compression threshold; the order the two keys of the router's answer are written
///in, which was not fixed across runs; and the reference's 405 for a method the pattern does not
///register, which this port answers with the router's 404, recorded as a divergence in
///`docs/parity.md`. The value of the realm is shown here, which is the half the pure suite of PR
///#87 named as not pinnable because it read the rule that decides whether the name is written
///rather than the value it carries: the patch that changed the value fires on this suite alone.
@Suite struct RestV1RouteTests {
    init() {
        TestLogging.bootstrapOnce()
    }

    private let storedHash = "$2a$10$hOrIpoEkDKAMFrOt2/k1yeyHBaZKOwK8zEg9JVchReOAtQZ5mEeFu"

    @Test func theRouteAnswersTheReadForThePathTheReferenceRegisters() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try await insertUser(connection, username: "alice",
                    passwordHash: storedHash)
                try await insertKey(connection, userID: alice, token: "key-for-alice")
            }

            let response = try await get(app, base, "/v1/me", token: "key-for-alice")
            #expect(response.status == .ok, "the registered path answers the read, not the router")
        }
    }

    @Test func theRowTheReadHandsTheHandler() async throws {
        try await withServedApp { storage, app, base in
            let rows = try await storage.withConnection { connection in
                let first = try await insertUser(connection, username: "alice",
                    passwordHash: storedHash)
                let second = try await insertUser(connection, username: "bob",
                    passwordHash: storedHash)
                try await insertKey(connection, userID: second, token: "key-for-bob")
                return (first, second)
            }

            let response = try await get(app, base, "/v1/me", token: "key-for-bob")
            #expect(try body(of: response) == "{\"id\":\(rows.1),\"username\":\"bob\",\"is_admin\":false}",
                "the document names the row the read found")
            #expect(try body(of: response) != "{\"id\":\(rows.0),\"username\":\"alice\",\"is_admin\":false}",
                "and not the first row, which is what a patch that read the first row answers")
        }
    }

    @Test func theStatusTheGuardAnswersOverTheSocket() async throws {
        try await withServedApp { _, app, base in
            let response = try await get(app, base, "/v1/me")
            #expect(response.status == .unauthorized, "the guard answers 401 over the socket")
            #expect(try body(of: response) == "{\"error_message\":\"access unauthorized\"}",
                "the reference's wording for a guard")
        }
    }

    @Test func theWwwAuthenticateNameOnTheSocketAnswer() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try await insertUser(connection, username: "alice",
                    passwordHash: storedHash)
                try await insertKey(connection, userID: alice, token: "key-for-alice")
            }

            let guarded = try await get(app, base, "/v1/me")
            #expect(guarded.headers.first(name: "WWW-Authenticate") == "Basic realm=\"Restricted\"",
                "the name is on the answer for a request whose token value was empty")

            let keyed = try await get(app, base, "/v1/me", token: "key-for-alice")
            #expect(keyed.headers.first(name: "WWW-Authenticate") == nil,
                "the key half answered this request, so the name is not on its answer")
        }
    }

    @Test func theThreeCorsNamesOnTheSocketAnswer() async throws {
        try await withServedApp { _, app, base in
            let response = try await get(app, base, "/v1/me")
            #expect(response.headers.first(name: "Access-Control-Allow-Origin") == "*",
                "the first name, read on its own")
            #expect(response.headers.first(name: "Access-Control-Allow-Methods") ==
                "GET, POST, PUT, DELETE, OPTIONS", "the second name, read on its own")
            #expect(response.headers.first(name: "Access-Control-Allow-Headers") ==
                "X-Auth-Token, Authorization, Content-Type, Accept", "the third name, read alone")
            #expect(response.headers.first(name: "Access-Control-Max-Age") == nil,
                "the reference writes that name only on its OPTIONS branch")
        }
    }

    @Test func theContentTypeOnTheSocketAnswer() async throws {
        try await withServedApp { _, app, base in
            let response = try await get(app, base, "/v1/me")
            #expect(response.headers.first(name: "Content-Type") == "application/json",
                "the value the reference's builder writes with no charset")
        }
    }

    @Test func theDocumentReadAsBytesOverTheSocket() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try await insertUser(connection, username: "alice",
                    passwordHash: storedHash)
                try await insertKey(connection, userID: alice, token: "key-for-alice")
            }

            let response = try await get(app, base, "/v1/me", token: "key-for-alice")
            #expect(try body(of: response) == "{\"id\":1,\"username\":\"alice\",\"is_admin\":false}",
                "the three keys, in the order the struct declares them")
        }
    }

    @Test func theMethodThePatternRegisters() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try await insertUser(connection, username: "alice",
                    passwordHash: storedHash)
                try await insertKey(connection, userID: alice, token: "key-for-alice")
            }

            let response = try await app.client.post(URI(string: base + "/v1/me")) { request in
                request.headers.add(name: "X-Auth-Token", value: "key-for-alice")
            }
            #expect(response.status == .notFound,
                "the pattern registers the method it names, so another method reaches the router")
        }
    }

    // MARK: - Requests and rows

    private func insertUser(_ connection: any Database, username: String,
        passwordHash: String) async throws -> Int {
        let row = try await sqlDatabase(connection).raw("""
            INSERT INTO users (username, password_hash, is_admin, created_at, updated_at)
            VALUES (\(bind: username), \(bind: passwordHash), \(bind: 0),
                \(bind: 1_000_000_000), \(bind: 1_000_000_000))
            RETURNING id
            """).first()
        return try #require(row).decode(column: "id", as: Int.self)
    }

    private func insertKey(_ connection: any Database, userID: Int, token: String) async throws {
        try await sqlDatabase(connection).raw("""
            INSERT INTO api_keys (user_id, token, description, created_at)
            VALUES (\(bind: userID), \(bind: token), \(bind: "phone app"), \(bind: 1_000_000_000))
            """).run()
    }

    private func get(_ app: Application, _ base: String, _ path: String,
        token: String? = nil) async throws -> ClientResponse {
        try await app.client.get(URI(string: base + path)) { request in
            if let token {
                request.headers.add(name: "X-Auth-Token", value: token)
            }
        }
    }

    private func body(of response: ClientResponse) throws -> String {
        let body = try #require(response.body)
        return String(decoding: body.readableBytesView, as: UTF8.self)
    }
}
