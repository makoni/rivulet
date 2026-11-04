import Foundation
import Testing
import Vapor
import RivuletApp
@testable import RivuletCore

/// The handlers and the route shape over a real socket: `internal/googlereader/handler.go` at
/// `c4d54f87`. The goldens are the reference's own answer for these inputs at the toolchain
/// `go.mod` pins, including the status the response builder writes.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the subpath match,
/// which a patch that registered only the exact catch-all path fails on; the row id found by the
/// auth read, which a patch that used the token name as the user document value fails on; which
/// endpoints apply the output check, which a patch that applied it everywhere fails on; the
/// category list order, which a patch that ordered by position fails on; `edit-tag` reading `i`
/// from the merged form while `a` and `r` are the body side, which a patch that read `i` from
/// `PostForm` fails on, and which the guard for an empty add shows for `a` on the input where the
/// body has no `a` at all and for `r` on the input where only `r` is in the query; the storage
/// values the tag branches write, which a patch that read the wrong value for one branch or from
/// the query instead of the body fails on; the handler order that reports a tag error before the
/// item read, which a patch that read the item ids first fails on; the status the answer writes for
/// the output and item-read errors, which a patch that swapped 400 and 500 fails on; the branch
/// switch with the two readings of the same exclude list, the feed filter that only a positive
/// value applies, the two times that every branch applies, the order the parameter read answers,
/// the continuation rule, and the page-size clamp.
///
/// What these pins cannot fail on: the user-info guard that a row found by auth is read back,
/// because no request this suite can build authenticates against a row that is not there, and the
/// status mapping helper is pinned directly; the handler's own answer for a form the read cannot
/// parse, which the transport reports as 401 first; integration settings the reference reads after
/// the storage write; the order of the two storage write sets, which are disjoint for every input
/// that reaches them; the error wording for a storage-layer failure, which this suite cannot
/// trigger; the method mismatch, where the reference answers 405 and this port answers Vapor's 404
/// — recorded as a divergence in `docs/parity.md`; and the redirect for the path without the
/// trailing slash, which `GoogleReaderAuthTests` already records as a divergence.
@Suite struct GoogleReaderHandlerTests {
    init() {
        TestLogging.bootstrapOnce()
    }

    private let storedHash = "$2a$10$hOrIpoEkDKAMFrOt2/k1yeyHBaZKOwK8zEg9JVchReOAtQZ5mEeFu"
    private let catchAll = "/reader/api/0/"
    private let state = "user/-/state/com.google/"

    @Test func theSubpathWildcardUsesTheCatchAllAnswer() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            try await requests.seed(storage, name: "alice", storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "alice", storedHash: storedHash)
            let header = "GoogleLogin auth=\(token)"

            // A patch that registered only the exact catch-all path answers Vapor's 404 here.
            let get = try await requests.get(catchAll + "unregistered", header: header)
            #expect(get.status == .ok, "the subpath reaches the catch-all handler")
            #expect(requests.contentType(of: get) == "application/json", "the answer is the JSON shape")
            #expect(try requests.body(of: get) == "[]", "the unimplemented endpoint answers the empty list")

