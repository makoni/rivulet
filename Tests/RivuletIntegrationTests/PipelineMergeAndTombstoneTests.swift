import Foundation
import SQLKit
import Testing
@testable import RivuletCore

/// What the entry loop does not write, read end to end through the pipeline at commit `c4d54f87`:
/// an entry the document no longer declares stays locally, and a tombstoned `(feed_id, hash)` never
/// resurfaces through a refresh. The reference's processor only inserts and updates — it never
/// deletes an entry upstream stopped declaring (`internal/reader/processor/processor.go`), and the
/// insert refuses a tombstoned pair, because `ArchiveEntries` writes the tombstone and the insert
/// reads it (`internal/storage/entry.go`).
/// What these pins can fail on, each checked by patching the rule and reverting: that the
/// pipeline runs no delete for entries the document stopped declaring — a patch that deletes the
/// rows of the feed whose hash is not in the parsed document fails the first pin — and that the
/// insert refuses a tombstoned `(feed_id, hash)` — a patch that drops the `NOT EXISTS` guard
/// fails the second, and so would a patch that stops the archive writing the tombstone. What
/// they cannot fail on: the age boundary, the batch limit and the starred rule of the archive,
/// which `RetentionTests` pins, because the pin that runs the archive runs it on an instant past
/// every stored row and on a single row; the atomicity of the delete and the tombstone insert,
/// which is the transaction boundary no test here can show; the user state an update must not
/// touch, which the storage suite pins; the user scope of the archive, which the reference does
/// not have, because retention is not scoped to one user; and the reference's return value,
/// which counts the tombstone rows it inserted rather than the rows it deleted. Nothing here
/// sleeps.
@Suite struct PipelineMergeAndTombstoneTests {
    /// The instant every stamp is read from, so a pin can tell the injected clock from the process
    /// one.
    private let now = 1_700_000_000
    private let policy = NextCheckPolicy()

    @Test func anEntryTheDocumentNoLongerDeclaresStaysLocally() async throws {
        try await withCase(behaviors: ["/feed": answer(rss([
            ("<p>Declared</p>", "https://example.org/declared"),
        ]))]) { storage, userID, feedID, pipeline in
            // The reference's processor writes only what the document declares. An entry that is
            // already stored and is not in the document is not touched: nothing in the pipeline can
            // delete it, so the row and its user state stay.
            _ = try await storage.withConnection { connection in
                try await seedEntry(connection, userID: userID, feedID: feedID, hash: "kept",
                    title: "Not declared upstream", content: "<p>Kept</p>")
            }

            let outcome = try await pipeline.refresh(userID: userID, feedID: feedID)

            let written = try #require(outcome.newEntryHashes.first)
            #expect(outcome.updatedEntryHashes.isEmpty)

            // The entry the document stopped declaring is still there, with the
            // state it had: only a delete could remove it, and the reference's
            // processor does not run one.
            #expect(try await entryCount(storage, feedID: feedID) == 2)
            #expect(try await storedHashes(storage, feedID: feedID) == ["kept", written])
            #expect(try await statusOf(storage, feedID: feedID, hash: "kept") == "unread")
        }
    }

    @Test func aTombstonedEntryNeverResurfacesThroughRefresh() async throws {
        try await withCase(behaviors: ["/feed": answer(rss([
            ("<p>Once archived</p>", "https://example.org/archived"),
        ]))]) { storage, userID, feedID, pipeline in
            let first = try await pipeline.refresh(userID: userID, feedID: feedID)
            let hash = try #require(first.newEntryHashes.first)
            #expect(try await entryCount(storage, feedID: feedID) == 1)

            // The daily cleanup is the reference's `ArchiveEntries`: it deletes the row and records
            // the tombstone for the same `(feed_id, hash)`, in one transaction.
            let archived = try await storage.withTransaction { connection in
                try await EntryRepository(connection).archive(status: .unread,
                    createdBefore: Int(Date.now.timeIntervalSince1970) + 1, limit: 100)
            }
            #expect(archived == 1)
            #expect(try await entryCount(storage, feedID: feedID) == 0)

            // The forced path sends no stored validators, so the answer cannot be a
            // conditional hit and the entry loop runs at all. Once the row is gone, any
            // modified answer reaches the insert branch, and the document declares the same
            // entry, which computes the same hash. The guard is the rule the pin reads.
            let second = try await pipeline.refresh(userID: userID, feedID: feedID,
                forceRefresh: true)
            #expect(second.newEntryHashes.isEmpty)
            #expect(second.updatedEntryHashes.isEmpty)
            #expect(try await entryCount(storage, feedID: feedID) == 0)
            #expect(try await tombstoneCount(storage, feedID: feedID, hash: hash) == 1)
        }
    }

