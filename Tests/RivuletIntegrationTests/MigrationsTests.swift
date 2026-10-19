import XCTest
import Fluent
import FluentSQLiteDriver
import SQLKit
@testable import RivuletCore

final class MigrationsTests: XCTestCase {
    private var database: TestDatabase!

    override func setUp() async throws {
        database = try await TestDatabase.make()
        // Production order: WAL first (the storage layer verifies it), then the schema.
        let storage = SQLiteStorage(database: database.app.db(.sqlite), path: database.path)
        try await storage.prepare()
        try await database.app.autoMigrate()
    }

    override func tearDown() async throws {
        await database.shutdown()
        database = nil
    }

    func testSchemaContainsAllTablesIncludingFTS() async throws {
        let tables = Set(try await schemaObjectNames(type: "table"))
        let expected: Set<String> = [
            "users", "categories", "feeds", "entries", "entry_tombstones",
            "enclosures", "icons", "entries_fts",
        ]
        XCTAssertTrue(expected.isSubset(of: tables), "missing tables: \(expected.subtracting(tables))")

        let ddl = try await entriesFTSDDL()
        XCTAssertTrue(ddl.contains("USING fts5"), "entries_fts must be an FTS5 virtual table: \(ddl)")
    }

    func testSchemaContainsFTSyncTriggers() async throws {
        let triggers = Set(try await schemaObjectNames(type: "trigger"))
        XCTAssertEqual(triggers, ["entries_fts_ai", "entries_fts_ad", "entries_fts_au"])
    }

    func testSchemaContainsIndexes() async throws {
        let indexes = Set(try await schemaObjectNames(type: "index"))
        let expected: Set<String> = [
            "entries_feed_status_idx",
            "entries_user_status_published_idx",
            "entries_user_status_created_idx",
            "entries_user_id_status_starred_idx",
            "feeds_user_category_idx",
            "feeds_next_check_at_idx",
            "enclosures_entry_id_idx",
            "entry_tombstones_deleted_at_idx",
        ]
        XCTAssertTrue(expected.isSubset(of: indexes), "missing indexes: \(expected.subtracting(indexes))")
    }

    func testIndexColumnsMatchTheQueriesTheyServe() async throws {
        try await assertIndexColumns("entries_feed_status_idx", ["feed_id", "status"])
        try await assertIndexColumns("entries_user_status_published_idx", ["user_id", "status", "published_at"])
        try await assertIndexColumns("entries_user_status_created_idx", ["user_id", "status", "created_at"])
        try await assertIndexColumns("entries_user_id_status_starred_idx", ["user_id", "status", "starred"])
    }

    func testMigrationsAreIdempotent() async throws {
        // setUp already migrated once; a second run must be a no-op.
        try await database.app.autoMigrate()

        let sql = try sqlDatabase()
        let row = try await sql.raw("SELECT COUNT(*) AS count FROM _fluent_migrations").first()
        let count = try XCTUnwrap(row?.decode(column: "count", as: Int.self))
        XCTAssertEqual(count, 1)

        // And the schema is still intact.
        let tables = Set(try await schemaObjectNames(type: "table"))
        XCTAssertTrue(tables.contains("users"))
        XCTAssertTrue(tables.contains("entries_fts"))
    }

    func testRevertRemovesSchema() async throws {
        try await database.app.autoRevert()

        let tables = Set(try await schemaObjectNames(type: "table"))
        for name in ["users", "categories", "feeds", "entries", "entry_tombstones", "enclosures", "icons", "entries_fts"] {
            XCTAssertFalse(tables.contains(name), "\(name) should have been dropped")
        }

        let triggers = Set(try await schemaObjectNames(type: "trigger"))
        XCTAssertTrue(triggers.isEmpty)
    }

    // MARK: - Helpers

    private func sqlDatabase() throws -> any SQLDatabase {
        try XCTUnwrap(database.app.db(.sqlite) as? any SQLDatabase)
    }

    private func schemaObjectNames(type: String) async throws -> [String] {
        let sql = try sqlDatabase()
        let rows = try await sql
            .raw("SELECT name FROM sqlite_master WHERE type = '\(unsafeRaw: type)'")
            .all()
        return try rows.map { try $0.decode(column: "name", as: String.self) }
    }

    private func entriesFTSDDL() async throws -> String {
        let sql = try sqlDatabase()
        let row = try await sql.raw("SELECT sql FROM sqlite_master WHERE name = 'entries_fts'").first()
        return try XCTUnwrap(row?.decode(column: "sql", as: String.self))
    }

    private func assertIndexColumns(_ index: String, _ expected: [String]) async throws {
        let sql = try sqlDatabase()
        let rows = try await sql.raw("PRAGMA index_info('\(unsafeRaw: index)')").all()
        let columns = try rows.map { try $0.decode(column: "name", as: String.self) }
        XCTAssertEqual(columns, expected, "unexpected columns for \(index)")
    }
}