            // POST reads the token through the form, as the method-specific transport already pins.
            let post = try await requests.post(catchAll + "unregistered", form: ["T": token])
            #expect(post.status == .ok, "the POST half of the subpath reaches the same handler")
            #expect(try requests.body(of: post) == "[]", "with the same answer")
        }
    }

    @Test func theUserDocumentUsesTheRowIDAndDoesNotApplyOutputCheck() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            try await requests.seed(storage, name: "alice", storedHash: storedHash, googleName: "7")
            let userID = try await storedUserID(storage, username: "alice")
            let token = GoogleReaderToken.derive(username: "7", storedHash: storedHash)

            // The row id and the stored account name, not the token name, are what the document
            // writes. A patch that used the token name answered `7` here.
            let response = try await requests.get(catchAll + "user-info?output=atom",
                header: "GoogleLogin auth=\(token)")
            #expect(response.status == .ok, "the handler does not apply the output check")
            #expect(try requests.body(of: response) ==
                "{\"userId\":\"\(userID)\",\"userName\":\"alice\",\"userProfileId\":\"\(userID)\",\"userEmail\":\"alice\"}",
                "the four fields, written with the row values")
        }
    }

    @Test func theTagListAppliesOutputCheckAndOrdersByTitle() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            try await requests.seed(storage, name: "alice", storedHash: storedHash, googleName: "7")
            let userID = try await storedUserID(storage, username: "alice")
            let token = GoogleReaderToken.derive(username: "7", storedHash: storedHash)
            let header = "GoogleLogin auth=\(token)"

            try await storage.withConnection { connection in
                _ = try await seedCategory(connection, userID: userID, title: "Tech")
                _ = try await seedCategory(connection, userID: userID, title: "News")
                // The positions are what make the title rule falsifiable: a patch that ordered by
                // position answered Tech first for these rows.
                let sql = try sqlDatabase(connection)
                try await sql.raw("UPDATE categories SET position = 2 WHERE title = 'News'").run()
                try await sql.raw("UPDATE categories SET position = 1 WHERE title = 'Tech'").run()
            }

            let bad = try await requests.get(catchAll + "tag/list?output=atom", header: header)
            #expect(bad.status == .badRequest, "this handler applies the output check")
            #expect(try requests.body(of: bad) ==
                "{\"error_message\":\"googlereader: only json output is supported\"}",
                "the wording the answer writes")

            let golden = "{\"tags\":[{\"id\":\"user/\(userID)/state/com.google/starred\"}," +
                "{\"id\":\"user/\(userID)/label/News\",\"label\":\"News\",\"type\":\"folder\"}," +
                "{\"id\":\"user/\(userID)/label/Tech\",\"label\":\"Tech\",\"type\":\"folder\"}]}"
            let ok = try await requests.get(catchAll + "tag/list?output=json", header: header)
            #expect(ok.status == .ok, "the output check passes for `json`")
            #expect(try requests.body(of: ok) == golden, "the starred entry comes first")
        }
    }

    @Test func editTagReadsTheItemIDsFromTheMergedFormAndTheTagsFromTheBody() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            try await requests.seed(storage, name: "alice", storedHash: storedHash)
            let userID = try await storedUserID(storage, username: "alice")
            let token = GoogleReaderToken.derive(username: "alice", storedHash: storedHash)
            let entryID = try await seedEntryForUser(storage, userID: userID, status: .unread, starred: false)

            // `i` is only in the query, so a patch that read it from PostForm answered the no-items
            // error here. A patch that read `a` from the query rather than from the body answered
            // the read value for the row.
            let response = try await requests.post(catchAll + "edit-tag",
                raw: body(token: token, pairs: ["a=\(state)starred"]),
                query: "a=\(state)read&i=\(entryID)",
                header: "GoogleLogin auth=\(token)")
            #expect(response.status == .ok, "the body value alone makes this request valid")
            #expect(requests.contentType(of: response) == "text/plain; charset=utf-8",
                "the write operation answers as text")
            #expect(try requests.body(of: response) == "OK", "the reference writes `OK`")

            try await storage.withConnection { connection in
                let stored = try #require(try await EntryRepository(connection).fetch(id: entryID))
                #expect(stored.starred, "the body value is the one read for `a`")
                #expect(stored.status == .unread, "the query value is not read for `a`")
            }

            // `r` is the body side as well: with `r` only in the query the guard still passes
            // because `a` is on the body side, so the value the add loop wrote stands. A patch that
            // read `r` through the merged form answered the pair error here.
            let removeHalf = try await requests.post(catchAll + "edit-tag",
                raw: body(token: token, pairs: ["a=\(state)read", "i=\(entryID)"]),
                query: "r=\(state)read", header: "GoogleLogin auth=\(token)")
            #expect(removeHalf.status == .ok, "the query half is not read for `r`")
        }
    }

    @Test func editTagDoesNotApplyOutputCheckAndWritesTheReadBranchValues() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            try await requests.seed(storage, name: "alice", storedHash: storedHash)
            let userID = try await storedUserID(storage, username: "alice")
            let token = GoogleReaderToken.derive(username: "alice", storedHash: storedHash)
            let entryID = try await seedEntryForUser(storage, userID: userID, status: .unread, starred: false)

            // The endpoint does not apply the output check, so `atom` still reaches the handler.
            let read = try await requests.post(catchAll + "edit-tag",
                raw: body(token: token, pairs: ["a=\(state)read", "i=\(entryID)", "output=atom"]),
                header: "GoogleLogin auth=\(token)")
            #expect(read.status == .ok, "the handler's choice, not the output read, decides this endpoint")
            #expect(try requests.body(of: read) == "OK", "the write operation answers text")
            try await storage.withConnection { connection in
                let stored = try #require(try await EntryRepository(connection).fetch(id: entryID))
                #expect(stored.status == .read, "add read changes an unread entry")
            }

            // The same type answers the other value on add, so the row that is now read becomes
            // unread again.
            let kept = try await requests.post(catchAll + "edit-tag",
                raw: body(token: token, pairs: ["a=\(state)kept-unread", "i=\(entryID)", "output=atom"]),
                header: "GoogleLogin auth=\(token)")
            #expect(kept.status == .ok, "the same endpoint answers text for this request too")
            try await storage.withConnection { connection in
                let stored = try #require(try await EntryRepository(connection).fetch(id: entryID))
                #expect(stored.status == .unread, "add kept-unread is the other value for the same type")
            }
        }
    }

    @Test func editTagWritesTheStarredBranchValuesAndTheirRemoval() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            try await requests.seed(storage, name: "alice", storedHash: storedHash)
            let userID = try await storedUserID(storage, username: "alice")
            let token = GoogleReaderToken.derive(username: "alice", storedHash: storedHash)
            let unstarred = try await seedEntryForUser(storage, userID: userID, status: .read, starred: false)

            let add = try await requests.post(catchAll + "edit-tag",
                raw: body(token: token, pairs: ["a=\(state)starred", "i=\(unstarred)"]),
                header: "GoogleLogin auth=\(token)")
            #expect(add.status == .ok, "add starred writes the entry")
            try await storage.withConnection { connection in
                let stored = try #require(try await EntryRepository(connection).fetch(id: unstarred))
                #expect(stored.starred, "the add branch writes true")
            }

            // `a=read` with `r=starred` is not the guard conflict: the read value is already true,
            // and the starred value becomes false for the entry that was starred.
            let remove = try await requests.post(catchAll + "edit-tag",
                raw: body(token: token, pairs: ["a=\(state)read", "r=\(state)starred", "i=\(unstarred)"]),
                header: "GoogleLogin auth=\(token)")
            #expect(remove.status == .ok, "the two branches answer values that do not conflict here")
            try await storage.withConnection { connection in
                let stored = try #require(try await EntryRepository(connection).fetch(id: unstarred))
                #expect(!stored.starred, "the remove branch writes the other value")
                #expect(stored.status == .read, "the entry was already read, so the read value writes nothing")
            }
        }
    }

    @Test func editTagTagReadErrorsAnswerServerBeforeTheItemRead() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            try await requests.seed(storage, name: "alice", storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "alice", storedHash: storedHash)

            // A wrong read that ran the item ids first answered the no-items or parse error here.
            let unsupported = try await requests.post(catchAll + "edit-tag",
                raw: body(token: token, pairs: ["a=user/-/label/x", "i=g"]),
                header: "GoogleLogin auth=\(token)")
            #expect(unsupported.status == .internalServerError,
                "the tag read runs before the item read on this handler")
            #expect(try requests.body(of: unsupported) ==
                "{\"error_message\":\"googlereader: unsupported tag type: LabelStream\"}",
                "the wording the 500 answer writes")

            // The body carries only the token, so `a` is not on the body side and the guard runs
            // before `i`. A patch that read `a` through the merged form answered the parse error
            // here.
            let empty = try await requests.post(catchAll + "edit-tag", raw: "T=\(token)",
                query: "a=\(state)read&i=g",
                header: "GoogleLogin auth=\(token)")
            #expect(empty.status == .internalServerError, "the empty add and remove guard is the handler's rule")
            #expect(try requests.body(of: empty) ==
                "{\"error_message\":\"googlreader: add or/and remove tags should be supplied\"}",
                "the reference's own wording, including its typo")
        }
    }

    @Test func editTagItemReadErrorMapsToBadRequest() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            try await requests.seed(storage, name: "alice", storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "alice", storedHash: storedHash)

            let response = try await requests.post(catchAll + "edit-tag",
                raw: body(token: token, pairs: ["a=\(state)read", "i=g"]),
                header: "GoogleLogin auth=\(token)")
            #expect(response.status == .badRequest, "the item read answers 400, not 500")
            #expect(try requests.body(of: response) ==
                "{\"error_message\":\"googlereader: failed to parse item ID g: failed to parse decimal item ID g: strconv.ParseInt: parsing \\\"g\\\": invalid syntax\"}",
                "the handler wrapper around the pure parse wording")
        }
    }

    @Test func streamItemIDsAppliesOutputCheckAndPinsTheBranchAndContinuationRules() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            try await requests.seed(storage, name: "alice", storedHash: storedHash, googleName: "7")
            let userID = try await storedUserID(storage, username: "alice")
            let token = GoogleReaderToken.derive(username: "7", storedHash: storedHash)
            let header = "GoogleLogin auth=\(token)"

            let (first, second, third, fourth) = try await storage.withConnection { connection in
                try await seedStreamEntries(connection, userID: userID)
            }

            let badOutput = try await requests.get(catchAll + "stream/items/ids?output=atom", header: header)
            #expect(badOutput.status == .badRequest, "this handler applies the output check before the filter read")
            #expect(try requests.body(of: badOutput) ==
                "{\"error_message\":\"googlereader: only json output is supported\"}",
                "the wording the 400 answer writes")

            let onlyOne = try await requests.get(
                catchAll + "stream/items/ids?output=json&s=\(state)read&s=\(state)starred", header: header)
            #expect(onlyOne.status == .internalServerError, "the handler requires one stream before the branch")
            #expect(try requests.body(of: onlyOne) ==
                "{\"error_message\":\"googlereader: only one stream type expected\"}",
                "the wording the 500 answer writes")

            let switchDefault = try await requests.get(catchAll + "stream/items/ids?output=json&s=user/-/label/x",
                header: header)
            #expect(switchDefault.status == .internalServerError, "a parsed label stream reaches the default branch")
            #expect(try requests.body(of: switchDefault) ==
                "{\"error_message\":\"googlereader: unknown stream type LabelStream\"}",
                "the handler's wording, not the stream read's colon wording")

            let readingList = try await requests.get(
                catchAll + "stream/items/ids?output=json&s=\(state)reading-list&n=4", header: header)
            #expect(readingList.status == .ok, "the reading-list branch reads all statuses when no filter is read")
            #expect(try requests.body(of: readingList) ==
                "{\"itemRefs\":[{\"id\":\"\(fourth)\"},{\"id\":\"\(third)\"},{\"id\":\"\(second)\"},{\"id\":\"\(first)\"}]}",
                "publication order, and the continuation rule omitted because returned equals total")

            let readBranch = try await requests.get(
                catchAll + "stream/items/ids?output=json&s=\(state)read&n=4", header: header)
            #expect(try requests.body(of: readBranch) ==
                "{\"itemRefs\":[{\"id\":\"\(fourth)\"},{\"id\":\"\(second)\"}]}",
                "the read branch selects read entries")

            let starredBranch = try await requests.get(
                catchAll + "stream/items/ids?output=json&s=\(state)starred&n=4", header: header)
            #expect(try requests.body(of: starredBranch) ==
                "{\"itemRefs\":[{\"id\":\"\(third)\"},{\"id\":\"\(second)\"}]}",
                "the starred branch selects starred entries")

            // A patch that answered the sum for every page failed on the omitted zero above and on
            // the offset below.
            let continuation = try await requests.get(
                catchAll + "stream/items/ids?output=json&s=\(state)reading-list&n=1&c=1", header: header)
            #expect(try requests.body(of: continuation) ==
                "{\"itemRefs\":[{\"id\":\"\(third)\"}],\"continuation\":\"2\"}",
                "the sum is written as a string only while it is below the total")

            // The order the parameter read answers is applied by the branch handler, so `r=o` is
            // the other direction for the same rows.
            let ascending = try await requests.get(
                catchAll + "stream/items/ids?output=json&s=\(state)reading-list&n=4&r=o", header: header)
            #expect(try requests.body(of: ascending) ==
                "{\"itemRefs\":[{\"id\":\"\(first)\"},{\"id\":\"\(second)\"},{\"id\":\"\(third)\"},{\"id\":\"\(fourth)\"}]}",
                "the ascending answer for the same rows")
        }
    }

    @Test func eachBranchReadsTheExcludeListTheWayItsOwnHandlerDoes() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            try await requests.seed(storage, name: "alice", storedHash: storedHash, googleName: "7")
            let userID = try await storedUserID(storage, username: "alice")
            let token = GoogleReaderToken.derive(username: "7", storedHash: storedHash)
            let header = "GoogleLogin auth=\(token)"
            let (first, second, third, fourth) = try await storage.withConnection { connection in
                try await seedStreamEntries(connection, userID: userID)
            }

            // The reading-list branch keeps the status the exclude name is the other side of, so a
            // patch that read it as an exclusion answered the read rows here.
            let readingList = try await requests.get(
                catchAll + "stream/items/ids?output=json&s=\(state)reading-list&xt=\(state)read&n=4",
                header: header)
            #expect(try requests.body(of: readingList) ==
                "{\"itemRefs\":[{\"id\":\"\(third)\"},{\"id\":\"\(first)\"}]}",
                "the excluded read name selects the unread rows on this branch")

            // A target that is not the read type adds nothing on either branch.
            let otherTarget = try await requests.get(
                catchAll + "stream/items/ids?output=json&s=\(state)reading-list&xt=\(state)starred&n=4",
                header: header)
            #expect(try requests.body(of: otherTarget) ==
                "{\"itemRefs\":[{\"id\":\"\(fourth)\"},{\"id\":\"\(third)\"},{\"id\":\"\(second)\"},{\"id\":\"\(first)\"}]}",
                "the branch with no filter for that type")

            // The feed branch reads the same name as the exclusion it names, which is the other
            // answer from the same rows.
            let feedBranch = try await requests.get(
                catchAll + "stream/items/ids?output=json&s=feed/2&xt=\(state)read&n=4", header: header)
            #expect(try requests.body(of: feedBranch) ==
                "{\"itemRefs\":[{\"id\":\"\(third)\"}]}",
                "the feed branch applies the status exclusion")

            // `WithFeedID` adds its condition only for a positive value, so `feed/0` and `feed/-5`
            // answer the whole listing, which a patch that applied the parsed value as read could
            // not.
            for value in ["feed/0", "feed/-5"] {
                let response = try await requests.get(catchAll + "stream/items/ids?output=json&s=\(value)&n=4", header: header)
                #expect(try requests.body(of: response) == "{\"itemRefs\":[{\"id\":\"\(fourth)\"},{\"id\":\"\(third)\"},{\"id\":\"\(second)\"},{\"id\":\"\(first)\"}]}", "the whole listing for a value that is not positive")
            }

            // Both times are read on every branch, and only a positive value is applied. A patch
            // that applied them on one branch answered all the starred rows here.
            let starredAfter = try await requests.get(
                catchAll + "stream/items/ids?output=json&s=\(state)starred&n=4&ot=250", header: header)
            #expect(try requests.body(of: starredAfter) == "{\"itemRefs\":[{\"id\":\"\(third)\"}]}",
                "the start time keeps the rows published after it")

            let beforeStop = try await requests.get(
                catchAll + "stream/items/ids?output=json&s=\(state)reading-list&n=4&nt=250", header: header)
            #expect(try requests.body(of: beforeStop) ==
                "{\"itemRefs\":[{\"id\":\"\(second)\"},{\"id\":\"\(first)\"}]}",
                "the stop time keeps the rows published before it")

            let zeroTime = try await requests.get(
                catchAll + "stream/items/ids?output=json&s=\(state)starred&n=4&ot=0", header: header)
            #expect(try requests.body(of: zeroTime) ==
                "{\"itemRefs\":[{\"id\":\"\(third)\"},{\"id\":\"\(second)\"}]}",
                "the default is not applied as a time")
        }
    }

    @Test func streamItemIDsClampsThePageAtTheStorageBoundary() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            try await requests.seed(storage, name: "alice", storedHash: storedHash, googleName: "7")
            let userID = try await storedUserID(storage, username: "alice")
            try await storage.withConnection { connection in
                let categoryID = try await seedCategory(connection, userID: userID, title: "Tech")
                let feedID = try await seedFeed(connection, userID: userID, categoryID: categoryID,
                    url: "https://example.com/1")
                try await seedManyEntries(connection, userID: userID, feedID: feedID, count: 1001)
            }

            let header = "GoogleLogin auth=\(GoogleReaderToken.derive(username: "7", storedHash: storedHash))"
            let response = try await requests.get(
                catchAll + "stream/items/ids?output=json&s=\(state)reading-list&n=2000", header: header)
            #expect(response.status == .ok, "the page-size value reaches the storage layer")

            let document = try JSONDecoder().decode(ItemIDsDocument.self,
                from: Data(try requests.body(of: response).utf8))
            #expect(document.itemRefs.count == 1000, "the page is clamped to 1000, not 2000")
            #expect(document.itemRefs.first?.id == "1001", "the storage layer applies the clamped page")
            #expect(document.itemRefs.last?.id == "2", "the last row on the page is the boundary")
            #expect(document.continuation == "1000", "the continuation is the returned count plus the offset")
        }
    }

    @Test func feedIDIsParsedByTheHandlerAndNotByTheStreamRead() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            try await requests.seed(storage, name: "alice", storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "alice", storedHash: storedHash)
            let response = try await requests.get(catchAll + "stream/items/ids?output=json&s=feed/x",
                header: "GoogleLogin auth=\(token)")
            #expect(response.status == .internalServerError, "the stream read keeps the value as text")
            #expect(try requests.body(of: response) ==
                "{\"error_message\":\"strconv.ParseInt: parsing \\\"x\\\": invalid syntax\"}",
                "the handler read that the stream read leaves for it")
        }
    }

    @Test func theStreamErrorWordingKeepsTheQueryReadErrorSeparateFromTheHandlerBranch() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            try await requests.seed(storage, name: "alice", storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "alice", storedHash: storedHash)

            // A value that matches no stream prefix is the query read's error, with the colon.
            let queryError = try await requests.get(catchAll + "stream/items/ids?output=json&s=bogus",
                header: "GoogleLogin auth=\(token)")
            #expect(queryError.status == .internalServerError, "the filter read reports the error before the handler branch")
            #expect(try requests.body(of: queryError) ==
                "{\"error_message\":\"googlereader: unknown stream type: bogus\"}",
                "the stream read's wording")
        }
    }

    // MARK: - Helpers

    /// The POST body as the transport reads it for this method: the token is the `T` field of the
    /// merged form, so for a POST request it has to be part of the bytes that are sent.
    private func body(token: String, pairs: [String]) -> String {
        "T=\(token)" + pairs.map { "&\($0)" }.joined()
    }

    private func storedUserID(_ storage: SQLiteStorage, username: String) async throws -> Int {
        try await storage.withConnection { connection in
            let user = try #require(try await UserRepository(connection).fetch(username: username))
            return try #require(user.id)
        }
    }

    private func seedEntryForUser(_ storage: SQLiteStorage, userID: Int, status: EntryStatus, starred: Bool)
        async throws -> Int {
        try await storage.withConnection { connection in
            let categoryID = try await seedCategory(connection, userID: userID, title: "Tech")
            let feedID = try await seedFeed(connection, userID: userID, categoryID: categoryID,
                url: "https://example.com/1")
            return try await seedEntry(connection, userID: userID, feedID: feedID, hash: "h1",
                status: status, starred: starred)
        }
    }

    private struct ItemIDsDocument: Decodable {
        struct Item: Decodable {
            let id: String
        }

        let itemRefs: [Item]
        let continuation: String?
    }
}
