import Foundation
import Fluent
import SQLKit
import Testing
@testable import RivuletApp
@testable import RivuletCore

/// The items read, over a real socket: `handleItems` of `internal/fever/handler.go` at `c4d54f87`.
/// The goldens are the reference's own answers for these inputs at the toolchain `go.mod` pins.
///
/// The rows are written on one connection and the request runs after that connection goes back to
/// the pool, because the driver keeps a single pooled connection, so a pin cannot hold one while
/// the handler checks out another.
///
/// What these pins can fail on, each checked by patching the rule and reverting (4 pins, 8 probes):
/// the page size is 50 and `total_items` is the count read without the page, which a patch that
/// used the page as the count fails on — 1 probe; the precedence the switch reads, which a patch
/// that read `max_id` before `since_id` fails on — 1 probe; the three paths `QueryInt64Param`
/// answers the default for — empty, unparseable and negative — so a negative `max_id` is the zero
/// half of the branch rather than a bound, which is 2 probes, one on the sign guard and one on the
/// half of the branch the default lands in; that a value the list read cannot read is 0 rather than
/// something skipped, which a patch that skipped it fails on because an empty id set applies no
/// filter here while `id IN (0)` selects nothing — 1 probe; the trim that is Go's
/// `unicode.IsSpace`, which a patch that read the value as given fails on — 1 probe; and the values
/// that reach the item document, which is 2 probes: the two flags read as 0 and 1, and the
/// publication time the reference's `entry.Date` holds, which a patch that read the `created_at`
/// column fails on because the fixture writes the two columns with different values.
///
/// What these pins cannot show: the order the reference answers for the branches that add no sort
/// expression, which its builder leaves to the engine — this port always carries a sort, which
/// `docs/reference-notes.md` records, so the pins read the port's own order for those branches; the
/// `html` field, which is the stored content because the media proxy is not ported, which
/// `docs/parity.md` records; the count the reference reads through its own builder rather than the
/// page, which is the same statement as this port's `count`; and the clock field, read through the
/// placeholder the request helper names.
@Suite struct FeverItemsTests {
    init() {
        TestLogging.bootstrapOnce()
    }

