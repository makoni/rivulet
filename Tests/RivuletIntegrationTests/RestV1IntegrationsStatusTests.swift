import FluentKit
import Foundation
import SQLKit
import Testing
import Vapor
@testable import RivuletApp
@testable import RivuletCore

/// The one integrations path this stage registers, read over a real socket.
///
/// What each pin can fail on, with the patch its probe names:
/// - the path and the method the pattern registers — a patch that moved the registration to another
///   path fires on the pin that reads the answer;
/// - the one key of the document and the value the read answers for an account, which a patch that
///   answered the credential columns of the account row instead of the rule this port has fires on;
/// - the status the path carries, which a patch that answered the status the write paths carry fires on.
///
/// What these pins cannot show: the reference's rule reads the twenty-four flags of the `integrations`
/// table, which this port has no table for — the credential pairs live on the account row and no save
/// integration runs here, so the answer is false for every account and the reference's side of the rule
/// has nothing to pin on this port; the 404 branch the handler has for a row its read does not find,
/// which no request this suite can build reaches because the read that hands the handler the id read the
/// same row; and the storage failure the read can answer with, which this suite cannot trigger.
@Suite struct RestV1IntegrationsStatusTests {
    init() {
        TestLogging.bootstrapOnce()
    }

    private let storedHash = "$2a$10$hOrIpoEkDKAMFrOt2/k1yeyHBaZKOwK8zEg9JVchReOAtQZ5mEeFu"
    private let token = "key-for-alice"

    @Test func thePathAnswersTheOneKeyDocumentTheResponseStructDeclares() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
            }

            let response = try await request(app, base, method: .GET, path: "/v1/integrations/status")
            #expect(response.status == .ok, "the registered path answers the read")
            #expect(try body(of: response) == "{\"has_integrations\":false}",
                "the one key the response struct declares, for an account with nothing on its row")
        }
    }

    @Test func theAnswerIsTheSameForAnAccountThatCarriesACredentialPair() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                // The port's own form of an integration: a credential pair on the account row. The
                // reference's rule reads the save-integration flags, not the credentials, so the answer
                // is the same here as for an account with nothing on its row. The patch that fires reads
                // the credential columns as the rule.
                try await RawSQL.sql(on: connection).raw("""
                    UPDATE users SET fever_username = \(bind: "fever-name") WHERE id = \(bind: 1)
                    """).run()
            }

            let response = try await request(app, base, method: .GET, path: "/v1/integrations/status")
            #expect(try body(of: response) == "{\"has_integrations\":false}",
                "the rule this port has, which is not the credential pair the row carries")
        }
    }

    // MARK: - Rows and requests

    private func insertKey(_ connection: any Database, userID: Int, token: String) async throws {
        try await RawSQL.sql(on: connection).raw("""
            INSERT INTO api_keys (user_id, token, description, created_at)
            VALUES (\(bind: userID), \(bind: token), \(bind: "phone app"), \(bind: 1_000_000_000))
            """).run()
    }

    private func request(_ app: Application, _ base: String, method: HTTPMethod, path: String,
        body: String = "") async throws -> ClientResponse {
        try await app.client.send(method, to: URI(string: base + path)) { request in
            request.headers.add(name: "X-Auth-Token", value: token)
            if !body.isEmpty {
                request.headers.add(name: "Content-Type", value: "application/json")
                request.body = .init(string: body)
            }
        }
    }

    private func body(of response: ClientResponse) throws -> String {
        let body = try #require(response.body)
        return String(decoding: body.readableBytesView, as: UTF8.self)
    }
}
