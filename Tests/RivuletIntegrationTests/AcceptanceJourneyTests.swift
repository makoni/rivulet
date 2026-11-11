import Foundation
import SQLKit
import Testing
import Vapor
import RivuletApp
@testable import RivuletCore

/// The acceptance journey: one chain run per pin, in the order `docs/plan/stage-5-apis.md` names it
/// — the two console runs that build the account and its credential pairs, the OPML run that writes
/// the rows, the pass over the batch that writes the entries, and the socket the client requests go
/// to.
///
/// The run half asserts nothing, so every failure is recorded by a pin. What each pin can fail on,
/// one rule per pin, each checked by patching the rule and reverting the file byte-identically:
///
/// - the login compares the password with the value stored on the row the run wrote;
/// - the Fever pair the run wrote is the pair the Fever read answers for, through the join and the
///   lowercase hex form;
/// - the rows the import run wrote are the rows the client listing reads, with the two urls and the
///   category the record names;
/// - the pass over the batch ran one job for each row the import wrote and wrote one row per item
///   the document declares, with the checksum the reference's `SHA256` gives for the value it
///   declares;
/// - the login answer is the three text lines in the order the reference writes them;
/// - the subscription listing answers with the values this handler writes, the label being the
///   category title and not the feed title;
/// - the stream read's exclude branch chooses which rows the ids answer carries;
/// - the contents document's `self` is the configured base rather than the host the request came in
///   on, and its item carries the row values the read answers;
/// - the tag read's add loop writes the status the counts read back;
/// - the Fever groups document carries the rows the two reads answer, the groups in the byte order
///   the titles answer in with the default row the schema writes named too, and the pairs in the
///   order their first feed appears in the feeds listing;
/// - the Fever feeds document carries the value the read answers for the stamp the pass put on the
///   row;
/// - the Fever items document reads the publication time, not the create time;
/// - the `mark` branch for the read name writes the status the counts read back;
/// - the `mark` branch for the saved name writes the starred flag the read answers back.
///
/// 14 pins and 16 probes, every probe seen to fail on the pin it names. Seven pins are read by one
/// patch and seven by more than one, one patch per rule they name, and four rows reach more than
/// one pin, because a pin reads a value an earlier link of the chain wrote: the login-compare patch
/// fires the pin for the three lines as well, because both read the same answer; the import-write
/// patch fires the listing pin, the pass pin, the contents pin and the Fever feeds pin, because all
/// four read the row that patch wrote; the patch for the site url the pass writes on the row fires
/// the same four, because the value that read answers comes from the parse; and the patch for the
/// first-appearance order fires the groups pin and the feeds pin together, because both documents
/// are built from it.
///
/// What no pin here can show: the ids the runs assign, because the pass runs the jobs of the batch
/// through the pool and the order the writes land in is not fixed — the pins read the ids through
/// SQL and assert the values per row, not the assignment; the clock fields, read here as the
/// placeholder `0`: the document's `updated`, which the handler builds from the instant it runs at,
/// and the item's `crawlTimeMsec` and `updated`, which it builds from the row's created and changed
/// instants; the column the Fever feeds document reads the stamp from, because the run creates the
/// row and stamps it in the same second, so the pin cannot tell the stamp from the create time, and
/// the zero half of that read, which has no row without a stamp here; the wordings of the console
/// lines and of the reported failures; the batch comparison, which `SchedulerBatchTests` pins,
/// because the pins here read the arrivals they count rather than the comparison itself; the two
/// stored values the login pin reads as data — the name as the console read it and the flag the run
/// writes — which its own suites pin; and the rules pinned by their own suites, which the round
/// reads only through this suite, so a patch to one of them fires the pin in that suite as well, a
/// reach reasoned there rather than shown here: the two token derivations, the document shapes, the
/// item-id forms, the stream and query reads, the storage reads and their orders, the sanitizer,
/// the date parse, the bcrypt compare, the single-row limits, and the icon path, which has no row
/// here because the fixture page carries no icon link.
@Suite
struct AcceptanceJourneyTests {
    @Test func theLoginComparesThePasswordWithTheStoredHash() async throws {
        try await withJourney { run in
            // The row the run wrote: the name as the console read it, and the flag the run writes.
            #expect(run.user.username == JourneyFixture.account)
            #expect(run.user.isAdmin == 1)

            // The rule this pin names: the compare reads the value stored on that row, so a compare
            // that reads the value the client sent answers the 401 shape rather than the login
            // shape.
            #expect(run.login.status.code == 200, "the compare ran on the stored hash")
        }
    }

