import Foundation
import SQLKit
import Testing
import Vapor
import RivuletApp
@testable import RivuletCore

/// `stream/items/contents` over a real socket: `streamItemContentsHandler` of
/// `internal/googlereader/handler.go` at `c4d54f87`. The goldens are the reference's own answer for
/// these inputs at the toolchain `go.mod` pins.
///
/// What these pins can fail on, each checked by patching the rule and reverting: that the values
/// the document is built from are the rows the read answers — the origin title is the feed row's
/// title, the categories label is the category row's title, and neither is the entry's own title;
/// the origin site url is the feed row's `site_url` column, not the feed url column and not the
/// entry url; the item id is the long hex form the reference writes; the three times are three
/// different columns and the two string forms are built by multiplying those whole seconds; the
/// document `author` is the account name while the item `author` is the entry's own; the document
/// `id` is the literal generic prefix while the categories carry the row number; `self` is the
/// configured base URL rather than the host the request came in on; the document `updated` is the
/// time the handler runs at; the order is read from the URL query and not from the body; `i` is
/// read from the merged form, so the query half alone answers for a POST; a form carrying no `i` is
/// the guard's answer; the output check runs before that guard, on an input that fails both; the
/// stream read runs before it too, on an input that fails both; and an entry with no attachment
/// answers `[]`.
///
/// What these pins cannot fail on: the answer for a form the read cannot parse, which the transport
/// reports as 401 first; the storage wordings for a failure this suite cannot trigger; the
/// read-back of the row the transport read found, which the reference has no answer for here
/// because auth found it; the page size, because this port's read for this endpoint has no `LIMIT`
/// clause at all — the reference's `fetchEntries` has none — so a handler that passed the value `n`
/// answers to the query could not change the answer, and the pin that names it can only show that
/// every row the ids name is written; the media proxy, which this port does not have and which
/// `docs/parity.md` records as a divergence; the inner join on categories, which this port's schema
/// cannot leave unfulfilled; and the order of the two statements that build the enclosures, which
/// is the reference's choice as well. The document time is pinned by the assertion that compares it
/// with the time the request ran at; the other whole-document pins read it from the answer, because
/// a pin that wrote the time it computed before the request could fail on the handler running at a
/// later second.
@Suite struct GoogleReaderContentHandlerTests {
    init() {
        TestLogging.bootstrapOnce()
    }

    private let storedHash = "$2a$10$hOrIpoEkDKAMFrOt2/k1yeyHBaZKOwK8zEg9JVchReOAtQZ5mEeFu"
    private let contents = "/reader/api/0/stream/items/contents"

    @Test func theDocumentIsTheReferenceAnswerForOneEntry() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            let userID = try await requests.seedIntegrationUser(storage, name: "alice",
                storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "alice", storedHash: storedHash)
            let header = "GoogleLogin auth=\(token)"

            let (feedID, entryID, created, changed) = try await seedContent(storage, userID: userID,
                feedURL: "https://feed.example/", siteURL: "https://site.example/",
                feedTitle: "Feed Title", categoryTitle: "Tech",
                entryURL: "https://entry.example/item", content: "<p>Hello</p>",
                publishedAt: 1_700_000_000, createdAt: 1_700_002_000, updatedAt: 1_700_003_000)
            let before = nowInSeconds()

            let response = try await requests.post(contents,
                raw: requests.body(token: token, pairs: ["i=\(itemID(entryID))"]),
                query: "s=user/-/state/com.google/reading-list&output=json", header: header)
            #expect(response.status == .ok, "the endpoint is registered for POST")
            #expect(requests.contentType(of: response) == "application/json", "the answer is JSON")

