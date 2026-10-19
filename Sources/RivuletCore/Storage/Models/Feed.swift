import FluentKit

/// A subscribed feed: the fetcher's unit of work.
///
/// A feed belongs to a user and a category and carries the fetch state the
/// scheduler and the fetcher maintain: the conditional-GET headers (`etag`,
/// `lastModified`), the next scheduled check, the parsing failure counter
/// and the last successful fetch time. URLs are unique per user.
public final class Feed: Model, @unchecked Sendable {
    public static let schema = "feeds"

    @ID(custom: .id) public var id: Int?

    /// Owner of the feed.
    @Field(key: "user_id") public var userID: Int

    /// Category the feed is listed under.
    @Field(key: "category_id") public var categoryID: Int

    /// Feed URL, unique per user.
    @Field(key: "url") public var url: String

    /// Site the feed links to; empty until the first successful fetch fills it.
    @Field(key: "site_url") public var siteURL: String

    /// Feed title; empty until the first successful fetch fills it.
    @Field(key: "title") public var title: String

    /// Feed description; empty until the first successful fetch fills it.
    @Field(key: "description") public var feedDescription: String

    /// Icon of the feed, `nil` until the fetcher downloads one.
    @OptionalField(key: "icon_id") public var iconID: Int?

    /// Value of the last `ETag` response header; empty until observed.
    @Field(key: "etag") public var etag: String

    /// Value of the last `Last-Modified` response header; empty until observed.
    @Field(key: "last_modified") public var lastModified: String

    /// Unix seconds of the next scheduled check.
    @OptionalField(key: "next_check_at") public var nextCheckAt: Int?

    /// Desired polling interval in minutes; the scheduler clamps it.
    @Field(key: "check_interval") public var checkInterval: Int

    /// Consecutive failed refreshes; reset by a successful one.
    @Field(key: "parsing_error_count") public var parsingErrorCount: Int

    /// Message of the latest failed refresh; empty when healthy.
    @Field(key: "parsing_error_message") public var parsingErrorMessage: String

    /// Per-feed request user agent; empty means the default.
    @Field(key: "user_agent") public var userAgent: String

    /// Disabled feeds are skipped by the scheduler until re-enabled.
    @Field(key: "disabled") public var disabled: Bool

    /// Unix seconds of the last successful fetch.
    @OptionalField(key: "fetched_at") public var fetchedAt: Int?

    /// Unix seconds; creation time.
    @Field(key: "created_at") public var createdAt: Int

    /// Unix seconds; updated on every mutation.
    @Field(key: "updated_at") public var updatedAt: Int

    /// Creates an unfilled feed; the repositories populate and persist it.
    ///
    /// Fields must be set before the instance is used with a query.
    public init() {}
}
