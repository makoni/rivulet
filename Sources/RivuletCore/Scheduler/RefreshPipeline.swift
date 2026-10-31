// Ported from Miniflux internal/reader/handler/handler.go `RefreshFeed` (Apache-2.0); adapted for
// Swift/SQLite.

import FluentKit
import Foundation

/// The refresh path for one feed: the caller the fetcher, the parser, the sanitizer and the storage
/// layer have been waiting for.  The order is the reference's (`RefreshFeed`,
/// `internal/reader/handler/handler.go` at commit `c4d54f87`): read the row through the user-scoped
/// lookup, stamp the check time and the schedule, build the request, fetch, recompute the schedule
/// for a rate-limited answer, then either record the failure or read the body, parse, sanitize and
/// store each entry, and write the fetch state. Three things are different here, recorded in
/// `docs/parity.md`: every write of one refresh commits in one transaction, the failure record is
/// committed before its error leaves, and the clock is the injected seam rather than a `time.Now()`
/// read inside the functions. The user rules the reference applies in its processor — filters,
/// rewrite, scraping — are later stages, and the duplicate check, the icon checker and the reading
/// time land with them.  - See: ``Clock`` for the injected instant, ``NextCheckPolicy`` for the
/// scheduling rule.
public struct RefreshPipeline: Sendable {
    private let storage: SQLiteStorage
    private let fetcher: Fetcher
    private let options: FetcherOptions
    private let nextCheck: NextCheckPolicy
    private let clock: any Clock
    private let sanitizerOptions: SanitizerOptions

    /// Creates the pipeline around the seams it runs through.
    public init(storage: SQLiteStorage, fetcher: Fetcher, options: FetcherOptions,
        nextCheck: NextCheckPolicy, clock: any Clock) {
        self.storage = storage
        self.fetcher = fetcher
        self.options = options
        self.nextCheck = nextCheck
        self.clock = clock
        self.sanitizerOptions = SanitizerOptions()
    }

    /// Refreshes one feed of one user.  - Parameters: - userID: The user the feed belongs to; a
    /// feed of another user is the typed error. - feedID: The feed to refresh. - forceRefresh: The
    /// forced path `rivulet refresh` takes: no stored validators are sent, and an existing entry is
    /// updated. - Returns: What the refresh produced, as ``RefreshOutcome``. - Throws: The typed
    /// failure the reference reports on this path: the feed not found, the fetch error, or the
    /// parse error. The failure record is committed before the error is thrown, so the caller sees
    /// the row the reference would have written.
    public func refresh(userID: Int, feedID: Int, forceRefresh: Bool = false)
        async throws -> RefreshOutcome {
        let result = try await storage.withTransaction { connection in
            try await refreshInsideTransaction(connection, userID: userID, feedID: feedID,
                forceRefresh: forceRefresh)
        }
        switch result {
        case .completed(let outcome):
            return outcome
        case .recorded(let error):
            throw error
        }
    }

    /// What the transaction answers with: the outcome, or the failure it recorded inside the
    /// transaction so the commit still carries it.
    private enum TransactionResult: Sendable {
        case completed(RefreshOutcome)
        case recorded(any Error & Sendable)
    }

    private func refreshInsideTransaction(_ connection: any Database, userID: Int, feedID: Int,
        forceRefresh: Bool) async throws -> TransactionResult {
        let feeds = FeedRepository(connection)
        guard let feed = try await feeds.fetch(userID: userID, id: feedID) else {
            return .recorded(StorageError.feedNotFound(id: feedID))
        }
        let checkedAt = clock.now()
        // `CheckedNow`: the check time, and the feed URL in place of an empty site URL.
        let siteURL = feed.siteURL.isEmpty ? feed.url : feed.siteURL
        // The reference reads the weekly count before the schedule, and only for the mode that
        // divides by it, so the other mode passes 0 and the number reads nothing.
        let weeklyCount = nextCheck.mode == .entryFrequency
            ? try await feeds.weeklyEntryCount(userID: userID, feedID: feedID, now: checkedAt)
            : 0
        var nextCheckAt = nextCheck.nextCheckAt(now: checkedAt, weeklyCount: weeklyCount,
            refreshDelay: .zero)

        guard let url = URL(string: feed.url) else {
            let error = FetchError.invalidURL(feed.url)
            try await recordFailure(feeds, feedID, error, nextCheckAt, checkedAt)
            return .recorded(error)
        }
        let state = FeedFetchState(feedID: feedID, url: url, etag: feed.etag,
            lastModified: feed.lastModified, userAgent: feed.userAgent,
            ignoreHTTPCache: feed.ignoreHTTPCache, fetchViaProxy: feed.fetchViaProxy)

        // A transport failure is recorded like the status failures below: the reference records
        // every fetch error through the same statement.
        let response: FetchResponse
        do {
            let request = try FetchRequestBuilder(options: options).build(feed: state,
                forceRefresh: forceRefresh)
            response = try await fetcher.fetch(request)
        } catch let error as FetchError {
            try await recordFailure(feeds, feedID, error, nextCheckAt, checkedAt)
            return .recorded(error)
        }

        // The reference recomputes the schedule for a rate-limited answer before it reports the
        // failure, so the `Retry-After` delay can move the schedule on the failure path.
        if response.isRateLimited {
            nextCheckAt = nextCheck.nextCheckAt(now: checkedAt, weeklyCount: weeklyCount,
                refreshDelay: response.retryAfter(now: checkedAt))
        }
        if let error = response.error() {
            try await recordFailure(feeds, feedID, error, nextCheckAt, checkedAt)
            return .recorded(error)
        }
        if forceRefresh || response.isModified(against: state) {
            return try await processModified(connection, feeds, state, response, userID, feedID,
                weeklyCount, siteURL, feed.url, nextCheckAt, checkedAt)
        }
        return try await processHit(feeds, feed, response, feedID, siteURL, nextCheckAt, checkedAt)
    }

