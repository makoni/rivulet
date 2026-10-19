import Foundation
import Fluent
import FluentSQLiteDriver
import Testing
@testable import RivuletCore

/// Round-trip for ``IconRepository``: dedup by hash plus the lookups the
/// feed-icon route and the feed list will use.
@Suite struct IconRepositoryTests {
    @Test func insertStoresTheIconAndAssignsAnExternalID() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let icons = IconRepository(connection)
                let content = Data([0x89, 0x50, 0x4E, 0x47])
                let icon = try await icons.insert(hash: "hash-a", mimeType: "image/png", content: content)
                let id = try #require(icon.id)

                let stored = try await icons.fetch(id: id)
                #expect(stored?.hash == "hash-a")
                #expect(stored?.mimeType == "image/png")
                #expect(stored?.content == content)
                let externalID = try #require(stored?.externalID)
                #expect(externalID.count == 40)
                #expect(externalID.allSatisfy { $0.isHexDigit })
                #expect(try await icons.fetch(externalID: externalID)?.id == id)
            }
        }
    }

    @Test func mimeTypeIsNormalizedLikeTheReference() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let icons = IconRepository(connection)
                _ = try await icons.insert(hash: "hash-a", mimeType: "IMAGE/PNG", content: Data([1]))
                _ = try await icons.insert(hash: "hash-b", mimeType: "application/octet-stream", content: Data([2]))
                _ = try await icons.insert(hash: "hash-c", mimeType: "image/GIF", content: Data([3]))

                #expect(try await icons.fetch(hash: "hash-a")?.mimeType == "image/png")
                #expect(try await icons.fetch(hash: "hash-b")?.mimeType == "image/x-icon")
                #expect(try await icons.fetch(hash: "hash-c")?.mimeType == "image/gif")
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
                let id = try #require(icon.id)

                #expect(try await icons.fetch(id: id)?.hash == "hash-a")
                #expect(try await icons.fetch(id: 999) == nil)
                #expect(try await icons.fetch(hash: "hash-b") == nil)
                #expect(try await icons.fetch(externalID: "nope") == nil)
            }
        }
    }
}
