import ConsoleKit
import Fluent
import Foundation
import SQLKit
import Testing
import RivuletApp
@testable import RivuletCore

/// The manual pass over the batch: `rivulet refresh` (`internal/cli/refresh_feeds.go` at commit
/// `c4d54f87`) reads one batch, runs each job of it once through the worker's path, reports what it
/// ran, and exits. The batch rules themselves are pinned by `SchedulerBatchTests` and the pool by
/// `SchedulerTickTests`; these pins are the command — the values it reads, that each job of the
/// batch reaches the pool once, the path the run takes, and what it does with a job that failed.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the command
/// runs the batch it read rather than every feed row, so a patch that drops the due comparison,
/// the disabled gate or reads the error limit as `at` rather than `under` fails the pins that
/// say the control paths receive no request; each job runs once, which a patch that runs a job
/// twice in the pool fails, because the server counts the arrivals per path; the values the
/// batch reads come from the environment, so a patch that keeps the reference defaults, or that
/// reads the batch size or the host filter as a fixed number rather than as the value the
/// environment names, fails the pin that sets one of them; the run is the worker's path, which
/// a patch that passes the forced flag fails, because the builder then leaves the stored
/// validator out of the request; a failed job is reported and does not stop the rest, which a
/// patch that propagates the first failure fails, and a patch that counts no failure fails the
/// report the pin reads; the pass left the schedule it advanced, which a patch that records the
/// fetch without moving `next_check_at` fails because the second pass runs the feed again; and
/// the migration flag gates this command, which a patch that migrates regardless of it fails.
///
/// Each feed is read on its own path, and its site URL on another, because the icon checker the run
/// calls asks the server for the site URL: a feed whose site path were its feed path could not
/// tell the job's request from the checker's, so the pins read the feed path only.
///
/// What they cannot fail on: the cadence, because this command makes one pass and no pin can
/// show that a loop is absent — a patch that looped would hang the suite rather than fail it;
/// the worker pool size, the cap `SchedulerTickTests` already names as unpinnable; the duration
/// the reference logs at the end, the pool-start line and the per-job line, which are logging
/// and `RivuletCore` has no layer for it, so what a pin reads is the report the port writes to
/// the console, and its wording is the port's own while what the pins read is the counts;
/// closing the fetcher the command created, which no pin can assert because a shutdown that
/// itself fails would hide the failure the test reports; the reference's check that the schema
/// is up to date, which this port does not port; and the order of the statements inside one
/// refresh, which the pipeline suite names. Nothing here sleeps or polls.
@Suite struct RefreshCommandTests {
    init() {
        TestLogging.bootstrapOnce()
    }

    // MARK: - Pins

