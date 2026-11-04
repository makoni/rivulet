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
/// title left rather than the last of the rows it read; the handler with no default branch, so the
/// stream types it does not handle answer `OK` writing nothing; the status the integer read error
/// maps to here, which is 400 where the same read answers 500 for `stream/items/ids`; the `ts`
/// length rule, the two units it gives, the sign guard, the default that is the time the handler
/// runs at, and the comparison that is strictly before.
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
/// read answers its rows in, which the statement does not order and which no pin can show.
@Suite struct GoogleReaderWriteHandlerTests {
    init() {
        TestLogging.bootstrapOnce()
    }

    private let storedHash = "$2a$10$hOrIpoEkDKAMFrOt2/k1yeyHBaZKOwK8zEg9JVchReOAtQZ5mEeFu"
    private let catchAll = "/reader/api/0/"
    private let state = "user/-/state/com.google/"

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
            let userID = try await requests.seedIntegrationUser(storage, name: "alice",
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
            let userID = try await requests.seedIntegrationUser(storage, name: "alice",
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
                "the title is compared as read, so the mixed-case form names nothing here")
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

            // The wording this handler has, which is not the one `rename-tag` has. The first value
            // passes this guard, so a patch that checked only the first value answered `OK` here.
            let type = try await requests.post(catchAll + "disable-tag",
                raw: requests.body(token: token, pairs: ["s=user/-/label/Tech", "s=\(state)read"]),
                header: header)
            #expect(type.status == .badRequest)
            #expect(try requests.body(of: type) ==
                "{\"error_message\":\"googlereader: only labels are supported\"}",
                "the guard runs per value, in the order the list is read")
            #expect(try await storedTitle(storage, userID: userID, title: "All") != nil,
                "and the guard answers before anything is deleted")

            // The input that would leave the user with no category at all: the guard counts what
            // the input does not name, and this is the storage failure this suite can trigger.
            let none = try await requests.post(catchAll + "disable-tag",
                raw: requests.body(token: token, pairs: ["s=user/-/label/All"]), header: header)
            #expect(none.status == .internalServerError, "the storage failure answers 500")
            #expect(try requests.body(of: none) ==
                "{\"error_message\":\"store: at least 1 category must remain after deletion\"}",
                "the wording the reference reports for this rule")
            #expect(try await storedTitle(storage, userID: userID, title: "All") != nil,
                "the guard runs before any write")
        }
    }

    @Test func markAllAsReadHasNoDefaultBranchSoTheTypesItDoesNotHandleWriteNothing() async throws {
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

            // A patch that gave this switch a default branch marked the entry for these types.
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
                "the length of the value as read, not the number of digits of the parsed value")
        }
    }

    @Test func markAllAsReadDefaultIsTheTimeTheHandlerRunsAtAndTheSignGuardLeavesIt() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            let userID = try await requests.seedIntegrationUser(storage, name: "alice",
                storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "alice", storedHash: storedHash)
            let header = "GoogleLogin auth=\(token)"

            let (feedID, pastID, futureID) = try await storage.withConnection { connection in
                let categoryID = try await seedCategory(connection, userID: userID, title: "Tech")
                let feed = try await seedFeed(connection, userID: userID, categoryID: categoryID,
                    url: "https://example.com/1")
                let past = try await seedEntry(connection, userID: userID, feedID: feed, hash: "h1",
                    publishedAt: 200)
                let future = try await seedEntry(connection, userID: userID, feedID: feed, hash: "h2",
                    publishedAt: nowInSeconds() + 3_600)
                return (feed, past, future)
            }

            // A patch that used the parsed value for an unpositive one answered the epoch here,
            // which marks nothing.
            let zero = try await requests.post(catchAll + "mark-all-as-read",
                raw: requests.body(token: token, pairs: ["s=feed/\(feedID)", "ts=0"]), header: header)
            #expect(zero.status == .ok)
            #expect(try await storedStatus(storage, entryID: pastID) == .read,
                "the sign guard leaves the default")
            #expect(try await storedStatus(storage, entryID: futureID) == .unread,
                "and the default is the time the handler runs at")

            // The negative side, where the length rule would have taken the microsecond branch.
            let negative = try await requests.post(catchAll + "mark-all-as-read",
                raw: requests.body(token: token,
                    pairs: ["s=feed/\(feedID)", "ts=-10000000000000000"]), header: header)
            #expect(negative.status == .ok)
            #expect(try await storedStatus(storage, entryID: futureID) == .unread,
                "the sign guard runs before the length test")

            // The value the form does not carry answers the same as the empty one, which is why the
            // guard reads the answer rather than the presence.
            let absent = try await requests.post(catchAll + "mark-all-as-read",
                raw: requests.body(token: token, pairs: ["s=feed/\(feedID)"]), header: header)
            #expect(absent.status == .ok)
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

    // MARK: - Helpers

    private func storedTitle(_ storage: SQLiteStorage, userID: Int, title: String) async throws -> String? {
        try await storage.withConnection { connection in
            try await CategoryRepository(connection).byTitle(userID: userID, title: title)?.title
        }
    }

    private func storedStatus(_ storage: SQLiteStorage, entryID: Int) async throws -> EntryStatus? {
        try await storage.withConnection { connection in
            try await EntryRepository(connection).fetch(id: entryID)?.status
        }
    }

    private func storedFeedCategory(_ storage: SQLiteStorage, feedID: Int) async throws -> String? {
        try await storage.withConnection { connection in
            let feed = try await FeedRepository(connection).fetch(id: feedID)
            guard let feed else { return nil }
            return try await CategoryRepository(connection).fetch(id: feed.categoryID)?.title
        }
    }
}