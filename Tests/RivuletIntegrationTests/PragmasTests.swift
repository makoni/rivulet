import XCTest
import Fluent
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

    func testPrepareEnablesWALThatPersistsOnTheFile() async throws {
        // WAL is a property of the database file: prepare through one pool, then read the
        // mode from a connection belonging to a different pool (event loop).
        let loops = Self.eventLoops(of: database.app)
        try XCTSkipUnless(loops.count > 1, "the persistence check needs at least two event loops")

        let writer = try makeStorage(on: loops[0])
        try await writer.prepare()

        let reader = try makeStorage(on: loops[1])
        try await reader.withConnection { connection in
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

    func testSessionPragmasAreAppliedOnConnectionsAcrossEventLoops() async throws {
        // The driver keeps one pooled connection per event loop: every loop must get a
        // connection with the pragmas applied (a single shared connection would hide a
        // wrapper that applies them only once).
        let loops = Self.eventLoops(of: database.app)
        try XCTSkipUnless(loops.count > 1, "the check needs at least two event loops")

        for loop in loops {
            let loopStorage = try makeStorage(on: loop)
            try await loopStorage.withConnection { connection in
                try await Self.assertSessionPragmas(on: connection)
            }
        }
    }

    // MARK: - Helpers

    private func makeStorage(on loop: any EventLoop) throws -> SQLiteStorage {
        let connection = try XCTUnwrap(
            database.app.databases.database(.sqlite, logger: database.app.logger, on: loop)
        )
        return SQLiteStorage(database: connection, path: database.path)
    }

    private static func eventLoops(of app: Application) -> [any EventLoop] {
        Array(app.eventLoopGroup.makeIterator()).prefix(4).map { $0 }
    }

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
