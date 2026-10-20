import Foundation
import Fluent
import Testing
@testable import RivuletCore

/// Full-text entry search: matching, ranking, scoping and query translation.
///
/// The reference searches a PostgreSQL `tsvector` with `websearch_to_tsquery`
/// and ranks by `ts_rank`; Rivulet searches the FTS5 index over `title` and
/// `content_text` and ranks by `bm25()`. These tests pin the behaviour the
/// storage layer promises: every term must match, the search is scoped by the
/// same filters as a listing, relevance wins over the requested order, and
/// user input is never interpreted as FTS5 syntax.
@Suite struct EntrySearchTests {
    @Test func searchMatchesEveryTermInTitlesAndPlainText() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                let titleMatch = try await seedEntry(
                    connection,
                    userID: feed.userID,
                    feedID: feed.feedID,
                    hash: "title",
                    title: "Swift on the server",
                    content: "<p>Notes only</p>",
                    publishedAt: 100
                )
                let contentMatch = try await seedEntry(
                    connection,
                    userID: feed.userID,
                    feedID: feed.feedID,
                    hash: "content",
                    title: "Framework notes",
                    content: "<p>Swift and Vapor together</p>",
                    publishedAt: 200
                )
                let plainTextMatch = try await seedEntry(
                    connection,
                    userID: feed.userID,
                    feedID: feed.feedID,
                    hash: "none",
                    title: "Other",
                    content: "<p>Nothing here, hello</p>",
                    publishedAt: 300
                )
                let entries = EntryRepository(connection)

                func search(_ text: String) -> EntryQuery {
                    EntryQuery(userID: feed.userID, search: text)
                }

