import FluentKit
import Foundation
import SQLKit
import Testing
import Vapor
@testable import RivuletApp
@testable import RivuletCore

/// The six category paths this stage registers, read over a real socket. 15 pins and 16 probes,
/// every probe seen to fail on the rule it names and to revert the file byte-identically.
///
/// Every pin reads the account the guard hands the handler, and the account read adds the default
/// category with the row, so the default row is part of the input each pin names.
///
/// What each pin can fail on, with the patch its probe names:
/// - the path and the method the pattern registers — a patch that moved one of the five registrations
///   to another path, which fires on every pin that reads the handler that registration gives;
/// - the order the plain list read answers in, which a patch that ordered it by the position column
///   fires here;
/// - the two counts being written only for the half that reads them — a patch that wrote them for
///   every answer, or that skipped a zero, fires on one of the two assertions here and on the pure
///   shape pin;
/// - the account the counts read is given, which a patch that dropped the account filter fires here;
/// - the value the query name is read as, which a patch that read the name as any non-empty string
///   fires on;
/// - the guard that the segment is read before anything is read against the storage layer, which a
///   patch that read the row first answers as the row's answer rather than as 400;
/// - the order the update handler runs in: the row is read before the body is read, so a request that
///   fails both answers the row's answer, which a patch that put the body read first fires on;
/// - the pair the update and the delete are guarded by, which a patch that took the account out of
///   both the guard's read and the statement that writes fires on — the statement's own guard alone
///   is shown by the pure pin, because no request reaches it for a row the guard did not read;
/// - the rule the validator answers first for an input that fails both rules, which a patch that put
///   the duplicate read first fires on;
/// - the status each answer carries: 201 for the two write paths, 204 for the delete, 404 for a row
///   that is not there, 400 for the segment and for a body the read fails on — one patch per status.
///
/// What these pins cannot show: the wording the reference's decoder answers for a body it cannot read,
/// which is the text its decoder builds from the position it failed at and is recorded in
/// `docs/parity.md`; the order the account read and the counts read run in for the `counts=true` half,
/// because the guard that hands the handler the id has already read the same row, so no request this
/// suite can build reaches the answer for a row that is not there; the storage failure each read can
/// answer with, which this suite cannot trigger; the report the delete makes for a row it did not
/// remove, which the guard reads before the write so no request reaches it here; the sorting order the
/// reference reads from the user row for the counts half, which this port's schema has no column for —
/// the port answers the reference's default order, recorded as a deviation; the feed document the
/// feeds half writes, which the feeds suite pins; and for the delete pin the assertion that the answer
/// carries no document, because the client does not read a body for a 204 — a patch that wrote one for
/// that status could not reach this pin, so only the status half of it is falsifiable here.
@Suite struct RestV1CategoryRouteTests {
    init() {
        TestLogging.bootstrapOnce()
    }

    private let storedHash = "$2a$10$hOrIpoEkDKAMFrOt2/k1yeyHBaZKOwK8zEg9JVchReOAtQZ5mEeFu"
    private let token = "key-for-alice"

