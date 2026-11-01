import Fluent
import Foundation
import SQLKit
import Testing
@testable import RivuletCore

/// The feed-state snapshot the minimal `status --json` contract reads. The reference has no status
/// command, so the shape is the port's own, recorded in `docs/parity.md`; what the snapshot
/// reads is the stored row and the batch rules, which `SchedulerBatchTests` pins one by one.
///
/// What these pins can fail on, each checked by patching the rule and reverting: every field is the
/// value the row holds, so a patch that reads a schema default or the process clock instead of the
/// stored number fails the pin that names it. The pin that reads the fields seeds values that are
/// not the defaults, because a pin reading an empty column can only show that an empty column reads
/// as `""` rather than as `nil`. An absent stamp is read as `nil`, which a patch turning it into
/// zero fails; the rows are listed in id order, which the pins show against the orders the storage
/// would give by reading another column, since the scan order for these rows is already the id
/// order; the totals count every row whatever its state, so a patch that counts only the enabled
/// ones fails. `due` is the batch's pick, and the pins seed the values that make each of its rules
/// falsifiable: a row scheduled at exactly the instant, which a patch reading the comparison as "at
/// or under" picks; a disabled row that would otherwise be due, which a patch dropping the gate
/// picks; a batch size of zero, which a patch that stops reading it as a switch answers as no rows
/// at all; and a window smaller than the matching rows, which a patch running the host filter
/// before the `LIMIT` fills with a row from another host. `at_error_limit` counts a row only when
/// the limit is positive: the pin that sets the limit to zero keeps its rows under the limit, so it
/// counts none, which a patch comparing unconditionally fails. The snapshot is not user-scoped,
/// which a patch adding a user condition fails.
///
/// What they cannot fail on: the order a table scan answers without the ordering clause, which for
/// these rows is the rowid order and already the id order; the order of rows sharing one
/// `next_check_at`, which SQL does not define; the JSON key names, which the command suite
/// pins; the clock the command is built with, which the command suite pins through the process
/// clock; and that the snapshot makes no network request, which no pin can show. Nothing here
/// sleeps or polls.
@Suite struct StatusSnapshotTests {
    /// The instant every pin passes. It is after the process clock until 2065, so a stored schedule
    /// the pins read as due can only be due relative to this one.
    private let now = 3_000_000_000