                #expect(Set(try await entries.listIDs(search("swift"))) == [titleMatch, contentMatch])
                #expect(Set(try await entries.listIDs(search("SWIFT"))) == [titleMatch, contentMatch])
                #expect(try await entries.listIDs(search("swift vapor")) == [contentMatch])
                #expect(try await entries.listIDs(search("swift missing")).isEmpty)
                #expect(try await entries.count(search("swift")) == 2)
                // HTML tags are not indexed; only the plain text is.
                #expect(try await entries.listIDs(search("<p>")).isEmpty)
                #expect(try await entries.listIDs(search("hello")) == [plainTextMatch])
                // An empty search is not a filter; whitespace has no term, so it
                // matches nothing (as `websearch_to_tsquery` would).
                #expect(try await entries.listIDs(search("")).count == 3)
                #expect(try await entries.listIDs(search("   ")).isEmpty)
            }
        }
    }

    @Test func searchRanksRelevanceBeforeTheRequestedOrder() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                for index in 0..<5 {
                    try await seedEntry(
                        connection,
                        userID: feed.userID,
                        feedID: feed.feedID,
                        hash: "distractor-\(index)",
                        title: "Unrelated",
                        content: "<p>Nothing to see</p>",
                        publishedAt: 1_700_000_000
                    )
                }
                // The weaker match is inserted first, so an id-based order would put it first.
                let weak = try await seedEntry(
                    connection,
                    userID: feed.userID,
                    feedID: feed.feedID,
                    hash: "weak",
                    title: "Same title",
                    content: "<p>swift alpha beta gamma</p>",
                    publishedAt: 1_700_000_000
                )
                let strong = try await seedEntry(
                    connection,
                    userID: feed.userID,
                    feedID: feed.feedID,
                    hash: "strong",
                    title: "Same title",
                    content: "<p>swift swift swift swift</p>",
                    publishedAt: 1_700_000_000
                )
                let entries = EntryRepository(connection)

                #expect(
                    try await entries.listIDs(EntryQuery(userID: feed.userID, search: "swift"))
                        == [strong, weak]
                )
            }
        }
    }

    @Test func searchRespectsTheOtherFilters() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let userID = try await seedUser(connection)
                let category = try await seedCategory(connection, userID: userID, title: "Tech")
                let firstFeed = try await seedFeed(
                    connection, userID: userID, categoryID: category, url: "https://example.com/1.xml"
                )
                let secondFeed = try await seedFeed(
                    connection, userID: userID, categoryID: category, url: "https://example.com/2.xml"
                )
                let otherUserID = try await seedUser(connection, username: "bob")
                let otherCategory = try await seedCategory(connection, userID: otherUserID, title: "Tech")
                let otherFeed = try await seedFeed(
                    connection, userID: otherUserID, categoryID: otherCategory, url: "https://example.com/other.xml"
                )
                let first = try await seedEntry(
                    connection,
                    userID: userID,
                    feedID: firstFeed,
                    hash: "first",
                    content: "<p>swift</p>",
                    publishedAt: 100
                )
                let second = try await seedEntry(
                    connection,
                    userID: userID,
                    feedID: secondFeed,
                    hash: "second",
                    content: "<p>swift</p>",
                    publishedAt: 200,
                    status: .read
                )
                let other = try await seedEntry(
                    connection,
                    userID: otherUserID,
                    feedID: otherFeed,
                    hash: "other",
                    content: "<p>swift</p>",
                    publishedAt: 300
                )
                let entries = EntryRepository(connection)

                #expect(
                    try await entries.listIDs(
                        EntryQuery(userID: userID, feedID: firstFeed, search: "swift")
                    ) == [first]
                )
                #expect(
                    try await entries.listIDs(
                        EntryQuery(userID: userID, categoryID: category, statuses: [.read], search: "swift")
                    ) == [second]
                )
                #expect(
                    try await entries.listIDs(EntryQuery(userID: otherUserID, search: "swift")) == [other]
                )
                #expect(
                    try await entries.listIDs(EntryQuery(userID: userID, search: "missing")).isEmpty
                )
            }
        }
    }

    @Test func searchTreatsOperatorsAsTextAndNeverFailsOnQuotes() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                let id = try await seedEntry(
                    connection,
                    userID: feed.userID,
                    feedID: feed.feedID,
                    hash: "phrase",
                    title: "Server side rendering",
                    content: "<p>AND OR NOT</p>",
                    publishedAt: 100
                )
                let entries = EntryRepository(connection)

                func search(_ text: String) -> EntryQuery {
                    EntryQuery(userID: feed.userID, search: text)
                }

                // Quoted phrases are preserved.
                #expect(try await entries.listIDs(search("\"server side\"")) == [id])
                // FTS5 keywords are searched as words, not interpreted.
                #expect(try await entries.listIDs(search("AND")) == [id])
                #expect(Set(try await entries.listIDs(search("AND OR"))) == [id])
                // An unmatched quote is treated as a phrase and cannot fail the query.
                #expect(try await entries.listIDs(search("\"server side")) == [id])
                // A query with no searchable term matches nothing.
                #expect(try await entries.listIDs(search("\"")).isEmpty)
                #expect(try await entries.listIDs(search("\"\"")).isEmpty)
            }
        }
    }

    @Test func searchKeepsRelevanceAheadOfThePublicationDate() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                for index in 0..<5 {
                    try await seedEntry(
                        connection,
                        userID: feed.userID,
                        feedID: feed.feedID,
                        hash: "distractor-\(index)",
                        title: "Unrelated",
                        content: "<p>Nothing to see</p>",
                        publishedAt: 1_700_000_000
                    )
                }
                let weak = try await seedEntry(
                    connection,
                    userID: feed.userID,
                    feedID: feed.feedID,
                    hash: "weak",
                    title: "Same title",
                    content: "<p>swift alpha beta gamma</p>",
                    publishedAt: 1_600_000_000
                )
                let strong = try await seedEntry(
                    connection,
                    userID: feed.userID,
                    feedID: feed.feedID,
                    hash: "strong",
                    title: "Same title",
                    content: "<p>swift swift swift swift</p>",
                    publishedAt: 1_700_000_000
                )
                let entries = EntryRepository(connection)

                // The default order would put the newest match last; relevance wins.
                #expect(
                    try await entries.listIDs(EntryQuery(userID: feed.userID, search: "swift"))
                        == [strong, weak]
                )
            }
        }
    }

    @Test func searchWeightsTitleMatchesAboveContentMatches() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                for index in 0..<3 {
                    try await seedEntry(
                        connection,
                        userID: feed.userID,
                        feedID: feed.feedID,
                        hash: "distractor-\(index)",
                        title: "Unrelated",
                        content: "<p>Nothing to see</p>",
                        publishedAt: 1_700_000_000
                    )
                }
                let contentMatch = try await seedEntry(
                    connection,
                    userID: feed.userID,
                    feedID: feed.feedID,
                    hash: "content",
                    title: "Notes",
                    content: "<p>swift swift alpha beta gamma delta epsilon</p>",
                    publishedAt: 1_600_000_000
                )
                let titleMatch = try await seedEntry(
                    connection,
                    userID: feed.userID,
                    feedID: feed.feedID,
                    hash: "title",
                    title: "Swift release notes today",
                    content: "<p>x</p>",
                    publishedAt: 1_700_000_000
                )
                let entries = EntryRepository(connection)

                // Date-first would put the newer title match last, and unweighted
                // bm25 prefers the two-term content match; the A/B weights flip it.
                #expect(
                    try await entries.listIDs(EntryQuery(userID: feed.userID, search: "swift"))
                        == [titleMatch, contentMatch]
                )
            }
        }
    }

    @Test func searchRanksCommonTermsByFrequency() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                for index in 0..<2 {
                    try await seedEntry(
                        connection,
                        userID: feed.userID,
                        feedID: feed.feedID,
                        hash: "distractor-\(index)",
                        title: "Other",
                        content: "<p>Nothing to see</p>",
                        publishedAt: 1_700_000_000
                    )
                }
                let strong = try await seedEntry(
                    connection,
                    userID: feed.userID,
                    feedID: feed.feedID,
                    hash: "strong",
                    title: "Post",
                    content: "<p>common common common common common</p>",
                    publishedAt: 1_700_000_000
                )
                let first = try await seedEntry(
                    connection,
                    userID: feed.userID,
                    feedID: feed.feedID,
                    hash: "first",
                    title: "Post",
                    content: "<p>common</p>",
                    publishedAt: 1_600_000_000
                )
                let second = try await seedEntry(
                    connection,
                    userID: feed.userID,
                    feedID: feed.feedID,
                    hash: "second",
                    title: "Post",
                    content: "<p>common</p>",
                    publishedAt: 1_600_000_000
                )
                let third = try await seedEntry(
                    connection,
                    userID: feed.userID,
                    feedID: feed.feedID,
                    hash: "third",
                    title: "Post",
                    content: "<p>common</p>",
                    publishedAt: 1_600_000_000
                )
                let entries = EntryRepository(connection)

                // A term present in most rows still ranks by frequency, even when
                // the frequent match is the newest (date-first would put it last)
                // and SQLite clamps its inverse document frequency.
                #expect(
                    try await entries.listIDs(EntryQuery(userID: feed.userID, search: "common"))
                        == [strong, first, second, third]
                )
            }
        }
    }

    @Test func searchSupportsPaginationAndModelListings() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                let graph = try await seedSearchPaginationEntries(
                    connection, userID: feed.userID, feedID: feed.feedID
                )
                let entries = EntryRepository(connection)

                var page = EntryQuery(userID: feed.userID, search: "swift", limit: 2)
                #expect(try await entries.listIDs(page) == [graph.four, graph.three])
                page.offset = 2
                #expect(try await entries.listIDs(page) == [graph.two, graph.one])
                // The model listing follows the same ranked order and full rows.
                let listed = try await entries.list(page)
                #expect(listed.compactMap(\.id) == [graph.two, graph.one])
                #expect(listed.map(\.contentText) == ["swift swift alpha beta", "swift alpha beta gamma"])
                #expect(listed.first?.content == "<p>swift swift alpha beta</p>")

                #expect(
                    try await entries.listIDs(
                        EntryQuery(userID: feed.userID, starred: true, search: "swift")
                    ) == [graph.one]
                )
                #expect(
                    try await entries.listIDs(
                        EntryQuery(userID: feed.userID, statuses: [.read], search: "swift")
                    ) == [graph.two]
                )
                // Date bounds stay strict when combined with search.
                #expect(
                    try await entries.listIDs(
                        EntryQuery(userID: feed.userID, publishedAfter: 100, search: "swift")
                    ).isEmpty
                )
            }
        }
    }
}