    @Test func thePageIsFiftyAndTheCountIsReadWithoutThePage() async throws {
        try await withServedApp { storage, app, base in
            let requests = FeverRequests(app, base)
            let (userID, token) = try await requests.seed(storage, name: "alice", password: "secret")

            let feed = try await storage.withConnection { connection in
                let category = try await seedCategory(connection, userID: userID, title: "Tech")
                let feed = try await seedFeed(connection, userID: userID, categoryID: category,
                    url: "https://e/1")
                try await seedManyEntries(connection, userID: userID, feedID: feed, count: 51,
                    firstPublishedAt: 1_700_000_000)
                try await writeCreatedAt(connection, (1...51).map { ($0, 1_700_001_000 + $0) })
                return feed
            }

            // Fifty rows and a count of fifty-one: a patch that wrote the page as the count
            // failed here, and one that dropped the limit answered fifty-one rows.
            let items = (1...50).map { n in
                FeverShape.item(id: n, feedID: feed, title: "Bulk \(n)", author: "", html: "", url: "",
                    isSaved: 0, isRead: 0, createdOnTime: Int64(1_700_000_000 + n))
            }
            #expect(requests.document(of: try await requests.get("api&items&api_key=\(token)")) ==
                FeverShape.itemsDocument(items: items, total: 51, lastRefreshed: 0).written(),
                "the page the read is given, the count read without it, and the publication time the rows hold")
        }
    }

    @Test func theThreeFormsOfTheItemSelectionAnswerInTheirPrecedenceOrder() async throws {
        try await withServedApp { storage, app, base in
            let requests = FeverRequests(app, base)
            let (userID, token) = try await requests.seed(storage, name: "alice", password: "secret")

            let (feed, ids) = try await storage.withConnection { connection in
                let category = try await seedCategory(connection, userID: userID, title: "Tech")
                let feed = try await seedFeed(connection, userID: userID, categoryID: category,
                    url: "https://e/1")
                var ids: [Int] = []
                for n in 1...3 {
                    let id = try await seedEntry(connection, userID: userID, feedID: feed, hash: "\(n)",
                        title: "\(n)", publishedAt: 100 * n)
                    try await writeCreatedAt(connection, [(id, 900 + id)])
                    ids.append(id)
                }
                return (feed, ids)
            }

            // The document reads the publication time, so the goldens carry it while the fixture
            // put a different value in `created_at` beside it — which is what a patch that read the
            // other column fails on.
            let times: [Int: Int] = [ids[0]: 100, ids[1]: 200, ids[2]: 300]
            func page(_ selected: [Int], total: Int = 3) -> String {
                FeverShape.itemsDocument(items: selected.map { id in
                    FeverShape.item(id: id, feedID: feed, title: String(id), author: "Author",
                        html: "<p>Hello world</p>", url: "https://example.com/entry",
                        isSaved: 0, isRead: 0, createdOnTime: Int64(times[id] ?? 0))
                }, total: total, lastRefreshed: 0).written()
            }

            // All three names on one request: the first branch of the switch answers. A patch
            // that read `max_id` first answered the `max_id` page here.
            #expect(requests.document(of: try await requests.get(
                "api&items&api_key=\(token)&since_id=\(ids[0])&max_id=\(ids[1])&with_ids=\(ids[2])")) ==
                page([ids[1], ids[2]]), "the cursor that comes first in the switch")

            // The two halves of the `max_id` branch: a value is a bound, and the zero is the
            // branch that takes the most recent rows.
            #expect(requests.document(of: try await requests.get(
                "api&items&api_key=\(token)&max_id=\(ids[1])")) == page([ids[0]]),
                "the rows below the bound, in the order the branch sorts them")
            #expect(requests.document(of: try await requests.get(
                "api&items&api_key=\(token)&max_id=abc")) == page([ids[2], ids[1], ids[0]]),
                "a value the read cannot read is 0, which is the most-recent half of the branch")

            // The three paths that answer the default are empty, unparseable and negative, so a
            // negative value is the zero half of the branch, not a bound. A patch that read the
            // sign as part of the value answered the port's own default order here instead.
            #expect(requests.document(of: try await requests.get(
                "api&items&api_key=\(token)&max_id=-\(ids[1])")) == page([ids[2], ids[1], ids[0]]),
                "the negative value answers the default, which is the zero half of the branch")

            // The `with_ids` branch is the third in the switch, so a request that carries only
            // that name answers it, in the order the port's own sort gives.
            #expect(requests.document(of: try await requests.get(
                "api&items&api_key=\(token)&with_ids=\(ids[2])")) == page([ids[2]]),
                "the branch that reads the list")
        }
    }

    @Test func theListReadTrimsAndKeepsAValueItCannotReadAsTheZero() async throws {
        try await withServedApp { storage, app, base in
            let requests = FeverRequests(app, base)
            let (userID, token) = try await requests.seed(storage, name: "alice", password: "secret")

            let (feed, first, second) = try await storage.withConnection { connection in
                let category = try await seedCategory(connection, userID: userID, title: "Tech")
                let feed = try await seedFeed(connection, userID: userID, categoryID: category,
                    url: "https://e/1")
                let first = try await seedEntry(connection, userID: userID, feedID: feed, hash: "1",
                    title: "1", publishedAt: 100)
                let second = try await seedEntry(connection, userID: userID, feedID: feed, hash: "2",
                    title: "2", publishedAt: 200)
                try await writeCreatedAt(connection, [(first, 900 + first), (second, 900 + second)])
                return (feed, first, second)
            }

            let times: [Int: Int] = [first: 100, second: 200]
            func page(_ selected: [Int]) -> String {
                FeverShape.itemsDocument(items: selected.map { id in
                    FeverShape.item(id: id, feedID: feed, title: String(id), author: "Author",
                        html: "<p>Hello world</p>", url: "https://example.com/entry",
                        isSaved: 0, isRead: 0, createdOnTime: Int64(times[id] ?? 0))
                }, total: 2, lastRefreshed: 0).written()
            }

            // The trim is Go's `unicode.IsSpace`, so the spaces around the value are read as part
            // of the pair the read keeps; a patch that read the value as given would have had a
            // value it could not read, which is the other half of this pin.
            #expect(requests.document(of: try await requests.get(
                "api&items&api_key=\(token)&with_ids=%20\(second)%20")) == page([second]),
                "the value after the trim")

            // A value the integer read cannot read is 0, and the id set is applied as read: this
            // request selects nothing. A patch that dropped the failing value answered the whole
            // page, because an empty id set applies no filter in this port's read.
            #expect(requests.document(of: try await requests.get(
                "api&items&api_key=\(token)&with_ids=x")) ==
                FeverShape.itemsDocument(items: [], total: 2, lastRefreshed: 0).written(),
                "the zero the read gives, applied as a filter")

            // And both are in the set when the pair carries them.
            #expect(requests.document(of: try await requests.get(
                "api&items&api_key=\(token)&with_ids=x,%20\(first)%20")) == page([first]),
                "the zero selects nothing and the value that reads selects its row")

            // An empty piece is kept by the split, so a pair that carries one answers the zero too.
            #expect(requests.document(of: try await requests.get(
                "api&items&api_key=\(token)&with_ids=%20%20")) ==
                FeverShape.itemsDocument(items: [], total: 2, lastRefreshed: 0).written(),
                "the empty piece is the zero, not a piece to skip")
        }
    }

    @Test func theItemDocumentCarriesTheValuesTheRowHolds() async throws {
        try await withServedApp { storage, app, base in
            let requests = FeverRequests(app, base)
            let (userID, token) = try await requests.seed(storage, name: "alice", password: "secret")

            // Two rows that answer the two flags differently, read in the order the port's
            // sort gives.
            let (feed, starred, read) = try await storage.withConnection { connection in
                let category = try await seedCategory(connection, userID: userID, title: "Tech")
                let feed = try await seedFeed(connection, userID: userID, categoryID: category,
                    url: "https://e/1")
                let starred = try await seedEntry(connection, userID: userID, feedID: feed, hash: "1",
                    title: "Starred", url: "https://example.com/1", author: "Author",
                    content: "<p>Hello</p>", publishedAt: 200, status: .unread, starred: true)
                let read = try await seedEntry(connection, userID: userID, feedID: feed, hash: "2",
                    title: "Read", url: "https://example.com/2", author: "",
                    content: "<p>Other</p>", publishedAt: 100, status: .read)
                try await writeCreatedAt(connection, [(starred, 900 + starred), (read, 900 + read)])
                return (feed, starred, read)
            }

            #expect(requests.document(of: try await requests.get("api&items&api_key=\(token)")) ==
                FeverShape.itemsDocument(items: [
                    FeverShape.item(id: read, feedID: feed, title: "Read", author: "",
                        html: "<p>Other</p>", url: "https://example.com/2", isSaved: 0, isRead: 1,
                        createdOnTime: 100),
                    FeverShape.item(id: starred, feedID: feed, title: "Starred", author: "Author",
                        html: "<p>Hello</p>", url: "https://example.com/1", isSaved: 1, isRead: 0,
                        createdOnTime: 200)
                ], total: 2, lastRefreshed: 0).written(),
                "the nine fields, the two flags as 0 and 1, and the publication time the row holds")
        }
    }

    /// Writes `created_at` as a value the pin can name, because the write path stamps it with the
    /// instant, which no pin can read. The document reads the publication time, so this is the
    /// column that has to hold a different value for the pin to name which one the document reads.
    private func writeCreatedAt(_ connection: any Database, _ rows: [(Int, Int)]) async throws {
        let sql = try sqlDatabase(connection)
        for (id, createdAt) in rows {
            try await sql.raw("UPDATE entries SET created_at = \(bind: createdAt) WHERE id = \(bind: id)")
                .run()
        }
    }
}
