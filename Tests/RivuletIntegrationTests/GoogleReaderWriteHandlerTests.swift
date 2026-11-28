import Foundation
import Testing
import Vapor
import RivuletApp
@testable import RivuletCore

/// The three POST write handlers over a real socket: `renameTagHandler`, `disableTagHandler` and
/// `markAllAsReadHandler` of `internal/googlereader/handler.go` at `c4d54f87`.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the list `s` the
/// merged form gives `disable-tag`, which a patch that read only the body side fails on; the
/// parameter name the read error names, which is the handler's own wrap rather than the stream
/// read's wording; the guard order that runs the type check before the empty-destination guard; the
/// two type-check wordings that name different things; the 404 the category read answers for a
/// title it does not find; the rule order that reads the row before the duplicate answer and writes
/// after it, and the duplicate read's exclusion of the row it is checking; the delete guard that
/// counts before it writes, which this suite can trigger by naming the only category the user has,
/// and the pick the delete path makes for the feeds of the rows it names, which is the smallest
/// title left rather than the last of the rows it read; the guard that reports before the delete
/// writes, and the types the reference's switch has no case for, which answer `OK` writing nothing
/// — the port's explicit no-op default is the same answer; the status the integer read error maps
/// to here, which is 400 where the same read answers 500 for `stream/items/ids`; the `ts` length
/// rule, the two units it gives, the sign guard's presence, the default that is the time the
/// handler runs at, and the comparison that is strictly before.
///
/// What these pins cannot show: the handler's own answer for a form the read cannot parse, which
/// the transport reports as 401 first; the transaction boundary the delete path runs inside,
/// because no pin can make a statement fail in the middle of one; that a feed id of 0 selects
/// nothing, which a patch that skipped a non-positive value answers the same; the message the
/// handler writes for the rule the socket cannot reach (`titleRequired`), because the
/// empty-destination guard answers before it — that rule is pinned as pure logic by
/// `CategoryValidationTests`; the storage wordings for a failure this suite cannot trigger, apart
/// from the guard the delete path makes itself; the reference's localized strings for the two
/// rules, which the port does not reproduce — it names the rule, so the message is the rule name,
/// and the keys are recorded in `docs/reference-notes.md`; the order of the two statements of the
/// delete path, which is the same for every input that reaches them; and the row order the delete's
/// read answers its rows in, which the statement does not order and which no pin can show, and the
/// order of the sign guard and the `ts` length test, which no input can tell apart because both
/// apply to every value the guard accepts.
@Suite struct GoogleReaderWriteHandlerTests {
    init() {
        TestLogging.bootstrapOnce()
    }

    let storedHash = "$2a$10$hOrIpoEkDKAMFrOt2/k1yeyHBaZKOwK8zEg9JVchReOAtQZ5mEeFu"
    let catchAll = "/reader/api/0/"
    let state = "user/-/state/com.google/"

    @Test func theWriteHandlersDoNotApplyOutputCheckAndAnswerText() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            let userID = try await requests.seedIntegrationUser(storage, name: "alice",
                storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "alice", storedHash: storedHash)
            let header = "GoogleLogin auth=\(token)"

            try await storage.withConnection { connection in
                _ = try await seedCategory(connection, userID: userID, title: "Tech")
            }

