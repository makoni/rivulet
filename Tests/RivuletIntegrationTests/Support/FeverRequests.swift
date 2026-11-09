import Foundation
import SQLKit
import Testing
import Vapor
import RivuletApp
@testable import RivuletCore

/// The socket the Fever suites read their pins through: the requests this path answers on, the
/// reads of the answers, and the rows the pins write.
///
/// The multipart body is sent as the bytes a client sends, so a rule about what the form read sees
/// is shown by the bytes rather than by an encoding the client added. On this path the key is read
/// through the merged form whatever the method is — the header the Google Reader path reads is
/// not a form field here — so the requests carry it as a part or as a query pair.
///
/// The clock field of every document is the instant the handler runs at, which no pin can name, so
/// `document(of:)` reads the answer with that field as the placeholder `0` and the pins compare
/// against the shape rule at that placeholder. The prefix the read checks is the order the three
/// base fields are written in, so a patch that changed that order makes the read return the answer
/// unchanged and the pin that names the order fails on it rather than on the helper.
struct FeverRequests: Sendable {
    private let app: Application
    private let base: String

    init(_ app: Application, _ base: String) {
        self.app = app
        self.base = base
    }

    /// Seeds a user with the token the derivation gives, written through the repository the
    /// credentials command uses, so a pin reads the stored value rather than a value the test made
    /// up. The account id is returned with it because the pins write rows for that account.
    func seed(_ storage: SQLiteStorage, name: String, password: String)
        async throws -> (userID: Int, token: String) {
        try await storage.withConnection { connection in
            let users = UserRepository(connection)
            let user = try await users.create(username: name, passwordHash: "hash", isAdmin: false)
            let userID = try #require(user.id)
            let token = FeverToken.derive(username: name, password: password)
            _ = try await users.updateIntegration(user, feverUsername: name, feverToken: token,
                googleReaderUsername: nil, googleReaderPasswordHash: nil)
            return (userID, token)
        }
    }

    /// The id a category row with this title holds, read through SQL so that a golden names the row
    /// the storage layer put there rather than a number the pin made up. The create path writes the
    /// default "All" row with the account, so the pins read that id from it.
    func categoryID(_ storage: SQLiteStorage, userID: Int, title: String) async throws -> Int {
        try await storage.withConnection { connection in
            let row = try await sqlDatabase(connection).raw("""
                SELECT id FROM categories WHERE user_id = \(bind: userID) AND title = \(bind: title)
                """).first()
            guard let row else { throw MissingRow(table: "categories") }
            return try row.decode(column: "id", as: Int.self)
        }
    }

    /// The path this handler answers on, as the client sends it: the base route with the query the
    /// dispatch reads.
    private func route(_ query: String) -> String {
        base + "/fever/" + (query.isEmpty ? "" : "?\(query)")
    }

    /// The body is sent as the bytes it is given, so a rule about what the read sees is shown by
    /// the bytes: `FormValue` reads a multipart body whatever the method is, which is why a pin
    /// that names that rule sends one on a `GET`.
    func get(_ query: String, body: String = "") async throws -> ClientResponse {
        let allocator = ByteBufferAllocator()
        return try await app.client.get(URI(string: route(query))) { request in
            if !body.isEmpty {
                request.headers.add(name: "Content-Type", value: "multipart/form-data; boundary=x")
                request.body = allocator.buffer(string: body)
            }
        }
    }

    func head(_ query: String) async throws -> ClientResponse {
        try await app.client.send(.HEAD, to: URI(string: route(query)))
    }

    func post(_ query: String, raw: String, contentType: String = "application/x-www-form-urlencoded")
        async throws -> ClientResponse {
        let allocator = ByteBufferAllocator()
        return try await app.client.post(URI(string: route(query))) { request in
            request.headers.add(name: "Content-Type", value: contentType)
            request.body = allocator.buffer(string: raw)
        }
    }

    /// A POST whose body is the parts as a client sends them, with the content type the client
    /// declares — the shape the acceptance client uses for the write calls. The urlencoded half
    /// of the form read is not the half this shape reaches, so the content type is part of the
    /// request.
    func postParts(_ query: String, _ parts: [(name: String, value: String)], boundary: String = "x")
        async throws -> ClientResponse {
        try await post(query, raw: multipart(parts, boundary: boundary),
            contentType: "multipart/form-data; boundary=\(boundary)")
    }

    /// A simple part set as Go's reader reads it. The value is written as it is given, so a part
    /// whose value carries an escape is not the pair the urlencoded half would read.
    func multipart(_ parts: [(name: String, value: String)], boundary: String = "x") -> String {
        parts.map { "--\(boundary)\r\nContent-Disposition: form-data; name=\"\($0.name)\"\r\n\r\n\($0.value)\r\n" }
            .joined() + "--\(boundary)--\r\n"
    }

    /// The answer as bytes. A response that writes nothing has no body buffer, so the read gives
    /// the empty value rather than failing — which is what the pins that name an empty body read.
    func body(of response: ClientResponse) -> String {
        guard let body = response.body else { return "" }
        return String(decoding: body.readableBytesView, as: UTF8.self)
    }

    func contentType(of response: ClientResponse) -> String {
        response.headers.first(name: "Content-Type") ?? ""
    }

    /// One response header, read the way the pins read it: the first value, or the empty value for
    /// a name the response does not carry.
    func header(_ response: ClientResponse, _ name: String) -> String {
        response.headers.first(name: name) ?? ""
    }

    /// The answer as the shape rule writes it, with the clock field read as the placeholder `0`.
    /// When the answer does not carry the three base fields first, the answer is returned as it
    /// came, which is what makes the pins that name the order fail.
    func document(of response: ClientResponse) -> String {
        let body = body(of: response)
        let prefix = "{\"api_version\":3,\"auth\":1,\"last_refreshed_on_time\":"
        guard body.hasPrefix(prefix) else { return body }
        let clock = body.dropFirst(prefix.count)
        let end = clock.firstIndex { $0 == "," || $0 == "}" } ?? clock.endIndex
        return prefix + "0" + String(clock[end...])
    }
}
