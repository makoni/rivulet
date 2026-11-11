import Foundation
import Fluent
import SQLKit
import Testing
@testable import RivuletCore

/// The OPML import and export paths, ported from Miniflux `internal/reader/opml/handler.go` at
/// commit `c4d54f87` (Apache-2.0): what the handler applies, in the order the reference applies it,
/// over a real SQLite database. The reads the handler consults are pinned where they live — the
/// duplicate read, the category reads, the listing order, and the rule order as pure logic in
/// `FeedValidationTests` — so these pins read only what the handler chooses on top of them.
///
/// What these pins can fail on, each checked by patching the rule and reverting: that the duplicate
/// answer runs before the category resolution and the validation, on the input that fails all three
/// at once; that the duplicate answer is the row of the account the run works for, on the url
/// another account has; that the duplicate answer takes the url the record carries as the feed half
/// rather than the site half, on the record whose two halves are different values; that the empty
/// category name reaches the smallest title in byte order, not the row the position-ordered listing
/// answers; that the named title is compared as given, with no lowering, and that a name the
/// account has no row for is created; that the first subscription the rules fail stops the run
/// after the earlier write, so the write is per subscription rather than all at the end; that each
/// setting reaches the row through the field the port schema has; that the url reaches the row from
/// the record the read answers; that the export lists in the order the reference query builder
/// answers; that the export joins the category title from the row; and that the settings the export
/// writes are the fields the port schema has. These pins read the handler's own choices, so the
/// patches they name are handler patches, except the one that reads the duplicate answer's account
/// half, which is a patch on the storage read itself and is the only probe of this round that
/// reaches a rule pinned outside these four suites, and its inputs are shaped so a patch to a rule
/// pinned elsewhere cannot reach them: the values two orders of a rule would answer differently are
/// not read here — the title and the text of a record are the same value, and the site url is read
/// from a record whose two halves are the same value except on the pin that names the url the
/// duplicate read takes — the pins read a row through its title or its category wherever another
/// pin names the url, and the export pins read fragments without the indent, so the serializer's
/// indent,
/// layout, field order and escape rules cannot reach them. The parsed inputs carry `type="rss"` on
/// every record with a url, so a patch that reads the branch through `type` instead of the url
/// still answers the same records here. What these pins cannot fail on: the rules the reference
/// validation applies after the four ported ones, which read the filter, scraper and proxy settings
/// this port's schema does not carry, so no input reaches them here; the rules the import path
/// cannot reach at all — the duplicate answer and the category answer inside the validation run,
/// because the handler skips a duplicate before validating and the category the resolution answers
/// always exists by the time the validation reads it, and the guard's url half, because a
/// subscription by definition carries a url; the storage failure the reference wraps as `opml:
/// unable to create this feed`, which has no input this suite can make it report; the reference's
/// answer for an empty category name with no rows at all, which is the nil it returns with no
/// guard, so no rule of the reference can be read there — the port answers through the guard's
/// category half, which is the port's own rule; and the wording the handler wraps around each rule,
/// which is the handler's own.
@Suite struct OPMLImportTests {
    private struct FeedRow: Sendable {
        let categoryTitle: String
        let url: String
        let title: String
        let siteURL: String
        let description: String
        let userID: Int
        let userAgent: String
        let ignoreHTTPCache: Bool
        let fetchViaProxy: Bool
        let disabled: Bool
    }

    private func rows(_ connection: any Database) async throws -> [FeedRow] {
        try await RawSQL.sql(on: connection).raw("""
            SELECT c.title AS category_title, f.url, f.title, f.site_url, f.description,
                f.user_id, f.user_agent, f.ignore_http_cache, f.fetch_via_proxy, f.disabled
            FROM feeds f JOIN categories c ON c.id = f.category_id
            ORDER BY f.id
            """).all().map { row in
            FeedRow(categoryTitle: try row.decode(column: "category_title", as: String.self),
                url: try row.decode(column: "url", as: String.self),
                title: try row.decode(column: "title", as: String.self),
                siteURL: try row.decode(column: "site_url", as: String.self),
                description: try row.decode(column: "description", as: String.self),
                userID: try row.decode(column: "user_id", as: Int.self),
                userAgent: try row.decode(column: "user_agent", as: String.self),
                ignoreHTTPCache: try row.decode(column: "ignore_http_cache", as: Bool.self),
                fetchViaProxy: try row.decode(column: "fetch_via_proxy", as: Bool.self),
                disabled: try row.decode(column: "disabled", as: Bool.self))
        }
    }

