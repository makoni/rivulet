import Foundation
import Fluent
import FluentSQLiteDriver
import Testing
import Vapor
@testable import RivuletCore

/// Maintenance operations on the storage wrapper: backup, vacuum, checkpoint,
/// the startup integrity check, and the failure behaviors (corruption, a full
/// disk) that must leave the database intact.
@Suite struct MaintenanceTests {
    @Test func backupProducesAnOpenableCopy() async throws {
        try await withMigratedStorage { database, storage in
            try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                for index in 0..<5 {
                    _ = try await seedEntry(
                        connection,
                        userID: feed.userID,
                        feedID: feed.feedID,
                        hash: "backup-\(index)",
                        content: "<p>Backup entry \(index)</p>"
                    )
                }
            }

            let backupPath = database.directory.appendingPathComponent("backup.db").path
            try await storage.backup(to: backupPath)

            // A second driver on the copy: the backup is a normal, openable
            // database with the same content as the source.
            database.registerDriver(at: backupPath, as: DatabaseID(string: "backup"))
            let copy = SQLiteStorage(
                database: database.app.db(DatabaseID(string: "backup")),
                path: backupPath
            )
            let source = try await storage.withConnection { connection in
                (
                    counts: try await Self.counts(on: connection),
                    entries: try await Self.entryDigests(on: connection)
                )
            }
            let backup = try await copy.withConnection { connection in
                (
                    counts: try await Self.counts(on: connection),
                    entries: try await Self.entryDigests(on: connection)
                )
            }
            #expect(source.counts == backup.counts)
            #expect(source.entries == backup.entries)
        }
    }

    @Test func backupRefusesToOverwriteAnExistingCopy() async throws {
        try await withMigratedStorage { database, storage in
            let destination = database.directory.appendingPathComponent("copy.db").path
            try await storage.backup(to: destination)
            do {
                try await storage.backup(to: destination)
                Issue.record("expected the second backup to fail")
            } catch {
                #expect(String(describing: error).contains("already exists"))
            }
        }
    }

    @Test func vacuumReclaimsPagesFromDeletedRows() async throws {
        try await withMigratedStorage { database, storage in
            let feed = try await storage.withConnection { connection -> (userID: Int, feedID: Int) in
                let graph = try await seedFeed(connection)
                for index in 0..<20 {
                    _ = try await seedEntry(
                        connection,
                        userID: graph.userID,
                        feedID: graph.feedID,
                        hash: "bloated-\(index)",
                        content: String(repeating: "x", count: 500_000)
                    )
                }
                return (graph.userID, graph.feedID)
            }

            let deleted = try await storage.withTransaction {
                try await EntryRepository($0).archive(
                    status: .unread,
                    createdBefore: Int(Date.now.timeIntervalSince1970) + 1,
                    limit: 100
                )
            }
            #expect(deleted == 20)
            try await storage.checkpoint()
            let bloated = try #require(Self.fileSize(database.path))
            #expect(bloated > 5_000_000)

            try await storage.vacuum()
            let shrunk = try #require(Self.fileSize(database.path))
            #expect(shrunk < bloated / 2)

            try await storage.quickCheck()
            try await storage.withConnection { connection in
                let count = try await EntryRepository(connection)
                    .count(EntryQuery(userID: feed.userID))
                #expect(count == 0)
            }
        }
    }

    @Test func checkpointTruncatesTheWALFile() async throws {
        try await withMigratedStorage { database, storage in
            try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                _ = try await seedEntry(
                    connection, userID: feed.userID, feedID: feed.feedID, hash: "checkpoint"
                )
            }
            let wal = database.path + "-wal"
            #expect(try #require(Self.fileSize(wal)) > 0)

            try await storage.checkpoint()
            #expect(Self.fileSize(wal) == 0)
        }
    }

    @Test func quickCheckPassesOnAHealthyDatabase() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                _ = try await seedEntry(
                    connection, userID: feed.userID, feedID: feed.feedID, hash: "healthy"
                )
            }
            try await storage.quickCheck()
        }
    }

    @Test func quickCheckReportsCorruption() async throws {
        try await withMigratedStorage { database, storage in
            // Page 2 (the `_fluent_migrations` root) already carries the SchemaV1 row.
            try await storage.checkpoint()
            try DatabaseCorruption.page2CellCount(at: database.path)

            // A second driver on the same file models the startup path; the
            // pooled connection above still has the uncorrupted page cached.
            database.registerDriver(at: database.path, as: DatabaseID(string: "check"))
            let checker = SQLiteStorage(
                database: database.app.db(DatabaseID(string: "check")),
                path: database.path
            )
            do {
                try await checker.quickCheck()
                Issue.record("expected quickCheck to report the corrupted database")
            } catch {
                guard case StorageError.databaseCorrupt(let details) = error else {
                    Issue.record("expected databaseCorrupt, got: \(error)")
                    return
                }
                // The check must actually see the damaged page, not just fail.
                #expect(details.joined(separator: " ").contains("page 2"))
            }
        }
    }

    @Test func quickCheckMapsAnUnreadableFileToCorruption() async throws {
        try await withMigratedStorage { database, storage in
            try await storage.checkpoint()
            // A zeroed file header is not a database at all: `PRAGMA quick_check`
            // fails as a statement instead of returning problem rows.
            var data = try Data(contentsOf: URL(fileURLWithPath: database.path))
            data.replaceSubrange(0..<16, with: Data(repeating: 0, count: 16))
            try data.write(to: URL(fileURLWithPath: database.path))

            database.registerDriver(at: database.path, as: DatabaseID(string: "check"))
            let checker = SQLiteStorage(
                database: database.app.db(DatabaseID(string: "check")),
                path: database.path
            )
            do {
                try await checker.quickCheck()
                Issue.record("expected quickCheck to reject an unreadable file")
            } catch {
                guard case StorageError.databaseCorrupt(let details) = error else {
                    Issue.record("expected databaseCorrupt, got: \(error)")
                    return
                }
                // The detail is the underlying failure, not a quick_check row.
                #expect(details.joined(separator: " ").contains("not a database"))
            }
        }
    }

    @Test func checkpointReportsAReaderThatBlocksTruncation() async throws {
        try await withMigratedStorage { database, storage in
            try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                _ = try await seedEntry(
                    connection, userID: feed.userID, feedID: feed.feedID, hash: "busy"
                )
            }

            // A second driver holds a read snapshot, so the truncating checkpoint
            // cannot reset the WAL and must report that instead of claiming success.
            database.registerDriver(at: database.path, as: DatabaseID(string: "reader"))
            let reader = SQLiteStorage(
                database: database.app.db(DatabaseID(string: "reader")),
                path: database.path
            )
            try await reader.withConnection { connection in
                try await RawSQL.run("BEGIN", on: connection)
                _ = try await RawSQL.first("SELECT count(*) AS n FROM entries", on: connection)
                do {
                    try await storage.checkpoint()
                    Issue.record("expected the checkpoint to report the busy reader")
                } catch {
                    #expect(error as? StorageError == .checkpointBusy)
                }
                try await RawSQL.run("ROLLBACK", on: connection)
            }
        }
    }

    @Test func diskFullFailsTheInsertAndKeepsTheDatabaseIntact() async throws {
        try await withMigratedStorage { _, storage in
            let seed = try await storage.withConnection { connection -> (userID: Int, feedID: Int) in
                let feed = try await seedFeed(connection)
                _ = try await seedEntry(
                    connection, userID: feed.userID, feedID: feed.feedID, hash: "small"
                )
                return (feed.userID, feed.feedID)
            }

            do {
                try await storage.withTransaction { connection in
                    let pageCount = try await Self.pageCount(on: connection)
                    try await RawSQL.run(
                        "PRAGMA max_page_count = \(pageCount + 10)", on: connection
                    )
                    defer { try? await RawSQL.run("PRAGMA max_page_count = -1", on: connection) }
                    _ = try await EntryRepository(connection).upsert(
                        userID: seed.userID,
                        feedID: seed.feedID,
                        input: entryInput(
                            hash: "oversized",
                            content: String(repeating: "y", count: 1_048_576)
                        ),
                        updateExisting: false
                    )
                    Issue.record("expected the oversized insert to fail")
                }
                Issue.record("expected the transaction to throw")
            } catch {
                #expect(String(describing: error).contains("disk is full"))
            }

            // The failed insert left the previous state intact.
            try await storage.withConnection { connection in
                try await RawSQL.run("PRAGMA max_page_count = -1", on: connection)
                let count = try await EntryRepository(connection)
                    .count(EntryQuery(userID: seed.userID))
                #expect(count == 1)
            }
            try await storage.quickCheck()
        }
    }

    /// Row counts of the tables the tests seed, in a comparable tuple.
    private static func counts(on connection: any Database) async throws
        -> (users: Int, categories: Int, feeds: Int, entries: Int)
    {
        let tables = ["users", "categories", "feeds", "entries"]
        var counts: (users: Int, categories: Int, feeds: Int, entries: Int) = (0, 0, 0, 0)
        for table in tables {
            let row = try await RawSQL.first("SELECT count(*) AS n FROM \(table)", on: connection)
            let value = try row?.decode(column: "n", as: Int.self) ?? 0
            switch table {
            case "users": counts.users = value
            case "categories": counts.categories = value
            case "feeds": counts.feeds = value
            default: counts.entries = value
            }
        }
        return counts
    }

    /// One digest line per entry, ordered by id: content equality, not just counts.
    private static func entryDigests(on connection: any Database) async throws -> [String] {
        let rows = try await RawSQL.sql(on: connection).raw("""
            SELECT id || '|' || hash || '|' || title || '|' || content
                   || '|' || CAST(published_at AS TEXT) AS digest
            FROM entries
            ORDER BY id
            """).all()
        return try rows.map { try $0.decode(column: "digest", as: String.self) }
    }

    private static func pageCount(on connection: any Database) async throws -> Int {
        let row = try await RawSQL.first("PRAGMA page_count", on: connection)
        return try row?.decode(column: "page_count", as: Int.self) ?? 0
    }

    /// Size of `path`, or nil when the file is missing: an assertion that the WAL is
    /// empty must not be satisfied by a deleted WAL.
    private static func fileSize(_ path: String) -> Int? {
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return (attributes?[.size] as? NSNumber)?.intValue ?? 0
    }
}
