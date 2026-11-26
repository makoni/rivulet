// Ported from Miniflux internal/model/user.go (Apache-2.0); adapted for Swift/SQLite.

import RivuletCore

/// The document this path writes for an account row.
///
/// The reference writes the 31 fields its struct declares; this port writes the three its schema
/// has columns for, which `docs/parity.md` records. The reference's `Password` field is not written
/// there either, because its tag names nothing. The key order is the order the struct declares,
/// which the pin reads on an input where swapping two of them changes the bytes.
enum RestV1Shape {
    /// `response.JSON(w, r, feeds)` for one row of the feed read.
    ///
    /// The reference's struct declares 43 fields it writes; this port writes the 14 its schema has
    /// columns for, in the order the struct declares them, which `docs/parity.md` records. The two
    /// non-persisted fields (`category` and `icon`) are read from other tables, not from the feed row,
    /// so the read that builds this document has nothing for them here.
    static func feedDocument(_ feed: Feed) -> JSONValue {
        .object([(key: "id", value: .integer(feed.id ?? 0)),
            (key: "user_id", value: .integer(feed.userID)),
            (key: "feed_url", value: .string(feed.url)),
            (key: "site_url", value: .string(feed.siteURL)),
            (key: "title", value: .string(feed.title)),
            (key: "description", value: .string(feed.feedDescription)),
            (key: "etag_header", value: .string(feed.etag)),
            (key: "last_modified_header", value: .string(feed.lastModified)),
            (key: "parsing_error_message", value: .string(feed.parsingErrorMessage)),
            (key: "parsing_error_count", value: .integer(feed.parsingErrorCount)),
            (key: "user_agent", value: .string(feed.userAgent)),
            (key: "disabled", value: .boolean(feed.disabled)),
            (key: "ignore_http_cache", value: .boolean(feed.ignoreHTTPCache)),
            (key: "fetch_via_proxy", value: .boolean(feed.fetchViaProxy))])
    }

    /// `response.JSON(w, r, &feedCreationResponse{FeedID: feed.ID})` — the one-key document the create
    /// path writes, which is not the feed document the other paths write.
    static func feedCreationDocument(_ feed: Feed) -> JSONValue {
        .object([(key: "feed_id", value: .integer(feed.id ?? 0))])
    }

    /// `response.JSON(w, r, &feedIconResponse{...})` for one icon row. The three keys are the fields the
    /// reference's response struct declares, in the order it declares them, and the third is the value
    /// ``Icon/dataURL()`` builds from the row.
    static func feedIconDocument(_ icon: Icon) -> JSONValue {
        .object([(key: "id", value: .integer(icon.id ?? 0)),
            (key: "mime_type", value: .string(icon.mimeType)),
            (key: "data", value: .string(icon.dataURL()))])
    }

    /// `response.JSON(w, r, user)` for the account read.
    static func userDocument(_ user: User) -> JSONValue {
        .object([(key: "id", value: .integer(user.id ?? 0)),
            (key: "username", value: .string(user.username)),
            (key: "is_admin", value: .boolean(user.isAdmin))])
    }

    /// `response.JSON(w, r, category)` for one row of the category read.
    ///
    /// The four keys are the fields the struct declares and this port has columns for. The two counts
    /// are pointers with `omitempty`: the half that read them writes them even for a zero, and the
    /// half that did not writes nothing, which is the rule `RestV1ShapeTests` pins.
    static func categoryDocument(_ category: Category, counts: CategoryCounts?) -> JSONValue {
        var keys: [(key: String, value: JSONValue)] = [
            (key: "id", value: .integer(category.id ?? 0)),
            (key: "user_id", value: .integer(category.userID)),
            (key: "title", value: .string(category.title)),
            (key: "hide_globally", value: .boolean(category.hideGlobally)),
        ]
        if let counts {
            keys.append((key: "feed_count", value: .integer(counts.feedCount)))
            keys.append((key: "total_unread", value: .integer(counts.totalUnread)))
        }
        return .object(keys)
    }
}