    @Test func theFieldsAreTheStoredValuesAndTheRowsAreListedInIdOrder() async throws {
        try await withMigratedStorage { _, storage in
            let graph = try await seedGraph(storage, username: "alice")
            // Seeded so that both the url order and the schedule order differ from the id order: a
            // patch ordering by either column answers 4, 2, 3 rather than the ids in order.
            let fourth = try await seedRow(storage, graph, id: 4, url: "http://host.test/fourth",
                nextCheckAt: 2_900_000_000, fetchedAt: 2_800_000_000, title: "Fourth")
            let second = try await seedRow(storage, graph, id: 2, url: "http://host.test/second",
                nextCheckAt: 2_900_000_010, fetchedAt: 2_800_000_010, title: "Second")
            let third = try await seedRow(storage, graph, id: 3, url: "http://host.test/third",
                nextCheckAt: 2_900_000_020, fetchedAt: 2_800_000_020, title: "Third",
                siteURL: "http://site.test/third", errors: 2, message: "parse failed", disabled: true)

            let snapshot = try await snapshot(storage, now: now, options: .defaults)
            #expect(snapshot.feeds.map(\.id) == [second, third, fourth],
                "the rows are listed in id order: \(snapshot.feeds)")

            // Every field is what the row holds, not a default or an instant the code invented. The
            // values named here are not the schema defaults, so a patch reading a default fails.
            let expected = [
                second: (url: "http://host.test/second", title: "Second", site: "", errors: 0,
                    message: "", disabled: false, fetched: 2_800_000_010, next: 2_900_000_010),
                third: (url: "http://host.test/third", title: "Third", site: "http://site.test/third",
                    errors: 2, message: "parse failed", disabled: true, fetched: 2_800_000_020,
                    next: 2_900_000_020),
                fourth: (url: "http://host.test/fourth", title: "Fourth", site: "", errors: 0,
                    message: "", disabled: false, fetched: 2_800_000_000, next: 2_900_000_000),
            ]
            for feed in snapshot.feeds {
                let row = try #require(expected[feed.id])
                #expect(feed.userID == graph.userID, "the row's user: \(feed.userID)")
                #expect(feed.url == row.url, "the row's url: \(feed.url)")
                #expect(feed.title == row.title, "\(feed.id): \(feed.title)")
                #expect(feed.siteURL == row.site, "\(feed.id): \(feed.siteURL)")
                #expect(feed.enabled == !row.disabled, "\(feed.id): \(feed.enabled)")
                #expect(feed.parsingErrorCount == row.errors, "\(feed.id): \(feed.parsingErrorCount)")
                #expect(feed.parsingErrorMessage == row.message, "\(feed.id): \(feed.parsingErrorMessage)")
                #expect(feed.fetchedAt == row.fetched, "\(feed.id): \(feed.fetchedAt)")
                #expect(feed.nextCheckAt == row.next, "\(feed.id): \(feed.nextCheckAt)")
            }
        }
    }

    @Test func anAbsentStampIsReadAsNilRatherThanAsZero() async throws {
        // A row written without a schedule: the create path stamps `next_check_at` with the instant
        // the reference reads, so this pin inserts the row the way the storage layer would see a
        // NULL column, which is what the contract must report as null rather than as zero.
        try await withMigratedStorage { _, storage in
            let graph = try await seedGraph(storage, username: "alice")
            _ = try await seedRow(storage, graph, id: 1, url: "http://host.test/fresh",
                nextCheckAt: nil, fetchedAt: nil)

            let snapshot = try await snapshot(storage, now: now, options: .defaults)
            let feed = try #require(snapshot.feeds.first)
            #expect(feed.fetchedAt == nil, "a row with no `fetched_at`: \(String(describing: feed.fetchedAt))")
            #expect(feed.nextCheckAt == nil, "a row with no `next_check_at`: \(String(describing: feed.nextCheckAt))")
            #expect(feed.title == "", "the empty value the row holds: \(feed.title)")
            #expect(feed.siteURL == "", "the empty value the row holds: \(feed.siteURL)")
        }
    }

    @Test func theTotalsCountEveryRowAndSeparateTheDueSetFromTheControlRows() async throws {
        try await withMigratedStorage { _, storage in
            let graph = try await seedGraph(storage, username: "alice")
            _ = try await seedRow(storage, graph, id: 1, url: "http://host.test/due",
                nextCheckAt: 2_900_000_000)
            _ = try await seedRow(storage, graph, id: 2, url: "http://host.test/not-yet-due",
                nextCheckAt: 3_000_000_010)
            _ = try await seedRow(storage, graph, id: 3, url: "http://host.test/disabled",
                nextCheckAt: 2_900_000_020, disabled: true)
            _ = try await seedRow(storage, graph, id: 4, url: "http://host.test/at-limit",
                nextCheckAt: 2_900_000_030, errors: 3)
            // The row at the boundary: the comparison is strict, so a row scheduled
            // at the instant is not due. A patch reading it as "at or under" picks
            // this row and fails the pin.
            _ = try await seedRow(storage, graph, id: 5, url: "http://host.test/at-the-instant",
                nextCheckAt: now)

            let snapshot = try await snapshot(storage, now: now, options: .defaults)
            #expect(snapshot.totals.feeds == 5, "every row counts, whatever its state: \(snapshot.totals)")
            #expect(snapshot.totals.enabled == 4, "\(snapshot.totals)")
            #expect(snapshot.totals.disabled == 1, "\(snapshot.totals)")
            #expect(snapshot.totals.due == 1,
                "only the row strictly under the instant is due: \(snapshot.totals)")
            #expect(snapshot.totals.atErrorLimit == 1, "\(snapshot.totals)")
        }
    }

    @Test func theSwitchesChangeTheDueTotalButNotTheRowsTheSnapshotLists() async throws {
        try await withMigratedStorage { _, storage in
            let graph = try await seedGraph(storage, username: "alice")
            // Four rows in the order the batch reads them. The first two share a
            // host, so the window keeps a row the host filter would have skipped had
            // the filter run before the `LIMIT`.
            _ = try await seedRow(storage, graph, id: 1, url: "http://host-a.test/first",
                nextCheckAt: 2_900_000_000)
            _ = try await seedRow(storage, graph, id: 2, url: "http://host-a.test/second",
                nextCheckAt: 2_900_000_010)
            _ = try await seedRow(storage, graph, id: 3, url: "http://host-b.test/third",
                nextCheckAt: 2_900_000_020)
            _ = try await seedRow(storage, graph, id: 4, url: "http://host-c.test/fourth",
                nextCheckAt: 2_900_000_030, errors: 2)

            // The window keeps the first two rows and the filter runs on those, so
            // the pick is one row. A patch that runs the filter before the window
            // keeps one host-a row and the host-b row and answers 2.
            let window = try await snapshot(storage, now: now,
                options: SchedulerOptions(pollingFrequency: .seconds(3600), batchSize: 2,
                    workerPoolSize: 16, parsingErrorLimit: 3, limitPerHost: 1))
            #expect(window.totals.feeds == 4, "the list is not capped by the batch size: \(window.totals)")
            #expect(window.totals.due == 1, "the filter runs on the rows the window kept: \(window.totals)")

            // Every row here passes the error condition, so the batch-size switch with zero adds no
            // `LIMIT` and picks all four. A patch that reads the switch as always on answers 0.
            let noWindow = try await snapshot(storage, now: now,
                options: SchedulerOptions(pollingFrequency: .seconds(3600), batchSize: 0,
                    workerPoolSize: 16, parsingErrorLimit: 3, limitPerHost: 0))
            #expect(noWindow.totals.due == 4, "zero adds no LIMIT: \(noWindow.totals)")

            // A limit of zero is the switch that appends no error condition, so
            // nothing is at a limit there is no filter for.
            let noErrorFilter = try await snapshot(storage, now: now,
                options: SchedulerOptions(pollingFrequency: .seconds(3600), batchSize: 0,
                    workerPoolSize: 16, parsingErrorLimit: 0, limitPerHost: 0))
            #expect(noErrorFilter.totals.due == 4, "zero appends no condition: \(noErrorFilter.totals)")
            #expect(noErrorFilter.totals.atErrorLimit == 0, "zero reads no filter: \(noErrorFilter.totals)")
        }
    }

    @Test func theSnapshotIsNotUserScoped() async throws {
        try await withMigratedStorage { _, storage in
            let alice = try await seedGraph(storage, username: "alice")
            let bob = try await seedGraph(storage, username: "bob")
            _ = try await seedRow(storage, alice, id: 1, url: "http://host.test/alice",
                nextCheckAt: 2_900_000_000)
            _ = try await seedRow(storage, bob, id: 2, url: "http://host.test/bob",
                nextCheckAt: 2_900_000_010)

            let snapshot = try await snapshot(storage, now: now, options: .defaults)
            #expect(snapshot.totals.feeds == 2, "no user scope: \(snapshot.totals)")
            #expect(Set(snapshot.feeds.map(\.userID)) == [alice.userID, bob.userID],
                "each row keeps its own user: \(snapshot.feeds)")
        }
    }

    // MARK: - Setup

    /// Seeds one feed row with the values the snapshot reads. The id is named so the pins
    /// can put the rows in an order the storage would not give by reading another column,
    /// which is what makes the ordering rule falsifiable.
    private func seedRow(_ storage: SQLiteStorage, _ graph: (userID: Int, categoryID: Int), id: Int,
        url: String, nextCheckAt: Int?, fetchedAt: Int? = nil, title: String = "",
        siteURL: String = "", errors: Int = 0, message: String = "", disabled: Bool = false)
        async throws -> Int {
        try await storage.withConnection { connection in
            try await sqlDatabase(connection).raw("""
                INSERT INTO feeds (id, user_id, category_id, url, site_url, title, next_check_at,
                    fetched_at, parsing_error_count, parsing_error_message, disabled,
                    created_at, updated_at)
                VALUES (\(bind: id), \(bind: graph.userID), \(bind: graph.categoryID),
                    \(bind: url), \(bind: siteURL), \(bind: title), \(bind: nextCheckAt),
                    \(bind: fetchedAt), \(bind: errors), \(bind: message), \(bind: disabled),
                    \(bind: 2_700_000_000), \(bind: 2_700_000_000))
                """).run()
            return id
        }
    }

    private func snapshot(_ storage: SQLiteStorage, now: Int, options: SchedulerOptions)
        async throws -> StatusSnapshot {
        try await storage.withConnection { connection in
            try await FeedRepository(connection).statusSnapshot(now: now, options: options)
        }
    }

    private func seedGraph(_ storage: SQLiteStorage, username: String) async throws
        -> (userID: Int, categoryID: Int) {
        try await storage.withConnection { connection in
            let userID = try await seedUser(connection, username: username)
            let categoryID = try await seedCategory(connection, userID: userID, title: "Tech")
            return (userID, categoryID)
        }
    }
}
