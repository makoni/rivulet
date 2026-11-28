import Foundation
import Testing
import Vapor
import RivuletApp
@testable import RivuletCore

/// The `mark-all-as-read` half of `GoogleReaderWriteHandlerTests`. What each pin can fail on is listed
/// on the suite.
extension GoogleReaderWriteHandlerTests {
    @Test func markAllAsReadWritesNothingForTheTypesTheReferenceSwitchHasNoCaseFor() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            let userID = try await requests.seedIntegrationUser(storage, name: "alice",
                storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "alice", storedHash: storedHash)
            let header = "GoogleLogin auth=\(token)"

            let entryID = try await storage.withConnection { connection in
                let categoryID = try await seedCategory(connection, userID: userID, title: "Tech")
                let feedID = try await seedFeed(connection, userID: userID, categoryID: categoryID,
                    url: "https://example.com/1")
                return try await seedEntry(connection, userID: userID, feedID: feedID, hash: "h1",
                    publishedAt: 200)
            }

            // The reference's switch has three cases, so a type it does not handle falls through
            // and writes nothing. A patch that answered the reading-list rule for these types
            // marked the entry.
            for type in ["like", "broadcast", "broadcast-friends", "kept-unread", "starred"] {
                let response = try await requests.post(catchAll + "mark-all-as-read",
                    raw: requests.body(token: token, pairs: ["s=\(state)\(type)"]), header: header)
                #expect(response.status == .ok, "the handler answers OK for a type it does not handle")
                #expect(try requests.body(of: response) == "OK")
                #expect(try await storedStatus(storage, entryID: entryID) == .unread,
                    "writing nothing for \(type)")
            }

            // An empty value is the no-stream type, which is also a branch the switch does not
            // have.
            let empty = try await requests.post(catchAll + "mark-all-as-read",
                raw: requests.body(token: token, pairs: ["s="]), header: header)
            #expect(empty.status == .ok)
            #expect(try await storedStatus(storage, entryID: entryID) == .unread,
                "the empty value is not an error for this read")
        }
    }

    @Test func markAllAsReadKeepsTheStreamReadErrorItsOwnAndMapsTheIntegerReadToBadRequest() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            let userID = try await requests.seedIntegrationUser(storage, name: "alice",
                storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "alice", storedHash: storedHash)
            let header = "GoogleLogin auth=\(token)"

            let entryID = try await storage.withConnection { connection in
                let categoryID = try await seedCategory(connection, userID: userID, title: "Tech")
                let feedID = try await seedFeed(connection, userID: userID, categoryID: categoryID,
                    url: "https://example.com/1")
                return try await seedEntry(connection, userID: userID, feedID: feedID, hash: "h1",
                    publishedAt: 200)
            }

            // This handler does not wrap the read error with the parameter name: that is what the
            // two tag handlers do, and the pin for it is in the rename suite.
            let stream = try await requests.post(catchAll + "mark-all-as-read",
                raw: requests.body(token: token, pairs: ["s=bogus"]), header: header)
            #expect(try requests.body(of: stream) ==
                "{\"error_message\":\"googlereader: unknown stream type: bogus\"}")

            // The integer read, not the stream read's hex form, and 400 here where the same read
            // answers 500 for `stream/items/ids`.
            let parsed = try await requests.post(catchAll + "mark-all-as-read",
                raw: requests.body(token: token, pairs: ["s=feed/x"]), header: header)
            #expect(parsed.status == .badRequest, "the status this handler maps this error to")
            #expect(try requests.body(of: parsed) ==
                "{\"error_message\":\"strconv.ParseInt: parsing \\\"x\\\": invalid syntax\"}")

            // A feed id of 0 is used as read, so the write selects nothing rather than every feed.
            let zero = try await requests.post(catchAll + "mark-all-as-read",
                raw: requests.body(token: token, pairs: ["s=feed/0"]), header: header)
            #expect(zero.status == .ok)
            #expect(try await storedStatus(storage, entryID: entryID) == .unread,
                "no row has id 0, so the read selects nothing")

            // The `s` value the merged form gave, read as the reference reads it.
            let merged = try await requests.post(catchAll + "mark-all-as-read",
                raw: requests.body(token: token, pairs: ["s=user/-/label/Nope"]), header: header)
            #expect(merged.status == .notFound, "the label branch answers the 404 shape")
            #expect(try requests.body(of: merged) == "{\"error_message\":\"resource not found\"}")
        }
    }

    @Test func markAllAsReadTsLengthDecidesTheUnitAndTheComparisonIsStrict() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            let userID = try await requests.seedIntegrationUser(storage, name: "alice",
                storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "alice", storedHash: storedHash)
            let header = "GoogleLogin auth=\(token)"

            let (feedID, beforeID, exactlyID) = try await storage.withConnection { connection in
                let categoryID = try await seedCategory(connection, userID: userID, title: "Tech")
                let feed = try await seedFeed(connection, userID: userID, categoryID: categoryID,
                    url: "https://example.com/1")
                let before = try await seedEntry(connection, userID: userID, feedID: feed, hash: "h1",
                    publishedAt: 200)
                let exactly = try await seedEntry(connection, userID: userID, feedID: feed, hash: "h2",
                    publishedAt: 1_000_000_000)
                return (feed, before, exactly)
            }

            // Sixteen characters are microseconds: 1e15 is the second 1_000_000_000, so the row
            // published at that second is not marked, which is the strict comparison.
            let micro = try await requests.post(catchAll + "mark-all-as-read",
                raw: requests.body(token: token, pairs: ["s=feed/\(feedID)", "ts=1000000000000000"]),
                header: header)
            #expect(micro.status == .ok)
            #expect(try await storedStatus(storage, entryID: beforeID) == .read,
                "the entry before the boundary is marked")
            #expect(try await storedStatus(storage, entryID: exactlyID) == .unread,
                "the entry at the boundary is not, because the comparison is strictly before")

            // The same digits one character shorter are seconds, which puts the boundary far ahead
            // and marks both rows.
            let seconds = try await requests.post(catchAll + "mark-all-as-read",
                raw: requests.body(token: token, pairs: ["s=feed/\(feedID)", "ts=100000000000000"]),
                header: header)
            #expect(seconds.status == .ok)
            #expect(try await storedStatus(storage, entryID: exactlyID) == .read,
                "the same digits one character shorter take the seconds branch")
        }
    }

    @Test func markAllAsReadDefaultIsTheTimeTheHandlerRunsAtAndTheSignGuardIsWhatLeavesIt() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            let userID = try await requests.seedIntegrationUser(storage, name: "alice",
                storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "alice", storedHash: storedHash)
            let header = "GoogleLogin auth=\(token)"

            // Each rule reads its own feed, so a request that marks the whole feed cannot mark the
            // row another assertion reads.
            let (zeroFeed, zeroRow, negativeFeed, negativeRow, defaultFeed, futureRow) =
                try await storage.withConnection { connection in
                    let categoryID = try await seedCategory(connection, userID: userID, title: "Tech")
                    let zeroFeed = try await seedFeed(connection, userID: userID, categoryID: categoryID,
                        url: "https://example.com/1")
                    let negativeFeed = try await seedFeed(connection, userID: userID,
                        categoryID: categoryID, url: "https://example.com/2")
                    let defaultFeed = try await seedFeed(connection, userID: userID,
                        categoryID: categoryID, url: "https://example.com/3")
                    let zero = try await seedEntry(connection, userID: userID, feedID: zeroFeed,
                        hash: "h1", publishedAt: 200)
                    let negative = try await seedEntry(connection, userID: userID, feedID: negativeFeed,
                        hash: "h2", publishedAt: 200)
                    let future = try await seedEntry(connection, userID: userID, feedID: defaultFeed,
                        hash: "h3", publishedAt: nowInSeconds() + 3_600)
                    return (zeroFeed, zero, negativeFeed, negative, defaultFeed, future)
                }

            // The guard's presence is what keeps the default for an unpositive value: without it
            // the boundary is the parsed value, which is in the past and marks nothing. The order
            // of the guard and the length test is not pinned, because a patch that ran the length
            // test first answers the same for a negative value.
            let zero = try await requests.post(catchAll + "mark-all-as-read",
                raw: requests.body(token: token, pairs: ["s=feed/\(zeroFeed)", "ts=0"]), header: header)
            #expect(zero.status == .ok)
            #expect(try await storedStatus(storage, entryID: zeroRow) == .read,
                "the guard leaves the default for zero, where the length test would have answered 0")

            let negative = try await requests.post(catchAll + "mark-all-as-read",
                raw: requests.body(token: token,
                    pairs: ["s=feed/\(negativeFeed)", "ts=-10000000000000000"]), header: header)
            #expect(negative.status == .ok)
            #expect(try await storedStatus(storage, entryID: negativeRow) == .read,
                "the guard leaves the default on the negative side too")

            // The default itself, on a feed that reads nothing else. The row is published after the
            // time the handler runs at, so the default does not reach it; a patch that used a fixed
            // time in the future marked it, which is what this assertion fails on.
            let absent = try await requests.post(catchAll + "mark-all-as-read",
                raw: requests.body(token: token, pairs: ["s=feed/\(defaultFeed)"]), header: header)
            #expect(absent.status == .ok)
            #expect(try await storedStatus(storage, entryID: futureRow) == .unread,
                "the default is the time the handler runs at, which is earlier than this row")
        }
    }

    @Test func markAllAsReadLabelBranchMarksTheFeedsOfItsRowAndReadingListMarksEveryFeed() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            let userID = try await requests.seedIntegrationUser(storage, name: "alice",
                storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "alice", storedHash: storedHash)
            let header = "GoogleLogin auth=\(token)"

            let (labelled, other) = try await storage.withConnection { connection in
                let techID = try await seedCategory(connection, userID: userID, title: "Tech")
                let newsID = try await seedCategory(connection, userID: userID, title: "News")
                let techFeed = try await seedFeed(connection, userID: userID, categoryID: techID,
                    url: "https://example.com/1")
                let newsFeed = try await seedFeed(connection, userID: userID, categoryID: newsID,
                    url: "https://example.com/2")
                let first = try await seedEntry(connection, userID: userID, feedID: techFeed, hash: "h1",
                    publishedAt: 200)
                let second = try await seedEntry(connection, userID: userID, feedID: newsFeed, hash: "h2",
                    publishedAt: 200)
                return (first, second)
            }

            let label = try await requests.post(catchAll + "mark-all-as-read",
                raw: requests.body(token: token, pairs: ["s=user/-/label/Tech", "ts=300"]), header: header)
            #expect(label.status == .ok)
            #expect(try await storedStatus(storage, entryID: labelled) == .read,
                "the label branch reaches the entry through its category")
            #expect(try await storedStatus(storage, entryID: other) == .unread,
                "the read joins the feeds of the same user")

            // A patch that read the whole user for the label branch left the label row for the
            // other entry, so the reading-list branch has to be shown on its own: it marks every
            // feed.
            let reading = try await requests.post(catchAll + "mark-all-as-read",
                raw: requests.body(token: token,
                    pairs: ["s=\(state)reading-list", "ts=300"]), header: header)
            #expect(reading.status == .ok)
            #expect(try await storedStatus(storage, entryID: other) == .read,
                "the reading-list branch has no feed filter")
        }
    }
}