    @Test func theFeverPairTheRunWroteIsThePairTheFeverReadAnswersFor() async throws {
        try await withJourney { run in
            #expect(run.user.feverName == JourneyFixture.feverName)

            // `md5(fever-name:fever-password)`: the reference's own answer for the pair the run
            // read.
            #expect(run.user.feverToken == JourneyFixture.feverGoldenToken)

            // The read finds the row through the stored value, so the answer carries the rows the
            // run wrote, in the order the read builds them: publication time, oldest first.
            let answer = try await feverDocument(run, named: "unread_item_ids")
            let joined = try ids(run, JourneyFixture.itemTitles(ascending: true))
            #expect(answer == feverBase() + ",\"unread_item_ids\":\"" + joined + "\"}")
        }
    }

    @Test func theImportRunWritesTheRowsTheClientListingReads() async throws {
        try await withJourney { run in
            for feed in JourneyFixture.feeds {
                let line = try await digest(run.storage, "feeds",
                    ["url", "site_url", "category_id"], key: "title", value: feed.title)
                let category = try lookup(run.categoryIDs, feed.category)
                let expected = url(run, feed.path) + "|" + url(run, feed.sitePath)
                    + "|" + String(category)
                #expect(line == expected, "the record names the category and the two urls: \(line)")
            }
        }
    }

    @Test func theRefreshRunFetchesTheRowsTheImportWrote() async throws {
        try await withJourney { run in
            for feed in JourneyFixture.feeds {
                #expect(run.server.received(for: feed.path).count == 1,
                    "the batch ran one job for the row the import wrote")
                #expect(run.server.received(for: feed.sitePath).count == 1,
                    "the checker ran for that row, on the site url the record wrote")
            }