            let body = try requests.body(of: response)
            let written = try #require(firstInt(body, marker: "\"updated\":"))
            #expect(written >= before && written <= nowInSeconds(),
                "the document time is the time the handler runs at; a fixed time fails here")

            // `self` is the configured value, not the host the request came in on, which is the
            // socket base this suite sends to.
            #expect(body == document(selfHref: "http://localhost" + contents, updated: written,
                author: "alice", items: [item(id: itemID(entryID),
                    categories: categories(userID, label: "Tech", read: false, starred: false),
                    title: "Title", crawlTimeMsec: created, timestampUsec: 1_700_000_000,
                    published: 1_700_000_000, updated: changed, author: "Author",
                    url: "https://entry.example/item",
                    content: "\\u003cp\\u003eHello\\u003c/p\\u003e", streamID: "feed/\(feedID)",
                    feedTitle: "Feed Title", siteURL: "https://site.example/", enclosures: "[]")]),
                "the fourteen item fields in the order the document declares them")
        }
    }

    @Test func theDocumentAuthorIsTheAccountNameAndTheItemAuthorIsTheEntryAuthor() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            let userID = try await requests.seedIntegrationUser(storage, name: "alice",
                storedHash: storedHash)

            // The name the transport read uses is the integration column, so writing a different
            // value here makes three names that differ: the account name the document writes, the
            // integration name the transport read found, and the entry's own author the item
            // writes.
            try await storage.withConnection { connection in
                try await sqlDatabase(connection).raw(
                    "UPDATE users SET google_reader_username = 'Alice' WHERE id = \(bind: userID)").run()
            }
            let token = GoogleReaderToken.derive(username: "Alice", storedHash: storedHash)
            let header = "GoogleLogin auth=\(token)"

            let (feedID, entryID, created, changed) = try await seedContent(storage, userID: userID,
                feedURL: "https://feed.example/", siteURL: "https://site.example/",
                feedTitle: "Feed Title", categoryTitle: "Tech",
                entryURL: "https://entry.example/item", content: "",
                publishedAt: 1_700_000_000, createdAt: 1_700_002_000, updatedAt: 1_700_003_000,
                author: "Entry Author")
            let response = try await requests.post(contents,
                raw: requests.body(token: token, pairs: ["i=\(itemID(entryID))"]),
                query: "s=user/-/state/com.google/reading-list&output=json", header: header)
            let body = try requests.body(of: response)
            // The time is read from the answer here; the rule that it is the time the handler runs
            // at is pinned by the first test, which compares it with the time the request ran at.
            let written = try #require(firstInt(body, marker: "\"updated\":"))
            #expect(body == document(selfHref: "http://localhost" + contents,
                updated: written, author: "alice", items: [item(id: itemID(entryID),
                    categories: categories(userID, label: "Tech", read: false, starred: false),
                    title: "Title", crawlTimeMsec: created, timestampUsec: 1_700_000_000,
                    published: 1_700_000_000, updated: changed, author: "Entry Author",
                    url: "https://entry.example/item", content: "", streamID: "feed/\(feedID)",
                    feedTitle: "Feed Title", siteURL: "https://site.example/", enclosures: "[]")]),
                "the account name here, not the integration name the token read used")
        }
    }

    @Test func theThreeTimesAreThreeDifferentColumnsAndTwoAreStringForms() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            let userID = try await requests.seedIntegrationUser(storage, name: "alice",
                storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "alice", storedHash: storedHash)
            let header = "GoogleLogin auth=\(token)"

            // Three values a patch reading one column for another cannot answer the same for. The
            // two string forms are the whole seconds multiplied, which is what a patch that wrote
            // the seconds themselves, or wrote a number rather than a string, fails on.
            let (feedID, entryID, created, changed) = try await seedContent(storage, userID: userID,
                feedURL: "https://feed.example/", siteURL: "https://site.example/",
                feedTitle: "Feed Title", categoryTitle: "Tech",
                entryURL: "https://entry.example/item", content: "",
                publishedAt: 1_700_001_000, createdAt: 1_700_002_000, updatedAt: 1_700_003_000)
            let response = try await requests.post(contents,
                raw: requests.body(token: token, pairs: ["i=\(itemID(entryID))"]),
                query: "s=user/-/state/com.google/reading-list&output=json", header: header)
            let body = try requests.body(of: response)
            // The time is read from the answer here; the rule that it is the time the handler runs
            // at is pinned by the first test, which compares it with the time the request ran at.
            let written = try #require(firstInt(body, marker: "\"updated\":"))
            #expect(body == document(selfHref: "http://localhost" + contents,
                updated: written, author: "alice", items: [item(id: itemID(entryID),
                    categories: categories(userID, label: "Tech", read: false, starred: false),
                    title: "Title", crawlTimeMsec: created, timestampUsec: 1_700_001_000,
                    published: 1_700_001_000, updated: changed, author: "Author",
                    url: "https://entry.example/item", content: "", streamID: "feed/\(feedID)",
                    feedTitle: "Feed Title", siteURL: "https://site.example/", enclosures: "[]")]),
                "the item time fields, each from its own column")
        }
    }

    @Test func theOriginTitleIsTheFeedRowAndTheLabelIsTheCategoryRow() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            let userID = try await requests.seedIntegrationUser(storage, name: "alice",
                storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "alice", storedHash: storedHash)
            let header = "GoogleLogin auth=\(token)"

            // Three rows carry three different titles here, so a patch that answered the origin
            // title from the entry or from the category fails on the pin that names the row it did
            // not read.
            let (feedID, entryID, created, changed) = try await seedContent(storage, userID: userID,
                feedURL: "https://feed.example/", siteURL: "https://site.example/",
                feedTitle: "Feed Title", categoryTitle: "Cat Title",
                entryURL: "https://entry.example/item", content: "",
                publishedAt: 100, createdAt: 200, updatedAt: 300)
            let response = try await requests.post(contents,
                raw: requests.body(token: token, pairs: ["i=\(itemID(entryID))"]),
                query: "s=user/-/state/com.google/reading-list&output=json", header: header)
            let body = try requests.body(of: response)
            // The time is read from the answer here; the rule that it is the time the handler runs
            // at is pinned by the first test, which compares it with the time the request ran at.
            let written = try #require(firstInt(body, marker: "\"updated\":"))
            #expect(body == document(selfHref: "http://localhost" + contents,
                updated: written, author: "alice", items: [item(id: itemID(entryID),
                    categories: categories(userID, label: "Cat Title", read: false, starred: false),
                    title: "Title", crawlTimeMsec: created, timestampUsec: 100,
                    published: 100, updated: changed, author: "Author",
                    url: "https://entry.example/item", content: "", streamID: "feed/\(feedID)",
                    feedTitle: "Feed Title", siteURL: "https://site.example/", enclosures: "[]")]),
                "the origin title is the feed row and the label is the category row")
        }
    }

    @Test func theReadAnswersEveryRowTheIdsNameBecauseItHasNoLimitClause() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            let userID = try await requests.seedIntegrationUser(storage, name: "alice",
                storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "alice", storedHash: storedHash)
            let header = "GoogleLogin auth=\(token)"

            // This read has no `LIMIT` clause, so the page size the input names cannot reduce the
            // answer; the pin shows that both rows the ids name are written.
            let ids = try await storage.withConnection { connection in
                let categoryID = try await seedCategory(connection, userID: userID, title: "Tech")
                let feedID = try await seedFeed(connection, userID: userID, categoryID: categoryID,
                    url: "https://example.com/feed")
                let first = try await seedEntry(connection, userID: userID, feedID: feedID, hash: "h1")
                let second = try await seedEntry(connection, userID: userID, feedID: feedID, hash: "h2")
                return [first, second]
            }

            let response = try await requests.post(contents,
                raw: requests.body(token: token, pairs: ["i=\(itemID(ids[0]))", "i=\(itemID(ids[1]))"]),
                query: "s=user/-/state/com.google/reading-list&output=json&n=1", header: header)
            #expect(response.status == .ok)
            let body = try requests.body(of: response)
            #expect(occurrences(of: body, of: "{\"id\":") == 2,
                "both rows the ids name are written, whatever the page size names")
            #expect(body.contains("\"id\":\"\(itemID(ids[0]))\"") &&
                body.contains("\"id\":\"\(itemID(ids[1]))\""), "the two rows the input names")
        }
    }

    @Test func theOrderIsReadFromTheQueryAndNotFromTheBody() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            let userID = try await requests.seedIntegrationUser(storage, name: "alice",
                storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "alice", storedHash: storedHash)
            let header = "GoogleLogin auth=\(token)"

            // Two rows whose publication order is the other way round from the order they are
            // seeded in, so the direction is what the pins read rather than the row order.
            let ids = try await storage.withConnection { connection in
                let categoryID = try await seedCategory(connection, userID: userID, title: "Tech")
                let feedID = try await seedFeed(connection, userID: userID, categoryID: categoryID,
                    url: "https://example.com/feed")
                let older = try await seedEntry(connection, userID: userID, feedID: feedID, hash: "h1",
                    publishedAt: 100)
                let later = try await seedEntry(connection, userID: userID, feedID: feedID, hash: "h2",
                    publishedAt: 200)
                return (older: older, later: later)
            }

            // The same name on the two sides answers two different values: the body half is not
            // what this read takes, so the query half's default is what the first request answers
            // with.
            let descendingBody = try requests.body(of: try await requests.post(contents,
                raw: requests.body(token: token, pairs: ["i=\(itemID(ids.older))",
                    "i=\(itemID(ids.later))", "r=o"]),
                query: "s=user/-/state/com.google/reading-list&output=json", header: header))
            #expect(firstPosition(of: descendingBody, of: itemID(ids.later)) <
                firstPosition(of: descendingBody, of: itemID(ids.older)),
                "the default direction, because `r` in the body is not what this read takes")

            // The value in the query half flips it, which is the difference the pin reads.
            let ascendingBody = try requests.body(of: try await requests.post(contents,
                raw: requests.body(token: token, pairs: ["i=\(itemID(ids.older))",
                    "i=\(itemID(ids.later))"]),
                query: "s=user/-/state/com.google/reading-list&output=json&r=o", header: header))
            #expect(firstPosition(of: ascendingBody, of: itemID(ids.older)) <
                firstPosition(of: ascendingBody, of: itemID(ids.later)),
                "the order parameter read from the query flips it")
        }
    }

    @Test func theItemIdsAreReadFromTheMergedFormAndTheGuardReportsAnEmptyOne() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            let userID = try await requests.seedIntegrationUser(storage, name: "alice",
                storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "alice", storedHash: storedHash)
            let header = "GoogleLogin auth=\(token)"
            let entryID = try await storage.withConnection { connection in
                let categoryID = try await seedCategory(connection, userID: userID, title: "Tech")
                let feedID = try await seedFeed(connection, userID: userID, categoryID: categoryID,
                    url: "https://example.com/feed")
                return try await seedEntry(connection, userID: userID, feedID: feedID, hash: "h1")
            }

            // `i` in the query only, for a POST: a patch that read `r.PostForm` reported the guard
            // here.
            let fromQuery = try await requests.post(contents,
                raw: requests.body(token: token, pairs: ["output=json"]),
                query: "s=user/-/state/com.google/reading-list&output=json&i=\(itemID(entryID))",
                header: header)
            #expect(fromQuery.status == .ok, "the merged form is what this read uses")
            #expect(try requests.body(of: fromQuery).contains("\"id\":\"\(itemID(entryID))\""),
                "and the id the query half names is applied")

            // No `i` on either side is the guard's answer, rather than an empty list.
            let none = try await requests.post(contents,
                raw: requests.body(token: token, pairs: ["output=json"]),
                query: "s=user/-/state/com.google/reading-list&output=json", header: header)
            #expect(none.status == .badRequest, "the status the guard answer writes")
            #expect(try requests.body(of: none) ==
                "{\"error_message\":\"googlereader: no items requested\"}", "the guard's own wording")
        }
    }

    @Test func theOutputCheckAndTheStreamReadRunBeforeTheItemIdsGuard() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            let userID = try await requests.seedIntegrationUser(storage, name: "alice",
                storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "alice", storedHash: storedHash)
            let header = "GoogleLogin auth=\(token)"

            // An input that fails both answers the first one: the output check, which is what this
            // endpoint applies. A patch that did not apply it here answered the `i` guard.
            let both = try await requests.post(contents,
                raw: requests.body(token: token, pairs: ["output=x"]), header: header)
            #expect(both.status == .badRequest)
            #expect(try requests.body(of: both) ==
                "{\"error_message\":\"googlereader: only json output is supported\"}",
                "the output check runs first, and this endpoint applies it")

            // The stream read is the second, so an unknown stream with no `i` is the 500 answer.
            let stream = try await requests.post(contents,
                raw: requests.body(token: token, pairs: ["output=json"]),
                query: "s=unknown&output=json", header: header)
            #expect(stream.status == .internalServerError, "the stream read runs before the item guard")
            #expect(try requests.body(of: stream) ==
                "{\"error_message\":\"googlereader: unknown stream type: unknown\"}",
                "with the wording the stream read gave")
        }
    }

    @Test func anEntryWithNoAttachmentAnswersTheEmptyList() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            let userID = try await requests.seedIntegrationUser(storage, name: "alice",
                storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "alice", storedHash: storedHash)
            let header = "GoogleLogin auth=\(token)"

            let (withOne, withNone) = try await storage.withConnection { connection in
                let categoryID = try await seedCategory(connection, userID: userID, title: "Tech")
                let feedID = try await seedFeed(connection, userID: userID, categoryID: categoryID,
                    url: "https://example.com/feed")
                let one = try await seedEntry(connection, userID: userID, feedID: feedID, hash: "h1")
                let none = try await seedEntry(connection, userID: userID, feedID: feedID, hash: "h2")
                let entries = EntryRepository(connection)
                try await entries.upsert(userID: userID, feedID: feedID,
                    input: entryInput(hash: "h1",
                        enclosures: [.init(url: "https://example.com/a.mp3", mimeType: "audio/mpeg")]),
                    updateExisting: true)
                return (one, none)
            }

            let response = try await requests.post(contents,
                raw: requests.body(token: token, pairs: ["i=\(itemID(withOne))", "i=\(itemID(withNone))"]),
                query: "s=user/-/state/com.google/reading-list&output=json", header: header)
            #expect(response.status == .ok)
            let body = try requests.body(of: response)
            #expect(body.contains("\"enclosure\":[{\"url\":\"https://example.com/a.mp3\","
                + "\"type\":\"audio/mpeg\"}]"), "the attachment the row carries")
            #expect(body.contains("\"enclosure\":[]"),
                "and the row with none, written as `[]` because the reference builds the slice with make")
        }
    }

    // MARK: - Helpers

    /// Seeds the graph one item needs, with a value for each rule a pin reads on its own row: the
    /// feed row's own title and site url, which the fixture writes as empty, and the three time
    /// columns.
    private func seedContent(_ storage: SQLiteStorage, userID: Int, feedURL: String, siteURL: String,
        feedTitle: String, categoryTitle: String, entryURL: String, content: String, publishedAt: Int,
        createdAt: Int, updatedAt: Int, author: String = "Author") async throws
        -> (feedID: Int, entryID: Int, created: Int, changed: Int) {
        try await storage.withConnection { connection in
            let categoryID = try await seedCategory(connection, userID: userID, title: categoryTitle)
            // An extra feed row is seeded first, so the feed id the origin stream id is built from
            // is a different number from the entry id the item id is built from.
            _ = try await seedFeed(connection, userID: userID, categoryID: categoryID,
                url: "https://other.example/")
            let feedID = try await seedFeed(connection, userID: userID, categoryID: categoryID,
                url: feedURL)
            try await sqlDatabase(connection).raw("""
                UPDATE feeds SET title = \(bind: feedTitle), site_url = \(bind: siteURL)
                WHERE id = \(bind: feedID)
                """).run()
            let entryID = try await seedEntry(connection, userID: userID, feedID: feedID, hash: "h1",
                url: entryURL, author: author, content: content, publishedAt: publishedAt)
            try await sqlDatabase(connection).raw("""
                UPDATE entries SET created_at = \(bind: createdAt), updated_at = \(bind: updatedAt)
                WHERE id = \(bind: entryID)
                """).run()
            return (feedID, entryID, createdAt, updatedAt)
        }
    }

    /// The whole answer, with the item parts as the reference declares them. The key order is
    /// pinned as pure logic by `GoogleReaderShapeTests`, so the pins here vary the values only.
    private func document(selfHref: String, updated: Int, author: String, items: [String]) -> String {
        "{\"direction\":\"ltr\",\"id\":\"user/-/state/com.google/reading-list\",\"title\":\"Reading "
            + "List\",\"self\":[{\"href\":\"\(selfHref)\"}],\"updated\":\(updated),\"items\":["
            + items.joined(separator: ",") + "],\"author\":\"\(author)\"}"
    }

    private func item(id: String, categories: String, title: String, crawlTimeMsec: Int,
        timestampUsec: Int, published: Int, updated: Int, author: String, url: String,
        content: String, streamID: String, feedTitle: String, siteURL: String,
        enclosures: String) -> String {
        "{\"id\":\"\(id)\",\"categories\":[\(categories)],\"title\":\"\(title)\","
            + "\"crawlTimeMsec\":\"\(crawlTimeMsec * 1_000)\",\"timestampUsec\":\"\(timestampUsec * 1_000_000)\","
            + "\"published\":\(published),\"updated\":\(updated),\"author\":\"\(author)\","
            + "\"alternate\":[{\"href\":\"\(url)\",\"type\":\"text/html\"}],"
            + "\"summary\":{\"direction\":\"ltr\",\"content\":\"\(content)\"},"
            + "\"content\":{\"direction\":\"ltr\",\"content\":\"\(content)\"},"
            + "\"origin\":{\"streamId\":\"\(streamID)\",\"title\":\"\(feedTitle)\",\"htmlUrl\":\"\(siteURL)\"},"
            + "\"enclosure\":\(enclosures),\"canonical\":[{\"href\":\"\(url)\"}]}"
    }

    /// The order the handler appends the categories in, which `GoogleReaderItemCategoriesTests`
    /// pins as the rule; here the list is what a pin asserts, not what it computes.
    private func categories(_ userID: Int, label: String, read: Bool, starred: Bool) -> String {
        var parts = ["\"user/\(userID)/state/com.google/reading-list\""]
        if !label.isEmpty { parts.append("\"user/\(userID)/label/\(label)\"") }
        if read { parts.append("\"user/\(userID)/state/com.google/read\"") }
        if starred { parts.append("\"user/\(userID)/state/com.google/starred\"") }
        return parts.joined(separator: ",")
    }

    /// `ItemIDFormat`: the prefix with the value as 16 lowercase hex digits.
    private func itemID(_ value: Int) -> String {
        "tag:google.com,2005:reader/item/" + String(format: "%016x", value)
    }

    private func firstInt(_ body: String, marker: String) -> Int? {
        guard let range = body.range(of: marker) else { return nil }
        return Int(body[range.upperBound...].prefix { $0.isNumber })
    }

    private func firstPosition(of body: String, of value: String) -> Int {
        body.distance(from: body.startIndex, to: body.range(of: value)!.lowerBound)
    }

    private func occurrences(of body: String, of value: String) -> Int {
        var count = 0
        var searchStart = body.startIndex
        while let range = body.range(of: value, range: searchStart..<body.endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count
    }
}
