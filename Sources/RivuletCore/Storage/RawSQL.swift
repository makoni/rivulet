import FluentKit
import SQLKit

/// Executes raw SQL statements.
///
/// sqlite-nio prepares exactly **one statement** per call: a string containing several
/// statements runs the first and silently ignores the rest. Keep every statement separate —
/// the semicolons inside a trigger body still belong to one `CREATE TRIGGER` statement.
enum RawSQL {
    static func run(_ statement: String, on database: any Database) async throws {
        try await sql(on: database).raw("\(unsafeRaw: statement)").run()
    }

    static func first(_ statement: String, on database: any Database) async throws -> (any SQLRow)? {
        try await sql(on: database).raw("\(unsafeRaw: statement)").first()
    }

    private static func sql(on database: any Database) throws -> any SQLDatabase {
        guard let sql = database as? any SQLDatabase else {
            throw StorageError.notSQLDatabase
        }
        return sql
    }
}
