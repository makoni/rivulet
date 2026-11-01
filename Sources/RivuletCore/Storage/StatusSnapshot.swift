import Foundation

/// The feed-state snapshot `rivulet status` prints: one entry per feed row plus the counts.
///
/// The reference has no status command, so this shape is the port's own machine-readable contract,
/// recorded in `docs/parity.md`: `docs/plan/stage-6-cli.md` keeps it stable for monitoring and for
/// the stage-4 soak, which reads these values repeatedly. The keys mirror the column names the
/// storage layer uses, because a contract that monitoring scripts read must not rename what it
/// reports: `id`, `user_id`, `title`, `url`, `site_url`, `fetched_at`, `next_check_at`,
/// `parsing_error_count`, `parsing_error_message`, and for the counts `feeds`, `enabled`,
/// `disabled`, `due`, `at_error_limit`. The one row key that is not a column is `enabled`, which
/// reports the `disabled` column as its positive form.
///
/// Two values are read as they are stored rather than as the schema's default: the stamps are `nil`
/// for a row that has never been checked or fetched, and `due` is the pick the batch rules make
/// at the instant the caller names, so the switches that read a zero as off show up in it.
public struct StatusSnapshot: Sendable, Codable {
    /// One feed row, as the storage holds it.
    public struct Feed: Sendable, Codable {
        /// Row id.
        public let id: Int

        /// Owner of the row, which the snapshot does not filter on.
        public let userID: Int

        /// Feed title, empty until the first successful fetch fills it.
        public let title: String

        /// Feed URL.
        public let url: String

        /// Site the feed links to, empty until the first successful fetch fills it.
        public let siteURL: String

        /// Whether the scheduler runs this row, which the batch gate excludes when it is false.
        public let enabled: Bool

        /// Unix seconds of the last successful fetch, `nil` for a row that has never been fetched.
        public let fetchedAt: Int?

        /// Unix seconds of the next scheduled check, `nil` for a row the schedule has not set.
        public let nextCheckAt: Int?

        /// Consecutive failed refreshes.
        public let parsingErrorCount: Int

        /// Message of the latest failed refresh, empty when healthy.
        public let parsingErrorMessage: String

        /// Creates one row of the snapshot.
        public init(id: Int, userID: Int, title: String, url: String, siteURL: String,
            enabled: Bool, fetchedAt: Int?, nextCheckAt: Int?, parsingErrorCount: Int,
            parsingErrorMessage: String) {
            self.id = id
            self.userID = userID
            self.title = title
            self.url = url
            self.siteURL = siteURL
            self.enabled = enabled
            self.fetchedAt = fetchedAt
            self.nextCheckAt = nextCheckAt
            self.parsingErrorCount = parsingErrorCount
            self.parsingErrorMessage = parsingErrorMessage
        }

        /// Encodes every documented key, including the ones the row has no value for.
        ///
        /// `JSONEncoder` drops a nil property from the output by default, which would make the
        /// contract report a row that has never been fetched as a row without those keys at all. A
        /// script comparing two runs needs the key to be there with `null`, so the
        /// encoder writes it explicitly.
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(userID, forKey: .userID)
            try container.encode(title, forKey: .title)
            try container.encode(url, forKey: .url)
            try container.encode(siteURL, forKey: .siteURL)
            try container.encode(enabled, forKey: .enabled)
            try container.encode(fetchedAt, forKey: .fetchedAt)
            try container.encode(nextCheckAt, forKey: .nextCheckAt)
            try container.encode(parsingErrorCount, forKey: .parsingErrorCount)
            try container.encode(parsingErrorMessage, forKey: .parsingErrorMessage)
        }

        /// Keys mirror the column names, so the document does not rename what it reports; `enabled`
        /// is the one key that is not a column, reporting the `disabled` column as its
        /// positive form.
        private enum CodingKeys: String, CodingKey {
            case id
            case userID = "user_id"
            case title
            case url
            case siteURL = "site_url"
            case enabled
            case fetchedAt = "fetched_at"
            case nextCheckAt = "next_check_at"
            case parsingErrorCount = "parsing_error_count"
            case parsingErrorMessage = "parsing_error_message"
        }
    }

    /// The counts the snapshot reports, read from the same rows.
    public struct Totals: Sendable, Codable {
        /// Every row, whatever its state.
        public let feeds: Int

        /// Rows the scheduler runs.
        public let enabled: Int

        /// Rows the batch gate excludes.
        public let disabled: Int

        /// The pick the batch rules make at the instant the snapshot was read — the
        /// rows the next tick would run, so the three rules that read a zero as a
        /// switch show up in this count.
        public let due: Int

        /// Rows at or over the error limit; zero when the limit is off, because for
        /// that switch no row is at a limit there is no filter for.
        public let atErrorLimit: Int

        /// Creates the counts.
        public init(feeds: Int, enabled: Int, disabled: Int, due: Int, atErrorLimit: Int) {
            self.feeds = feeds
            self.enabled = enabled
            self.disabled = disabled
            self.due = due
            self.atErrorLimit = atErrorLimit
        }

        /// Keys mirror the shape the contract documents.
        private enum CodingKeys: String, CodingKey {
            case feeds
            case enabled
            case disabled
            case due
            case atErrorLimit = "at_error_limit"
        }
    }

    /// The rows, in id order.
    public let feeds: [Feed]

    /// The counts.
    public let totals: Totals

    /// Creates a snapshot.
    public init(feeds: [Feed], totals: Totals) {
        self.feeds = feeds
        self.totals = totals
    }
}
