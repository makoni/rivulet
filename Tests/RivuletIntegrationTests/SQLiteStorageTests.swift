import XCTest
import Fluent
import FluentSQLiteDriver
@testable import RivuletCore

/// Pins the storage contract documented on `SQLiteStorage.withConnection`.
final class SQLiteStorageTests: XCTestCase {
    private var database: TestDatabase!

    override func setUp() async throws {
        database = try await TestDatabase.make(poolTimeoutMilliseconds: 200)
    }

    override func tearDown() async throws {
        await database.shutdown()
        database = nil
    }

    func testNestedConnectionCheckoutFailsFastInsteadOfHanging() async throws {
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
            XCTFail("expected the nested checkout to fail")
        } catch {
            let elapsed = clock.now - start
            XCTAssertLessThan(elapsed, .seconds(5), "nested checkout must fail fast, not hang")
        }
    }
}
