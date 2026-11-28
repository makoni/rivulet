import FluentKit
import Foundation
import SQLKit
import Testing
import Vapor
@testable import RivuletApp
@testable import RivuletCore

/// The write paths of `RestV1EntryRouteTests`: the status update, the bookmark toggle and the status
/// each answer carries. What each pin can fail on is listed on the suite.
extension RestV1EntryRouteTests {
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
}