            for (feed, item) in JourneyFixture.rows {
                let line = try await digest(run.storage, "entries",
                    ["hash", "content", "url", "status", "published_at"],
                    key: "title", value: item.title)
                let golden = try #require(JourneyFixture.goldens[item.url])
                let expected = golden + "|" + JourneyFixture.content + "|" + item.url
                    + "|unread|" + String(item.publishedAt)
                #expect(line == expected,
                    "the pass wrote one row for the item \(feed.title) declared: \(line)")
            }
        }
    }

    @Test func theLoginAnswerIsTheThreeTextLines() async throws {
        try await withJourney { run in
            #expect(run.google.contentType(of: run.login) == "text/plain; charset=utf-8")

            let lines = try run.google.body(of: run.login)
                .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            #expect(lines.count == 4, "the last line ends with its own newline: \(lines)")
            let value = token(run)
            #expect(lines.prefix(3).map { String($0) }
                == ["SID", "LSID", "Auth"].map { "\($0)=\(value)" })
        }
    }

    @Test func theListingAnswersTheValuesThisHandlerWrites() async throws {
        try await withJourney { run in
            let response = try await run.google.get(
                "/reader/api/0/subscription/list?output=json", header: authHeader(run))
            let answer = try run.google.body(of: response)

            var documents: [String] = []
            for feed in JourneyFixture.feeds {
                let feedID = try lookup(run.feedIDs, feed.title)
                let label = feed.category
                documents.append("{\"id\":\"feed/" + String(feedID) + "\",\"title\":\""
                    + feed.title + "\",\"categories\":[{\"id\":\"user/" + String(run.user.id)
                    + "/label/" + label + "\",\"label\":\"" + label + "\",\"type\":\"folder\"}],"
                    + "\"url\":\"" + url(run, feed.path) + "\",\"htmlUrl\":\""
                    + url(run, feed.sitePath) + "\",\"iconUrl\":\"\"}")
            }
            #expect(answer == "{\"subscriptions\":[" + documents.joined(separator: ",") + "]}",
                "the label is the category title, not the feed title: \(answer)")
        }
    }

    @Test func theStreamReadsExcludeBranchChoosesTheRows() async throws {
        try await withJourney { run in
            let stream = "/reader/api/0/stream/items/ids?output=json&s=user/"
                + String(run.user.id) + "/state/com.google/reading-list"
                + "&xt=user/-/state/com.google/read"
            let answer = try run.google.body(of: try await run.google.get(stream,
                header: authHeader(run)))

            // The name says the status to keep is the other one, so every row is here, in the order
            // the read builds it: publication time, newest first.
            var refs: [String] = []
            for title in JourneyFixture.itemTitles(ascending: false) {
                refs.append("{\"id\":\"" + String(try lookup(run.entryIDs, title)) + "\"}")
            }
            #expect(answer == "{\"itemRefs\":[" + refs.joined(separator: ",") + "]}",
                "the exclude branch chose the rows: \(answer)")
        }
    }

    @Test func theContentsDocumentCarriesTheConfiguredBaseAndTheRows() async throws {
        try await withJourney { run in
            let titles = JourneyFixture.itemTitles(ascending: false)
            var requested: [String] = []
            for title in titles {
                requested.append(String(try lookup(run.entryIDs, title)))
            }
            let raw = run.google.body(token: token(run), pairs: [
                "s=user/" + String(run.user.id) + "/state/com.google/reading-list",
                "xt=user/-/state/com.google/read",
                "i=" + requested.joined(separator: "&i=")])
            let answer = try run.google.body(of: try await run.google.post(
                "/reader/api/0/stream/items/contents", raw: raw, query: "output=json",
                header: authHeader(run)))
            let body = withoutRunInstant(answer)
            let items = try contentsItems(run, titles)
            let expected = "{\"direction\":\"ltr\",\"id\":\"user/-/state/com.google/reading-list\","
                + "\"title\":\"Reading List\",\"self\":[{\"href\":\"" + JourneyFixture.baseURL
                + "/reader/api/0/stream/items/contents\"}],\"updated\":0,\"items\":[" + items
                + "],\"author\":\"" + JourneyFixture.account + "\"}"
            #expect(body == expected, "self is the configured base, not the host it came in on: \(body)")
        }
    }

    @Test func theTagReadWritesTheStatusTheCountsReadBack() async throws {
        try await withJourney { run in
            let item = JourneyFixture.rows[0].item
            let raw = run.google.body(token: token(run), pairs: [
                "i=" + String(try lookup(run.entryIDs, item.title)),
                "a=user/-/state/com.google/read"])
            let answer = try run.google.body(of: try await run.google.post(
                "/reader/api/0/edit-tag", raw: raw, header: authHeader(run)))
            #expect(answer == "OK", "the answer the branch the tag read chose writes: \(answer)")
            #expect(try await digest(run.storage, "entries", ["status"],
                key: "title", value: item.title) == "read",
                "the add loop wrote the status the name says")
        }
    }

    @Test func theFeverGroupsDocumentCarriesTheRowsTheReadsAnswer() async throws {
        try await withJourney { run in
            var groups: [String] = []
            for title in JourneyFixture.categoryTitles.sorted() {
                groups.append("{\"id\":" + String(try lookup(run.categoryIDs, title))
                    + ",\"title\":\"" + title + "\"}")
            }
            let pairs = try feedsGroups(run)
            let answer = try await feverDocument(run, named: "groups")
            #expect(answer == feverBase() + ",\"groups\":[" + groups.joined(separator: ",")
                + "],\"feeds_groups\":[" + pairs + "]}",
                "the groups carry the default row too, in the byte order the titles answer in: \(answer)")
        }
    }

    @Test func theFeverFeedsDocumentReadsTheStampTheRefreshRunWrote() async throws {
        try await withJourney { run in
            var feeds: [String] = []
            for feed in JourneyFixture.feeds {
                let stamp = try await digest(run.storage, "feeds", ["fetched_at"],
                    key: "title", value: feed.title)
                // The pin reads the row through SQL, so it fails when the document writes something
                // other than the value the read answers. The stamp column and the create column
                // cannot be told apart here, because the run creates the row and stamps it in the
                // same second. The icon column holds nothing for these rows, which the document
                // writes as the zero.
                feeds.append("{\"id\":" + String(try lookup(run.feedIDs, feed.title))
                    + ",\"favicon_id\":0,\"title\":\"" + feed.title + "\",\"url\":\""
                    + url(run, feed.path) + "\",\"site_url\":\"" + url(run, feed.sitePath)
                    + "\",\"is_spark\":0,\"last_updated_on_time\":" + stamp + "}")
            }
            let pairs = try feedsGroups(run)
            let answer = try await feverDocument(run, named: "feeds")
            #expect(answer == feverBase() + ",\"feeds\":[" + feeds.joined(separator: ",")
                + "],\"feeds_groups\":[" + pairs + "]}",
                "the field reads the stamp the pass put on the row: \(answer)")
        }
    }

    @Test func theFeverItemsDocumentReadsThePublicationTime() async throws {
        try await withJourney { run in
            var items: [String] = []
            for title in JourneyFixture.itemTitles(ascending: true) {
                let row = try #require(JourneyFixture.rows.first { $0.item.title == title })
                items.append("{\"id\":" + String(try lookup(run.entryIDs, title)) + ",\"feed_id\":"
                    + String(try lookup(run.feedIDs, row.feed.title)) + ",\"title\":\"" + title
                    + "\",\"author\":\"\",\"html\":\"" + JourneyFixture.content + "\",\"url\":\""
                    + row.item.url + "\",\"is_saved\":0,\"is_read\":0,\"created_on_time\":"
                    + String(row.item.publishedAt) + "}")
            }
            let answer = try await feverDocument(run, named: "items")
            #expect(answer == feverBase() + ",\"items\":[" + items.joined(separator: ",")
                + "],\"total_items\":" + String(items.count) + "}",
                "the field reads the publication time, not the create time: \(answer)")
        }
    }

    @Test func theFeverMarkItemReadBranchWritesTheStatus() async throws {
        try await withJourney { run in
            let item = JourneyFixture.rows[0].item
            let response = try await run.fever.postParts("mark=item&api_key=" + run.user.feverToken,
                [("id", String(try lookup(run.entryIDs, item.title))), ("as", "read")])
            #expect(run.fever.document(of: response) == feverBase() + "}",
                "the write answer writes only the three base fields")
            let status = try await digest(run.storage, "entries", ["status"],
                key: "title", value: item.title)
            #expect(status == "read", "the branch the name chose wrote the status the name says: \(status)")
            let starred = try await digest(run.storage, "entries", ["starred"],
                key: "title", value: item.title)
            #expect(starred == "0", "and the other branch wrote nothing: \(starred)")
        }
    }

    @Test func theFeverMarkItemSavedBranchWritesTheStarredFlag() async throws {
        try await withJourney { run in
            let item = JourneyFixture.rows[0].item
            let response = try await run.fever.postParts("mark=item&api_key=" + run.user.feverToken,
                [("id", String(try lookup(run.entryIDs, item.title))), ("as", "saved")])
            #expect(run.fever.document(of: response) == feverBase() + "}",
                "the write answer writes only the three base fields")
            let starred = try await digest(run.storage, "entries", ["starred"],
                key: "title", value: item.title)
            #expect(starred == "1", "the branch the name chose wrote the flag the name says: \(starred)")
            let status = try await digest(run.storage, "entries", ["status"],
                key: "title", value: item.title)
            #expect(status == "unread", "and the other branch wrote nothing: \(status)")
        }
    }

    // MARK: - What the pins read the answer through

    /// The token the requests carry, read from the values the run stored. The derivation itself is
    /// pinned by `GoogleReaderTokenTests`, so a patch to it changes the token sent and the value
    /// the handler compares in the same way and cannot show here alone.
    private func token(_ run: JourneyRun) -> String {
        GoogleReaderToken.derive(username: run.user.googleName, storedHash: run.user.storedHash)
    }

    private func authHeader(_ run: JourneyRun) -> String {
        "GoogleLogin auth=" + token(run)
    }

    private func url(_ run: JourneyRun, _ path: String) -> String {
        run.server.url(path).absoluteString
    }

    /// The three base fields, with the clock field read as the placeholder the request helper
    /// names.
    private func feverBase() -> String {
        "{\"api_version\":3,\"auth\":1,\"last_refreshed_on_time\":0"
    }

    private func feverDocument(_ run: JourneyRun, named name: String) async throws -> String {
        run.fever.document(of: try await run.fever.get(name + "=1&api_key=" + run.user.feverToken))
    }

    /// The groups in the order their first feed appears in the feeds listing, which is the title
    /// order.
    private func feedsGroups(_ run: JourneyRun) throws -> String {
        var pairs: [String] = []
        for feed in JourneyFixture.feeds {
            pairs.append("{\"group_id\":" + String(try lookup(run.categoryIDs, feed.category))
                + ",\"feed_ids\":\"" + String(try lookup(run.feedIDs, feed.title)) + "\"}")
        }
        return pairs.joined(separator: ",")
    }

    private func ids(_ run: JourneyRun, _ titles: [String]) throws -> String {
        var values: [String] = []
        for title in titles {
            values.append(String(try lookup(run.entryIDs, title)))
        }
        return values.joined(separator: ",")
    }

    /// One row id written as the reference writes the item id: `fmt.Sprintf("%016x", id)`.
    private func itemHex(_ id: Int) -> String {
        String(format: "%016x", id)
    }

    private func contentsItems(_ run: JourneyRun, _ titles: [String]) throws -> String {
        let userID = String(run.user.id)
        var items: [String] = []
        for title in titles {
            let row = try #require(JourneyFixture.rows.first { $0.item.title == title })
            let itemID = try lookup(run.entryIDs, title)
            let feedID = try lookup(run.feedIDs, row.feed.title)
            let stamp = String(row.item.publishedAt)
            let categories = "\"categories\":[\"user/" + userID + "/state/com.google/reading-list"
                + "\",\"user/" + userID + "/label/" + row.feed.category + "\"]"
            let times = "\"title\":\"" + title + "\",\"crawlTimeMsec\":\"0\",\"timestampUsec\":\""
                + stamp + "000000\",\"published\":" + stamp + ",\"updated\":0,\"author\":\"\""
            let alternate = "\"alternate\":[{\"href\":\"" + row.item.url + "\",\"type\":\"text/html\"}]"
            let text = "\"summary\":{\"direction\":\"ltr\",\"content\":\"" + JourneyFixture.content
                + "\"},\"content\":{\"direction\":\"ltr\",\"content\":\"" + JourneyFixture.content + "\"}"
            let origin = "\"origin\":{\"streamId\":\"feed/" + String(feedID) + "\",\"title\":\""
                + row.feed.title + "\",\"htmlUrl\":\"" + url(run, row.feed.sitePath) + "\"}"
            let pieces = ["\"id\":\"tag:google.com,2005:reader/item/" + itemHex(itemID) + "\"",
                categories, times, alternate, text, origin, "\"enclosure\":[]",
                "\"canonical\":[{\"href\":\"" + row.item.url + "\"}]"]
            items.append("{" + pieces.joined(separator: ",") + "}")
        }
        return items.joined(separator: ",")
    }

    /// The two fields the handler builds from the instant it runs at, read as the placeholder, so
    /// the document can be compared as one string. The number is replaced where it sits, so the
    /// quotes the shape writes around `crawlTimeMsec` stay where the shape writes them.
    private func withoutRunInstant(_ body: String) -> String {
        var text = body
        for key in ["\"updated\":", "\"crawlTimeMsec\":\""] {
            var search = text.startIndex
            while let found = text.range(of: key, range: search..<text.endIndex) {
                var end = found.upperBound
                while end < text.endIndex, text[end].isNumber { end = text.index(after: end) }
                text.replaceSubrange(found.upperBound..<end, with: "0")
                search = end
            }
        }
        return text
    }

    /// One row read through SQL as one digest line, so a pin is not satisfied by the read it tests.
    private func digest(_ storage: SQLiteStorage, _ table: String, _ columns: [String],
        key: String, value: String) async throws -> String {
        try await storage.withConnection { connection in
            let sql = try sqlDatabase(connection)
            let joined = columns.joined(separator: " || '|' || ")
            let selected: SQLQueryString = "SELECT \(unsafeRaw: joined) AS digest"
            let filter: SQLQueryString = " FROM \(ident: table) WHERE \(ident: key) = \(bind: value)"
            let row = try await sql.raw(selected + filter).first()
            guard let row else { throw MissingRow(table: table) }
            return try row.decode(column: "digest", as: String.self)
        }
    }

    /// A row id the pins read through SQL: the pins assert the values per row, not the id
    /// assignment, which the pass does not fix.
    private func lookup(_ values: [String: Int], _ key: String) throws -> Int {
        try #require(values[key])
    }
}