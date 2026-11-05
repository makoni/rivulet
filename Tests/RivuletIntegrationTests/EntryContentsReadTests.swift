import Foundation
import SQLKit
import Testing
@testable import RivuletCore

/// What `stream/items/contents` reads (`internal/storage/entry_query_builder.go` at `c4d54f87`):
/// the listing joined with the feed and category rows, and the attachments of the entries it
/// answers.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the two titles
/// come from two different rows — the origin's title is the feed row's, the label is the category
/// row's, and neither is the entry's own title — that the origin's site url is the feed row's
/// `site_url` column rather than the feed url column or the entry url; that the attachments are
/// attached to their own entry, which a patch that gave every row of the page the whole page's
/// attachments fails on, and that a row with none answers the empty list rather than nothing; that
/// the order is the query's column with the direction the query carries, so a patch that hardcoded
/// one direction fails on the other pin; and that the id filter applies only the names it is given,
/// on an input where the names are not the whole set.
///
/// What these pins cannot show: the page size, because `nil` means unbounded here and the clamp is
/// pinned by `EntryQueryTests`; the inner join on categories, because this port's schema does not
/// allow a feed whose category row is missing; the order of the two statements, which is the
/// reference's choice as well; and the search filter, which this caller never builds.
@Suite struct EntryContentsReadTests {
    @Test func theTwoTitlesAndTheSiteUrlComeFromTheirOwnRows() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let entries = EntryRepository(connection)
                let userID = try await seedUser(connection, username: "alice")
                let categoryID = try await seedCategory(connection, userID: userID, title: "Tech")
                let feedID = try await seedFeed(connection, userID: userID, categoryID: categoryID,
                    url: "https://example.com/feed.xml")

                // The fixture writes the two feed columns as empty, so the values are set here;
                // each of the three is a value no other row carries.
                try await sqlDatabase(connection).raw("""
                    UPDATE feeds SET title = \(bind: "Feed Title"),
                        site_url = \(bind: "https://example.com/site")
                    WHERE id = \(bind: feedID)
                    """).run()
                let entryID = try await seedEntry(connection, userID: userID, feedID: feedID, hash: "h1",
                    title: "Entry Title", url: "https://example.com/item", author: "Entry Author",
                    content: "<p>Hello</p>")

