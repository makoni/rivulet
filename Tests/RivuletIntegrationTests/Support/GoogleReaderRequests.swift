import Foundation
import SQLKit
import Testing
import Vapor
@testable import RivuletCore

/// The requests the Google Reader suite sends over the socket, and the reads of the answer they
/// come back with. The body is sent as the bytes are given, so a rule about what the form read sees
/// is shown by the bytes rather than by an encoding the client added.
struct GoogleReaderRequests {
    private let app: Application
    private let base: String

    init(_ app: Application, _ base: String) {
        self.app = app
        self.base = base
    }

    func login(fields: [String: String]) async throws -> ClientResponse {
        try await post("/accounts/ClientLogin", form: fields)
    }

    func get(_ pathAndQuery: String, header: String? = nil) async throws -> ClientResponse {
        try await app.client.get(URI(string: base + pathAndQuery)) { request in
            if let header {
                request.headers.add(name: "Authorization", value: header)
            }
        }
    }

    func post(_ pathAndQuery: String, form: [String: String], contentType: String? = nil,
        header: String? = nil) async throws -> ClientResponse {
        try await post(pathAndQuery, raw: form.map {
            "\($0.key)=\(Self.escape($0.value))" }.joined(separator: "&"),
            contentType: contentType ?? "application/x-www-form-urlencoded", header: header)
    }

    func post(_ pathAndQuery: String, raw: String, query: String = "",
        contentType: String = "application/x-www-form-urlencoded",
        header: String? = nil) async throws -> ClientResponse {
        let path = pathAndQuery + (query.isEmpty ? "" : "?\(query)")
        let allocator = ByteBufferAllocator()
        return try await app.client.post(URI(string: base + path)) { request in
            request.headers.add(name: "Content-Type", value: contentType)
            if let header {
                request.headers.add(name: "Authorization", value: header)
            }
            request.body = allocator.buffer(string: raw)
        }
    }

    func body(of response: ClientResponse) throws -> String {
        let body = try #require(response.body)
        return String(decoding: body.readableBytesView, as: UTF8.self)
    }

    func contentType(of response: ClientResponse) -> String {
        response.headers.first(name: "Content-Type") ?? ""
    }

    /// Seeds a row through SQL, as the other storage pins do: the account name is stored lowercase
    /// and the integration name as it is given.
    func seed(_ storage: SQLiteStorage, name: String, storedHash: String,
        googleName: String? = nil) async throws {
        try await storage.withConnection { connection in
            let sql = try sqlDatabase(connection)
            try await sql.raw("""
                INSERT INTO users (username, password_hash, is_admin, google_reader_username,
                    google_reader_password_hash, created_at, updated_at)
                VALUES (\(bind: name), \(bind: "seed-hash"), \(bind: 0),
                    \(bind: googleName ?? name), \(bind: storedHash),
                    \(bind: 1_000_000_000), \(bind: 1_000_000_000))
                """).run()
        }
    }

    /// Percent-encoding for a form value, so a token with a slash in it reaches the handler as the
    /// reference reads it.
    private static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }
}
