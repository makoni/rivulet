import Foundation
import Testing
@testable import RivuletCore

/// Opt-in heavy scenarios, disabled unless `RIVULET_HEAVY=1` (see `docs/testing.md`).
@Suite struct HeavyTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RIVULET_HEAVY"] == "1"))
    func ensureA100KEntryCorpusIsUsable() async throws {
        try await withMigratedStorage { _, storage in
            let corpus = try await Seeding.seed(on: storage, feeds: 100, entries: 100_000)
            #expect(corpus.entries == 100_000)

            try await storage.withConnection { connection in
                let entries = try await EntryRepository(connection)
                    .count(EntryQuery(userID: corpus.userID))
                #expect(entries == 100_000)

                // The seeded corpus answers the hot listing query used by clients.
                let page = try await EntryRepository(connection)
                    .listIDs(EntryQuery(userID: corpus.userID, limit: 50))
                #expect(page.count == 50)
            }
        }
    }
}
