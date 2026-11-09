import Foundation
import Fluent
import SQLKit
import Testing
@testable import RivuletApp
@testable import RivuletCore

/// The three write handlers, over a real socket: `handleWriteItems`, `handleWriteFeeds` and
/// `handleWriteGroups` of `internal/fever/handler.go` at `c4d54f87`. The rows are written through
/// SQL and read back through SQL, so a pin is not satisfied by the read it is testing.
///
/// The rows are written on one connection, the request runs after that connection goes back to the
/// pool, and the read back opens its own, because the driver keeps a single pooled connection and a
/// pin cannot hold one while the handler checks out another.
///
/// What these pins can fail on, each checked by patching the rule and reverting (4 pins, 11 probes:
/// 2 on the guards, 4 on the item switch, 2 on the feed branch, 3 on the group guard): the guards
/// that write nothing at all — the handler returns before the response builder runs, so the answer
/// is an empty body at 200 with no content type, which a patch that answered the base document
/// fails on, and the value the integer read cannot read is the zero the guard reads; the two
/// branches of the item switch that write the status and the two that flip the starred flag, which
/// a patch that read the wrong value for one of them fails on, and the switch with no default case,
/// which a patch that wrote something for an unknown value fails on; that the row the read does not
/// find answers the base document without writing; that the `as` name is not read on the feed
/// branch, which a patch that read it there fails on; that the comparison is strictly before, so a
/// row published exactly at the instant is left alone; and the three branches of the group guard —
/// below zero writes nothing, which a patch that read the sign as part of the value fails on, zero
/// marks every row whatever the instant is, and a value marks the rows of that category before the
/// instant, which a patch that read the user-wide write for that branch fails on.
///
/// What these pins cannot show: the reference's `go func()` that sends the entry to the integration
/// settings after a `saved` write, which this port has no layer for; the transaction boundary the
/// write path runs inside; the wording of a storage failure this suite cannot trigger; and the
/// clock field, read through the placeholder the request helper names.
@Suite struct FeverWriteTests {
    init() {
        TestLogging.bootstrapOnce()
    }

    @Test func theGuardsWriteNothingAndAnswerAnEmptyBodyAtTwoHundred() async throws {
        try await withServedApp { storage, app, base in
            let requests = FeverRequests(app, base)
            let (userID, token) = try await requests.seed(storage, name: "alice", password: "secret")

            // `FormInt64Value` answers 0 for a value it cannot read, and the guard reads that
            // value: the handler returns before the response builder runs, so nothing is written at
            // all. A patch that answered the base document failed on the body and on the
            // content type.
            for query in ["api&mark=item&id=0", "api&mark=item", "api&mark=item&id=abc"] {
                let response = try await requests.get("api&api_key=\(token)&" + query)
                #expect(response.status == .ok, "the status is 200")
                #expect(requests.body(of: response) == "", "nothing is written for the guard")
                #expect(requests.contentType(of: response) == "", "and the response builder never ran")
            }

            // The same guard read from a part, which is the shape the acceptance client sends, and
            // the row it names is left as it was.
            let fromPart = try await requests.postParts("api&api_key=\(token)",
                [(name: "mark", value: "item"), (name: "id", value: "0")])
            #expect(requests.body(of: fromPart) == "", "the name comes from the part")

            let entry = try await storage.withConnection { connection in
                let category = try await seedCategory(connection, userID: userID, title: "Tech")
                let feed = try await seedFeed(connection, userID: userID, categoryID: category,
                    url: "https://e/1")
                return try await seedEntry(connection, userID: userID, feedID: feed, hash: "1")
            }
            #expect(try await statusOf(storage, entry) == "unread", "the guard left the row as it was")
        }
    }