    @Test func thePlainListAnswersTheOrderTheReadAnswersIn() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                // The position order and the title order disagree on this input: the row that came
                // first carries the title that comes second, so a patch that ordered by the position
                // column answers the other order here.
                _ = try await seedCategory(connection, userID: alice, title: "Zeta", position: 0)
                _ = try await seedCategory(connection, userID: alice, title: "Amy", position: 1)
            }

            let response = try await request(app, base, method: .GET, path: "/v1/categories")
            #expect(response.status == .ok, "the registered path answers the read, not the router")
            #expect(try body(of: response) ==
                "[{\"id\":1,\"user_id\":1,\"title\":\"All\",\"hide_globally\":false},"
                + "{\"id\":3,\"user_id\":1,\"title\":\"Amy\",\"hide_globally\":false},"
                + "{\"id\":2,\"user_id\":1,\"title\":\"Zeta\",\"hide_globally\":false}]",
                "the title order, and no counts for this half")
        }
    }

    @Test func theCountsHalfWritesTheCountsAndTheOrderTheReferenceDefaultsTo() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                // The default row has no unread entry and the named row has one, so the two orders
                // the read could answer disagree: the count order puts Zeta first, the title order
                // puts the default row first.
                let zeta = try #require(try await CategoryRepository(connection)
                    .create(userID: alice, title: "Zeta").id)
                let zetaFeed = try #require(try await FeedRepository(connection)
                    .create(userID: alice, categoryID: zeta, url: "https://example.com/zeta").id)
                try await seedEntry(connection, userID: alice, feedID: zetaFeed, hash: "h-zeta",
                    status: "unread")
                let aliceFeed = try #require(try await FeedRepository(connection)
                    .create(userID: alice, categoryID: 1, url: "https://example.com/all").id)
                try await seedEntry(connection, userID: alice, feedID: aliceFeed, hash: "h-all",
                    status: "read")
            }

            let response = try await request(app, base, method: .GET,
                path: "/v1/categories?counts=true")
            #expect(try body(of: response) ==
                "[{\"id\":2,\"user_id\":1,\"title\":\"Zeta\",\"hide_globally\":false,"
                + "\"feed_count\":1,\"total_unread\":1},"
                + "{\"id\":1,\"user_id\":1,\"title\":\"All\",\"hide_globally\":false,"
                + "\"feed_count\":1,\"total_unread\":0}]",
                "the unread count first, then the title, with the counts written, a zero included")
        }
    }

    @Test func theCountsHalfIsReachedOnlyByTheValueTheQueryNameAnswersAsTrue() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
            }

            // The reference reads the name as a boolean, so a value the parse fails on answers the
            // default, which is false, and the counts half is not reached. A patch that read the name
            // as any non-empty string fired on this pin.
            let notABoolean = try await request(app, base, method: .GET,
                path: "/v1/categories?counts=maybe")
            #expect(try body(of: notABoolean) ==
                "[{\"id\":1,\"user_id\":1,\"title\":\"All\",\"hide_globally\":false}]",
                "a value the read cannot answer as true is the default")

            let on = try await request(app, base, method: .GET, path: "/v1/categories?counts=1")
            #expect(try body(of: on) ==
                "[{\"id\":1,\"user_id\":1,\"title\":\"All\",\"hide_globally\":false,"
                + "\"feed_count\":0,\"total_unread\":0}]",
                "the value the read answers as true reaches the counts half")
        }
    }

    @Test func theCountsReadAppliesTheAccountItIsGivenOverTheSocket() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                let bob = try #require(try await UserRepository(connection)
                    .create(username: "bob", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                _ = try await seedCategory(connection, userID: bob, title: "Only bob")
            }

            let response = try await request(app, base, method: .GET, path: "/v1/categories?counts=true")
            #expect(try body(of: response) ==
                "[{\"id\":1,\"user_id\":1,\"title\":\"All\",\"hide_globally\":false,"
                + "\"feed_count\":0,\"total_unread\":0}]",
                "the account the read is given, not every row")
        }
    }

    @Test func thePathTheReferenceHasNoPatternForAnswersTheRouter() async throws {
        try await withServedApp { _, app, base in
            // The reference's mux has no GET pattern for this path: it registers PUT and DELETE on it
            // only. The port registers no route for it either, so the answer is the router's, which is
            // the parity row this pin reads.
            let response = try await request(app, base, method: .GET, path: "/v1/categories/1")
            #expect(response.status == .notFound, "no pattern, so the router answers")
            #expect(try body(of: response).contains("\"error\":true"),
                "the router's own shape, read key by key: the key order was not fixed across runs")
            #expect(try body(of: response).contains("\"reason\":\"Not Found\""),
                "the other key of the same shape, read on its own")
        }
    }

    @Test func theSegmentIsReadBeforeAnythingIsReadAgainstTheStorageLayer() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
            }

            // A segment the read answers 0 for: the guard runs before the row read, so the answer is
            // 400 for the segment, not 404 for a row that is not there. A patch that read the row
            // first answered 404 here.
            let response = try await request(app, base, method: .PUT,
                path: "/v1/categories/not-a-number", body: "{\"title\":\"Renamed\"}")
            #expect(response.status == .badRequest, "the segment is read first")
            #expect(try body(of: response) == "{\"error_message\":\"invalid category ID\"}",
                "the reference's wording for the segment rule")
            #expect(try await categoryTitle(storage, userID: 1, id: 1) == "All",
                "and nothing was written for the segment the read answered 0 for")
        }
    }

    @Test func theCreateAnswersTheDocumentAndTheStatusTheWritePathCarries() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
            }

            let response = try await request(app, base, method: .POST, path: "/v1/categories",
                body: "{\"title\":\"News\",\"hide_globally\":true}")
            #expect(response.status == .created, "the status the create path writes")
            #expect(try body(of: response) ==
                "{\"id\":2,\"user_id\":1,\"title\":\"News\",\"hide_globally\":true}",
                "the document for the row the write made")
        }
    }

    @Test func theValidatorAnswersTheRuleItReadsFirstForAnInputThatFailsBoth() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                // The input fails both rules only when a row already carries the empty title, so the
                // answer names the rule the reference reads first. A patch that put the duplicate read
                // first answered the other rule here.
                _ = try await seedCategory(connection, userID: alice, title: "")
            }

            let response = try await request(app, base, method: .POST, path: "/v1/categories",
                body: "{\"title\":\"\"}")
            #expect(response.status == .badRequest, "the rule block answers 400")
            #expect(try body(of: response) == "{\"error_message\":\"titleRequired\"}",
                "the rule the reference reads first, named as this port names it")
        }
    }

    @Test func theDuplicateTitleAnswersItsOwnRule() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                _ = try await seedCategory(connection, userID: alice, title: "News")
            }

            let response = try await request(app, base, method: .POST, path: "/v1/categories",
                body: "{\"title\":\"news\"}")
            #expect(response.status == .badRequest, "the duplicate read lowercases both sides")
            #expect(try body(of: response) == "{\"error_message\":\"alreadyExists\"}",
                "the other rule, named as this port names it")
        }
    }

    @Test func aBodyTheReadFailsOnAnswersBadRequest() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
            }

            let response = try await request(app, base, method: .POST, path: "/v1/categories", body: "")
            #expect(response.status == .badRequest,
                "a body with no value is a failure, not an empty document")
            #expect(try body(of: response) == "{\"error_message\":\"unexpectedEnd\"}",
                "the rule this port names for it")
        }
    }

    @Test func theUpdateReadsTheRowBeforeItReadsTheBody() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
            }

            // Both halves fail on this input: the row is not there and the body is not a document the
            // read can answer. The reference reads the row first, so the answer is the row's, which a
            // patch that put the body read first turned into 400.
            let response = try await request(app, base, method: .PUT, path: "/v1/categories/9", body: "{")
            #expect(response.status == .notFound, "the row read runs before the body read")
            #expect(try body(of: response) == "{\"error_message\":\"resource not found\"}",
                "the reference's wording for a row its read does not find")
        }
    }

    @Test func theUpdatePatchesOnlyTheFieldsTheRequestCarries() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                try await CategoryRepository(connection).update(userID: alice, id: 1, title: "All",
                    hideGlobally: true)
            }

            let response = try await request(app, base, method: .PUT, path: "/v1/categories/1",
                body: "{\"title\":\"Renamed\"}")
            #expect(response.status == .created, "the status the update path writes")
            #expect(try body(of: response) ==
                "{\"id\":1,\"user_id\":1,\"title\":\"Renamed\",\"hide_globally\":true}",
                "the field the request carried, and the one it did not left as the row had it")
        }
    }

    @Test func theUpdateWritesOnlyTheRowOfTheAccountItIsGiven() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                let bob = try #require(try await UserRepository(connection)
                    .create(username: "bob", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                _ = try await seedCategory(connection, userID: bob, title: "Bob")
            }

            // The pair is read before the write, so another account's row with this id answers 404 and
            // stays where it is. The patch that fires here takes the account out of both the read the
            // guard runs and the statement that writes; the write's own guard alone is shown by the
            // pure pin, because no request reaches the write for a row the guard did not read.
            let response = try await request(app, base, method: .PUT, path: "/v1/categories/3",
                body: "{\"title\":\"Renamed\"}")
            #expect(response.status == .notFound, "the pair, not the id alone")
            #expect(try await categoryTitle(storage, userID: 2, id: 3) == "Bob",
                "and the row is still there as it was")
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
                _ = try await seedCategory(connection, userID: bob, title: "Bob")
            }

            // The pair is read before the write, so another account's row with this id answers 404 and
            // stays. The patch that fires here takes the account out of both the guard's read and the
            // statement that deletes; the statement's own guard alone is shown by the pure pin,
            // because no request reaches it for a row the guard did not read.
            let other = try await request(app, base, method: .DELETE, path: "/v1/categories/3")
            #expect(other.status == .notFound, "the pair, not the id alone")
            #expect(try await categoryTitle(storage, userID: 2, id: 3) == "Bob",
                "and the row the guard did not read is still there")

            let mine = try await request(app, base, method: .DELETE, path: "/v1/categories/1")
            #expect(mine.status == .noContent, "the status the delete path writes")
            #expect(mine.body == nil, "and no document")
        }
    }

    @Test func theCategoryFeedsHalfReadsTheRowBeforeItReadsTheFeeds() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                let bob = try #require(try await UserRepository(connection)
                    .create(username: "bob", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                // A row of another account under the same category: the read is guarded by the pair,
                // so a patch that dropped the account filter answered it here.
                _ = try await FeedRepository(connection).create(userID: bob, categoryID: 1,
                    url: "https://example.com/bob")
            }

            // The row is read before the feeds, so a request that names a row that is not there answers
            // the row's answer. The patch that fires here takes the row guard out, so the feeds read
            // answers first.
            let missing = try await request(app, base, method: .GET, path: "/v1/categories/9/feeds")
            #expect(missing.status == .notFound, "the row read runs before the feeds read")

            let response = try await request(app, base, method: .GET, path: "/v1/categories/1/feeds")
            #expect(response.status == .ok, "the registered path answers the read")
            #expect(try body(of: response) == "[]", "the account has no feed row on this input")
        }
    }

    // MARK: - Rows and requests

    private func seedCategory(_ connection: any Database, userID: Int, title: String,
        position: Int = 0, hideGlobally: Bool = false) async throws -> Int {
        let category = try await CategoryRepository(connection)
            .create(userID: userID, title: title, hideGlobally: hideGlobally)
        let id = try #require(category.id)
        if position != 0 {
            try await RawSQL.sql(on: connection).raw(
                "UPDATE categories SET position = \(bind: position) WHERE id = \(bind: id)").run()
        }
        return id
    }

    private func seedEntry(_ connection: any Database, userID: Int, feedID: Int, hash: String,
        status: String) async throws {
        try await RawSQL.sql(on: connection).raw("""
            INSERT INTO entries (user_id, feed_id, hash, status, published_at, created_at, updated_at)
            VALUES (\(bind: userID), \(bind: feedID), \(bind: hash), \(bind: status),
                \(bind: 1_000_000_000), \(bind: 1_000_000_000), \(bind: 1_000_000_000))
            """).run()
    }

    private func insertKey(_ connection: any Database, userID: Int, token: String) async throws {
        try await RawSQL.sql(on: connection).raw("""
            INSERT INTO api_keys (user_id, token, description, created_at)
            VALUES (\(bind: userID), \(bind: token), \(bind: "phone app"), \(bind: 1_000_000_000))
            """).run()
    }

    private func categoryTitle(_ storage: SQLiteStorage, userID: Int, id: Int) async throws -> String? {
        try await storage.withConnection { connection in
            try await CategoryRepository(connection).fetch(userID: userID, id: id)?.title
        }
    }

    private func request(_ app: Application, _ base: String, method: HTTPMethod, path: String,
        body: String = "") async throws -> ClientResponse {
        try await app.client.send(method, to: URI(string: base + path)) { request in
            request.headers.add(name: "X-Auth-Token", value: token)
            if !body.isEmpty {
                request.headers.add(name: "Content-Type", value: "application/json")
                request.body = .init(string: body)
            }
        }
    }

    private func body(of response: ClientResponse) throws -> String {
        let body = try #require(response.body)
        return String(decoding: body.readableBytesView, as: UTF8.self)
    }
}
