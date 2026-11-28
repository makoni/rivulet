import FluentKit
import Foundation
import SQLKit
import Testing
import Vapor
@testable import RivuletApp
@testable import RivuletCore

/// The write paths of `RestV1FeedRouteTests`: the update, the delete, the icon read, the refresh and
/// the mark-all-as-read write. What each pin can fail on is listed on the suite.
extension RestV1FeedRouteTests {
    @Test func theUpdatePatchesOnlyTheFieldsTheRequestCarries() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                _ = try await FeedRepository(connection).create(userID: alice, categoryID: 1,
                    url: "https://example.com/kept")
            }

            let response = try await request(app, base, method: .PUT, path: "/v1/feeds/1",
                body: "{\"title\":\"Renamed\"}")
            #expect(response.status == .created, "the status the update path writes")
            #expect(try body(of: response) == feedDocument(id: 1, url: "https://example.com/kept",
                title: "Renamed", errorCount: 0),
                "the field the request carried, and the url left as the row had it")
        }
    }

    @Test func theUpdateResetsTheErrorCounterBeforeItWrites() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                _ = try await FeedRepository(connection).create(userID: alice, categoryID: 1,
                    url: "https://example.com/kept")
                try await setFeedTitle(connection, id: 1, title: "Kept", errorCount: 5,
                    errorMessage: "boom")
            }

            let response = try await request(app, base, method: .PUT, path: "/v1/feeds/1",
                body: "{\"title\":\"Renamed\"}")
            #expect(try body(of: response) == feedDocument(id: 1, url: "https://example.com/kept",
                title: "Renamed", errorCount: 0),
                "the counter and the message the reset clears, written as the reset left them")
            #expect(try await feedErrorCount(storage, userID: 1, id: 1) == 0,
                "and the row carries the reset, not the value it had")
        }
    }

    @Test func theUpdateAnswersTheDocumentFromTheRowAfterTheWrite() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                _ = try await FeedRepository(connection).create(userID: alice, categoryID: 1,
                    url: "https://example.com/kept")
            }

            // The document is built from the row as it is after the write, so the answer carries the
            // patched title. A patch that answered the row as it was read answered the title the row
            // had before the patch.
            let response = try await request(app, base, method: .PUT, path: "/v1/feeds/1",
                body: "{\"title\":\"Renamed\"}")
            #expect(try body(of: response).contains("\"title\":\"Renamed\""),
                "the document reads the row after the write, not the value before it")
            #expect(try await feedTitle(storage, userID: 1, id: 1) == "Renamed",
                "and the write ran before the document was built")
        }
    }

    @Test func theDeleteAnswersNoContentForTheRowOfTheAccountItIsGiven() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                let bob = try #require(try await UserRepository(connection)
                    .create(username: "bob", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                _ = try await FeedRepository(connection).create(userID: alice, categoryID: 1,
                    url: "https://example.com/mine")
                _ = try await FeedRepository(connection).create(userID: bob, categoryID: 2,
                    url: "https://example.com/bob")
            }

            // The pair is read before the write, so another account's row with this id answers 404 and
            // stays where it is. The patch that fires here takes the account out of both the guard's
            // read and the statement that writes.
            let other = try await request(app, base, method: .DELETE, path: "/v1/feeds/2")
            #expect(other.status == .notFound, "the pair, not the id alone")
            #expect(try await feedURL(storage, userID: 2, id: 2) == "https://example.com/bob",
                "and the row the guard did not read is still there")

            let mine = try await request(app, base, method: .DELETE, path: "/v1/feeds/1")
            #expect(mine.status == .noContent, "the status the delete path writes")
            #expect(try await feedURL(storage, userID: 1, id: 1) == nil,
                "and the row of the account the guard read is gone")
        }
    }

    @Test func theIconReadIsGuardedByTheAccountAndAnswersTheThreeKeysInOrder() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                let bob = try #require(try await UserRepository(connection)
                    .create(username: "bob", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                let aliceFeed = try #require(try await FeedRepository(connection)
                    .create(userID: alice, categoryID: 1, url: "https://example.com/a").id)
                let bobFeed = try #require(try await FeedRepository(connection)
                    .create(userID: bob, categoryID: 2, url: "https://example.com/bob").id)
                let icon = try #require(try await IconRepository(connection)
                    .insert(hash: "h-icon", mimeType: "image/png", content: Data([0x89])).id)
                // The icon row is shared by both feeds, which is the reference's dedup by content hash.
                try await IconRepository(connection).link(feedID: bobFeed, iconID: icon)
                try await IconRepository(connection).link(feedID: aliceFeed, iconID: icon)
                // A feed of this account with no mapping row, so the read has nothing to answer.
                _ = try await FeedRepository(connection).create(userID: alice, categoryID: 1,
                    url: "https://example.com/no-icon")
            }

            // The join is guarded by the account, so a row of another account with this id answers 404.
            let other = try await request(app, base, method: .GET, path: "/v1/feeds/2/icon")
            #expect(other.status == .notFound, "the pair, not the id alone")

            // A feed with no mapping row answers 404, which is what the reference's scan answers when
            // it finds nothing there.
            let none = try await request(app, base, method: .GET, path: "/v1/feeds/3/icon")
            #expect(none.status == .notFound, "no mapping row, so no document")

            let response = try await request(app, base, method: .GET, path: "/v1/feeds/1/icon")
            #expect(response.status == .ok, "the registered path answers the read")
            #expect(try body(of: response) ==
                "{\"id\":1,\"mime_type\":\"image/png\",\"data\":\"image/png;base64,iQ==\"}",
                "the three keys, in the order the reference's response struct declares them")
        }
    }

    @Test func theRefreshReadsThePairBeforeItRunsTheFetch() async throws {
        let recording = RecordingRunner()
        try await withServedApp(runner: recording) { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                _ = try await FeedRepository(connection).create(userID: alice, categoryID: 1,
                    url: "https://example.com/a")
            }

            // The pair is read before the fetch runs, so a request for a row that is not there
            // answers 404 and the runner is never reached. A patch that ran the fetch first
            // reached it here.
            let missing = try await request(app, base, method: .PUT, path: "/v1/feeds/9/refresh")
            #expect(missing.status == .notFound, "the pair is read before the fetch runs")
            #expect(await recording.calls.isEmpty, "and the fetch was not reached for that request")

            let response = try await request(app, base, method: .PUT, path: "/v1/feeds/1/refresh")
            #expect(response.status == .noContent, "the status the refresh path writes")
            #expect(await recording.calls == [1], "the fetch runs for the row the guard read")
        }
    }

    @Test func theMarkWriteAnswersNoContentForTheRowsOfTheFeedAndAccountItIsGiven() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                let bob = try #require(try await UserRepository(connection)
                    .create(username: "bob", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                _ = try await FeedRepository(connection).create(userID: alice, categoryID: 1,
                    url: "https://example.com/a")
                _ = try await FeedRepository(connection).create(userID: alice, categoryID: 1,
                    url: "https://example.com/other")
                // The three conditions the statement has: the account, the feed, and the status. The
                // row of another account sits in this account's feed, so a patch that took the account
                // condition out of the statement wrote it here; the row of another feed of this account
                // shows the feed condition.
                try await seedEntry(connection, userID: alice, feedID: 1, hash: "h-alice",
                    status: "unread")
                try await seedEntry(connection, userID: alice, feedID: 2, hash: "h-other",
                    status: "unread")
                try await seedEntry(connection, userID: bob, feedID: 1, hash: "h-bob",
                    status: "unread")
            }

            let response = try await request(app, base, method: .PUT, path: "/v1/feeds/1/mark-all-as-read")
            #expect(response.status == .noContent, "the status the write path writes")
            #expect(try await entryStatus(storage, userID: 1, hash: "h-alice") == "read",
                "the rows of the feed the segment names")
            #expect(try await entryStatus(storage, userID: 1, hash: "h-other") == "unread",
                "and not the rows of another feed of the same account")
            #expect(try await entryStatus(storage, userID: 2, hash: "h-bob") == "unread",
                "and not the rows of another account")

            // The pair is read before the write, so a request for a row that is not there answers the
            // row's answer and nothing is written.
            let missing = try await request(app, base, method: .PUT, path: "/v1/feeds/9/mark-all-as-read")
            #expect(missing.status == .notFound, "the pair, read before the write")
            #expect(try await entryStatus(storage, userID: 1, hash: "h-alice") == "read",
                "and the write ran only for the row the guard read")
        }
    }
}