    @Test func theItemSwitchWritesTheStatusAndFlipsTheStarredFlag() async throws {
        try await withServedApp { storage, app, base in
            let requests = FeverRequests(app, base)
            let (userID, token) = try await requests.seed(storage, name: "alice", password: "secret")

            let (entry, missing) = try await storage.withConnection { connection in
                let category = try await seedCategory(connection, userID: userID, title: "Tech")
                let feed = try await seedFeed(connection, userID: userID, categoryID: category,
                    url: "https://e/1")
                let entry = try await seedEntry(connection, userID: userID, feedID: feed, hash: "1")
                let missing = try await seedEntry(connection, userID: userID, feedID: feed, hash: "2")
                return (entry, missing)
            }

            func answer(_ state: String, _ id: Int) async throws -> String {
                let response = try await requests.postParts("api&api_key=\(token)",
                    [(name: "mark", value: "item"), (name: "as", value: state),
                        (name: "id", value: String(id))])
                return requests.document(of: response)
            }

            #expect(try await answer("read", entry) ==
                FeverShape.baseDocument(authenticated: 1, lastRefreshed: 0).written(),
                "the answer the switch ends with")
            #expect(try await statusOf(storage, entry) == "read", "the status the branch writes")

            // The switch has no default case, so a value it does not have writes nothing and
            // answers the same document.
            #expect(try await answer("anything", entry) ==
                FeverShape.baseDocument(authenticated: 1, lastRefreshed: 0).written(),
                "the branch that is not in the switch")
            #expect(try await statusOf(storage, entry) == "read", "and nothing was written for it")

