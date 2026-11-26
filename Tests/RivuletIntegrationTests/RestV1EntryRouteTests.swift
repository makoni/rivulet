import FluentKit
import Foundation
import SQLKit
import Testing
import Vapor
@testable import RivuletApp
@testable import RivuletCore

/// The five entry paths this stage registers, read over a real socket.
///
/// Every pin reads the account the guard hands the handler, and the account read adds the default
/// category with the row, so the default row is part of the input each pin names.
///
/// What each pin can fail on, with the patch its probe names:
/// - the path and the method the pattern registers — a patch that moved one of the five
///   registrations to another path fires on every pin that reads the handler it gives;
/// - the order the query rules run in: the status rule before the order rule, the order rule before
///   the direction rule, the direction rule before the range rule, and the range rule before the two
///   reads the guards run — one patch per pair of rules, each firing on its own assertion;
/// - the value the list read skips, which a patch that checked every value including the empty one
///   fires on: an input carrying an empty status answers the next rule;
/// - the two reads the guards run being guarded by the account, and the order between them, which a
///   patch that put the feed read first fires on;
/// - the order the listing answers in, which a patch that ordered it by the row id fires on, and the
///   order and direction the query carries, which a patch that ignored them fires on;
/// - the count being read without the page, which a patch that answered the count as the page size
///   fires on, and the two keys of the document being written in the order the struct declares them,
///   which a patch that reordered them fires on;
/// - the page size and the offset the read applies, one patch each;
/// - the filter the query carries, which a patch that took it out of the handler fires on, and the
///   value the parse fails on answering nothing rather than the default, which a patch that read it
///   through the defaulting form fires on;
/// - the account condition of the listing, which a patch that took it out of the read fires on;
/// - the guard that the segment is read before anything is read against the storage layer, one patch
///   per path: the three paths that name a segment each answer 400 for a segment the read answers 0
///   for, so a patch that removed one guard turns that one answer into the row's answer; and the guard
///   before the query rules, which a patch that ran the rules first fires on;
/// - the rule the body block answers first for an input that fails two rules: the empty-list rule
///   before the either-field rule, read on an input that carries an empty status and no flag;
/// - the write the status path runs after the block, which a patch that wrote before the block fires
///   on, and the half the request did not carry being left as the row had it, which a patch that wrote
///   both halves fires on, one patch per half;
/// - the account condition of the two writes and of the toggle statement, which a patch that took it
///   out of each statement fires on;
/// - the single-row document: the 13 keys this port has columns for in the order the reference's struct
///   declares them, and the escape class the document writer has for the three HTML-sensitive characters,
///   read on a content value that carries all three;
/// - the status each answer carries, one patch per status the pin reads: the listing, the feed
///   listing, the single-row read, the row that is not there, the rule block, the segment, the write
///   path and the toggle.
///
/// The wording an answer writes for a rule is the name this port gives it, and for the storage failure
/// it is the description this port writes; the reference's wording for both is recorded in
/// `docs/reference-notes.md`.
///
/// What these pins cannot show: the order between the status write and the starred write, because both
/// write different columns of the same rows and a patch that swapped them answers the same; the order
/// between the either-field rule and the status rule, because the first answers only for an empty
/// status and the second only for a non-empty one, so no input fails both and no patch can flip the
/// answer; the `changed_at` filter the reference's `configureFilters` reads, which this port's query has
/// no field for, so the consumer's `changed_after` has nothing to be applied to and the pin records the
/// answer the port gives without it; the nine other filter names that block reads — the eight id and
/// date names plus `search` — which this handler does not read at all because the consumer sends none of
/// them, so the pins name only the filter the consumer sends; the `globally_visible` half, which has no column here; the tags and the enclosures
/// the reference's builder adds, which this port has no table for; the storage failure each read can
/// answer with, which this suite cannot trigger on the list paths; the fields the reference's entry
/// struct declares and this port has no column for, which the document pin records as the keys the
/// port writes; the `updated_at` stamp the writes make, which no pin reads; and for the two paths that
/// answer 204 the assertion that the answer carries no document, because the client does not read a
/// body for a 204 — a patch that wrote one for that status could not reach these pins, so only the
/// status half of each is falsifiable here.
///
/// 16 pins and 43 probes, every probe seen to fail on the rule it names and to revert the file
/// byte-identically.
@Suite struct RestV1EntryRouteTests {
    init() {
        TestLogging.bootstrapOnce()
    }

