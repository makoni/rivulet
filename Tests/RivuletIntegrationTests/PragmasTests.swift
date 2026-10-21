import Fluent
import FluentSQLiteDriver
import SQLKit
import Testing
import Vapor
@testable import RivuletCore

@Suite struct PragmasTests {
    /// Creates a database, prepares the storage (which applies WAL), then runs `body`.
    private func withPreparedStorage(
        _ body: (TestDatabase, SQLiteStorage) async throws -> Void
    ) async throws {
        let database = try await TestDatabase.make()
        do {
            let storage = SQLiteStorage(database: database.app.db(.sqlite), path: database.path)
            try await storage.prepare()
            try await body(database, storage)
        } catch {
            await database.shutdown()
            throw error
        }
        await database.shutdown()
    }

    @Test func prepareEnablesWALThatPersistsOnTheFile() async throws {
        try await withPreparedStorage { database, _ in
            // WAL is a property of the database file: prepare through one pool, then read the
            // mode from a connection belonging to a different pool (event loop).
            let loops = Self.eventLoops(of: database.app)
            guard loops.count > 1 else {
                try Test.cancel("the persistence check needs at least two event loops")
            }

            let writer = try makeStorage(on: loops[0], in: database)
            try await writer.prepare()

            let reader = try makeStorage(on: loops[1], in: database)
            try await reader.withConnection { connection in
                let sql = try Self.sqlDatabase(from: connection)
                let row = try await sql.raw("PRAGMA journal_mode").first()
                let mode = try row?.decode(column: "journal_mode", as: String.self)
                #expect(mode?.lowercased() == "wal")
            }
        }
    }

    @Test func sessionPragmasAreAppliedOnCheckout() async throws {
        try await withPreparedStorage { _, storage in
            try await storage.withConnection { connection in
                try await Self.assertSessionPragmas(on: connection)
            }
        }
    }

    @Test func sessionPragmasAreAppliedOnConnectionsAcrossEventLoops() async throws {
        try await withPreparedStorage { database, _ in
            // The driver keeps one pooled connection per event loop: every loop must get a
            // connection with the pragmas applied (a single shared connection would hide a
            // wrapper that applies them only once).
            let loops = Self.eventLoops(of: database.app)
            guard loops.count > 1 else {
                try Test.cancel("the check needs at least two event loops")
            }

            for loop in loops {
                let loopStorage = try makeStorage(on: loop, in: database)
                try await loopStorage.withConnection { connection in
                    try await Self.assertSessionPragmas(on: connection)
                }
            }
        }
    }

    // MARK: - Helpers

    private func makeStorage(on loop: any EventLoop, in database: TestDatabase) throws -> SQLiteStorage {
        let connection = try #require(
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
        let timeout = try busyTimeout?.decode(column: "timeout", as: Int.self)
        #expect(timeout == SQLiteStorage.busyTimeoutMilliseconds)

        let synchronous = try await sql.raw("PRAGMA synchronous").first()
        let synchronousValue = try synchronous?.decode(column: "synchronous", as: Int.self)
        #expect(synchronousValue == 1, "synchronous must be NORMAL (1)")

        let foreignKeys = try await sql.raw("PRAGMA foreign_keys").first()
        let foreignKeysValue = try foreignKeys?.decode(column: "foreign_keys", as: Int.self)
        #expect(foreignKeysValue == 1)

        let journalSizeLimit = try await sql.raw("PRAGMA journal_size_limit").first()
        let limit = try journalSizeLimit?.decode(column: "journal_size_limit", as: Int.self)
        #expect(limit == SQLiteStorage.journalSizeLimit)
    }

    private static func sqlDatabase(from connection: any Database) throws -> any SQLDatabase {
        guard let sql = connection as? any SQLDatabase else {
            throw StorageError.notSQLDatabase
        }
        return sql
    }
}