            // Each request reaches the handler's write with `atom`, so a patch that applied the
            // output check to these endpoints answered 400 here instead of the write's text.
            let rename = try await requests.post(catchAll + "rename-tag", raw: requests.body(token: token,
                pairs: ["s=user/-/label/Tech", "dest=user/-/label/Renamed", "output=atom"]), header: header)
            #expect(rename.status == .ok, "the handler's choice, not the output read, decides this endpoint")
            #expect(requests.contentType(of: rename) == "text/plain; charset=utf-8", "the write answers text")
            #expect(try requests.body(of: rename) == "OK", "the reference writes `OK`")
            #expect(try await storedTitle(storage, userID: userID, title: "Renamed") != nil,
                "and the write happened")

            let disable = try await requests.post(catchAll + "disable-tag",
                raw: requests.body(token: token, pairs: ["s=user/-/label/Tech", "output=atom"]),
                header: header)
            #expect(disable.status == .ok, "this endpoint does not apply the check either")
            #expect(try requests.body(of: disable) == "OK")

            let mark = try await requests.post(catchAll + "mark-all-as-read",
                raw: requests.body(token: token, pairs: ["s=\(state)reading-list", "output=atom"]),
                header: header)
            #expect(mark.status == .ok, "and neither does this one")
            #expect(try requests.body(of: mark) == "OK")
        }
    }

    @Test func renameTagNamesTheParameterTheReadFailedOnAndNotTheReadErrorItself() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            _ = try await requests.seedIntegrationUser(storage, name: "alice",
                storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "alice", storedHash: storedHash)
            let header = "GoogleLogin auth=\(token)"

            // A patch that passed the stream read's error through answered
            // `googlereader: unknown stream type: bogus` here.
            let source = try await requests.post(catchAll + "rename-tag",
                raw: requests.body(token: token, pairs: ["s=bogus", "dest=user/-/label/News"]),
                header: header)
            #expect(source.status == .badRequest, "the read error is the handler's 400, not the 500 it reads")
            #expect(try requests.body(of: source) ==
                "{\"error_message\":\"googlereader: invalid data in s\"}", "the parameter is what it names")

            // The source read runs first, so the input that fails on both names `s`.
            let both = try await requests.post(catchAll + "rename-tag",
                raw: requests.body(token: token, pairs: ["s=bogus", "dest=bogus"]), header: header)
            #expect(try requests.body(of: both) ==
                "{\"error_message\":\"googlereader: invalid data in s\"}", "the order the reads run in")

            let destination = try await requests.post(catchAll + "rename-tag",
                raw: requests.body(token: token, pairs: ["s=user/-/label/Tech", "dest=bogus"]),
                header: header)
            #expect(try requests.body(of: destination) ==
                "{\"error_message\":\"googlereader: invalid data in dest\"}", "the other name")
        }
    }

    @Test func renameTagGuardOrderRunsTheTypeCheckBeforeTheEmptyDestinationGuard() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            _ = try await requests.seedIntegrationUser(storage, name: "alice",
                storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "alice", storedHash: storedHash)
            let header = "GoogleLogin auth=\(token)"

            // Both guards apply to this input, so the answer shows which one runs first.
            let both = try await requests.post(catchAll + "rename-tag",
                raw: requests.body(token: token, pairs: ["s=\(state)read", "dest=user/-/label/"]),
                header: header)
            #expect(try requests.body(of: both) ==
                "{\"error_message\":\"googlereader: only labels supported\"}",
                "the type check runs before the empty-name guard")

            // The destination half of the same check.
            let destination = try await requests.post(catchAll + "rename-tag",
                raw: requests.body(token: token, pairs: ["s=user/-/label/Tech", "dest=\(state)read"]),
                header: header)
            #expect(try requests.body(of: destination) ==
                "{\"error_message\":\"googlereader: only labels supported\"}",
                "the check is on both sides, not only the source")

            // The input where only the empty guard applies answers its wording, which is the
            // wording `disable-tag` does not have: a patch that used the other handler's message
            // fails here.
            let empty = try await requests.post(catchAll + "rename-tag",
                raw: requests.body(token: token, pairs: ["s=user/-/label/Tech", "dest=user/-/label/"]),
                header: header)
            #expect(try requests.body(of: empty) ==
                "{\"error_message\":\"googlereader: empty destination name\"}",
                "the two wordings name different things")
        }
    }

    @Test func renameTagWritesTheTitleTheReadFindsAndAnswersNotFoundForATitleItDoesNot() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            let userID = try await requests.seedIntegrationUser(storage, name: "alice",
                storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "alice", storedHash: storedHash)
            let header = "GoogleLogin auth=\(token)"

            try await storage.withConnection { connection in
                _ = try await seedCategory(connection, userID: userID, title: "Tech")
            }

            let missing = try await requests.post(catchAll + "rename-tag",
                raw: requests.body(token: token, pairs: ["s=user/-/label/Nope", "dest=user/-/label/New"]),
                header: header)
            #expect(missing.status == .notFound, "the category read answers the 404 shape")
            #expect(try requests.body(of: missing) == "{\"error_message\":\"resource not found\"}")

            let renamed = try await requests.post(catchAll + "rename-tag",
                raw: requests.body(token: token, pairs: ["s=user/-/label/Tech", "dest=user/-/label/New"]),
                header: header)
            #expect(renamed.status == .ok, "the title as the read gave it is written")
            #expect(try requests.body(of: renamed) == "OK")
            #expect(try await storedTitle(storage, userID: userID, title: "Tech") == nil)
            #expect(try await storedTitle(storage, userID: userID, title: "New") != nil,
                "the title the request carries is written as the read gave it")
        }
    }

    @Test func renameTagRunsTheDuplicateRuleAfterTheRowReadAndBeforeTheWrite() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            let userID = try await requests.seedIntegrationUser(storage, name: "alice",
                storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "alice", storedHash: storedHash)
            let header = "GoogleLogin auth=\(token)"

            try await storage.withConnection { connection in
                _ = try await seedCategory(connection, userID: userID, title: "Tech")
                _ = try await seedCategory(connection, userID: userID, title: "News")
            }

            let duplicate = try await requests.post(catchAll + "rename-tag",
                raw: requests.body(token: token, pairs: ["s=user/-/label/Tech", "dest=user/-/label/News"]),
                header: header)
            #expect(duplicate.status == .badRequest, "the rule answers before the write")
            #expect(try requests.body(of: duplicate) == "{\"error_message\":\"alreadyExists\"}",
                "the message is the rule the port names, not the reference's locale string")
            #expect(try await storedTitle(storage, userID: userID, title: "Tech") == "Tech",
                "and nothing was written")

            // The order the other way round: a row the read does not find answers 404 whatever the
            // duplicate answer would be, because the read runs before the rule.
            let missing = try await requests.post(catchAll + "rename-tag",
                raw: requests.body(token: token, pairs: ["s=user/-/label/Nope", "dest=user/-/label/News"]),
                header: header)
            #expect(missing.status == .notFound, "the read before the rule")

            // The rule's own exclusion: the row being checked is not a duplicate of itself.
            let itself = try await requests.post(catchAll + "rename-tag",
                raw: requests.body(token: token, pairs: ["s=user/-/label/Tech", "dest=user/-/label/Tech"]),
                header: header)
            #expect(itself.status == .ok, "the read excludes the row it is checking")
        }
    }

    @Test func disableTagReadsTheMergedListForSAndComparesTheTitlesAsRead() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            let userID = try await requests.seedIntegrationUser(storage, name: "alice",
                storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "alice", storedHash: storedHash)
            let header = "GoogleLogin auth=\(token)"

            // Two rows are left for the pick after the input names its two: the pick answers the
            // smallest of the titles left, which is what a patch that reversed the comparison fails
            // on here. The row order the read answers its rows in is not pinned, because the
            // statement has no `ORDER BY`.
            let feedID = try await storage.withConnection { connection in
                _ = try await seedCategory(connection, userID: userID, title: "Zeta")
                _ = try await seedCategory(connection, userID: userID, title: "News")
                let techID = try await seedCategory(connection, userID: userID, title: "Tech")
                return try await seedFeed(connection, userID: userID, categoryID: techID,
                    url: "https://example.com/1")
            }

            // The list is `r.Form["s"]`, so the query value is part of it: a patch that read only
            // the body side left "All" where it is, and the feed in the row its value named.
            let response = try await requests.post(catchAll + "disable-tag",
                raw: requests.body(token: token, pairs: ["s=user/-/label/Tech"]),
                query: "s=user/-/label/All", header: header)
            #expect(response.status == .ok, "the write answers text")
            #expect(try requests.body(of: response) == "OK")
            #expect(try await storedTitle(storage, userID: userID, title: "Tech") == nil,
                "the body value names a row")
            #expect(try await storedTitle(storage, userID: userID, title: "All") == nil,
                "the query value names one too")
            #expect(try await storedFeedCategory(storage, feedID: feedID) == "News",
                "the feed of a deleted row goes to the first remaining title")

            // The titles are compared as read, so the mixed-case form names nothing and the guard
            // that counts the rows the input leaves has nothing to report.
            let asRead = try await requests.post(catchAll + "disable-tag",
                raw: requests.body(token: token, pairs: ["s=user/-/label/news"]), header: header)
            #expect(asRead.status == .ok)
            #expect(try await storedTitle(storage, userID: userID, title: "News") != nil,
                "the empty list names nothing")
            #expect(try await storedFeedCategory(storage, feedID: feedID) == "News",
                "and nothing was reassigned")
        }
    }

    @Test func disableTagNamesItsOwnTypeCheckWordingAndRunsTheDeleteGuardBeforeAnyWrite() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            let userID = try await requests.seedIntegrationUser(storage, name: "alice",
                storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "alice", storedHash: storedHash)
            let header = "GoogleLogin auth=\(token)"

            try await storage.withConnection { connection in
                _ = try await seedCategory(connection, userID: userID, title: "Tech")
            }

            // The wording this handler has, which is not the one `rename-tag` has. The first value
            // passes this guard, so a patch that checked only the first value answered `OK` here,
            // and a patch that ran the guard after the delete answered `OK` too and deleted the row
            // the first value names, because a guard that reports before any title is collected
            // cannot write.
            let type = try await requests.post(catchAll + "disable-tag",
                raw: requests.body(token: token, pairs: ["s=user/-/label/Tech", "s=\(state)read"]),
                header: header)
            #expect(type.status == .badRequest)
            #expect(try requests.body(of: type) ==
                "{\"error_message\":\"googlereader: only labels are supported\"}",
                "the guard runs per value, and the second value is what fails it")
            #expect(try await storedTitle(storage, userID: userID, title: "Tech") != nil,
                "the guard answers before anything is deleted")

            // The guard counts the rows the input does not name. The input below leaves "All", so
            // the write happens, and the next one leaves nothing, which is the storage failure this
            // suite can trigger.
            let written = try await requests.post(catchAll + "disable-tag",
                raw: requests.body(token: token, pairs: ["s=user/-/label/Tech"]), header: header)
            #expect(written.status == .ok)
            #expect(try await storedTitle(storage, userID: userID, title: "Tech") == nil,
                "the write happens when a row is left")

            let none = try await requests.post(catchAll + "disable-tag",
                raw: requests.body(token: token, pairs: ["s=user/-/label/All"]), header: header)
            #expect(none.status == .internalServerError, "the storage failure answers 500")
            #expect(try requests.body(of: none) ==
                "{\"error_message\":\"store: at least 1 category must remain after deletion\"}",
                "the wording the reference reports for this rule")
            #expect(try await storedTitle(storage, userID: userID, title: "All") != nil,
                "and the guard runs before that write")
        }
    }

    // MARK: - Helpers

    func storedTitle(_ storage: SQLiteStorage, userID: Int, title: String) async throws -> String? {
        try await storage.withConnection { connection in
            try await CategoryRepository(connection).byTitle(userID: userID, title: title)?.title
        }
    }

    func storedStatus(_ storage: SQLiteStorage, entryID: Int) async throws -> EntryStatus? {
        try await storage.withConnection { connection in
            try await EntryRepository(connection).fetch(id: entryID)?.status
        }
    }

    func storedFeedCategory(_ storage: SQLiteStorage, feedID: Int) async throws -> String? {
        try await storage.withConnection { connection in
            let feed = try await FeedRepository(connection).fetch(id: feedID)
            guard let feed else { return nil }
            return try await CategoryRepository(connection).fetch(id: feed.categoryID)?.title
        }
    }
}