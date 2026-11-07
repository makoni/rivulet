import Fluent
import Foundation
import SQLKit
@testable import RivuletCore

/// What one database holds: the tables it has and one digest line per entry, ordered by id.
///
/// The pins read the rows through SQL, so a pin is not satisfied by the read it is testing.
struct Content: Sendable, Equatable {
    let tables: [String]
    let entries: [String]
}

/// Content read through the connection the pin was handed.
func content(on connection: any Database) async throws -> Content {
    let sql = try sqlDatabase(connection)
    let tables = try await sql.raw("""
        SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name
        """).all().map { try $0.decode(column: "name", as: String.self) }
    let entries = try await sql.raw("""
        SELECT id || '|' || hash || '|' || content AS digest FROM entries ORDER BY id
        """).all().map { try $0.decode(column: "digest", as: String.self) }
    return Content(tables: tables, entries: entries)
}

/// Content read through the storage the pin was handed.
func content(of storage: SQLiteStorage) async throws -> Content {
    try await storage.withConnection { connection in try await content(on: connection) }
}

/// Content of another file, read through its own driver: the copy the run wrote is not the
/// connection the test seeded with, so a pin is not satisfied by the write it is testing.
func content(at path: String, on database: TestDatabase, as id: String) async throws -> Content {
    database.registerDriver(at: path, as: DatabaseID(string: id))
    let copy = SQLiteStorage(database: database.app.db(DatabaseID(string: id)), path: path)
    return try await content(of: copy)
}
