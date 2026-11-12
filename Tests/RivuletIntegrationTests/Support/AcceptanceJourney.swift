import Foundation
import SQLKit
import Vapor
import RivuletApp
@testable import RivuletCore

/// The chain one journey pin runs, in the order `docs/plan/stage-5-apis.md` names it: the two
/// console runs that build the account and its credential pairs, the OPML run that writes the rows,
/// the pass over the batch that writes the entries, and the socket the client requests go to.
///
/// The helper asserts nothing, so a pin is where a failure is recorded. A patch that changes what
/// an earlier link writes changes what the later links read, which is what the suite header names.
///
/// The tokens the requests carry are read from the stored values, so a patch to the rule that
/// builds a token changes the token the pins send and the answer they compare in the same way, and
/// only the pin that names that rule can fail on it. The pins that read a stored value read it
/// through SQL, so a patch to the write and a patch to the read answer differently, which is what
/// makes each pin fail on the rule it names.
///
/// The rule that decides whether a row is fetched is pinned by `SchedulerBatchTests`, and it
/// compares strictly, so the helper puts the rows the import wrote in the batch the way that read
/// compares them. The pins that read the fetch link read the arrivals and the rows, not the
/// comparison.
struct JourneyRun: Sendable {
    let storage: SQLiteStorage
    let app: Application
    let base: String
    let server: StubFeedServer
    let google: GoogleReaderRequests
    let fever: FeverRequests

    /// What each console run left behind, keyed by the command name.
    let runs: [String: RunOutcome]

    /// The login answer, which the pins that name the login read, and the stored values the other
    /// pins read the requests through.
    let login: ClientResponse
    let user: JourneyUser

    /// The rows the runs wrote, keyed by the value the pins name them by: the feed by the title the
    /// record carries, the entry by the title the document declares, the category by the name the
    /// record names. The pins read only the ids from these, because the ids themselves are the
    /// order the batch ran its jobs in, which the read does not fix.
    let feedIDs: [String: Int]
    let entryIDs: [String: Int]
    let categoryIDs: [String: Int]
}

/// The account values the console reads, and the fixture the runs and the requests go through.
///
/// The names are the forms the pins expect them stored: the account name as the storage layer
/// writes it, the two credential names as the command writes them. The goldens are the reference's
/// own answers for the values the fixture declares — the Fever token for the pair the run reads,
/// and the checksum for the value each item declares — taken from the reference's rules, not from
/// this port's, so the pins that name those rules can fail on them.
enum JourneyFixture {
    static let account = "journey"
    static let accountPassword = "journey-password"
    static let feverName = "fever-name"
    static let feverPassword = "fever-password"
    static let googleName = "google-name"
    static let googlePassword = "google-password"

    /// `md5(fever-name:fever-password)`.
    static let feverGoldenToken = "6e8e434687eeeb028244dc457a194e00"

    /// `SHA256` of the value each item declares, which is what the reference's RSS adapter hashes
    /// when the document carries one.
    static let goldens = [
        "https://entry.example/one": "b3d8e2c2df177339fd24cd649b084e26f36610b6f2e21bdcf8592b0aed4fd6e2",
        "https://entry.example/two": "5935b6c4c3a1bd0e2926c694816936b07baa4fc3cdaba29b6f70aadb18fef5f6",
        "https://entry.example/three": "424cea9b8fd388e4f1c4512437a36431e987cf15b9772923f7177c2c7e6f995d",
    ]

    /// The base the handler writes for its `self` link, named here so the pin reads it as the
    /// configured value rather than as the host the request came in on.
    static let baseURL = "http://journey.example"

    /// One feed row as the record names it, with the items the document declares in the order it
    /// declares them.
    struct Feed {
        let category: String
        let title: String
        let path: String
        let sitePath: String
        let items: [Item]
    }

    struct Item {
        let title: String
        let url: String
        let publishedAt: Int
    }

    /// The content every item declares, which the sanitizer writes as it is given because it
    /// carries no tag and no entity.
    static let content = "Entry text"

