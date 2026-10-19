import Fluent
import FluentSQLiteDriver
import Testing
@testable import RivuletCore

/// Pins the storage contract documented on `SQLiteStorage.withConnection`.
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
}
