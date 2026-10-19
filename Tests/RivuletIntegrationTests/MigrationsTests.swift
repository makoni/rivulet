import Fluent
import FluentSQLiteDriver
import SQLKit
import Testing
@testable import RivuletCore

@Suite struct MigrationsTests {
    /// Creates a database in production order — WAL first (the storage layer verifies
    /// it), then the schema — and runs `body` against it.
    private func withMigratedDatabase(_ body: (TestDatabase) async throws -> Void) async throws {
        let database = try await TestDatabase.make()
        do {
            let storage = SQLiteStorage(database: database.app.db(.sqlite), path: database.path)
            try await storage.prepare()
            try await database.app.autoMigrate()
            try await body(database)
        } catch {
            await database.shutdown()
            throw error
        }
        await database.shutdown()
    }

    @Test func schemaContainsAllTablesIncludingFTS() async throws {
        try await withMigratedDatabase { database in
            let tables = Set(try await schemaObjectNames(type: "table", on: database))
            let expected: Set<String> = [
                "users", "categories", "feeds", "entries", "entry_tombstones",
                "enclosures", "icons", "entries_fts",
            ]
            #expect(expected.isSubset(of: tables), "missing tables: \(expected.subtracting(tables))")

            let ddl = try await entriesFTSDDL(on: database)
            #expect(ddl.contains("USING fts5"), "entries_fts must be an FTS5 virtual table: \(ddl)")
        }
    }

    @Test func schemaContainsFTSyncTriggers() async throws {
        try await withMigratedDatabase { database in
            let triggers = Set(try await schemaObjectNames(type: "trigger", on: database))
            #expect(triggers == ["entries_fts_ai", "entries_fts_ad", "entries_fts_au"])
        }
    }

    @Test func ftsUpdateTriggerIsScopedToIndexedColumns() async throws {
        try await withMigratedDatabase { database in
            let sql = try sqlDatabase(of: database)
            let row = try await sql.raw("SELECT sql FROM sqlite_master WHERE name = 'entries_fts_au'").first()
            let decodedDDL = try row?.decode(column: "sql", as: String.self)
            let ddl = try #require(decodedDDL)
            #expect(
                ddl.contains("UPDATE OF title, content_text"),
                "the FTS update trigger must stay scoped to the indexed columns: \(ddl)"
            )
        }
    }

    @Test func schemaContainsIndexes() async throws {
        try await withMigratedDatabase { database in
            let indexes = Set(try await schemaObjectNames(type: "index", on: database))
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
            #expect(expected.isSubset(of: indexes), "missing indexes: \(expected.subtracting(indexes))")
        }
    }

    @Test func indexColumnsMatchTheQueriesTheyServe() async throws {
        try await withMigratedDatabase { database in
            let sql = try sqlDatabase(of: database)
            try await Self.assertIndexColumns("entries_feed_status_idx", ["feed_id", "status"], on: sql)
            try await Self.assertIndexColumns("entries_user_status_published_idx", ["user_id", "status", "published_at"], on: sql)
            try await Self.assertIndexColumns("entries_user_status_created_idx", ["user_id", "status", "created_at"], on: sql)
            try await Self.assertIndexColumns("entries_user_id_status_starred_idx", ["user_id", "status", "starred"], on: sql)
        }
    }

    @Test func indexColumnsAreVisibleOnAPreMigrationConnection() async throws {
        // Regression: a pooled connection can load its schema before the migration runs —
        // `SQLiteStorage.prepare()` does that, since `PRAGMA journal_mode=WAL` on a fresh
        // database populates the connection's schema cache. Index inspection must still
        // see the migrated schema on such a connection.
        let fresh = try await TestDatabase.make()
        let loops = Array(fresh.app.eventLoopGroup.makeIterator())
        guard loops.count > 1 else {
            await fresh.shutdown()
            try Test.cancel("the scenario needs two event loops")
        }

        do {
            let preMigration = try #require(
                fresh.app.databases.database(.sqlite, logger: fresh.app.logger, on: loops[0])
            )
            let modeRow = try await RawSQL.first("PRAGMA journal_mode = WAL", on: preMigration)
            let mode = try modeRow?.decode(column: "journal_mode", as: String.self)
            #expect(mode?.lowercased() == "wal")

            let migration = try #require(
                fresh.app.databases.database(.sqlite, logger: fresh.app.logger, on: loops[1])
            )
            try await SchemaV1().prepare(on: migration)

            let sql = try #require(preMigration as? any SQLDatabase)
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

    @Test func migrationsAreIdempotent() async throws {
        try await withMigratedDatabase { database in
            // The helper migrated once; a second run must be a no-op.
            try await database.app.autoMigrate()

            let sql = try sqlDatabase(of: database)
            let row = try await sql.raw("SELECT COUNT(*) AS count FROM _fluent_migrations").first()
            let decodedCount = try row?.decode(column: "count", as: Int.self)
            let count = try #require(decodedCount)
            #expect(count == 1)

            // And the schema is still intact.
            let tables = Set(try await schemaObjectNames(type: "table", on: database))
            #expect(tables.contains("users"))
            #expect(tables.contains("entries_fts"))
        }
    }

    @Test func revertRemovesSchema() async throws {
        try await withMigratedDatabase { database in
            try await database.app.autoRevert()

            let tables = Set(try await schemaObjectNames(type: "table", on: database))
            for name in ["users", "categories", "feeds", "entries", "entry_tombstones", "enclosures", "icons", "entries_fts"] {
                #expect(!tables.contains(name), "\(name) should have been dropped")
            }

            let triggers = Set(try await schemaObjectNames(type: "trigger", on: database))
            #expect(triggers.isEmpty)
        }
    }

    // MARK: - Helpers

    private func sqlDatabase(of database: TestDatabase) throws -> any SQLDatabase {
        try #require(database.app.db(.sqlite) as? any SQLDatabase)
    }

    private func schemaObjectNames(type: String, on database: TestDatabase) async throws -> [String] {
        let sql = try sqlDatabase(of: database)
        let rows = try await sql
            .raw("SELECT name FROM sqlite_master WHERE type = '\(unsafeRaw: type)'")
            .all()
        return try rows.map { try $0.decode(column: "name", as: String.self) }
    }

    private func entriesFTSDDL(on database: TestDatabase) async throws -> String {
        let sql = try sqlDatabase(of: database)
        let row = try await sql.raw("SELECT sql FROM sqlite_master WHERE name = 'entries_fts'").first()
        let decodedDDL = try row?.decode(column: "sql", as: String.self)
        return try #require(decodedDDL)
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
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        _ = try await sql.raw("SELECT COUNT(*) FROM entries").all()
        let rows = try await sql.raw("PRAGMA index_info('\(unsafeRaw: index)')").all()
        let columns = try rows.map { try $0.decode(column: "name", as: String.self) }
        #expect(columns == expected, "unexpected columns for \(index)", sourceLocation: sourceLocation)
    }
}
