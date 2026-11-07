import SQLKit
import Testing
@testable import RivuletCore

/// The reduced large-feed scenario the plan names: the read path over a 10k-entry corpus, with the
/// budgets the suite documents. Four of the five pins read something countable — the plan the
/// schema answers, the page the query is given, the relevance order the FTS index answers, and the
/// batch the retention pass takes — so those pins cannot fail because one machine was slower than
/// another. The fifth pin reads a wall-clock bound, which is the machine's number and not a rule.
///
/// `HeavyTests` is the opt-in 100k corpus gated on `RIVULET_HEAVY`; this suite is the reduced
/// version that runs in the default CI job, so it is not gated and stays well inside the job's
/// time. On this machine the corpus read path measures 1 to 4 ms and the suite about 1.2 s; the
/// bound the timed pin reads is 250 ms, so the pin is not the measured time but the distance a
/// wrong implementation has to cross. The memory budget `docs/testing.md` documents is not read by
/// any pin, because nothing here can name the memory a process holds.
///
/// What these pins can fail on, each checked by patching the rule and reverting byte-identically,
/// with each probe named by what it flips — six probes for five pins: the owner read through an
/// expression the planner cannot use, which answered the plan pin with a scan and a temporary
/// b-tree for the order; the page size dropped from the clause, which answered the page pin with
/// the whole corpus; the order read in the direction the query did not ask for, which answered the
/// same pin's head of the page with a row from the front of the corpus; relevance read after the
/// requested order, which answered the relevance pin with the newest row first; the batch dropped
/// from the archive statement, which answered the retention pin with every qualifying row; and the
/// ranked read answered row by row, which took the read path past the bound.
///
/// What these pins cannot fail on: the memory budget named above; the numbers of another machine,
/// which the timed pin reads as the bound rather than as the time it measured; that the index the
/// plan names is what serves the ordering as well as the filter, which the planner decides from the
/// statistics of the rows it has and which the pin reads only as the name in the plan; the plan pin
/// reads the text the builder produces through the internal builder, which is the only way a pin
/// can name a plan without writing its own `SELECT` — a patch that changes the text changes the
/// plan the pin reads; the FTS ranking itself, which `EntrySearchTests` pin term by term, and which
/// this suite reads only as the order at the corpus size; the single-row limit of the reads; the
/// retention rules `RetentionTests` pin — the age guards, the starred rows kept, the tombstones and
/// the transaction boundary — which this suite reads only as the batch at the documented size; the
/// wording of the reported failures; and the rules the port names rather than the reference, whose
/// storage layer is Postgres and has no index of this shape.

@Suite struct LargeFeedTests {
    private let feeds = 100
    private let entries = 10_000

    /// The order a client listing reads, newest first, which is the order the hot path is used in.
    private let newestFirst = EntrySort(field: .publishedAt, direction: .descending)

    @Test func theHotUnreadListingReadsThroughTheIndexTheSchemaNames() async throws {
        try await withMigratedStorage { _, storage in
            let corpus = try await Seeding.seed(on: storage, feeds: feeds, entries: entries)
            try await storage.withConnection { connection in
                let query = EntryQuery(userID: corpus.userID, statuses: [.unread], sort: newestFirst, limit: 50)
                let sql = EntryRepository.selectSQL(query, columns: "e.id", paginate: true)
                let rows = try await RawSQL.sql(on: connection)
                    .raw(("EXPLAIN QUERY PLAN " as SQLQueryString) + sql)
                    .all()
                let plan = rows.compactMap { row in
                    (try? row.decode(column: "detail", as: String.self)) ?? ""
                }
                let read = plan.joined(separator: " | ")
                #expect(read.contains("entries_user_status_published_idx"), "the plan the read answers: \(read)")
            }
        }
    }

    @Test func theReadAnswersThePageItIsGivenFromTheCorpus() async throws {
        try await withMigratedStorage { _, storage in
            let corpus = try await Seeding.seed(on: storage, feeds: feeds, entries: entries)
            try await storage.withConnection { connection in
                let repository = EntryRepository(connection)
                let query = EntryQuery(userID: corpus.userID, statuses: [.unread], sort: newestFirst, limit: 50)
                let page = try await repository.listIDs(query)
                #expect(page.count == 50)
                // The page is the head of the order it was given, not any 50 rows of the corpus.
                #expect(page.first == entries)
            }
        }
    }

    @Test func theRankedReadAnswersTheTopRowsInRelevanceOrderAtTheCorpusSize() async throws {
        try await withMigratedStorage { _, storage in
            let corpus = try await Seeding.seed(on: storage, feeds: feeds, entries: entries)
            try await storage.withConnection { connection in
                // Three rows the term can rank: the strongest match is not the newest, so the
                // requested order alone would answer a different row first.
                let strongest = try await seedEntry(connection, userID: corpus.userID, feedID: 1, hash: "strong",
                    title: "sparrow sparrow sparrow sparrow", content: "<p>plain</p>", publishedAt: 1_600_000_000)
                let middle = try await seedEntry(connection, userID: corpus.userID, feedID: 1, hash: "middle",
                    title: "sparrow", content: "<p>plain</p>", publishedAt: 1_600_000_001)
                let weakest = try await seedEntry(connection, userID: corpus.userID, feedID: 1, hash: "weak",
                    title: "title", content: "<p>sparrow</p>", publishedAt: 1_600_000_002)

                let query = EntryQuery(userID: corpus.userID, statuses: [.unread], search: "sparrow",
                    sort: newestFirst, limit: 3)
                #expect(try await EntryRepository(connection).listIDs(query) == [strongest, middle, weakest])
            }
        }
    }

    @Test func theRetentionPassTakesTheDocumentedBatchAndLeavesTheRestForTheNextRun() async throws {
        try await withMigratedStorage { _, storage in
            let corpus = try await Seeding.seed(on: storage, feeds: feeds, entries: entries)
            try await storage.withConnection { connection in
                // More rows past the documented age than the documented batch can take in one run.
                for index in 1...500 {
                    let old = Seeding.seedEpoch - 200 * 86_400
                    let id = try await seedEntry(connection, userID: corpus.userID, feedID: 1,
                        hash: "extra-\(index)", title: "Extra", publishedAt: old)
                    try await backdateCreatedAt(connection, id: id, createdAt: old)
                }
            }

            let archived = try await Retention().run(on: storage, now: Seeding.seedEpoch + 180 * 86_400)
            #expect(archived.unread == RetentionPolicy.default.batchSize)
            try await storage.withConnection { connection in
                let remaining = try await EntryRepository(connection)
                    .count(EntryQuery(userID: corpus.userID, statuses: [.unread]))
                #expect(remaining == 500, "the rows the batch left for the next run")
            }
        }
    }

    @Test func theReadPathStaysInsideTheDocumentedBoundForTheCorpus() async throws {
        try await withMigratedStorage { _, storage in
            let corpus = try await Seeding.seed(on: storage, feeds: feeds, entries: entries)
            try await storage.withConnection { connection in
                let repository = EntryRepository(connection)
                let started = ContinuousClock.now
                _ = try await repository.listIDs(EntryQuery(userID: corpus.userID, statuses: [.unread],
                    sort: newestFirst, limit: 50))
                _ = try await repository.listIDs(EntryQuery(userID: corpus.userID, statuses: [.unread],
                    search: "sparrow", sort: newestFirst, limit: 20))
                let elapsed = ContinuousClock.now - started
                #expect(elapsed < .milliseconds(250), "the read path took \(elapsed)")
            }
        }
    }
}