                let row = try #require(try await entries.contents(EntryQuery(userID: userID)).first)
                #expect(row.entryID == entryID, "the listing is the same read the client APIs use")
                #expect(row.feedID == feedID, "the feed id the origin stream id is built from")
                #expect(row.feedTitle == "Feed Title", "the feed row's title, not the entry's own")
                #expect(row.siteURL == "https://example.com/site",
                    "the feed row's site url, not the feed url column and not the entry url")
                #expect(row.categoryTitle == "Tech", "the category row's title, not the feed row's")
                #expect(row.title == "Entry Title", "and the entry's own fields are still the entry's")
                #expect(row.url == "https://example.com/item", "the url canonical and alternate use")
                #expect(row.author == "Entry Author", "the author the item carries")
                #expect(row.content == "<p>Hello</p>",
                    "the content as stored, with no media proxy applied")
                #expect(row.status == .unread, "the status the read part of the categories reads")
                #expect(!row.starred, "the flag the starred part reads")
                #expect(row.publishedAt == 1_700_000_000, "the column the string form is built from")
            }
        }
    }

    @Test func eachRowCarriesItsOwnAttachmentsAndAnAbsentSetIsTheEmptyList() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let entries = EntryRepository(connection)
                let userID = try await seedUser(connection, username: "alice")
                let categoryID = try await seedCategory(connection, userID: userID, title: "Tech")
                let feedID = try await seedFeed(connection, userID: userID, categoryID: categoryID,
                    url: "https://example.com/feed")
                let first = try await seedEntry(connection, userID: userID, feedID: feedID, hash: "h1")
                let second = try await seedEntry(connection, userID: userID, feedID: feedID, hash: "h2")

                // A patch that attached the whole page's attachments to every row answered both
                // rows with the two urls, so the two rows are seeded with different sets.
                try await entries.upsert(userID: userID, feedID: feedID,
                    input: entryInput(hash: "h1",
                        enclosures: [.init(url: "https://example.com/a.mp3", mimeType: "audio/mpeg")]),
                    updateExisting: true)
                try await entries.upsert(userID: userID, feedID: feedID,
                    input: entryInput(hash: "h2",
                        enclosures: [.init(url: "https://example.com/b.pdf", mimeType: "application/pdf")]),
                    updateExisting: true)

                let rows = try await entries.contents(EntryQuery(userID: userID,
                    entryIDs: [first, second]))
                #expect(rows.count == 2, "the listing answers the ids the input names")
                #expect(rows.first(where: { $0.entryID == first })?.attachments.map(\.url) ==
                    ["https://example.com/a.mp3"], "the attachments of this row")
                #expect(rows.first(where: { $0.entryID == second })?.attachments.map(\.mimeType) ==
                    ["application/pdf"], "and the type that row declares")

                // A row with none answers the empty list, which is what the reference's `make`
                // writes, rather than nothing, which is what a patch that read the map would
                // answer.
                let third = try await seedEntry(connection, userID: userID, feedID: feedID, hash: "h3")
                let withNone = try await entries.contents(EntryQuery(userID: userID, entryIDs: [third]))
                #expect(withNone.first?.attachments.isEmpty == true, "the row with no attachment")
            }
        }
    }

    @Test func theOrderIsTheQueryColumnAndTheQueryDirection() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let entries = EntryRepository(connection)
                let userID = try await seedUser(connection, username: "alice")
                let categoryID = try await seedCategory(connection, userID: userID, title: "Tech")
                let feedID = try await seedFeed(connection, userID: userID, categoryID: categoryID,
                    url: "https://example.com/feed")

                // The row published later is seeded first, so the id order and the publication
                // order are the two different orders a patch that ordered by the id instead of the
                // column answers differently for.
                let later = try await seedEntry(connection, userID: userID, feedID: feedID, hash: "h1",
                    publishedAt: 200)
                let older = try await seedEntry(connection, userID: userID, feedID: feedID, hash: "h2",
                    publishedAt: 100)

                let descending = try await entries.contents(EntryQuery(userID: userID,
                    sort: EntrySort(field: .publishedAt, direction: .descending)))
                #expect(descending.map(\.entryID) == [later, older],
                    "the direction the read answers for the order parameter's default")

                // The same column with the other direction, which is what the read answers for the
                // one value the order parameter takes. A patch that hardcoded the direction of the
                // first pin fails here.
                let ascending = try await entries.contents(EntryQuery(userID: userID,
                    sort: EntrySort(field: .publishedAt, direction: .ascending)))
                #expect(ascending.map(\.entryID) == [older, later],
                    "the direction is the query's, not a hardcoded one")
            }
        }
    }

    @Test func theIdFilterSelectsOnlyTheNamesItIsGiven() async throws {
        try await withMigratedStorage { _, storage in
            try await storage.withConnection { connection in
                let entries = EntryRepository(connection)
                let userID = try await seedUser(connection, username: "alice")
                let categoryID = try await seedCategory(connection, userID: userID, title: "Tech")
                let feedID = try await seedFeed(connection, userID: userID, categoryID: categoryID,
                    url: "https://example.com/feed")
                let named = try await seedEntry(connection, userID: userID, feedID: feedID, hash: "h1")
                _ = try await seedEntry(connection, userID: userID, feedID: feedID, hash: "h2")
                _ = try await seedEntry(connection, userID: userID, feedID: feedID, hash: "h3")

                // `WithEntryIDs` applies nothing for an empty list, so the same read answers all
                // three rows without ids and one row with a name.
                let one = try await entries.contents(EntryQuery(userID: userID, entryIDs: [named]))
                #expect(one.map(\.entryID) == [named], "the filter is the list the input names")

                let all = try await entries.contents(EntryQuery(userID: userID))
                #expect(all.count == 3, "the empty list applies nothing")
            }
        }
    }
}
