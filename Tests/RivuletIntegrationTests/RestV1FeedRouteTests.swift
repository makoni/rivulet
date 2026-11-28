import FluentKit
import Foundation
import SQLKit
import Testing
import Vapor
@testable import RivuletApp
@testable import RivuletCore

/// The eight feed paths this stage registers, read over a real socket.
///
/// Every pin reads the account the guard hands the handler, and the account read adds the default
/// category with the row, so the default row is part of the input each pin names.
///
/// What each pin can fail on, with the patch its probe names:
/// - the path and the method the pattern registers — a patch that moved one of the eight
///   registrations to another path fires on every pin that reads the handler it gives;
/// - the order the feed list read answers in, which a patch that ordered it by the row id fires here;
/// - the account the list, the single-row read, the category fallback, the icon read and the mark write
///   are given, which a patch that dropped the account condition from each of them fires on;
/// - the feed the mark write is given, which a patch that took the feed condition out of the statement
///   fires on — the input carries a row of this account in another feed, so the statement's own feed
///   condition is what the pin reads;
/// - the guard that the segment is read before anything is read against the storage layer, one patch
///   per path: the six paths that name a segment each answer 400 for a segment the read answers 0 for,
///   so a patch that removed one guard turns that one answer into the row's answer;
/// - the order the update handler runs in: the body is read before the row, so a request that fails
///   both answers the body's answer, which a patch that put the row read first fires on — this is the
///   opposite order from the category update, and the two pins read the two orders;
/// - the rule the validator answers first for an input that fails two rules, one patch per pair of
///   rules: the mandatory rule before the duplicate read, and the absolute-URL rule before it;
/// - the category fallback, which a patch that wrote the category the request carried fires on;
/// - the write the create path runs after the rule block, which a patch that wrote before the block
///   fires on;
/// - the patch semantics of the update: a field the request did not carry is left as the row had it,
///   which a patch that wrote a field the request did not carry as the zero value fires on;
/// - the error-counter reset, which a patch that skipped it fires on;
/// - the document the update writes being built from the row as it is after the write, which a patch
///   that answered the row as it was read fires on;
/// - the three keys of the icon document and the order they are written in, which a patch that
///   reordered them fires on;
/// - the order the refresh handler runs in: the pair is read before the fetch runs, which a patch that
///   ran the fetch first fires on — the fetch is read through the seam the pin names, because the
///   network half itself is not what this pin reads;
/// - the status each answer carries: 201 for the two write paths, 204 for the three paths that write
///   without a document, 404 for a row that is not there on each of the six paths that name a segment,
///   400 for the segment and for a body the read fails on — one patch per status.
///
/// What these pins cannot show: the fetch, the parse and the icon check the create path runs, which
/// are the network half and are pinned by the refresh suite through the fetcher, not here; the
/// `feed_icons` mapping the reference reads for the icon, which this port keeps as `feeds.icon_id` and
/// which `docs/parity.md` records as a divergence — the pin reads the answer the port's mapping gives;
/// the duplicate read the modification path consults, which the schema's `UNIQUE (user_id, url)` means
/// can never answer true for the same account, so the order between it and the rule before it is not
/// pinnable here and the read itself is pinned by `FeedManagementReadsTests`; the account condition of
/// the create path's duplicate read, which no request this suite can build reaches because the read is
/// guarded by the rules before it; the delete statement's own account guard, which no request reaches
/// for a row the guard did not read, so the pure pin shows it; the storage failure each read can answer
/// with, which this suite cannot trigger; the fields the
/// reference's feed struct declares and this port has no column for, which the shape pin records; the
/// `updated_at` stamp the write makes, which no pin reads; and for the three paths that answer 204 the
/// assertion that the answer carries no document, because the client does not read a body for a 204 —
/// a patch that wrote one for that status could not reach these pins, so only the status half of each
/// is falsifiable here.
@Suite struct RestV1FeedRouteTests {
    init() {
        TestLogging.bootstrapOnce()
    }

    let storedHash = "$2a$10$hOrIpoEkDKAMFrOt2/k1yeyHBaZKOwK8zEg9JVchReOAtQZ5mEeFu"
    let token = "key-for-alice"