    @Test func theDuplicateAnswerRunsBeforeTheCategoryResolutionAndTheRules() async throws {
        try await withMigratedStorage { _, storage in
            let userID = try await storage.withConnection { connection in
                let id = try await seedUser(connection, username: "alice")
                let tech = try await seedCategory(connection, userID: id, title: "Tech")
                // The row is written through the seed path, which stores the url as it is given, so
                // a relative url stands as a row the duplicate answer can find.
                _ = try await seedFeed(connection, userID: id, categoryID: tech,
                    url: "relative.example/feed")
                return id
            }

            // The input fails three things at once: the url the account already has, a category
            // name the account has no row for, and the absolute-URL rule. The record is nested
            // under a parent outline, so it carries that name as its category; a top-level record
            // would carry the empty name, which the resolution answers through the existing row and
            // could not tell the two orders apart. The duplicate answer runs first, so the input is
            // skipped and nothing is written. A patch that resolved the category before the
            // duplicate answer would create the `WouldCreate` row here, and a patch that ran the
            // rules before it would report the URL rule.
            try await OPMLHandler(storage).importFeeds(userID: userID, data: Data("""
                <opml version="2.0"><head></head><body>
                <outline title="WouldCreate">
                <outline text="Skipped" title="Skipped" xmlUrl="relative.example/feed" type="rss"/>
                </outline>
                </body></opml>
                """.utf8))

            try await storage.withConnection { connection in
                let written = try await rows(connection)
                #expect(written.count == 1, "the skipped input reaches no write")
                let titles = try await categoryTitles(connection)
                #expect(titles == ["All", "Tech"].sorted(),
                    "the category the resolution would create is not there: \(titles)")
            }
        }
    }

    @Test func theDuplicateAnswerIsTheRowOfTheAccountTheRunWorksFor() async throws {
        try await withMigratedStorage { _, storage in
            _ = try await storage.withConnection { connection in
                let id = try await seedUser(connection, username: "alice")
                let tech = try await seedCategory(connection, userID: id, title: "Tech")
                _ = try await seedFeed(connection, userID: id, categoryID: tech,
                    url: "https://shared.example/feed")
                return id
            }
            let bob = try await storage.withConnection { connection in
                try await seedUser(connection, username: "bob")
            }

            // The url both accounts have is not this account's row, so the run writes it for `bob`.
            try await OPMLHandler(storage).importFeeds(userID: bob, data: Data("""
                <opml version="2.0"><head></head><body>
                <outline text="Cat" title="Shared" xmlUrl="https://shared.example/feed" type="rss"/>
                </body></opml>
                """.utf8))

            try await storage.withConnection { connection in
                let written = try await rows(connection)
                #expect(written.count == 2,
                    "the url is not this account's row, so the run reaches the write: \(written)")
                #expect(written.contains { $0.userID == bob },
                    "the row written is the one for the account the run works for: \(written)")
            }
        }
    }

    @Test func theDuplicateAnswerReadsTheFeedUrlNotTheSiteUrl() async throws {
        try await withMigratedStorage { _, storage in
            let userID = try await storage.withConnection { connection in
                let id = try await seedUser(connection, username: "alice")
                let tech = try await seedCategory(connection, userID: id, title: "Tech")
                _ = try await seedFeed(connection, userID: id, categoryID: tech,
                    url: "https://half.example/feed")
                return id
            }

            // The record carries two different url halves, and the row the account has is the feed
            // half, so this is the one input where the two rules the duplicate read could answer
            // differ. The read answers the record's feed url, so the record is skipped and nothing
            // is written; a patch that read the site url found no row here and wrote the record.
            // The category name is one the account has no row for, which the resolution would
            // create, but the duplicate answer runs before it, so the pin reads only the rows.
            try await OPMLHandler(storage).importFeeds(userID: userID, data: Data("""
                <opml version="2.0"><head></head><body>
                <outline text="Cat" title="Half" xmlUrl="https://half.example/feed" \
                htmlUrl="https://half.example/site" type="rss"/>
                </body></opml>
                """.utf8))

            try await storage.withConnection { connection in
                let written = try await rows(connection)
                #expect(written.count == 1, "the duplicate answer reads the feed url: \(written)")
                #expect(written.first?.url == "https://half.example/feed",
                    "the row that stands is the seeded one: \(written)")
            }
        }
    }

    @Test func theEmptyCategoryNameReachesTheSmallestTitleNotThePositionOrderTheListingAnswers() async throws {
        try await withMigratedStorage { _, storage in
            let userID = try await storage.withConnection { connection in
                let id = try await seedUser(connection, username: "alice")
                // The user-create path writes `All` at the position the schema default gives; `Aa`
                // is written after it with a position above it, so the two orders the reads could
                // answer differ and the pin names the one the resolution reads.
                let aa = try await seedCategory(connection, userID: id, title: "Aa")
                try await RawSQL.sql(on: connection).raw(
                    "UPDATE categories SET position = 2 WHERE id = \(bind: aa)").run()
                return id
            }

            try await OPMLHandler(storage).importFeeds(userID: userID, data: Data("""
                <opml version="2.0"><head></head><body>
                <outline><outline xmlUrl="https://empty.example/feed" type="rss"/></outline>
                </body></opml>
                """.utf8))

            try await storage.withConnection { connection in
                let written = try await rows(connection)
                let row = try #require(written.first)
                #expect(row.categoryTitle == "Aa", "the smallest title, not the position order: \(row)")
            }
        }
    }

    @Test func theNamedTitleIsComparedAsGivenAndCreatedWhenTheAccountHasNoRowForIt() async throws {
        try await withMigratedStorage { _, storage in
            let userID = try await storage.withConnection { connection in
                let id = try await seedUser(connection, username: "alice")
                _ = try await seedCategory(connection, userID: id, title: "tech")
                return id
            }

            // The record's category is the parent's title read through the chain, so the input
            // carries the name as a parent outline; `Tech` does not find the `tech` row, so the
            // created row carries the name as the record holds it. A patch that compared the title
            // lowercased would resolve to `tech` and write nothing new.
            try await OPMLHandler(storage).importFeeds(userID: userID, data: Data("""
                <opml version="2.0"><head></head><body>
                <outline text="Tech"><outline xmlUrl="https://named.example/feed" type="rss"/></outline>
                </body></opml>
                """.utf8))

            try await storage.withConnection { connection in
                // The row is read through its category, not through its url, so the pin that names
                // which field the create path is given stays the one below.
                let written = try await rows(connection)
                let row = try #require(written.first)
                #expect(row.categoryTitle == "Tech",
                    "the created row, not the row a lower-comparing patch would find: \(row)")
                let titles = try await categoryTitles(connection)
                #expect(titles == ["All", "Tech", "tech"],
                    "the created row is the name as the record holds it: \(titles)")
            }
        }
    }

    @Test func anEmptyCategoryNameWithNoRowsIsThePortsOwnAnswerThroughTheGuard() async throws {
        try await withMigratedStorage { _, storage in
            let userID = try await storage.withConnection { connection in
                try await seedUserWithoutCategories(connection, username: "carol")
            }

            // The reference answers nil for this input and has no guard for it, so no rule of the
            // reference can be read here; the port answers through the guard's category half, which
            // reads the resolved category as a positive number and fails on the id the resolution
            // answers as 0.
            do {
                try await OPMLHandler(storage).importFeeds(userID: userID, data: Data("""
                    <opml version="2.0"><head></head><body>
                    <outline><outline xmlUrl="https://nocat.example/feed" type="rss"/></outline>
                    </body></opml>
                    """.utf8))
                Issue.record("the run must report the rule the port names")
            } catch let error as OPMLError {
                #expect(error == .invalidFeedSettings(rule: .mandatoryFields,
                    feedURL: "https://nocat.example/feed"), "\(error)")
            }

            try await storage.withConnection { connection in
                let written = try await rows(connection)
                #expect(written.isEmpty, "a run that fails writes nothing")
            }
        }
    }

    @Test func theFirstSubscriptionTheRulesFailStopsTheRunAfterTheEarlierWrite() async throws {
        try await withMigratedStorage { _, storage in
            let userID = try await storage.withConnection { connection in
                try await seedUser(connection, username: "alice")
            }

            // The reference validates and creates per subscription, so the first input is written
            // before the second fails. A patch that ran the rules for the whole list before the
            // first write would report the same rule with nothing written, which fails this pin
            // alone. The titles here are the text values, so the title chain cannot reach the value
            // this pin reads.
            do {
                try await OPMLHandler(storage).importFeeds(userID: userID, data: Data("""
                    <opml version="2.0"><head></head><body>
                    <outline text="Ok" title="Ok" xmlUrl="https://ok.example/feed" type="rss"/>
                    <outline text="Bad" title="Bad" xmlUrl="bad.example/feed" type="rss"/>
                    <outline text="Later" title="Later" xmlUrl="https://later.example/feed" type="rss"/>
                    </body></opml>
                    """.utf8))
                Issue.record("the failing subscription must reach as the rule it fails on")
            } catch let error as OPMLError {
                #expect(error == .invalidFeedSettings(rule: .invalidURL,
                    feedURL: "bad.example/feed"), "\(error)")
            }

            try await storage.withConnection { connection in
                // The pin reads only that one row exists, so a patch to the field mapping cannot
                // reach it; the pin that reads which field the create path is given is the one
                // below.
                let written = try await rows(connection)
                #expect(written.count == 1,
                    "the write before the failure stands, and the later subscription never runs: \(written)")
            }
        }
    }

    @Test func theSettingsReachTheRowThroughTheFieldsThePortSchemaHas() async throws {
        try await withMigratedStorage { _, storage in
            let userID = try await storage.withConnection { connection in
                try await seedUser(connection, username: "alice")
            }

            // The schema carries four of the settings the record holds, so the import applies
            // exactly those. The pin separates each of the four from the storage default, so a
            // mapping patch that drops one field fails on its own assertion.
            try await OPMLHandler(storage).importFeeds(userID: userID, data: Data("""
                <opml xmlns:miniflux="https://miniflux.app/opml" version="2.0">
                <head></head><body>
                <outline text="Cat">
                <outline title="Settings" text="Settings" xmlUrl="https://settings.example/feed" \
                htmlUrl="https://settings.example/feed" description="desc" \
                miniflux:userAgent="true" miniflux:ignoreHTTPCache="true" \
                miniflux:fetchViaProxy="true" miniflux:disabled="true" type="rss"/>
                </outline>
                </body></opml>
                """.utf8))

            try await storage.withConnection { connection in
                let written = try await rows(connection)
                let row = try #require(written.first)
                #expect(row.title == "Settings",
                    "the title reaches the row through the handler's mapping: \(row)")
                #expect(row.siteURL == "https://settings.example/feed",
                    "the site url reaches the row through the handler's mapping: \(row)")
                #expect(row.description == "desc", "\(row)")
                #expect(row.categoryTitle == "Cat", "\(row)")
                #expect(row.userID == userID, "the row is for the account the run works for: \(row)")
                #expect(row.userAgent == "true", "\(row)")
                #expect(row.ignoreHTTPCache, "\(row)")
                #expect(row.fetchViaProxy, "\(row)")
                #expect(row.disabled, "\(row)")
            }
        }
    }

    @Test func theUrlReachesTheRowFromTheRecordTheReadAnswers() async throws {
        try await withMigratedStorage { _, storage in
            let userID = try await storage.withConnection { connection in
                try await seedUser(connection, username: "alice")
            }

            // The pin reads that the write path passes the record's url to the create path, which
            // is the half the reference writes as submitted. The record here carries a title that
            // is not the url, so a patch that hands the create path another field of the record
            // fails this pin, and the pin that reads the record's own value is the read suite's.
            try await OPMLHandler(storage).importFeeds(userID: userID, data: Data("""
                <opml version="2.0"><head></head><body>
                <outline text="Cat" title="Named" xmlUrl="https://fromrecord.example/feed" type="rss"/>
                </body></opml>
                """.utf8))

            try await storage.withConnection { connection in
                let written = try await rows(connection)
                let row = try #require(written.first)
                #expect(row.url == "https://fromrecord.example/feed",
                    "the url the record answers reaches the row: \(row)")
            }
        }
    }

    @Test func theExportListsInTheOrderTheQueryBuilderAnswers() async throws {
        try await withMigratedStorage { _, storage in
            let userID = try await storage.withConnection { connection in
                try await seedUser(connection, username: "alice")
            }
            let tech = try await storage.withConnection { connection in
                try await seedCategory(connection, userID: userID, title: "Tech")
            }
            try await storage.withConnection { connection in
                // The insertion order is the one that is not the read's order, and the titles are
                // in the byte order the grouping rule would answer, so the pin reads only the
                // read's order and a patch to the grouping rule cannot reach it.
                try await seedAndName(connection, userID: userID, categoryID: tech,
                    url: "https://beta.example/feed", title: "Beta", errorCount: 0)
                try await seedAndName(connection, userID: userID, categoryID: tech,
                    url: "https://alpha.example/feed", title: "Alpha", errorCount: 2)
            }

            // The order the export reads is the builder's: the error count descending, which puts
            // `Alpha` first although it was written second, while the plain listing order would put
            // `Beta` first.
            let output = try await OPMLHandler(storage).exportFeeds(userID: userID,
                now: Date(timeIntervalSince1970: 0))
            let linesOfRecords = output.split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init).filter { $0.contains("xmlUrl=") }
            #expect(linesOfRecords.count == 2, "\(linesOfRecords)")
            #expect(linesOfRecords[0].contains("title=\"Alpha\""),
                    "the error count puts the row with the higher count first: \(linesOfRecords)")
            #expect(linesOfRecords[1].contains("title=\"Beta\""),
                    "and the row written second comes second: \(linesOfRecords)")
        }
    }

    @Test func theExportJoinsTheCategoryTitleFromTheRow() async throws {
        try await withMigratedStorage { _, storage in
            let userID = try await storage.withConnection { connection in
                try await seedUser(connection, username: "alice")
            }
            try await storage.withConnection { connection in
                let other = try await seedCategory(connection, userID: userID, title: "Other")
                try await seedAndName(connection, userID: userID, categoryID: other,
                    url: "https://b.example/feed", title: "B", errorCount: 0)
            }

            // The group line carries the title the row points at through the join, not the id. The
            // fragment is read without the indent so a patch to the indent or the layout cannot
            // reach it.
            let output = try await OPMLHandler(storage).exportFeeds(userID: userID,
                now: Date(timeIntervalSince1970: 0))
            #expect(output.contains("text=\"Other\""), "the join half: \(output)")
        }
    }

    @Test func theSettingsTheExportWritesAreTheFieldsThePortSchemaHas() async throws {
        try await withMigratedStorage { _, storage in
            let userID = try await storage.withConnection { connection in
                try await seedUser(connection, username: "alice")
            }
            try await storage.withConnection { connection in
                let tech = try await seedCategory(connection, userID: userID, title: "Tech")
                try await seedAndName(connection, userID: userID, categoryID: tech,
                    url: "https://a.example/feed", title: "A", errorCount: 0)
                try await RawSQL.sql(on: connection).raw(
                    "UPDATE feeds SET user_agent = 'UA', disabled = 1 WHERE url = 'https://a.example/feed'").run()
            }

            // Each setting is read on its own fragment, so a patch that drops one field of the
            // mapping fails the assertion that names it. The settings the schema has no column for
            // cannot be read here at all, which the header names.
            let output = try await OPMLHandler(storage).exportFeeds(userID: userID,
                now: Date(timeIntervalSince1970: 0))
            #expect(output.contains("miniflux:userAgent=\"UA\""),
                "the string setting the row carries reaches the export: \(output)")
            #expect(output.contains("miniflux:disabled=\"true\""),
                "the bool setting the row carries reaches the export: \(output)")
        }
    }

    private func categoryTitles(_ connection: any Database) async throws -> [String] {
        try await RawSQL.sql(on: connection).raw("SELECT title FROM categories ORDER BY title").all()
            .map { try $0.decode(column: "title", as: String.self) }
    }

    private func seedAndName(_ connection: any Database, userID: Int, categoryID: Int,
        url: String, title: String, errorCount: Int) async throws {
        _ = try await seedFeed(connection, userID: userID, categoryID: categoryID, url: url)
        try await RawSQL.sql(on: connection).raw(
            "UPDATE feeds SET title = \(bind: title), parsing_error_count = \(bind: errorCount) WHERE url = \(bind: url)").run()
    }

    /// Seeds an account with no category rows, which the user-create path cannot leave: the pin
    /// above reads the ports own answer for the input the reference has no guard for.
    private func seedUserWithoutCategories(_ connection: any Database, username: String)
        async throws -> Int {
        try await RawSQL.sql(on: connection).raw(
            "INSERT INTO users (username, password_hash, created_at, updated_at) VALUES (\(bind: username), 'hash', 0, 0)").run()
        let row = try await RawSQL.sql(on: connection).raw(
            "SELECT id FROM users WHERE username = \(bind: username)").first()
        let decoded = try row?.decode(column: "id", as: Int.self)
        return try #require(decoded)
    }
}
