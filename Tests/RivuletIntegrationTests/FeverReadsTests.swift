import Foundation
import Fluent
import SQLKit
import Testing
@testable import RivuletApp
@testable import RivuletCore

/// The five storage reads the documents of this path are built from, read over a real socket:
/// `internal/fever/handler.go` at `c4d54f87`. The rows are written through SQL so that a pin is not
/// satisfied by the read it is testing.
///
/// The rows are written on one connection and the request runs after that connection goes back to
/// the pool, because the driver keeps a single pooled connection, so a pin cannot hold one while
/// the handler checks out another.
///
/// What these pins can fail on, each checked by patching the rule and reverting (4 pins, 8 probes):
/// the groups document answers the title order the read builds, which a patch that used the listing
/// read with the position column fails on — the pins write positions so the two orders part; the
/// feed ids inside a group are in the order the feeds listing answers, which a patch that grouped
/// them in row order fails on; the group order is the order the feeds first appear in, which a
/// patch that built it from the categories read or from the row order fails on — 3 probes on that
/// pin; the feeds document answers the order the sort read builds rather than the row order, and
/// `favicon_id` is the icon row the feed points at and the zero for a feed that points at nothing —
/// 2 probes; the comma join of the id documents, which a patch that joined them another way fails
/// on, and the two filters those documents read — the status filter and the starred flag — which a
/// patch that read one filter for both documents fails on — 3 probes on that pin. The join itself
/// and the `data` field are pinned as a read by `IconRepositoryTests`, so the favicons pin here
/// reads those two rules through the document and no patch is run against it here.
///
/// What these pins cannot show: the group order the reference answers, which comes from a Go map
/// and is not fixed, so the pins read this port's own order as the rule the handler has; the order
/// the join answers for rows sharing one icon id, which the statement does not fix until the port
/// names it; the order the two id reads answer in for rows sharing one publication time, which the
/// statement does not order; the `html` field, which is the stored content because this port has no
/// media proxy — the row in `docs/parity.md` names it; the clock field, read through the
/// placeholder the request helper names; and the `hide_globally` column the reference reads on the
/// same category row, which this port's schema does not have.
@Suite struct FeverReadsTests {
    init() {
        TestLogging.bootstrapOnce()
    }