    @Test func theFeedListAnswersTheOrderTheReadAnswersIn() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                // The row that came first carries the lower error count, so the id order and the
                // count order disagree on this input: the read answers the count order.
                let first = try #require(try await FeedRepository(connection)
                    .create(userID: alice, categoryID: 1, url: "https://example.com/a").id)
                let second = try #require(try await FeedRepository(connection)
                    .create(userID: alice, categoryID: 1, url: "https://example.com/b").id)
                try await setFeedTitle(connection, id: first, title: "Zeta", errorCount: 0)
                try await setFeedTitle(connection, id: second, title: "Amy", errorCount: 5)
            }

            let response = try await request(app, base, method: .GET, path: "/v1/feeds")
            #expect(response.status == .ok, "the registered path answers the read, not the router")
            #expect(try body(of: response) == "[" + feedDocument(id: 2,
                url: "https://example.com/b", title: "Amy", errorCount: 5) + ","
                + feedDocument(id: 1, url: "https://example.com/a", title: "Zeta", errorCount: 0) + "]",
                "the error count descending, not the row id")
        }
    }

    @Test func theFeedListAppliesTheAccountItIsGiven() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                let bob = try #require(try await UserRepository(connection)
                    .create(username: "bob", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                _ = try await FeedRepository(connection).create(userID: bob, categoryID: 2,
                    url: "https://example.com/bob")
            }

            let response = try await request(app, base, method: .GET, path: "/v1/feeds")
            #expect(try body(of: response) == "[]", "the account the read is given, not every row")
        }
    }

    @Test func theSingleRowReadIsGuardedByTheAccount() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                let bob = try #require(try await UserRepository(connection)
                    .create(username: "bob", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                _ = try await FeedRepository(connection).create(userID: bob, categoryID: 2,
                    url: "https://example.com/bob")
            }

            let response = try await request(app, base, method: .GET, path: "/v1/feeds/1")
            #expect(response.status == .notFound, "the pair, not the id alone")
        }
    }

    @Test func theSegmentIsReadBeforeAnythingIsReadAgainstTheStorageLayer() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
            }

            // A segment the read answers 0 for on each of the six paths that name one: the guard runs
            // before anything is read against the storage layer, so the answer is 400 for the segment,
            // not 404 for a row that is not there. One patch per path, each removing that path's guard.
            #expect(try body(of: try await request(app, base, method: .GET, path: "/v1/feeds/0"))
                == "{\"error_message\":\"invalid feed ID\"}", "the single-row read's own guard")
            #expect(try body(of: try await request(app, base, method: .PUT, path: "/v1/feeds/0",
                body: "{\"title\":\"Renamed\"}")) == "{\"error_message\":\"invalid feed ID\"}",
                "the update's own guard")
            #expect(try body(of: try await request(app, base, method: .DELETE, path: "/v1/feeds/0"))
                == "{\"error_message\":\"invalid feed ID\"}", "the delete's own guard")
            #expect(try body(of: try await request(app, base, method: .GET, path: "/v1/feeds/0/icon"))
                == "{\"error_message\":\"invalid feed ID\"}", "the icon read's own guard")
            #expect(try body(of: try await request(app, base, method: .PUT, path: "/v1/feeds/0/refresh"))
                == "{\"error_message\":\"invalid feed ID\"}", "the refresh's own guard")
            #expect(try body(of: try await request(app, base, method: .PUT,
                path: "/v1/feeds/0/mark-all-as-read")) == "{\"error_message\":\"invalid feed ID\"}",
                "the mark write's own guard")
        }
    }

    @Test func theUpdateReadsTheBodyBeforeItReadsTheRow() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
            }

            // Both halves fail on this input: the body is not a document the read can answer and
            // the row is not there. The reference reads the body first, so the answer is the
            // body's, which a patch that put the row read first turned into 404.
            let response = try await request(app, base, method: .PUT, path: "/v1/feeds/9", body: "{")
            #expect(response.status == .badRequest, "the body read runs before the row read")
            #expect(try body(of: response) == "{\"error_message\":\"unexpectedEnd\"}",
                "the rule this port names for a body with no value")

            // The same path with an input that fails only the row: the answer is the row's, which a
            // patch that answered the row's half with the status the write path writes fires on.
            let missing = try await request(app, base, method: .PUT, path: "/v1/feeds/9",
                body: "{\"title\":\"Renamed\"}")
            #expect(missing.status == .notFound, "the row read answers for a row that is not there")
        }
    }

    @Test func theCreateAnswersTheDocumentAndTheStatusTheWritePathCarries() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
            }

            let response = try await request(app, base, method: .POST, path: "/v1/feeds",
                body: "{\"feed_url\":\"https://example.com/new\"}")
            #expect(response.status == .created, "the status the create path writes")
            #expect(try body(of: response) == "{\"feed_id\":1}",
                "the one-key document the create path writes, for the row the write made")
        }
    }

    @Test func theCreateResolvesAZeroCategoryToTheFirstRowByTitle() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                let bob = try #require(try await UserRepository(connection)
                    .create(username: "bob", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                // The default row is not the first by title on this input, so a patch that skipped the
                // fallback wrote the category the request carried, which is 0. And the first row by
                // title of another account sorts before this account's, so a patch that took the account
                // condition out of the read answered that row here.
                _ = try await seedCategory(connection, userID: bob, title: "Aa")
                _ = try await seedCategory(connection, userID: alice, title: "Aardvark")
            }

            let response = try await request(app, base, method: .POST, path: "/v1/feeds",
                body: "{\"feed_url\":\"https://example.com/new\",\"category_id\":0}")
            #expect(response.status == .created, "the fallback ran before the category rule")
            #expect(try await feedCategory(storage, userID: 1, id: 1) == 4,
                "the first row by title of this account, not the value the request carried")
        }
    }

    @Test func theCreateValidatorAnswersTheRuleItReadsFirstForAnInputThatFailsTwoRules() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                // Two rows that the two rules would answer for: the empty url and the non-absolute one,
                // so an input that names either fails the rule block and the duplicate read at once.
                _ = try await FeedRepository(connection).create(userID: alice, categoryID: 1, url: "")
                _ = try await FeedRepository(connection).create(userID: alice, categoryID: 1,
                    url: "example.com/there")
            }

            // The input fails the mandatory rule and the duplicate read at once, so the answer names
            // the rule the reference reads first. The patch that fires here puts the duplicate read
            // before the mandatory guard.
            let both = try await request(app, base, method: .POST, path: "/v1/feeds",
                body: "{\"feed_url\":\"\",\"category_id\":1}")
            #expect(both.status == .badRequest, "the rule block answers 400")
            #expect(try body(of: both) == "{\"error_message\":\"mandatoryFields\"}",
                "the mandatory rule, read before the duplicate read")

            // The same shape of input fails the absolute-URL rule and the duplicate read, so the answer
            // names the rule read first; the patch that fires here puts the duplicate read before it.
            let absolute = try await request(app, base, method: .POST, path: "/v1/feeds",
                body: "{\"feed_url\":\"example.com/there\",\"category_id\":1}")
            #expect(try body(of: absolute) == "{\"error_message\":\"invalidURL\"}",
                "the absolute-URL rule, read before the duplicate read")
        }
    }

    @Test func theCreateWritesNothingWhenTheRuleBlockAnswers() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
            }

            let response = try await request(app, base, method: .POST, path: "/v1/feeds",
                body: "{\"feed_url\":\"not-a-url\",\"category_id\":1}")
            #expect(response.status == .badRequest, "the rule block answers before the write runs")
            #expect(try await feedTitle(storage, userID: 1, id: 1) == nil,
                "and no row was written for an input the block answered")
        }
    }

    @Test func theModificationRuleBlockAnswersForAnInputThatFailsIt() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                _ = try await FeedRepository(connection).create(userID: alice, categoryID: 1,
                    url: "https://example.com/kept")
            }

            // The rule the modification path reads first for a field the request carried. A patch that
            // took the empty check out of the block wrote the url and answered 201 here. The order
            // between this rule and the duplicate read is not pinnable: the schema's UNIQUE
            // (user_id, url) means the duplicate read can never answer true for the same account, so no
            // request this suite can build reaches the second rule.
            let response = try await request(app, base, method: .PUT, path: "/v1/feeds/1",
                body: "{\"feed_url\":\"\"}")
            #expect(response.status == .badRequest, "the rule block answers 400")
            #expect(try body(of: response) == "{\"error_message\":\"feedURLNotEmpty\"}",
                "the rule this port names for the modification path")
            #expect(try await feedURL(storage, userID: 1, id: 1) == "https://example.com/kept",
                "and nothing was written for an input the block answered")
        }
    }

    // MARK: - Rows and requests

    func feedDocument(id: Int, url: String, title: String, errorCount: Int) -> String {
        // The 14 keys the shape writes, in the order the reference's struct declares them; the pin
        // that reads the order is `RestV1ShapeTests`, which writes the whole document from literals.
        "{\"id\":\(id),\"user_id\":1,\"feed_url\":\"\(url)\",\"site_url\":\"\",\"title\":\"\(title)\","
        + "\"description\":\"\",\"etag_header\":\"\",\"last_modified_header\":\"\","
        + "\"parsing_error_message\":\"\",\"parsing_error_count\":\(errorCount),\"user_agent\":\"\","
        + "\"disabled\":false,\"ignore_http_cache\":false,\"fetch_via_proxy\":false}"
    }

    func setFeedTitle(_ connection: any Database, id: Int, title: String, errorCount: Int,
        errorMessage: String = "") async throws {
        try await RawSQL.sql(on: connection).raw("""
            UPDATE feeds SET title = \(bind: title), parsing_error_count = \(bind: errorCount),
                parsing_error_message = \(bind: errorMessage) WHERE id = \(bind: id)
            """).run()
    }

    func seedCategory(_ connection: any Database, userID: Int, title: String) async throws -> Int {
        let category = try await CategoryRepository(connection).create(userID: userID, title: title)
        return try #require(category.id)
    }

    func seedEntry(_ connection: any Database, userID: Int, feedID: Int, hash: String,
        status: String) async throws {
        try await RawSQL.sql(on: connection).raw("""
            INSERT INTO entries (user_id, feed_id, hash, status, published_at, created_at, updated_at)
            VALUES (\(bind: userID), \(bind: feedID), \(bind: hash), \(bind: status),
                \(bind: 1_000_000_000), \(bind: 1_000_000_000), \(bind: 1_000_000_000))
            """).run()
    }

    func insertKey(_ connection: any Database, userID: Int, token: String) async throws {
        try await RawSQL.sql(on: connection).raw("""
            INSERT INTO api_keys (user_id, token, description, created_at)
            VALUES (\(bind: userID), \(bind: token), \(bind: "phone app"), \(bind: 1_000_000_000))
            """).run()
    }

    func feedTitle(_ storage: SQLiteStorage, userID: Int, id: Int) async throws -> String? {
        try await storage.withConnection { connection in
            try await FeedRepository(connection).fetch(userID: userID, id: id)?.title
        }
    }

    func feedURL(_ storage: SQLiteStorage, userID: Int, id: Int) async throws -> String? {
        try await storage.withConnection { connection in
            try await FeedRepository(connection).fetch(userID: userID, id: id)?.url
        }
    }

    func feedCategory(_ storage: SQLiteStorage, userID: Int, id: Int) async throws -> Int? {
        try await storage.withConnection { connection in
            try await FeedRepository(connection).fetch(userID: userID, id: id)?.categoryID
        }
    }

    func feedErrorCount(_ storage: SQLiteStorage, userID: Int, id: Int) async throws -> Int? {
        try await storage.withConnection { connection in
            try await FeedRepository(connection).fetch(userID: userID, id: id)?.parsingErrorCount
        }
    }

    func entryStatus(_ storage: SQLiteStorage, userID: Int, hash: String) async throws -> String? {
        try await storage.withConnection { connection in
            let row = try await RawSQL.sql(on: connection).raw("""
                SELECT status FROM entries WHERE user_id = \(bind: userID) AND hash = \(bind: hash)
                LIMIT 1
                """).first()
            return try row?.decode(column: "status", as: String.self)
        }
    }

    /// The seam the refresh pin names: the fetch is the network half, so the pin records whether the
    /// handler reached it after the pair read, rather than reading a socket.
    actor RecordingRunner: FeedRefreshRunner {
        private var recorded: [Int] = []

        func run(userID: Int, feedID: Int) async throws -> RefreshOutcome {
            recorded.append(feedID)
            return RefreshOutcome(conditionalHit: false, newEntryHashes: [], updatedEntryHashes: [],
                nextCheckAt: 0)
        }

        var calls: [Int] { recorded }
    }

    func request(_ app: Application, _ base: String, method: HTTPMethod, path: String,
        body: String = "") async throws -> ClientResponse {
        try await app.client.send(method, to: URI(string: base + path)) { request in
            request.headers.add(name: "X-Auth-Token", value: token)
            if !body.isEmpty {
                request.headers.add(name: "Content-Type", value: "application/json")
                request.body = .init(string: body)
            }
        }
    }

    func body(of response: ClientResponse) throws -> String {
        let body = try #require(response.body)
        return String(decoding: body.readableBytesView, as: UTF8.self)
    }
}
