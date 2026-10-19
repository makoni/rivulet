import XCTest
import FluentSQLiteDriver
import SQLKit
@testable import RivuletCore

final class MigrationsTests: XCTestCase {
    private var database: TestDatabase!

    override func setUp() async throws {
        database = try await TestDatabase.make()
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
            "feeds_next_check_at_idx",
            "feeds_user_id_idx",
            "entry_tombstones_deleted_at_idx",
        ]
        XCTAssertTrue(expected.isSubset(of: indexes), "missing indexes: \(expected.subtracting(indexes))")
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
}
