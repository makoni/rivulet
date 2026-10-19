import XCTest
import Fluent
import FluentSQLiteDriver
import SQLKit
@testable import RivuletCore

/// Pins how `RawSQL` treats strings that contain several statements.
final class RawSQLTests: XCTestCase {
    private var database: TestDatabase!

    override func setUp() async throws {
        database = try await TestDatabase.make()
    }

    override func tearDown() async throws {
        await database.shutdown()
        database = nil
    }

    func testOnlyTheFirstStatementOfAStringIsExecuted() async throws {
        // sqlite-nio prepares one statement per call; the rest of the string is silently
        // ignored (see `RawSQL`). This test pins that behavior so a multi-statement
        // string is never mistaken for "applied".
        let storage = SQLiteStorage(database: database.app.db(.sqlite), path: database.path)
        try await storage.withConnection { connection in
            let sql = try Self.sqlDatabase(from: connection)
            try await RawSQL.run(
                "CREATE TABLE first_table (id INTEGER); CREATE TABLE second_table (id INTEGER)",
                on: connection
            )

            let names = try await Self.tableNames(sql)
            XCTAssertTrue(names.contains("first_table"), "the first statement should run")
            XCTAssertFalse(names.contains("second_table"), "trailing statements must never run")
        }
    }

    // MARK: - Helpers

    private static func tableNames(_ sql: any SQLDatabase) async throws -> [String] {
        let rows = try await sql.raw("SELECT name FROM sqlite_master WHERE type = 'table'").all()
        return try rows.map { try $0.decode(column: "name", as: String.self) }
    }

    private static func sqlDatabase(from connection: any Database) throws -> any SQLDatabase {
        guard let sql = connection as? any SQLDatabase else {
            throw StorageError.notSQLDatabase
        }
        return sql
    }
}
