import Foundation
import Fluent
import FluentSQLiteDriver
import Testing
@testable import RivuletCore

/// Round-trip for ``IconRepository``: dedup by hash plus the lookups the
/// feed-icon route and the feed list will use.
@Suite struct IconRepositoryTests {
    /// Creates a database with the schema migrated and runs `body` against it.
    private func withMigratedStorage(
        _ body: (TestDatabase, SQLiteStorage) async throws -> Void
    ) async throws {
        let database = try await TestDatabase.make()
        do {
            let storage = SQLiteStorage(database: database.app.db(.sqlite), path: database.path)
            try await storage.prepare()
            try await database.app.autoMigrate()
            try await body(database, storage)
        } catch {
            await database.shutdown()
            throw error
        }
        await database.shutdown()
    }

    @Test func insertStoresTheIconAndAssignsAnExternalID() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let icons = IconRepository(connection)
                let content = Data([0x89, 0x50, 0x4E, 0x47])
                let icon = try await icons.insert(hash: "hash-a", mimeType: "image/png", content: content)

                #expect(icon.id != nil)
                #expect(icon.hash == "hash-a")
                #expect(icon.mimeType == "image/png")
                #expect(icon.content == content)
                #expect(!icon.externalID.isEmpty)
                #expect(try await icons.fetch(externalID: icon.externalID)?.id == icon.id)
            }
        }
    }

    @Test func insertWithTheSameHashReturnsTheExistingIcon() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let icons = IconRepository(connection)
                let first = try await icons.insert(hash: "hash-a", mimeType: "image/png", content: Data([1]))
                let second = try await icons.insert(hash: "hash-a", mimeType: "image/png", content: Data([2]))

                #expect(second.id == first.id)
                #expect(second.externalID == first.externalID)
                #expect(second.content == Data([1]))
                #expect(try await icons.fetch(hash: "hash-a")?.id == first.id)
            }
        }
    }

    @Test func fetchByIDAndHashFindTheStoredIcon() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let icons = IconRepository(connection)
                let icon = try await icons.insert(hash: "hash-a", mimeType: "image/png", content: Data([1]))

                #expect(try await icons.fetch(id: icon.id!)?.hash == "hash-a")
                #expect(try await icons.fetch(id: 999) == nil)
                #expect(try await icons.fetch(hash: "hash-b") == nil)
                #expect(try await icons.fetch(externalID: "nope") == nil)
            }
        }
    }
}
