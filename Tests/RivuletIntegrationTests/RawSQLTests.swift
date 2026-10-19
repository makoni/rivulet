import Fluent
import FluentSQLiteDriver
import SQLKit
import Testing
@testable import RivuletCore

/// Pins how `RawSQL` treats strings that contain several statements.
@Suite struct RawSQLTests {
    /// Creates a bare database (no migration) and runs `body` against it.
    private func withDatabase(_ body: (TestDatabase) async throws -> Void) async throws {
        let database = try await TestDatabase.make()
        do {
            try await body(database)
        } catch {
            await database.shutdown()
            throw error
        }
        await database.shutdown()
    }

    @Test func onlyTheFirstStatementOfAStringIsExecuted() async throws {
        try await withDatabase { database in
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
                #expect(names.contains("first_table"), "the first statement should run")
                #expect(!names.contains("second_table"), "trailing statements must never run")
            }
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