    // MARK: - Helpers

    /// One case: the server answers each path, the feed row points at `/feed`, and the test reads
    /// what the pipeline stored. The connection is not held across `refresh`, because the pipeline
    /// opens its own single write transaction and a held checkout would nest a second one.
    private func withCase(
        behaviors: [String: StubFeedServer.Behavior],
        _ body: (SQLiteStorage, Int, Int, RefreshPipeline) async throws -> Void
    ) async throws {
        let options = FetchTestSupport.options()
        try await withMigratedStorage { _, storage in
            try await FetchTestSupport.withServer(behaviors: behaviors) { server in
                try await FetchTestSupport.withFetcher(options: options) { fetcher in
                    let (userID, _, feedID) = try await storage.withConnection { connection in
                        try await seedFeed(connection, feedURL: server.url("/feed").absoluteString)
                    }
                    let pipeline = RefreshPipeline(storage: storage, fetcher: fetcher,
                        options: options, nextCheck: policy, clock: FixedClock(now: now))
                    try await body(storage, userID, feedID, pipeline)
                }
            }
        }
    }

    private func rss(_ entries: [(content: String, url: String)]) -> String {
        var document = "<rss version=\"2.0\"><channel><title>T</title>"
        for entry in entries {
            let text = entry.content.replacing("<", with: "&lt;").replacing(">", with: "&gt;")
            document += "<item><title>E</title><link>\(entry.url)</link>"
                + "<description>\(text)</description></item>"
        }
        return document + "</channel></rss>"
    }

    private func answer(_ body: String) -> StubFeedServer.Behavior {
        StubFeedServer.Behavior(body: Data(body.utf8))
    }

    private func entryCount(_ storage: SQLiteStorage, feedID: Int) async throws -> Int {
        try await readCount(storage, """
            SELECT COUNT(*) AS n FROM entries WHERE feed_id = \(bind: feedID)
            """)
    }

    private func tombstoneCount(_ storage: SQLiteStorage, feedID: Int, hash: String)
        async throws -> Int {
        try await readCount(storage, """
            SELECT COUNT(*) AS n FROM entry_tombstones
            WHERE feed_id = \(bind: feedID) AND hash = \(bind: hash)
            """)
    }

    private func readCount(_ storage: SQLiteStorage, _ query: SQLQueryString) async throws
        -> Int {
        try await storage.withConnection { connection in
            let row = try await sqlDatabase(connection).raw(query).first()
            return try row?.decode(column: "n", as: Int.self) ?? 0
        }
    }

    private func storedHashes(_ storage: SQLiteStorage, feedID: Int) async throws -> [String] {
        try await storage.withConnection { connection in
            let rows = try await sqlDatabase(connection).raw("""
                SELECT hash FROM entries WHERE feed_id = \(bind: feedID) ORDER BY id
                """).all()
            return try rows.map { try $0.decode(column: "hash", as: String.self) }
        }
    }

    private func statusOf(_ storage: SQLiteStorage, feedID: Int, hash: String) async throws
        -> String {
        try await storage.withConnection { connection in
            let row = try await sqlDatabase(connection).raw("""
                SELECT status FROM entries WHERE feed_id = \(bind: feedID) AND hash = \(bind: hash)
                """).first()
            return try #require(row).decode(column: "status", as: String.self)
        }
    }
}