    static let feeds = [
        Feed(category: "Tech", title: "Feed one", path: "/p/one", sitePath: "/s/one", items: [
            Item(title: "Entry one", url: "https://entry.example/one", publishedAt: 1_767_550_803),
            Item(title: "Entry two", url: "https://entry.example/two", publishedAt: 1_767_464_400),
        ]),
        Feed(category: "Travel", title: "Feed two", path: "/p/two", sitePath: "/s/two", items: [
            Item(title: "Entry three", url: "https://entry.example/three", publishedAt: 1_767_378_000),
        ]),
    ]

    /// One pair as the record put it together: the record that named the feed and the item the
    /// document declared, which is what the pins name the row by.
    static var rows: [(feed: Feed, item: Item)] {
        feeds.flatMap { feed in feed.items.map { (feed, $0) } }
    }

    /// The category rows the read answers: the default row the schema writes for the account, which
    /// no record names, and the two the records name.
    static let defaultCategory = "All"

    static var categoryTitles: [String] { [defaultCategory] + feeds.map { $0.category } }

    /// The item titles in the order a read builds them: the publication time in the direction the
    /// pin names, which is what the pins assert the answers in.
    static func itemTitles(ascending: Bool) -> [String] {
        rows.map(\.item).sorted { ascending ? $0.publishedAt < $1.publishedAt
            : $0.publishedAt > $1.publishedAt }.map(\.title)
    }

    /// RFC 822 as the reference's date parser reads it, with the weekday the instant answers for.
    static func pubDate(_ seconds: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
    }

    static func rss(_ feed: Feed) -> String {
        "<rss version=\"2.0\"><channel><title>\(feed.title)</title>"
            + "<link>https://site.example/\(feed.sitePath.dropFirst())</link>"
            + feed.items.map {
                "<item><title>\($0.title)</title><link>\($0.url)</link><guid>\($0.url)</guid>"
                + "<pubDate>\(pubDate($0.publishedAt))</pubDate>"
                + "<description>\(content)</description></item>"
            }.joined()
            + "</channel></rss>"
    }

    /// The page the checker reads: no icon link, so no icon row is written for the feed.
    static func page(_ feed: Feed) -> String {
        "<html><head></head><body>https://site.example/\(feed.sitePath.dropFirst())</body></html>"
    }

    static func behaviors() -> [String: StubFeedServer.Behavior] {
        var table: [String: StubFeedServer.Behavior] = [:]
        for feed in feeds {
            table[feed.path] = StubFeedServer.Behavior(body: Data(rss(feed).utf8))
            table[feed.sitePath] = StubFeedServer.Behavior(
                headers: ["Content-Type": "text/html"], body: Data(page(feed).utf8))
        }
        return table
    }

    /// The document the import run reads: one outline per record, with the category the record
    /// names as its parent, and the two url attributes the handler maps to the row's url and site
    /// url.
    static func opml(on server: StubFeedServer) -> String {
        let outlines = feeds.map { feed in
            "<outline text=\"\(feed.category)\" title=\"\(feed.category)\">"
                + "<outline type=\"rss\" text=\"\(feed.title)\" title=\"\(feed.title)\" "
                + "xmlUrl=\"\(server.url(feed.path).absoluteString)\" "
                + "htmlUrl=\"\(server.url(feed.sitePath).absoluteString)\"/>"
                + "</outline>"
        }.joined()
        return "<opml version=\"2.0\"><head><title>journey</title></head><body>"
            + outlines + "</body></opml>"
    }
}

/// Runs the chain once for one pin, on a database and a server started for that pin only.
func withJourney(_ body: (JourneyRun) async throws -> Void) async throws {
    let directory = try TemporaryDirectory()
    let path = directory.path("journey.db")

    do {
        try await FetchTestSupport.withServer(behaviors: JourneyFixture.behaviors()) { server in
            let runs = try await consoleRuns(databasePath: path, directory: directory, server: server)
            try await journeyRun(databasePath: path, server: server, runs: runs, body: body)
        }
    } catch {
        directory.remove()
        throw error
    }
    directory.remove()
}

