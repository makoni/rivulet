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

    func testFTSUpdateTriggerIsScopedToIndexedColumns() async throws {
        let sql = try sqlDatabase()
        let row = try await sql.raw("SELECT sql FROM sqlite_master WHERE name = 'entries_fts_au'").first()
        let ddl = try XCTUnwrap(row?.decode(column: "sql", as: String.self))
        XCTAssertTrue(
            ddl.contains("UPDATE OF title, content_text"),
            "the FTS update trigger must stay scoped to the indexed columns: \(ddl)"
        )
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
        let sql = try sqlDatabase()
        try await Self.assertIndexColumns("entries_feed_status_idx", ["feed_id", "status"], on: sql)
        try await Self.assertIndexColumns("entries_user_status_published_idx", ["user_id", "status", "published_at"], on: sql)
        try await Self.assertIndexColumns("entries_user_status_created_idx", ["user_id", "status", "created_at"], on: sql)
        try await Self.assertIndexColumns("entries_user_id_status_starred_idx", ["user_id", "status", "starred"], on: sql)
    }

    func testIndexColumnsAreVisibleOnAPreMigrationConnection() async throws {
        // Regression: a pooled connection can load its schema before the migration runs —
        // `SQLiteStorage.prepare()` does that, since `PRAGMA journal_mode=WAL` on a fresh
        // database populates the connection's schema cache. Index inspection must still
        // see the migrated schema on such a connection.
        let fresh = try await TestDatabase.make()
        do {
            let loops = Array(fresh.app.eventLoopGroup.makeIterator())
            try XCTSkipUnless(loops.count > 1, "the scenario needs two event loops")

            let preMigration = try XCTUnwrap(
                fresh.app.databases.database(.sqlite, logger: fresh.app.logger, on: loops[0])
            )
            let modeRow = try await RawSQL.first("PRAGMA journal_mode = WAL", on: preMigration)
            let mode = try modeRow?.decode(column: "journal_mode", as: String.self)
            XCTAssertEqual(mode?.lowercased(), "wal")

            let migration = try XCTUnwrap(
                fresh.app.databases.database(.sqlite, logger: fresh.app.logger, on: loops[1])
            )
            try await SchemaV1().prepare(on: migration)

            let sql = try XCTUnwrap(preMigration as? any SQLDatabase)
            try await Self.assertIndexColumns(
                "entries_user_status_created_idx",
                ["user_id", "status", "created_at"],
                on: sql
            )
        } catch {
            await fresh.shutdown()
            throw error
        }
        await fresh.shutdown()
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

    /// Asserts the column layout of an index as the schema migration created it.
    ///
    /// `PRAGMA index_info` resolves the index in the connection's cached schema at compile
    /// time and does not refresh a stale cache, so a pooled connection that loaded its schema
    /// before the migration would report no columns. The leading `SELECT` is an ordinary
    /// statement: it goes through the schema-cookie check and refreshes the cache.
    static func assertIndexColumns(
        _ index: String,
        _ expected: [String],
        on sql: any SQLDatabase,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        _ = try await sql.raw("SELECT COUNT(*) FROM entries").all()
        let rows = try await sql.raw("PRAGMA index_info('\(unsafeRaw: index)')").all()
        let columns = try rows.map { try $0.decode(column: "name", as: String.self) }
        XCTAssertEqual(columns, expected, "unexpected columns for \(index)", file: file, line: line)
    }
}
