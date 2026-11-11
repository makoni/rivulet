import Foundation
import FluentKit
import SQLKit
import Testing
import Vapor
import RivuletApp
@testable import RivuletCore

/// The socket the three subscription suites read their pins through: one socket with the account it
/// authenticated as, the rows the pins write, and the values they read back through SQL.
///
/// The pins read the answer rather than the transport. The POST half carries the token as the form
/// field the merged read answers, because that is the form the write routes read; the GET half
/// reads it through the header the transport pins. The rows are written through SQL so that a pin
/// is not satisfied by the read it is testing, and a seed that produced no row is reported as the
/// pin's own failure rather than as a value the pin could not name.
struct SubscriptionSocket: Sendable {
    /// The stored hash the token read compares, the same one the auth suite uses.
    static let storedHash = "$2a$10$hOrIpoEkDKAMFrOt2/k1yeyHBaZKOwK8zEg9JVchReOAtQZ5mEeFu"

    let requests: GoogleReaderRequests
    let storage: SQLiteStorage
    let userID: Int
    let token: String

    /// The group the three pins post to.
    let routes: String

    /// One socket with the account it authenticated as. `routes` is the group the three pins post
    /// to.
    static func session(requests: GoogleReaderRequests, storage: SQLiteStorage, routes: String)
        async throws -> SubscriptionSocket {
        let userID = try await requests.seedIntegrationUser(storage, name: "alice",
            storedHash: storedHash)
        return SubscriptionSocket(requests: requests, storage: storage, userID: userID,
            token: GoogleReaderToken.derive(username: "alice", storedHash: storedHash), routes: routes)
    }

    func answer(_ path: String, pairs: [String] = []) async throws -> String {
        try requests.body(of: await post(path, pairs))
    }

    func status(_ path: String, pairs: [String] = []) async throws -> HTTPStatus {
        (try await post(path, pairs)).status
    }

    /// The GET half, which is the method the listing route is registered on.
    func get(_ pathAndQuery: String) async throws -> String {
        try requests.body(of: await requests.get(routes + pathAndQuery, header: header))
    }

    private func post(_ path: String, _ pairs: [String]) async throws -> ClientResponse {
        try await requests.post(routes + path, raw: form(pairs), header: header)
    }

    private func form(_ pairs: [String]) -> String {
        "T=\(token)" + (pairs.isEmpty ? "" : "&" + pairs.joined(separator: "&"))
    }

    private var header: String { "GoogleLogin auth=\(token)" }

    // MARK: - The rows the pins write and the values they read back
    @discardableResult
    func seedFeed(_ categoryID: Int, _ url: String, _ title: String, _ siteURL: String, _ errors: Int,
        icon: Int? = nil) async throws -> Int {
        try await storage.withConnection { connection in
            try await sqlDatabase(connection).raw("""
                INSERT INTO feeds (user_id, category_id, url, site_url, title, icon_id,
                    parsing_error_count, created_at, updated_at)
                VALUES (\(bind: userID), \(bind: categoryID), \(bind: url), \(bind: siteURL),
                    \(bind: title), \(bind: icon), \(bind: errors),
                    \(bind: 1_000_000_000), \(bind: 1_000_000_000))
                """).run()
            return try await lastID(connection, table: "feeds")
        }
    }

    @discardableResult
    func seedCategory(_ title: String) async throws -> Int {
        try await storage.withConnection { connection in
            try await sqlDatabase(connection).raw("""
                INSERT INTO categories (user_id, title, position, created_at, updated_at)
                VALUES (\(bind: userID), \(bind: title), \(bind: 0), \(bind: 1_000_000_000),
                    \(bind: 1_000_000_000))
                """).run()
            return try await lastID(connection, table: "categories")
        }
    }

    @discardableResult
    func seedIcon(_ hash: String, _ externalID: String) async throws -> Int {
        try await storage.withConnection { connection in
            try await sqlDatabase(connection).raw("""
                INSERT INTO icons (hash, mime_type, content, external_id, created_at)
                VALUES (\(bind: hash), \(bind: "image/png"), \(bind: Data([1])), \(bind: externalID),
                    \(bind: 1_000_000_000))
                """).run()
            return try await lastID(connection, table: "icons")
        }
    }

    private func lastID(_ connection: any Database, table: String) async throws -> Int {
        let row = try await sqlDatabase(connection).raw("""
            SELECT id FROM \(unsafeRaw: table) ORDER BY id DESC LIMIT 1
            """).first()
        guard let row else { throw MissingRow(table: table) }
        return try row.decode(column: "id", as: Int.self)
    }

    func feed(_ url: String) async throws -> Feed? {
        try await storage.withConnection { connection in
            try await FeedRepository(connection).fetch(userID: userID, url: url)
        }
    }

    func feedTitle(_ feedID: Int) async throws -> String? {
        try await value(column: "title", table: "feeds", id: feedID)
    }

    /// The category the row points at, through the join the listing read builds.
    func categoryTitle(_ feedID: Int) async throws -> String? {
        try await storage.withConnection { connection in
            let row = try await sqlDatabase(connection).raw("""
                SELECT c.title AS title FROM feeds f
                JOIN categories c ON c.id = f.category_id WHERE f.id = \(bind: feedID)
                """).first()
            guard let row else { return nil }
            return try row.decode(column: "title", as: String.self)
        }
    }

    func categoryID(_ title: String) async throws -> Int {
        try await storage.withConnection { connection in
            let row = try await sqlDatabase(connection).raw("""
                SELECT id FROM categories WHERE user_id = \(bind: userID) AND title = \(bind: title)
                """).first()
            guard let row else { throw MissingRow(table: "categories") }
            return try row.decode(column: "id", as: Int.self)
        }
    }

    private func value(column: String, table: String, id: Int) async throws -> String? {
        try await storage.withConnection { connection in
            let row = try await sqlDatabase(connection).raw("""
                SELECT \(unsafeRaw: column) AS value FROM \(unsafeRaw: table) WHERE id = \(bind: id)
                """).first()
            guard let row else { return nil }
            return try row.decode(column: "value", as: String.self)
        }
    }
}