/// The three console runs of the chain: the account, the two credential pairs, and the OPML run.
private func consoleRuns(databasePath path: String, directory: TemporaryDirectory,
    server: StubFeedServer) async throws -> [String: RunOutcome] {
    var runs: [String: RunOutcome] = [:]
    runs["create-admin"] = try await runCommand(databasePath: path, arguments: ["create-admin"],
        inputs: [JourneyFixture.account, JourneyFixture.accountPassword])
    runs["integration-credentials"] = try await runCommand(databasePath: path,
        arguments: ["integration-credentials"],
        inputs: [JourneyFixture.account, JourneyFixture.feverName, JourneyFixture.feverPassword,
            JourneyFixture.googleName, JourneyFixture.googlePassword])

    let file = directory.path("feeds.opml")
    try JourneyFixture.opml(on: server).write(to: URL(fileURLWithPath: file),
        atomically: true, encoding: .utf8)
    runs["import"] = try await runCommand(databasePath: path, arguments: ["import", file])
    return runs
}

/// The half the pins read through the socket: the stamp, the pass over the batch, the login, and
/// the rows the runs wrote.
private func journeyRun(databasePath path: String, server: StubFeedServer,
    runs: [String: RunOutcome], body: (JourneyRun) async throws -> Void) async throws {
    try await withServedApp(environment: ["FETCHER_ALLOW_PRIVATE_NETWORKS": "1",
        "BASE_URL": JourneyFixture.baseURL], databasePath: path) { storage, app, base in
        try await stampBatch(storage)

        var arrivals = runs
        arrivals["refresh"] = try await runCommand(databasePath: path, arguments: ["refresh"],
            environment: ["FETCHER_ALLOW_PRIVATE_NETWORKS": "1"])

        let user = try await journeyUser(storage)
        let login = try await GoogleReaderRequests(app, base).login(
            fields: ["Email": user.googleName, "Passwd": JourneyFixture.googlePassword])

        let run = JourneyRun(storage: storage, app: app, base: base, server: server,
            google: GoogleReaderRequests(app, base), fever: FeverRequests(app, base),
            runs: arrivals, login: login, user: user,
            feedIDs: try await ids(storage, "feeds", "title"),
            entryIDs: try await ids(storage, "entries", "title"),
            categoryIDs: try await ids(storage, "categories", "title"))
        try await body(run)
    }
}

/// The batch rule compares strictly, so the rows the import wrote are put in the batch the way that
/// read compares them; the pins read the arrivals, not this.
private func stampBatch(_ storage: SQLiteStorage) async throws {
    try await storage.withConnection { connection in
        try await sqlDatabase(connection)
            .raw("UPDATE feeds SET next_check_at = \(bind: 1_000_000_000)").run()
    }
}

/// The row the first run wrote and the second run wrote the pairs onto, read as the pins read it.
struct JourneyUser: Sendable {
    let id: Int
    let username: String
    let isAdmin: Int
    let storedHash: String
    let googleName: String
    let feverName: String
    let feverToken: String
}

private func journeyUser(_ storage: SQLiteStorage) async throws -> JourneyUser {
    try await storage.withConnection { connection in
        let row = try await sqlDatabase(connection).raw("""
            SELECT id, username, is_admin, google_reader_password_hash, google_reader_username,
                fever_username, fever_token FROM users LIMIT 1
            """).first()
        guard let row else { throw MissingRow(table: "users") }
        return JourneyUser(id: try row.decode(column: "id", as: Int.self),
            username: try row.decode(column: "username", as: String.self),
            isAdmin: try row.decode(column: "is_admin", as: Int.self),
            storedHash: try row.decode(column: "google_reader_password_hash", as: String.self),
            googleName: try row.decode(column: "google_reader_username", as: String.self),
            feverName: try row.decode(column: "fever_username", as: String.self),
            feverToken: try row.decode(column: "fever_token", as: String.self))
    }
}

/// The ids the runs left behind, keyed by the value the pins name the rows by.
private func ids(_ storage: SQLiteStorage, _ table: String, _ column: String) async throws
    -> [String: Int] {
    try await storage.withConnection { connection in
        let rows = try await sqlDatabase(connection)
            .raw("SELECT id, \(SQLRaw(column)) FROM \(SQLRaw(table))").all()
        var values: [String: Int] = [:]
        for row in rows {
            values[try row.decode(column: column, as: String.self)] =
                try row.decode(column: "id", as: Int.self)
        }
        return values
    }
}