/// Seed graph for the pagination test: four "swift" matches with rising term
/// frequency (one starred, one read) plus one non-matching entry.
private func seedSearchPaginationEntries(
    _ connection: any Database, userID: Int, feedID: Int
) async throws -> (one: Int, two: Int, three: Int, four: Int) {
    let one = try await seedEntry(
        connection,
        userID: userID,
        feedID: feedID,
        hash: "one",
        title: "One",
        content: "<p>swift alpha beta gamma</p>",
        publishedAt: 100,
        starred: true
    )
    let two = try await seedEntry(
        connection,
        userID: userID,
        feedID: feedID,
        hash: "two",
        title: "Two",
        content: "<p>swift swift alpha beta</p>",
        publishedAt: 100,
        status: .read
    )
    let three = try await seedEntry(
        connection,
        userID: userID,
        feedID: feedID,
        hash: "three",
        title: "Three",
        content: "<p>swift swift swift alpha</p>",
        publishedAt: 100
    )
    let four = try await seedEntry(
        connection,
        userID: userID,
        feedID: feedID,
        hash: "four",
        title: "Four",
        content: "<p>swift swift swift swift</p>",
        publishedAt: 100
    )
    _ = try await seedEntry(
        connection,
        userID: userID,
        feedID: feedID,
        hash: "none",
        title: "Other",
        content: "<p>Nothing here</p>",
        publishedAt: 100
    )
    return (one, two, three, four)
}