    /// The parse-and-store branch, in the reference's order: parse, take the delay the answer
    /// carries, process the entries, then store the validators the response produced. The delay is
    /// compared as a `Duration`, as the reference does, so a value that is not a whole number of
    /// minutes keeps its seconds; the comparison itself is pinned in ``NextCheckPolicy``.
    /// `feedURL` is the value the row holds, which is what the reference's processor parses, and
    /// `weeklyCount` is the number read before the fetch, which is what the schedule is built from.
    private func processModified(_ connection: any Database, _ feeds: FeedRepository,
        _ state: FeedFetchState, _ response: FetchResponse, _ userID: Int, _ feedID: Int,
        _ weeklyCount: Int, _ siteURL: String, _ feedURL: String, _ nextCheckAt: Int,
        _ checkedAt: Int) async throws -> TransactionResult {
        let parsed: ParsedFeed
        do {
            parsed = try FeedParser.parse(baseURL: response.effectiveURL.absoluteString,
                data: response.body, now: parsedDate(checkedAt))
        } catch let error as ParserError {
            try await recordFailure(feeds, feedID, error, nextCheckAt, checkedAt)
            return .recorded(error)
        }

        let delay = max(max(Duration.seconds(parsed.ttlMinutes * 60), response.cacheControlMaxAge),
            response.expires(now: checkedAt))
        let nextCheckAt = nextCheck.nextCheckAt(now: checkedAt, weeklyCount: weeklyCount,
            refreshDelay: delay)
        let hashes = try await processEntries(parsed, connection, userID, feedID, siteURL, feedURL)

        try await feeds.recordFetch(feedID: feedID, etag: response.etag,
            lastModified: response.lastModified, nextCheckAt: nextCheckAt, checkedAt: checkedAt,
            siteURL: siteURL)
        return .completed(RefreshOutcome(conditionalHit: response.isConditionalHit,
            newEntryHashes: hashes.new, updatedEntryHashes: hashes.updated,
            nextCheckAt: nextCheckAt))
    }

    /// The branch for an answer that was not modified: RFC9111 as the reference reads it — only
    /// `Last-Modified` can move, the stored validators otherwise stay, and the error state is
    /// reset.
    private func processHit(_ feeds: FeedRepository, _ feed: Feed, _ response: FetchResponse,
        _ feedID: Int, _ siteURL: String, _ nextCheckAt: Int, _ checkedAt: Int) async throws
        -> TransactionResult {
        try await feeds.recordFetch(feedID: feedID, etag: feed.etag,
            lastModified: response.lastModified.isEmpty ? feed.lastModified : response.lastModified,
            nextCheckAt: nextCheckAt, checkedAt: checkedAt, siteURL: siteURL)
        return .completed(RefreshOutcome(conditionalHit: response.isConditionalHit,
            newEntryHashes: [], updatedEntryHashes: [], nextCheckAt: nextCheckAt))
    }

    /// The entry loop, in the reference's order. The entries are processed oldest first, so the row
    /// created first is the one the document declares last. The parsed URLs are read once, before
    /// the loop, as the reference's processor does, and the feed half is the URL the stored row
    /// holds, which is what the reference's processor parses, not the URL the parse produced. A URL
    /// the cleaner cannot read stays as the feed wrote it. The hash is the adapter's, taken before
    /// the cleaner ran. The user rules are later stages.
    private func processEntries(_ parsed: ParsedFeed, _ connection: any Database, _ userID: Int,
        _ feedID: Int, _ siteURL: String, _ feedURL: String) async throws
        -> (new: [String], updated: [String]) {
        let entries = EntryRepository(connection)
        let siteParsed = try? ParsedURL.parse(siteURL)
        let feedParsed = try? ParsedURL.parse(feedURL)
        var new: [String] = []
        var updated: [String] = []

        for entry in parsed.entries.reversed() {
            var url = entry.url
            if let input = try? ParsedURL.parse(entry.url),
                let cleaned = try? TrackingParameters.remove(base: siteParsed,
                    feed: feedParsed, input: input) {
                url = cleaned
            }
            let content = Sanitizer.sanitize(baseURL: url, rawHTML: entry.content,
                options: sanitizerOptions)
            let input = EntryInput(hash: entry.hash, title: entry.title, url: url,
                author: entry.author, content: content,
                publishedAt: Int(entry.date.epochSeconds),
                enclosures: entry.enclosures.map {
                    EntryInput.Enclosure(url: $0.url, mimeType: $0.mimeType, size: $0.size)
                })
            switch try await entries.upsert(userID: userID, feedID: feedID, input: input,
                updateExisting: true) {
            case .created:
                new.append(input.hash)
            case .updated:
                updated.append(input.hash)
            case .existing, .tombstoned:
                break
            }
        }
        return (new, updated)
    }

    /// The failure record the reference writes on this path: message, counter, check time and the
    /// schedule as it stood, with no validators.
    private func recordFailure(_ feeds: FeedRepository, _ feedID: Int,
        _ error: any Error & Sendable, _ nextCheckAt: Int, _ checkedAt: Int) async throws {
        try await feeds.recordParsingError(feedID: feedID, message: String(describing: error),
            nextCheckAt: nextCheckAt, checkedAt: checkedAt)
    }

    /// The clock instant as the adapters read it: the date the parse resolves to when an entry has
    /// no date of its own.
    private func parsedDate(_ checkedAt: Int) -> ParsedDate {
        ParsedDate(epochSeconds: Int64(checkedAt), nanoseconds: 0, zoneName: "UTC",
            zoneOffsetSeconds: 0)
    }
}
