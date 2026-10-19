import XCTest
import FluentSQLiteDriver
import SQLKit
import Vapor
@testable import RivuletCore

final class PragmasTests: XCTestCase {
    private var database: TestDatabase!
    private var storage: SQLiteStorage!

    override func setUp() async throws {
        database = try await TestDatabase.make()
        storage = SQLiteStorage(database: database.app.db(.sqlite), path: database.path)
        try await storage.prepare()
    }

    override func tearDown() async throws {
        await database.shutdown()
        database = nil
        storage = nil
    }

    func testPrepareEnablesWAL() async throws {
        try await storage.withConnection { connection in
            let sql = try Self.sqlDatabase(from: connection)
            let row = try await sql.raw("PRAGMA journal_mode").first()
            let mode = try row?.decode(column: "journal_mode", as: String.self)
            XCTAssertEqual(mode?.lowercased(), "wal")
        }
    }

    func testSessionPragmasAreAppliedOnCheckout() async throws {
        try await storage.withConnection { connection in
            try await Self.assertSessionPragmas(on: connection)
        }
    }

    func testSessionPragmasAreAppliedOnConcurrentConnections() async throws {
        let storage = storage!
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    try await storage.withConnection { connection in
                        try await Self.assertSessionPragmas(on: connection)
                    }
                }
            }
            try await group.waitForAll()
        }
    }

    // MARK: - Helpers

    private static func assertSessionPragmas(on connection: any Database) async throws {
        let sql = try sqlDatabase(from: connection)

        let busyTimeout = try await sql.raw("PRAGMA busy_timeout").first()
        XCTAssertEqual(
            try busyTimeout?.decode(column: "timeout", as: Int.self),
            5000
        )

        let synchronous = try await sql.raw("PRAGMA synchronous").first()
        XCTAssertEqual(
            try synchronous?.decode(column: "synchronous", as: Int.self),
            1, // NORMAL
        )

        let foreignKeys = try await sql.raw("PRAGMA foreign_keys").first()
        XCTAssertEqual(
            try foreignKeys?.decode(column: "foreign_keys", as: Int.self),
            1
        )
    }

    private static func sqlDatabase(from connection: any Database) throws -> any SQLDatabase {
        guard let sql = connection as? any SQLDatabase else {
            throw StorageError.notSQLDatabase
        }
        return sql
    }
}