            // A row the read does not find answers the base document without writing: the row
            // below the guard is left as it was, which is what a patch that wrote before the
            // read fails on.
            #expect(try await answer("unread", 9_000) ==
                FeverShape.baseDocument(authenticated: 1, lastRefreshed: 0).written(),
                "the row the read does not find")
            #expect(try await statusOf(storage, missing) == "unread", "and its state is left alone")

            // The two toggle branches, read on the same row: the first sets the flag, the
            // second flips it back, so a patch that set the flag for both failed here.
            #expect(try await answer("saved", missing) ==
                FeverShape.baseDocument(authenticated: 1, lastRefreshed: 0).written(), "the saved branch")
            #expect(try await starredOf(storage, missing) == 1, "the flag set")
            #expect(try await answer("unsaved", missing) ==
                FeverShape.baseDocument(authenticated: 1, lastRefreshed: 0).written(), "the unsaved branch")
            #expect(try await starredOf(storage, missing) == 0, "and flipped back")
        }
    }

    @Test func theFeedBranchDoesNotReadTheStateNameAndComparesStrictlyBefore() async throws {
        try await withServedApp { storage, app, base in
            let requests = FeverRequests(app, base)
            let (userID, token) = try await requests.seed(storage, name: "alice", password: "secret")

            let (feed, before, exactly, other) = try await storage.withConnection { connection in
                let category = try await seedCategory(connection, userID: userID, title: "Tech")
                let feed = try await seedFeed(connection, userID: userID, categoryID: category,
                    url: "https://e/1")
                let before = try await seedEntry(connection, userID: userID, feedID: feed, hash: "1",
                    publishedAt: 100)
                let exactly = try await seedEntry(connection, userID: userID, feedID: feed, hash: "2",
                    publishedAt: 200)
                let other = try await seedEntry(connection, userID: userID, feedID: feed, hash: "3",
                    publishedAt: 300)
                return (feed, before, exactly, other)
            }

            // `as` is not read on this branch: the part carries a value the item switch would
            // have used, and the write is still the status read.
            let response = try await requests.postParts("api&api_key=\(token)",
                [(name: "mark", value: "feed"), (name: "as", value: "saved"),
                    (name: "id", value: String(feed)), (name: "before", value: "200")])
            #expect(requests.document(of: response) ==
                FeverShape.baseDocument(authenticated: 1, lastRefreshed: 0).written(), "the answer")
            #expect(try await statusOf(storage, before) == "read", "the row before the instant")
            #expect(try await statusOf(storage, exactly) == "unread",
                "the comparison is strictly before, so the row at the instant is left alone")
            #expect(try await starredOf(storage, before) == 0, "and the name was not read here")
            #expect(try await statusOf(storage, other) == "unread", "a row after the instant is left")

            // The guard reads a value below zero as itself, not as the zero the read answers.
            let guardAnswer = try await requests.postParts("api&api_key=\(token)",
                [(name: "mark", value: "feed"), (name: "id", value: "-1"), (name: "before", value: "500")])
            #expect(requests.body(of: guardAnswer) == "", "the guard for a value below zero")
        }
    }

    @Test func theGroupGuardMarksEverythingForTheZeroAndIgnoresTheInstant() async throws {
        try await withServedApp { storage, app, base in
            let requests = FeverRequests(app, base)
            let (userID, token) = try await requests.seed(storage, name: "alice", password: "secret")

            let (first, inside, outside) = try await storage.withConnection { connection in
                let first = try await seedCategory(connection, userID: userID, title: "First")
                let second = try await seedCategory(connection, userID: userID, title: "Second")
                let firstFeed = try await seedFeed(connection, userID: userID, categoryID: first,
                    url: "https://e/1")
                let secondFeed = try await seedFeed(connection, userID: userID, categoryID: second,
                    url: "https://e/2")
                let inside = try await seedEntry(connection, userID: userID, feedID: firstFeed, hash: "1",
                    publishedAt: 300)
                let outside = try await seedEntry(connection, userID: userID, feedID: secondFeed, hash: "2",
                    publishedAt: 400)
                return (first, inside, outside)
            }

            // The reference marks the rows of this category before the instant; a patch that
            // read the instant for the zero branch would have left the row after it unread.
            let categoryAnswer = try await requests.postParts("api&api_key=\(token)",
                [(name: "mark", value: "group"), (name: "id", value: String(first)),
                    (name: "before", value: "350")])
            #expect(requests.document(of: categoryAnswer) ==
                FeverShape.baseDocument(authenticated: 1, lastRefreshed: 0).written(),
                "the category branch answers the base document")
            #expect(try await statusOf(storage, inside) == "read", "the row of that category")
            #expect(try await statusOf(storage, outside) == "unread", "and not the row of another")

            // Zero is the user-wide write, whatever the instant names: the row after it is
            // written too.
            let zeroAnswer = try await requests.postParts("api&api_key=\(token)",
                [(name: "mark", value: "group"), (name: "id", value: "0"), (name: "before", value: "350")])
            #expect(requests.document(of: zeroAnswer) ==
                FeverShape.baseDocument(authenticated: 1, lastRefreshed: 0).written(), "the zero branch")
            #expect(try await statusOf(storage, outside) == "read", "the row after the instant is written")

            // Below zero writes nothing, and a value the read cannot read is the zero, which is
            // the user-wide branch — not the guard.
            let nothing = try await requests.postParts("api&api_key=\(token)",
                [(name: "mark", value: "group"), (name: "id", value: "-1"), (name: "before", value: "500")])
            #expect(requests.body(of: nothing) == "", "below zero writes nothing")

            // The row the user-wide branch would write is put back to its first state, so the
            // second request has a row to write.
            try await storage.withConnection { connection in
                try await sqlDatabase(connection)
                    .raw("UPDATE entries SET status = 'unread' WHERE id = \(bind: inside)").run()
            }
            let unparsed = try await requests.postParts("api&api_key=\(token)",
                [(name: "mark", value: "group"), (name: "id", value: "x"), (name: "before", value: "350")])
            #expect(requests.document(of: unparsed) ==
                FeverShape.baseDocument(authenticated: 1, lastRefreshed: 0).written(),
                "the value the read cannot read is the zero")
            #expect(try await statusOf(storage, inside) == "read", "so the user-wide branch ran")
        }
    }

    private func statusOf(_ storage: SQLiteStorage, _ id: Int) async throws -> String {
        try await storage.withConnection { connection in
            try await statusOf(connection, id)
        }
    }

    private func starredOf(_ storage: SQLiteStorage, _ id: Int) async throws -> Int {
        try await storage.withConnection { connection in
            try await starredOf(connection, id)
        }
    }

    private func statusOf(_ connection: any Database, _ id: Int) async throws -> String {
        let row = try await sqlDatabase(connection).raw("SELECT status FROM entries WHERE id = \(bind: id)")
            .first()
        return try row?.decode(column: "status", as: String.self) ?? ""
    }

    private func starredOf(_ connection: any Database, _ id: Int) async throws -> Int {
        let row = try await sqlDatabase(connection).raw("SELECT starred FROM entries WHERE id = \(bind: id)")
            .first()
        return try row?.decode(column: "starred", as: Int.self) ?? -1
    }
}