    @Test func theGroupsDocumentAnswersTheTitleOrderAndTheFeedIdsTheListingOrder() async throws {
        try await withServedApp { storage, app, base in
            let requests = FeverRequests(app, base)
            let (userID, token) = try await requests.seed(storage, name: "alice", password: "secret")

            // The three orders the pins read are three different answers on this data: the
            // categories are created in an order that is neither the title order nor the row order,
            // and the feed counts put the group whose row is third first. The default "All" row the
            // create path writes with the account is the first row of the title order, so the
            // golden names it through the id the row holds.
            let (zeta, alpha, tech, first, second, third, fourth) =
                try await storage.withConnection { connection in
                    let zeta = try await seedCategory(connection, userID: userID, title: "Zeta")
                    let alpha = try await seedCategory(connection, userID: userID, title: "Alpha")
                    let tech = try await seedCategory(connection, userID: userID, title: "Tech")
                    let first = try await seedFeed(connection, userID: userID, categoryID: tech,
                        url: "https://e/1")
                    let second = try await seedFeed(connection, userID: userID, categoryID: zeta,
                        url: "https://e/2")
                    let third = try await seedFeed(connection, userID: userID, categoryID: alpha,
                        url: "https://e/3")
                    let fourth = try await seedFeed(connection, userID: userID, categoryID: alpha,
                        url: "https://e/4")
                    try await writeCounts(connection, [(first, 5), (second, 4), (fourth, 3), (third, 1)])
                    // The positions are written so the two category reads part: the listing read
                    // would answer Tech, Zeta, Alpha, and the read this handler uses answers the
                    // title order.
                    try await writePositions(connection, [(tech, 0), (zeta, 1), (alpha, 5)])
                    return (zeta, alpha, tech, first, second, third, fourth)
                }

            let allID = try await requests.categoryID(storage, userID: userID, title: "All")
            let answer = FeverShape.groupsDocument(groups: [
                FeverShape.group(id: allID, title: "All"),
                FeverShape.group(id: alpha, title: "Alpha"),
                FeverShape.group(id: tech, title: "Tech"),
                FeverShape.group(id: zeta, title: "Zeta")
            ], feedsGroups: [
                FeverShape.feedsGroup(groupID: tech, feedIDs: "\(first)"),
                FeverShape.feedsGroup(groupID: zeta, feedIDs: "\(second)"),
                FeverShape.feedsGroup(groupID: alpha, feedIDs: "\(fourth),\(third)")
            ], lastRefreshed: 0)
            #expect(requests.document(of: try await requests.get("api&groups&api_key=\(token)"))
                == answer.written(),
                "the title order, the feed ids in the listing order, and the group order")
        }
    }

    @Test func theFeedsDocumentAnswersTheSortTheReadBuildsWithTheIconRow() async throws {
        try await withServedApp { storage, app, base in
            let requests = FeverRequests(app, base)
            let (userID, token) = try await requests.seed(storage, name: "alice", password: "secret")

            let (category, first, second, iconID) = try await storage.withConnection { connection in
                let category = try await seedCategory(connection, userID: userID, title: "Tech")
                let first = try await seedFeed(connection, userID: userID, categoryID: category,
                    url: "https://e/1")
                let second = try await seedFeed(connection, userID: userID, categoryID: category,
                    url: "https://e/2")
                let icon = try await IconRepository(connection)
                    .insert(hash: "hash-a", mimeType: "image/png", content: Data([0x89, 0x50, 0x4E, 0x47]))
                let iconID = try #require(icon.id)
                try await IconRepository(connection).link(feedID: first, iconID: iconID)

                // Equal counts, so the appended tiebreaker is what orders the two rows: the
                // lowercase reading puts the second row first, which is not the row order.
                try await writeTitles(connection, [(first, "B"), (second, "a")])
                try await writeCheckedAt(connection, [(first, 1_700_000_001), (second, 1_700_000_002)])
                return (category, first, second, iconID)
            }

            let answer = FeverShape.feedsDocument(feeds: [
                FeverShape.feed(id: second, faviconID: 0, title: "a", url: "https://e/2",
                    siteURL: "", lastUpdated: 1_700_000_002),
                FeverShape.feed(id: first, faviconID: iconID, title: "B", url: "https://e/1",
                    siteURL: "", lastUpdated: 1_700_000_001)
            ], feedsGroups: [FeverShape.feedsGroup(groupID: category, feedIDs: "\(second),\(first)")],
            lastRefreshed: 0)
            #expect(requests.document(of: try await requests.get("api&feeds&api_key=\(token)"))
                == answer.written(),
                "the sort order, the icon row, the zero for a feed without one, the check time")
        }
    }

    @Test func theFaviconsDocumentCarriesOneRowPerFeedAndTheDataFieldIsTheReferenceForm() async throws {
        try await withServedApp { storage, app, base in
            let requests = FeverRequests(app, base)
            let (userID, token) = try await requests.seed(storage, name: "alice", password: "secret")

            // The shared icon is the second row, so the order the join answers is not the order the
            // feeds are read in: the first feed points at the later row. The pins write the icon
            // rows so the two orders part, and the shared icon answers one row for each feed that
            // points at it, which is the second and third row of the answer.
            let (singleID, sharedID) = try await storage.withConnection { connection in
                let category = try await seedCategory(connection, userID: userID, title: "Tech")
                let first = try await seedFeed(connection, userID: userID, categoryID: category,
                    url: "https://e/1")
                let second = try await seedFeed(connection, userID: userID, categoryID: category,
                    url: "https://e/2")
                let single = try await IconRepository(connection)
                    .insert(hash: "hash-a", mimeType: "image/gif", content: Data([0x47, 0x49, 0x46]))
                let shared = try await IconRepository(connection)
                    .insert(hash: "hash-b", mimeType: "image/png", content: Data([0x00]))
                let singleID = try #require(single.id)
                let sharedID = try #require(shared.id)
                try await IconRepository(connection).link(feedID: first, iconID: sharedID)
                try await IconRepository(connection).link(feedID: second, iconID: singleID)

                // A row that is not the first is the row the join answers twice, so the document
                // carries the shared icon once for each feed that points at it.
                let third = try await seedFeed(connection, userID: userID, categoryID: category,
                    url: "https://e/3")
                try await IconRepository(connection).link(feedID: third, iconID: sharedID)
                return (singleID, sharedID)
            }

            let answer = FeverShape.faviconsDocument(favicons: [
                FeverShape.favicon(id: singleID, data: "image/gif;base64,R0lG"),
                FeverShape.favicon(id: sharedID, data: "image/png;base64,AA=="),
                FeverShape.favicon(id: sharedID, data: "image/png;base64,AA==")
            ], lastRefreshed: 0)
            #expect(requests.document(of: try await requests.get("api&favicons&api_key=\(token)"))
                == answer.written(), "the join answers one row per feed, and the data form")
        }
    }

    @Test func theIdDocumentsCarryTheJoinedListTheReadAnswersAndTheEmptyAnswer() async throws {
        try await withServedApp { storage, app, base in
            let requests = FeverRequests(app, base)
            let (userID, token) = try await requests.seed(storage, name: "alice", password: "secret")

            // The publication times put the rows in an order that is not the row order, and no row
            // carries the starred flag, so the second document answers the empty answer. The two
            // filters are read on the same rows: a patch that read the flag for the first document
            // answered the empty string here, and one that read the status for the second answered
            // the list.
            let (first, second, third) = try await storage.withConnection { connection in
                let category = try await seedCategory(connection, userID: userID, title: "Tech")
                let feed = try await seedFeed(connection, userID: userID, categoryID: category,
                    url: "https://e/1")
                let first = try await seedEntry(connection, userID: userID, feedID: feed, hash: "1",
                    publishedAt: 300)
                let second = try await seedEntry(connection, userID: userID, feedID: feed, hash: "2",
                    publishedAt: 100)
                let third = try await seedEntry(connection, userID: userID, feedID: feed, hash: "3",
                    publishedAt: 200)
                return (first, second, third)
            }

            #expect(requests.document(of: try await requests.get(
                "api&unread_item_ids&api_key=\(token)")) ==
                FeverShape.unreadDocument(
                    ids: [second, third, first].map { String($0) }.joined(separator: ","),
                    lastRefreshed: 0).written(),
                "the order the read answers, which is not the row order")
            #expect(requests.document(of: try await requests.get(
                "api&saved_item_ids&api_key=\(token)")) ==
                FeverShape.savedDocument(ids: "", lastRefreshed: 0).written(),
                "the empty answer for the filter that matches no row")
        }
    }

    private func writeCounts(_ connection: any Database, _ rows: [(Int, Int)]) async throws {
        let sql = try sqlDatabase(connection)
        for (id, count) in rows {
            try await sql.raw("UPDATE feeds SET parsing_error_count = \(bind: count) WHERE id = \(bind: id)")
                .run()
        }
    }

    private func writeTitles(_ connection: any Database, _ rows: [(Int, String)]) async throws {
        let sql = try sqlDatabase(connection)
        for (id, title) in rows {
            try await sql.raw("UPDATE feeds SET title = \(bind: title) WHERE id = \(bind: id)").run()
        }
    }

    private func writePositions(_ connection: any Database, _ rows: [(Int, Int)]) async throws {
        let sql = try sqlDatabase(connection)
        for (id, position) in rows {
            try await sql.raw("UPDATE categories SET position = \(bind: position) WHERE id = \(bind: id)")
                .run()
        }
    }

    private func writeCheckedAt(_ connection: any Database, _ rows: [(Int, Int)]) async throws {
        let sql = try sqlDatabase(connection)
        for (id, checkedAt) in rows {
            try await sql.raw("UPDATE feeds SET fetched_at = \(bind: checkedAt) WHERE id = \(bind: id)").run()
        }
    }
}