    @Test func theCommandRunsTheBatchItReadAndNotEveryFeedRow() async throws {
        try await withRun(behaviors: answered, feeds: [
            spec(path: "/a", due: -3000),
            spec(path: "/b", due: -2000),
            spec(path: "/c", due: -1000),
            spec(path: "/late", due: 3600),
            spec(path: "/off", due: -2000, disabled: true),
            spec(path: "/limit", due: -2000, errors: 3),
        ]) { server, console, storage, ran in
            // The batch is what the command runs: each job once, and no control row at all.
            for path in ["/a", "/b", "/c"] {
                #expect(server.received(for: path).count == 1, "each job runs once: \(console.output)")
            }
            for path in ["/late", "/off", "/limit"] {
                #expect(server.received(for: path).isEmpty,
                    "the control rows are not in the batch: \(console.output)")
            }
            #expect(console.output.contains("3 feed(s)"), "\(console.output)")
            #expect(console.output.contains("0 failed"), "\(console.output)")

            // The jobs reached the storage, not only the server.
            let entries = try await storage.withConnection { connection in
                try await Entry.query(on: connection).count()
            }
            #expect(entries == 3, "one entry per document the batch ran: \(entries)")
        }
    }

    @Test func theValuesTheBatchReadsComeFromTheEnvironment() async throws {
        // A batch size of one keeps the row that is due first, which the reference default of 100
        // would not.
        try await withRun(behaviors: answered, environment: ["BATCH_SIZE": "1"], feeds: [
            spec(path: "/first", due: -3000),
            spec(path: "/second", due: -2000),
        ]) { server, console, _, _ in
            #expect(server.received(for: "/first").count == 1, "\(console.output)")
            #expect(server.received(for: "/second").isEmpty, "\(console.output)")
            #expect(console.output.contains("1 feed(s)"), "\(console.output)")
        }

        // The host limit is applied while the rows are read, so two rows on one host share the one
        // slot the value gives. The grouping per host itself is pinned in
        // `SchedulerBatchTests`; what is pinned here is that the value reaches the batch
        // through the command.
        try await withRun(behaviors: answered, environment: ["POLLING_LIMIT_PER_HOST": "1"], feeds: [
            spec(path: "/x", due: -3000),
            spec(path: "/y", due: -2000),
        ]) { server, console, _, _ in
            #expect(server.received(for: "/x").count == 1, "\(console.output)")
            #expect(server.received(for: "/y").isEmpty, "\(console.output)")
            #expect(console.output.contains("1 feed(s)"), "\(console.output)")
        }

        // A limit of zero is the switch that writes no filter, so the row at the default limit of
        // three is part of the batch here.
        try await withRun(behaviors: answered, environment: ["POLLING_PARSING_ERROR_LIMIT": "0"],
            feeds: [spec(path: "/at-limit", due: -1000, errors: 3)]) { server, console, _, _ in
            #expect(server.received(for: "/at-limit").count == 1, "\(console.output)")
            #expect(console.output.contains("1 feed(s)"), "\(console.output)")
        }
    }

    @Test func theRunIsTheWorkerPathSoTheStoredValidatorsReachTheRequest() async throws {
        try await withRun(behaviors: answered,
            feeds: [spec(path: "/feed", due: -1000, etag: "\"stored-etag\"")]) { server, console, _, _ in
            let request = try #require(server.received(for: "/feed").first)
            #expect(request.headers["If-None-Match"] == "\"stored-etag\"", "\(request.headers)")
            #expect(console.output.contains("1 feed(s)"), "\(console.output)")
        }
    }

    @Test func aFailedJobIsReportedAndDoesNotStopTheRest() async throws {
        try await withRun(behaviors: [
            "/failed": StubFeedServer.Behavior(status: 500, body: Data("nope".utf8)),
            "/failed-site": document(),
            "/ok": answer(rss),
            "/ok-site": document(),
        ], feeds: [spec(path: "/failed", due: -3000), spec(path: "/ok", due: -2000)]) {
            server, console, storage, ran in
            #expect(server.received(for: "/failed").count == 1, "\(console.output)")
            #expect(server.received(for: "/ok").count == 1,
                "a failure does not stop the rest: \(console.output)")
            #expect(console.output.contains("1 failed"), "\(console.output)")

            // The job that failed still wrote the record the reference writes for it.
            let failed = try await storage.withConnection { connection in
                try await FeedRepository(connection).fetch(id: ran[0].feedID)
            }
            #expect(failed?.parsingErrorCount == 1, "\(failed?.parsingErrorCount)")
        }
    }

    @Test func theFirstPassAdvancesTheScheduleSoTheSecondRunsNothing() async throws {
        try await withRun(behaviors: answered, feeds: [spec(path: "/feed", due: -1000)],
            runs: 2) { server, console, _, _ in
            #expect(server.received(for: "/feed").count == 1, "\(console.output)")
            #expect(console.output.contains("1 feed(s)"), "\(console.output)")
            #expect(console.output.contains("0 feed(s)"),
                "the second pass runs nothing: \(console.output)")
        }
    }

    @Test func theMigrationFlagGatesThisCommand() async throws {
        // The flag on: the command builds the schema and reads the batch through it.
        let migrated = try TemporaryDirectory()
        defer { migrated.remove() }
        let on = TestConsole()
        try await RivuletCLI.run(console: on, environment: ["DATABASE_URL": migrated.path("on.db")],
            arguments: ["rivulet", "refresh"])
        #expect(on.output.contains("0 feed(s)"), "\(on.output)")
        let created = try await tables(at: migrated.path("on.db"))
        #expect(created.contains("feeds"), "the flag on migrates: \(created)")

        // The flag off: the command does not create the schema, so it cannot read the batch and
        // fails rather than reporting an empty batch.
        let unmigrated = try TemporaryDirectory()
        defer { unmigrated.remove() }
        let off = TestConsole()
        do {
            try await RivuletCLI.run(console: off,
                environment: ["DATABASE_URL": unmigrated.path("off.db"), "RUN_MIGRATIONS": "false"],
                arguments: ["rivulet", "refresh"])
            Issue.record("a command that does not migrate must fail on a fresh database")
        } catch {
            #expect(String(describing: error).contains("feeds"), "\(error)")
        }
        let absent = try await tables(at: unmigrated.path("off.db"))
        #expect(!absent.contains("feeds"), "the flag off does not migrate: \(absent)")
    }

    // MARK: - Setup

    /// A feed row as the command's batch reads it: the path its URL names, the path its
    /// site URL names, the instant its `next_check_at` holds, the error count, the disabled
    /// flag and the validator.
    private struct FeedSpec: Sendable {
        let path: String
        let sitePath: String
        let dueAt: Int
        let errors: Int
        let disabled: Bool
        let etag: String
    }

    /// The row id and the path its URL names, which is where a pin reads the arrivals.
    private struct SeededFeed: Sendable {
        let feedID: Int
        let path: String
    }

    private func spec(path: String, due: Int, errors: Int = 0, disabled: Bool = false,
        etag: String = "") -> FeedSpec {
        FeedSpec(path: path, sitePath: "\(path)-site",
            dueAt: Int(Date.now.timeIntervalSince1970) + due, errors: errors, disabled: disabled,
            etag: etag)
    }

    /// Runs `rivulet refresh` `runs` times against a database and a server started for this
    /// test only, as `docs/testing.md` requires, and hands the pins what the runs left: the
    /// arrivals, the console report, the rows and the ids.
    ///
    /// The setup connection is not held across the run: the command opens its own
    /// application and its own write transaction, which the single pooled connection of the
    /// test storage cannot serve from inside a checkout of its own.
    private func withRun(
        behaviors: [String: StubFeedServer.Behavior],
        environment: [String: String] = [:],
        feeds: [FeedSpec],
        runs: Int = 1,
        _ body: @escaping @Sendable (StubFeedServer, TestConsole, SQLiteStorage, [SeededFeed])
            async throws -> Void
    ) async throws {
        try await withMigratedStorage { database, storage in
            try await FetchTestSupport.withServer(behaviors: behaviors) { server in
                let seeded = try await storage.withConnection { connection in
                    let userID = try await seedUser(connection)
                    let categoryID = try await seedCategory(connection, userID: userID, title: "Tech")
                    var rows: [SeededFeed] = []
                    for feed in feeds {
                        let feedID = try await seedFeed(connection, userID: userID,
                            categoryID: categoryID, url: server.url(feed.path).absoluteString)
                        let row = try #require(await FeedRepository(connection).fetch(id: feedID))
                        row.siteURL = server.url(feed.sitePath).absoluteString
                        row.nextCheckAt = feed.dueAt
                        row.parsingErrorCount = feed.errors
                        row.disabled = feed.disabled
                        row.etag = feed.etag
                        try await row.update(on: connection)
                        rows.append(SeededFeed(feedID: feedID, path: feed.path))
                    }
                    return rows
                }

                var env = environment
                env["DATABASE_URL"] = database.path
                env["FETCHER_ALLOW_PRIVATE_NETWORKS"] = "true"
                let console = TestConsole()
                for _ in 0..<runs {
                    try await RivuletCLI.run(console: console, environment: env,
                        arguments: ["rivulet", "refresh"])
                }
                try await body(server, console, storage, seeded)
            }
        }
    }

    /// The table every path the pins read answers with one entry, so an arrival on a feed
    /// path is the record of the job that ran, and every site path answers a document with
    /// no icon link, which keeps the checker's request on the site path rather than on the
    /// feed path.
    private var answered: [String: StubFeedServer.Behavior] {
        var table: [String: StubFeedServer.Behavior] = [:]
        for path in ["/a", "/b", "/c", "/late", "/off", "/limit", "/first", "/second",
                     "/x", "/y", "/at-limit", "/feed", "/ok"] {
            table[path] = answer(rss)
            table["\(path)-site"] = document()
        }
        return table
    }

    private var rss: String {
        "<rss version=\"2.0\"><channel><title>Feed</title><link></link>"
            + "<item><title>Entry</title><link>https://example.org/a</link>"
            + "<description>Entry text</description></item></channel></rss>"
    }

    private func answer(_ body: String) -> StubFeedServer.Behavior {
        StubFeedServer.Behavior(headers: ["ETag": "\"stub-etag\""], body: Data(body.utf8))
    }

    private func document() -> StubFeedServer.Behavior {
        StubFeedServer.Behavior(headers: ["Content-Type": "text/html"], body: Data("<html></html>".utf8))
    }

    /// The tables the database file holds, read through a connection of its own.
    private func tables(at path: String) async throws -> [String] {
        let config = try Config.load(environment: ["DATABASE_URL": path])
        let rivulet = try await ApplicationFactory.make(config: config)
        do {
            let sql = try #require(rivulet.application.db(.sqlite) as? any SQLDatabase)
            let rows = try await sql.raw("SELECT name FROM sqlite_master WHERE type = 'table'").all()
            let names = try rows.map { try $0.decode(column: "name", as: String.self) }
            try await rivulet.shutdown()
            return names
        } catch {
            try? await rivulet.shutdown()
            throw error
        }
    }
}