    private let storedHash = "$2a$10$hOrIpoEkDKAMFrOt2/k1yeyHBaZKOwK8zEg9JVchReOAtQZ5mEeFu"
    private let token = "key-for-alice"

    @Test func theStatusRuleIsAnsweredBeforeTheOrderAndDirectionRules() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
            }

            // Three rules this path reads in order, so an input that fails all three answers the first.
            // The patch that fires here moves the order rule, or the direction rule, before the status
            // rule.
            let all = try await request(app, base, method: .GET,
                path: "/v1/entries?status=bad&order=bad&direction=bad")
            #expect(all.status == .badRequest, "the rule block answers 400")
            #expect(try body(of: all) == "{\"error_message\":\"statusInvalid\"}",
                "the status rule, read before the other two")

            // A value the list read skips is not checked, so the next rule answers for an input whose
            // status is empty. The patch that fires here checks every value rather than the ones the
            // read keeps.
            let skipped = try await request(app, base, method: .GET, path: "/v1/entries?status=&order=bad")
            #expect(try body(of: skipped) == "{\"error_message\":\"orderInvalid\"}",
                "the empty value is skipped by the list read, so the order rule answers")
        }
    }

    @Test func theQueryRulesAreAnsweredInTheOrderTheReadRunsThem() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                // The default category of the second account is the row the guard would find for an
                // input that names it, so the account condition of the read is what the pin reads.
                _ = try await UserRepository(connection)
                    .create(username: "bob", passwordHash: storedHash, isAdmin: false)
            }

            // The order rule before the direction rule: the patch that fires here moves the direction
            // check before the order check.
            let order = try await request(app, base, method: .GET, path: "/v1/entries?order=bad&direction=bad")
            #expect(try body(of: order) == "{\"error_message\":\"orderInvalid\"}",
                "the order rule, read before the direction rule")

            // The direction rule before the range rule: the patch that fires here moves the range check
            // before the direction check.
            let direction = try await request(app, base, method: .GET,
                path: "/v1/entries?direction=bad&limit=1001")
            #expect(try body(of: direction) == "{\"error_message\":\"directionInvalid\"}",
                "the direction rule, read before the range rule")

            // The range rule before the category read: the patch that fires here moves the category
            // guard before the range check.
            let range = try await request(app, base, method: .GET,
                path: "/v1/entries?limit=1001&category_id=2")
            #expect(try body(of: range) == "{\"error_message\":\"limitTooLarge\"}",
                "the range rule, read before the category read")
        }
    }

    @Test func theCategoryReadIsGuardedByTheAccountAndRunsBeforeTheFeedRead() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                let bob = try #require(try await UserRepository(connection)
                    .create(username: "bob", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                // The two rows each guard reads: bob's feed first so its id is 1, alice's second, so the
                // input that passes the category guard names bob's feed and fails the feed guard.
                _ = try await FeedRepository(connection).create(userID: bob, categoryID: 2,
                    url: "https://example.com/bob")
                _ = try await FeedRepository(connection).create(userID: alice, categoryID: 1,
                    url: "https://example.com/a")
            }

            // Both guards fail on this input, so the answer names the read the reference runs first.
            // The patch that fires here puts the feed guard before the category guard, or takes the
            // account out of the category read, which would have found bob's row for alice.
            let both = try await request(app, base, method: .GET,
                path: "/v1/entries?category_id=2&feed_id=1")
            #expect(try body(of: both) == "{\"error_message\":\"invalid category ID\"}",
                "the category guard, read before the feed guard, and by the account it is given")

            // The same input with the first half passed: the answer is the second guard's, which a patch
            // that took the account out of the feed read answered the listing here.
            let feed = try await request(app, base, method: .GET, path: "/v1/entries?category_id=1&feed_id=1")
            #expect(try body(of: feed) == "{\"error_message\":\"invalid feed ID\"}",
                "the feed guard, and the account it is given")

            // An input that passes both answers the listing, which a patch that answered the guard's
            // answer for a row of this account fires on.
            let ok = try await request(app, base, method: .GET, path: "/v1/entries?category_id=1&feed_id=2")
            #expect(ok.status == .ok, "the two guards answer nothing for the rows of this account")
        }
    }

    @Test func theListingAnswersTheTwoKeysInTheOrderTheStructDeclaresThemAndTheCountIgnoresThePage() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                _ = try await FeedRepository(connection).create(userID: alice, categoryID: 1,
                    url: "https://example.com/a")
                try await seedEntry(connection, userID: 1, feedID: 1, hash: "h-1", title: "One",
                    publishedAt: 1_000_000_003, starred: false)
                try await seedEntry(connection, userID: 1, feedID: 1, hash: "h-2", title: "Two",
                    publishedAt: 1_000_000_001, starred: false)
                try await seedEntry(connection, userID: 1, feedID: 1, hash: "h-3", title: "Three",
                    publishedAt: 1_000_000_002, starred: false)
            }

            // The count is read without the page, so the answer carries three for a page of two. The
            // patch that fires here answered the count as the size of the page.
            let response = try await request(app, base, method: .GET, path: "/v1/entries?limit=2")
            #expect(response.status == .ok, "the registered path answers the read")
            #expect(try body(of: response) == "{\"total\":3,\"entries\":["
                + entryDocument(id: 2, hash: "h-2", title: "Two", publishedAt: 1_000_000_001) + ","
                + entryDocument(id: 3, hash: "h-3", title: "Three", publishedAt: 1_000_000_002) + "]}",
                "the two keys in the order the struct declares them, and the count as the read answers it")
        }
    }

    @Test func theListingAnswersTheOrderTheReadAnswersInAndTheOrderAndDirectionTheQueryCarries() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                _ = try await FeedRepository(connection).create(userID: alice, categoryID: 1,
                    url: "https://example.com/a")
                try await seedEntry(connection, userID: 1, feedID: 1, hash: "h-1", title: "One",
                    publishedAt: 1_000_000_003, starred: false)
                try await seedEntry(connection, userID: 1, feedID: 1, hash: "h-2", title: "Two",
                    publishedAt: 1_000_000_001, starred: false)
                try await seedEntry(connection, userID: 1, feedID: 1, hash: "h-3", title: "Three",
                    publishedAt: 1_000_000_002, starred: false)
            }

            // The default order is the publication time, oldest first, which is not the row order on
            // this input: a patch that ordered the listing by the row id answered 1,2,3 here.
            let byDefault = try await request(app, base, method: .GET, path: "/v1/entries")
            #expect(try body(of: byDefault) == "{\"total\":3,\"entries\":["
                + entryDocument(id: 2, hash: "h-2", title: "Two", publishedAt: 1_000_000_001) + ","
                + entryDocument(id: 3, hash: "h-3", title: "Three", publishedAt: 1_000_000_002) + ","
                + entryDocument(id: 1, hash: "h-1", title: "One", publishedAt: 1_000_000_003) + "]}",
                "the default order, not the row order")

            // The order and the direction the query carries, which a patch that read the query name but
            // left the sort at the default answered the same as the pin above.
            let byId = try await request(app, base, method: .GET, path: "/v1/entries?order=id&direction=desc")
            #expect(try body(of: byId) == "{\"total\":3,\"entries\":["
                + entryDocument(id: 3, hash: "h-3", title: "Three", publishedAt: 1_000_000_002) + ","
                + entryDocument(id: 2, hash: "h-2", title: "Two", publishedAt: 1_000_000_001) + ","
                + entryDocument(id: 1, hash: "h-1", title: "One", publishedAt: 1_000_000_003) + "]}",
                "the order and the direction the query carries")
        }
    }

    @Test func theListingAppliesThePageAndTheOffsetTheQueryCarries() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                _ = try await FeedRepository(connection).create(userID: alice, categoryID: 1,
                    url: "https://example.com/a")
                try await seedEntry(connection, userID: 1, feedID: 1, hash: "h-1", title: "One",
                    publishedAt: 1_000_000_003, starred: false)
                try await seedEntry(connection, userID: 1, feedID: 1, hash: "h-2", title: "Two",
                    publishedAt: 1_000_000_001, starred: false)
                try await seedEntry(connection, userID: 1, feedID: 1, hash: "h-3", title: "Three",
                    publishedAt: 1_000_000_002, starred: false)
            }

            // The page size the query carries, which a patch that left the query's limit at the default
            // answered three here.
            let page = try await request(app, base, method: .GET, path: "/v1/entries?limit=1")
            #expect(try body(of: page) == "{\"total\":3,\"entries\":["
                + entryDocument(id: 2, hash: "h-2", title: "Two", publishedAt: 1_000_000_001) + "]}",
                "the page size the query carries")

            // The offset the query carries, which a patch that read the name but never applied it
            // answered the first row here.
            let skipped = try await request(app, base, method: .GET, path: "/v1/entries?limit=1&offset=1")
            #expect(try body(of: skipped) == "{\"total\":3,\"entries\":["
                + entryDocument(id: 3, hash: "h-3", title: "Three", publishedAt: 1_000_000_002) + "]}",
                "the offset the query carries")
        }
    }

    @Test func theListingAppliesTheFilterTheQueryCarriesAndSkipsAValueTheParseFailsOn() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                _ = try await FeedRepository(connection).create(userID: alice, categoryID: 1,
                    url: "https://example.com/a")
                try await seedEntry(connection, userID: 1, feedID: 1, hash: "h-1", title: "One",
                    publishedAt: 1_000_000_001, starred: false)
                try await seedEntry(connection, userID: 1, feedID: 1, hash: "h-2", title: "Two",
                    publishedAt: 1_000_000_002, starred: true)
            }

            // The filter the consumer sends, which a patch that took it out of the handler answered both
            // rows here.
            let starred = try await request(app, base, method: .GET, path: "/v1/entries?starred=true")
            #expect(try body(of: starred) == "{\"total\":1,\"entries\":["
                + entryDocument(id: 2, hash: "h-2", title: "Two", publishedAt: 1_000_000_002,
                    starred: true) + "]}",
                "the filter the query carries")

            // A value the parse fails on answers nothing here rather than the default, so the filter is
            // not applied at all. The patch that fires here read the name through the form that answers
            // the default for an unparseable value, which would have applied the false filter and
            // answered the first row alone.
            let unparseable = try await request(app, base, method: .GET, path: "/v1/entries?starred=maybe")
            #expect(try body(of: unparseable) == "{\"total\":2,\"entries\":["
                + entryDocument(id: 1, hash: "h-1", title: "One", publishedAt: 1_000_000_001) + ","
                + entryDocument(id: 2, hash: "h-2", title: "Two", publishedAt: 1_000_000_002,
                    starred: true) + "]}",
                "a value the parse fails on answers nothing, so no filter is applied")
        }
    }

    @Test func theListingAppliesTheAccountItIsGiven() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                let bob = try #require(try await UserRepository(connection)
                    .create(username: "bob", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                _ = try await FeedRepository(connection).create(userID: bob, categoryID: 2,
                    url: "https://example.com/bob")
                try await seedEntry(connection, userID: bob, feedID: 1, hash: "h-bob", title: "Bob",
                    publishedAt: 1_000_000_001, starred: false)
            }

            let response = try await request(app, base, method: .GET, path: "/v1/entries")
            #expect(try body(of: response) == "{\"total\":0,\"entries\":[]}",
                "the account the read is given, not every row")
        }
    }

    @Test func theSegmentIsReadBeforeAnythingIsReadAgainstTheStorageLayer() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
            }

            // A segment the read answers 0 for on each of the three paths that name one: the guard runs
            // before anything is read against the storage layer, so the answer is 400 for the segment,
            // not 404 for a row that is not there. One patch per path, each removing that path's guard.
            #expect(try body(of: try await request(app, base, method: .GET, path: "/v1/entries/0"))
                == "{\"error_message\":\"invalid entry ID\"}", "the single-row read's own guard")
            #expect(try body(of: try await request(app, base, method: .GET, path: "/v1/feeds/0/entries"))
                == "{\"error_message\":\"invalid feed ID\"}", "the feed listing's own guard")
            #expect(try body(of: try await request(app, base, method: .PUT,
                path: "/v1/entries/0/bookmark")) == "{\"error_message\":\"invalid entry ID\"}",
                "the toggle's own guard")

            // The segment before the query rules: the same path with an input that fails a rule answers
            // the guard's, which a patch that ran the rules first turned into the rule's answer.
            #expect(try body(of: try await request(app, base, method: .GET,
                path: "/v1/feeds/0/entries?order=bad")) == "{\"error_message\":\"invalid feed ID\"}",
                "the guard runs before the query rules")
        }
    }

    @Test func theSingleEntryReadIsGuardedByTheAccountAndAnswersTheKeysTheShapeWritesInOrder() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                let bob = try #require(try await UserRepository(connection)
                    .create(username: "bob", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                _ = try await FeedRepository(connection).create(userID: alice, categoryID: 1,
                    url: "https://example.com/a")
                _ = try await FeedRepository(connection).create(userID: bob, categoryID: 2,
                    url: "https://example.com/bob")
                try await seedEntry(connection, userID: alice, feedID: 1, hash: "h-one", title: "Hello",
                    url: "https://example.com/one", author: "Ada", content: "<p>A&B</p>",
                    publishedAt: 1_000_000_000, createdAt: 1_000_000_001, updatedAt: 1_000_000_002,
                    status: "unread", starred: false)
                try await seedEntry(connection, userID: bob, feedID: 2, hash: "h-bob", title: "Bob",
                    publishedAt: 1_000_000_000, starred: false)
            }

            // The pair is read before the document is written, so a row of another account with this id
            // answers 404. The patch that fires here takes the account out of the read.
            let other = try await request(app, base, method: .GET, path: "/v1/entries/2")
            #expect(other.status == .notFound, "the pair, not the id alone")

            let response = try await request(app, base, method: .GET, path: "/v1/entries/1")
            #expect(response.status == .ok, "the registered path answers the read")
            #expect(try body(of: response) == "{\"id\":1,\"user_id\":1,\"feed_id\":1,\"status\":\"unread\","
                + "\"hash\":\"h-one\",\"title\":\"Hello\",\"url\":\"https://example.com/one\","
                + "\"published_at\":1000000000,\"created_at\":1000000001,\"changed_at\":1000000002,"
                + "\"content\":\"\\u003cp\\u003eA\\u0026B\\u003c/p\\u003e\",\"author\":\"Ada\",\"starred\":false}",
                "the keys this port has columns for, in the order the reference's struct declares them")
        }
    }

    @Test func theStatusUpdateAnswersTheRuleItReadsFirstForAnInputThatFailsTwoRules() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                _ = try await FeedRepository(connection).create(userID: alice, categoryID: 1,
                    url: "https://example.com/a")
                try await seedEntry(connection, userID: 1, feedID: 1, hash: "h-1", title: "One",
                    publishedAt: 1_000_000_000, starred: false)
            }

            // The empty-list rule before the either-field rule: the patch that fires here puts the
            // either-field check first, which would have answered it for this input as well, because
            // the input carries an empty status and no flag.
            let empty = try await request(app, base, method: .PUT, path: "/v1/entries",
                body: "{\"entry_ids\":[],\"status\":\"\"}")
            #expect(empty.status == .badRequest, "the rule block answers 400")
            #expect(try body(of: empty) == "{\"error_message\":\"entryIDsEmpty\"}",
                "the empty-list rule, read before the either-field rule, on an input that fails both")

            // The either-field rule on an input that fails only it: no status and no flag.
            let neither = try await request(app, base, method: .PUT, path: "/v1/entries",
                body: "{\"entry_ids\":[1]}")
            #expect(try body(of: neither) == "{\"error_message\":\"statusOrStarredRequired\"}",
                "the either-field rule, for an input that carries neither field")

            // The status rule on an input that fails only it: the order between this rule and the
            // either-field rule cannot be read, because the first answers only for an empty status and
            // this one only for a non-empty one, so no input fails both.
            let status = try await request(app, base, method: .PUT, path: "/v1/entries",
                body: "{\"entry_ids\":[1],\"status\":\"bad\"}")
            #expect(try body(of: status) == "{\"error_message\":\"statusInvalid\"}",
                "the status rule, for an input that carries the field")
        }
    }

    @Test func theStatusUpdateWritesNothingWhenTheRuleBlockAnswers() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                _ = try await FeedRepository(connection).create(userID: alice, categoryID: 1,
                    url: "https://example.com/a")
                try await seedEntry(connection, userID: 1, feedID: 1, hash: "h-1", title: "One",
                    publishedAt: 1_000_000_000, starred: false)
            }

            let response = try await request(app, base, method: .PUT, path: "/v1/entries",
                body: "{\"entry_ids\":[1],\"status\":\"bad\"}")
            #expect(response.status == .badRequest, "the rule block answers before the write runs")
            #expect(try await entryStatus(storage, userID: 1, hash: "h-1") == "unread",
                "and nothing was written for an input the block answered")
        }
    }

    @Test func theStatusUpdateWritesOnlyTheHalfTheRequestCarries() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                _ = try await FeedRepository(connection).create(userID: alice, categoryID: 1,
                    url: "https://example.com/a")
                try await seedEntry(connection, userID: 1, feedID: 1, hash: "h-status", title: "Status",
                    publishedAt: 1_000_000_000, starred: true)
                try await seedEntry(connection, userID: 1, feedID: 1, hash: "h-starred", title: "Starred",
                    publishedAt: 1_000_000_001, status: "read", starred: false)
            }

            // A request that carries only the status leaves the flag as the row had it, which a patch
            // that wrote both halves for every request fires on. The row is seeded with the flag set, so
            // that a patch which wrote the zero value for a field the request did not carry would answer
            // the other way here.
            let statusOnly = try await request(app, base, method: .PUT, path: "/v1/entries",
                body: "{\"entry_ids\":[1],\"status\":\"read\"}")
            #expect(statusOnly.status == .noContent, "the status the write path writes")
            #expect(try await entryStatus(storage, userID: 1, hash: "h-status") == "read",
                "the half the request carried")
            #expect(try await entryStarred(storage, userID: 1, hash: "h-status") == true,
                "and the half it did not carry, left as the row had it")

            // The other half on its own, which a patch that skipped the starred write fires on. The row
            // is seeded as read so that the assertion on the half this request did not carry can fail: a
            // patch that ran the status write for every request, including one that carried no status,
            // wrote the fallback value here.
            let starredOnly = try await request(app, base, method: .PUT, path: "/v1/entries",
                body: "{\"entry_ids\":[2],\"starred\":true}")
            #expect(starredOnly.status == .noContent, "the write path answers 204 for the half it ran")
            #expect(try await entryStarred(storage, userID: 1, hash: "h-starred") == true,
                "the starred write runs for a request that carries only it")
            #expect(try await entryStatus(storage, userID: 1, hash: "h-starred") == "read",
                "and the status is left as the row had it")
        }
    }

    @Test func theTwoWritesAreGuardedByTheAccount() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                let bob = try #require(try await UserRepository(connection)
                    .create(username: "bob", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                _ = try await FeedRepository(connection).create(userID: alice, categoryID: 1,
                    url: "https://example.com/a")
                try await seedEntry(connection, userID: bob, feedID: 1, hash: "h-bob", title: "Bob",
                    publishedAt: 1_000_000_000, starred: false)
            }

            // The row of another account is named by the request, so a patch that took the account
            // condition out of the two statements wrote it here. The answer is still 204, because the
            // reference writes it for a statement that updated nothing.
            let response = try await request(app, base, method: .PUT, path: "/v1/entries",
                body: "{\"entry_ids\":[1],\"status\":\"read\",\"starred\":true}")
            #expect(response.status == .noContent, "the status the write path writes")
            #expect(try await entryStatus(storage, userID: 2, hash: "h-bob") == "unread",
                "the account condition of the status statement")
            #expect(try await entryStarred(storage, userID: 2, hash: "h-bob") == false,
                "and the account condition of the starred statement")
        }
    }

    @Test func theToggleGuardsTheSegmentThenWritesThenAnswersNoContent() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                let bob = try #require(try await UserRepository(connection)
                    .create(username: "bob", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                _ = try await FeedRepository(connection).create(userID: alice, categoryID: 1,
                    url: "https://example.com/a")
                try await seedEntry(connection, userID: 1, feedID: 1, hash: "h-flip", title: "Flip",
                    publishedAt: 1_000_000_000, starred: false)
                try await seedEntry(connection, userID: bob, feedID: 1, hash: "h-bob", title: "Bob",
                    publishedAt: 1_000_000_001, starred: false)
            }

            let response = try await request(app, base, method: .PUT, path: "/v1/entries/1/bookmark")
            #expect(response.status == .noContent, "the status the write path writes")
            #expect(try await entryStarred(storage, userID: 1, hash: "h-flip") == true,
                "the statement flips the flag")

            // The statement is guarded by the account, so a row of another account with this id answers
            // the error the reference's builder writes for a statement that updated nothing, and the row
            // stays where it is. A patch that took the account condition out of the statement wrote it
            // here and answered 204. The row is read before the answer's document: under that patch the
            // answer is a 204, which carries no document, so the document assertion would stop the pin
            // before the row was read.
            let other = try await request(app, base, method: .PUT, path: "/v1/entries/2/bookmark")
            #expect(other.status == .internalServerError,
                "the answer the reference's builder writes for a statement that updated nothing")
            #expect(try await entryStarred(storage, userID: 2, hash: "h-bob") == false,
                "and the row the guard did not read is untouched")
            #expect(try body(of: other) == "{\"error_message\":\"entry #2 does not exist\"}",
                "the message this port writes for the rule it names, not the reference's wording")
        }
    }

    @Test func theStatusEachAnswerCarries() async throws {
        try await withServedApp { storage, app, base in
            try await storage.withConnection { connection in
                let alice = try #require(try await UserRepository(connection)
                    .create(username: "alice", passwordHash: storedHash, isAdmin: false).id)
                try await insertKey(connection, userID: alice, token: token)
                _ = try await FeedRepository(connection).create(userID: alice, categoryID: 1,
                    url: "https://example.com/a")
                try await seedEntry(connection, userID: 1, feedID: 1, hash: "h-1", title: "One",
                    publishedAt: 1_000_000_000, starred: false)
            }

            // One patch per status: the three list paths answer 200, the rule blocks and the segments
            // answer 400, a row that is not there answers 404, the two write paths answer 204.
            #expect((try await request(app, base, method: .GET, path: "/v1/entries")).status == .ok,
                "the listing")
            #expect((try await request(app, base, method: .GET, path: "/v1/feeds/1/entries")).status == .ok,
                "the feed listing")
            #expect((try await request(app, base, method: .GET, path: "/v1/entries/1")).status == .ok,
                "the single-row read")
            #expect((try await request(app, base, method: .GET, path: "/v1/entries/9")).status == .notFound,
                "a row that is not there")
            #expect((try await request(app, base, method: .GET, path: "/v1/entries?status=bad")).status
                == .badRequest, "the rule block")
            #expect((try await request(app, base, method: .GET, path: "/v1/entries/0")).status
                == .badRequest, "the segment")
            #expect((try await request(app, base, method: .PUT, path: "/v1/entries",
                body: "{\"entry_ids\":[1],\"status\":\"read\"}")).status == .noContent,
                "the write path")
            #expect((try await request(app, base, method: .PUT, path: "/v1/entries/1/bookmark")).status
                == .noContent, "the toggle")
        }
    }

    // MARK: - Rows and requests

    private func entryDocument(id: Int, hash: String, title: String, publishedAt: Int,
        starred: Bool = false) -> String {
        // The 13 keys this port has columns for, in the order the reference's struct declares them; the
        // pin that reads the order is the single-row pin, which writes the whole document from literals.
        "{\"id\":\(id),\"user_id\":1,\"feed_id\":1,\"status\":\"unread\",\"hash\":\"\(hash)\","
        + "\"title\":\"\(title)\",\"url\":\"\",\"published_at\":\(publishedAt),"
        + "\"created_at\":1000000000,\"changed_at\":1000000000,\"content\":\"\",\"author\":\"\","
        + "\"starred\":\(starred)}"
    }

    private func seedEntry(_ connection: any Database, userID: Int, feedID: Int, hash: String,
        title: String, url: String = "", author: String = "", content: String = "",
        publishedAt: Int, createdAt: Int = 1_000_000_000, updatedAt: Int = 1_000_000_000,
        status: String = "unread", starred: Bool) async throws {
        try await RawSQL.sql(on: connection).raw("""
            INSERT INTO entries (user_id, feed_id, hash, title, url, author, content, status, starred,
                published_at, created_at, updated_at)
            VALUES (\(bind: userID), \(bind: feedID), \(bind: hash), \(bind: title), \(bind: url),
                \(bind: author), \(bind: content), \(bind: status), \(bind: starred),
                \(bind: publishedAt), \(bind: createdAt), \(bind: updatedAt))
            """).run()
    }

    private func insertKey(_ connection: any Database, userID: Int, token: String) async throws {
        try await RawSQL.sql(on: connection).raw("""
            INSERT INTO api_keys (user_id, token, description, created_at)
            VALUES (\(bind: userID), \(bind: token), \(bind: "phone app"), \(bind: 1_000_000_000))
            """).run()
    }

    private func entryStatus(_ storage: SQLiteStorage, userID: Int, hash: String) async throws -> String? {
        try await storage.withConnection { connection in
            let row = try await RawSQL.sql(on: connection).raw("""
                SELECT status FROM entries WHERE user_id = \(bind: userID) AND hash = \(bind: hash)
                LIMIT 1
                """).first()
            return try row?.decode(column: "status", as: String.self)
        }
    }

    private func entryStarred(_ storage: SQLiteStorage, userID: Int, hash: String) async throws -> Bool? {
        try await storage.withConnection { connection in
            let row = try await RawSQL.sql(on: connection).raw("""
                SELECT starred FROM entries WHERE user_id = \(bind: userID) AND hash = \(bind: hash)
                LIMIT 1
                """).first()
            return try row?.decode(column: "starred", as: Bool.self)
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
