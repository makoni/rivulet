import Fluent
import FluentSQLiteDriver
import Testing
@testable import RivuletCore

/// Pins the storage contracts documented on `SQLiteStorage.withConnection` and
/// `SQLiteStorage.withTransaction`.
@Suite struct SQLiteStorageTests {
    /// Creates a database with a short connection-pool timeout and runs `body` against it.
    private func withDatabase(_ body: (TestDatabase) async throws -> Void) async throws {
        let database = try await TestDatabase.make(poolTimeoutMilliseconds: 200)
        do {
            try await body(database)
        } catch {
            await database.shutdown()
            throw error
        }
        await database.shutdown()
    }

    @Test func nestedConnectionCheckoutFailsFastInsteadOfHanging() async throws {
        try await withDatabase { database in
            // The driver keeps a single pooled connection per event loop. A nested checkout
            // would wait for that connection, so it must fail on the pool timeout instead of
            // deadlocking; repositories must accept the checked-out connection instead.
            let storage = SQLiteStorage(database: database.app.db(.sqlite), path: database.path)

            let clock = ContinuousClock()
            let start = clock.now
            do {
                try await storage.withConnection { _ in
                    try await storage.withConnection { _ in }
                }
                Issue.record("expected the nested checkout to fail")
            } catch {
                let elapsed = clock.now - start
                #expect(elapsed < .seconds(5), "nested checkout must fail fast, not hang")
            }
        }
    }

    @Test func withTransactionCommitsTheWholeBatch() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withTransaction { connection in
                _ = try await UserRepository(connection)
                    .create(username: "alice", passwordHash: "hash", isAdmin: false)
            }

            try await storage.withConnection { connection in
                let user = try await UserRepository(connection).fetch(username: "alice")
                #expect(user != nil)
                let userID = try #require(user?.id)
                // The default "All" category is part of the same committed batch.
                #expect(try await CategoryRepository(connection).list(userID: userID).count == 1)
            }
        }
    }

    @Test func withTransactionRollsBackTheWholeBatchOnError() async throws {
        try await withMigratedStorage { _, storage in
            do {
                try await storage.withTransaction { connection in
                    _ = try await UserRepository(connection)
                        .create(username: "alice", passwordHash: "hash", isAdmin: false)
                    throw TransactionTestError.expected
                }
                Issue.record("expected the transaction body to throw")
            } catch TransactionTestError.expected {
                // The original error must reach the caller after the rollback.
            }

            try await storage.withConnection { connection in
                let user = try await UserRepository(connection).fetch(username: "alice")
                #expect(user == nil)
                let users = try await UserRepository(connection).list()
                #expect(users.isEmpty)
            }
        }
    }
}

/// Marker error for the rollback test.
private enum TransactionTestError: Error {
    case expected
}
