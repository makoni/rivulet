import FluentKit
import SQLKit

/// Executes a single raw SQL statement.
///
/// sqlite-nio prepares exactly one statement per call, so every DDL statement —
/// FTS5 tables and triggers included — must be passed separately.
enum RawSQL {
    static func run(_ statement: String, on database: any Database) async throws {
        guard let sql = database as? any SQLDatabase else {
            throw StorageError.notSQLDatabase
        }
        try await sql.raw("\(unsafeRaw: statement)").run()
    }
}
