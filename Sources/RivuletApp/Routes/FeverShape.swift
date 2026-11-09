// Ported from Miniflux internal/fever/response.go (Apache-2.0); adapted for Swift/SQLite.

/// The documents this path writes, as the reference's encoder writes them.
///
/// `baseResponse` is embedded by every document of this path, so its three fields are written
/// before the document's own. No field of any document here has `omitempty`, so every field is
/// written whatever the value is — including `favicon_id` for a feed row with no icon.
///
/// An empty list is written as `[]`. For `items`, `feeds` and the `feeds_groups` of the groups
/// document that is what the reference writes too, because it builds those slices with `make`
/// before writing the document. For `groups` and `favicons` the reference writes `null` for the nil
/// slice its build path leaves, which this port does not: the row in `docs/parity.md` records it,
/// because the acceptance client's deserializer refuses `null` for those two.
enum FeverShape {
    /// The version this path reports, which `SetCommonValues` writes on every document.
    static let reportedVersion = 3

    /// `baseResponse`. `newAuthFailureResponse` is the one document that writes the zero for both
    /// the flag and the clock field, because it never runs the common-value rule.
    static func baseDocument(authenticated: Int, lastRefreshed: Int64) -> JSONValue {
        Self.document([], lastRefreshed: lastRefreshed, authenticated: authenticated)
    }

    static func authFailure() -> JSONValue {
        baseDocument(authenticated: 0, lastRefreshed: 0)
    }

    /// The six documents that embed the base response, each writing its own fields after it in the
    /// order the struct declares them.
    static func groupsDocument(groups: [JSONValue], feedsGroups: [JSONValue],
        lastRefreshed: Int64) -> JSONValue {
        Self.document([(key: "groups", value: .array(groups)),
            (key: "feeds_groups", value: .array(feedsGroups))], lastRefreshed: lastRefreshed)
    }

    static func feedsDocument(feeds: [JSONValue], feedsGroups: [JSONValue],
        lastRefreshed: Int64) -> JSONValue {
        Self.document([(key: "feeds", value: .array(feeds)),
            (key: "feeds_groups", value: .array(feedsGroups))], lastRefreshed: lastRefreshed)
    }

    static func faviconsDocument(favicons: [JSONValue], lastRefreshed: Int64) -> JSONValue {
        Self.document([(key: "favicons", value: .array(favicons))], lastRefreshed: lastRefreshed)
    }

    /// `total_items` is written as a number even when it is 0: the field has neither `omitempty`
    /// nor the `,string` option.
    static func itemsDocument(items: [JSONValue], total: Int, lastRefreshed: Int64) -> JSONValue {
        Self.document([(key: "items", value: .array(items)),
            (key: "total_items", value: .integer(total))], lastRefreshed: lastRefreshed)
    }

    static func unreadDocument(ids: String, lastRefreshed: Int64) -> JSONValue {
        Self.document([(key: "unread_item_ids", value: .string(ids))], lastRefreshed: lastRefreshed)
    }

    static func savedDocument(ids: String, lastRefreshed: Int64) -> JSONValue {
        Self.document([(key: "saved_item_ids", value: .string(ids))], lastRefreshed: lastRefreshed)
    }

    /// The value documents, each writing every field its struct declares.
    static func group(id: Int, title: String) -> JSONValue {
        .object([(key: "id", value: .integer(id)), (key: "title", value: .string(title))])
    }

    static func feedsGroup(groupID: Int, feedIDs: String) -> JSONValue {
        .object([(key: "group_id", value: .integer(groupID)), (key: "feed_ids", value: .string(feedIDs))])
    }

    /// `is_spark` is the value this handler writes for every row, whatever the reference's model
    /// carries, and `last_updated_on_time` is the check time the feed row holds.
    static func feed(id: Int, faviconID: Int, title: String, url: String, siteURL: String,
        lastUpdated: Int64) -> JSONValue {
        .object([(key: "id", value: .integer(id)), (key: "favicon_id", value: .integer(faviconID)),
            (key: "title", value: .string(title)), (key: "url", value: .string(url)),
            (key: "site_url", value: .string(siteURL)), (key: "is_spark", value: .integer(0)),
            (key: "last_updated_on_time", value: .integer(Int(lastUpdated)))])
    }

    /// The two flags are written as 0 and 1, which is what this handler reads from the row, and the
    /// time is the publication time the reference's `entry.Date` holds.
    static func item(id: Int, feedID: Int, title: String, author: String, html: String, url: String,
        isSaved: Int, isRead: Int, createdOnTime: Int64) -> JSONValue {
        .object([(key: "id", value: .integer(id)), (key: "feed_id", value: .integer(feedID)),
            (key: "title", value: .string(title)), (key: "author", value: .string(author)),
            (key: "html", value: .string(html)), (key: "url", value: .string(url)),
            (key: "is_saved", value: .integer(isSaved)), (key: "is_read", value: .integer(isRead)),
            (key: "created_on_time", value: .integer(Int(createdOnTime)))])
    }

    static func favicon(id: Int, data: String) -> JSONValue {
        .object([(key: "id", value: .integer(id)), (key: "data", value: .string(data))])
    }

    /// One document that embeds `baseResponse`: the three fields first, then the document's own.
    private static func document(_ fields: [(key: String, value: JSONValue)], lastRefreshed: Int64,
        authenticated: Int = 1) -> JSONValue {
        .object([(key: "api_version", value: .integer(reportedVersion)),
            (key: "auth", value: .integer(authenticated)),
            (key: "last_refreshed_on_time", value: .integer(Int(lastRefreshed)))] + fields)
    }
}
