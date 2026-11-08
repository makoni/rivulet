// Ported from Miniflux internal/googlereader/response.go's documents (Apache-2.0); adapted for
// Swift/SQLite.

/// The documents this path writes, as the struct tags declare them.
///
/// `encoding/json` writes a field with `omitempty` only when its value is empty, and the
/// continuation carries the `,string` option, so a value that is written is a JSON string. Those
/// two rules, the key order, and the rule that an empty list is `[]` rather than `null` — because
/// the reference builds the slice with `make` before it writes it — are what
/// `GoogleReaderShapeTests` pins against the reference's own output.
enum GoogleReaderShape {
    /// `itemRef`: only `id` is written without `omitempty`.
    static func itemRef(id: String, directStreamIDs: String = "", timestampUsec: String = "") -> JSONValue {
        var pairs: [(key: String, value: JSONValue)] = [(key: "id", value: .string(id))]
        if !directStreamIDs.isEmpty {
            pairs.append((key: "directStreamIds", value: .string(directStreamIDs)))
        }
        if !timestampUsec.isEmpty {
            pairs.append((key: "timestampUsec", value: .string(timestampUsec)))
        }
        return .object(pairs)
    }

    /// `streamIDResponse`: the list is always written, the continuation only when it is not 0, and
    /// as a string.
    static func streamIDResponse(itemRefs: [JSONValue], continuation: Int) -> JSONValue {
        var pairs: [(key: String, value: JSONValue)] = [(key: "itemRefs", value: .array(itemRefs))]
        if continuation != 0 {
            pairs.append((key: "continuation", value: .string(String(continuation))))
        }
        return .object(pairs)
    }

    /// `userInfoResponse`: no field has `omitempty`, so the empty values are written as empty
    /// strings.
    static func userInfoResponse(userID: String, userName: String, userProfileID: String,
        userEmail: String) -> JSONValue {
        .object([
            (key: "userId", value: .string(userID)),
            (key: "userName", value: .string(userName)),
            (key: "userProfileId", value: .string(userProfileID)),
            (key: "userEmail", value: .string(userEmail)),
        ])
    }

    /// `subscriptionCategoryResponse`: `id` is written on its own, the other two only when they
    /// have a value.
    static func categoryResponse(id: String, label: String = "", type: String = "") -> JSONValue {
        var pairs: [(key: String, value: JSONValue)] = [(key: "id", value: .string(id))]
        if !label.isEmpty { pairs.append((key: "label", value: .string(label))) }
        if !type.isEmpty { pairs.append((key: "type", value: .string(type))) }
        return .object(pairs)
    }

    /// `subscriptionResponse`: the six fields are written in the order the struct declares them,
    /// and none has `omitempty`, so an empty value is written as an empty string.
    static func subscriptionResponse(id: String, title: String, categories: [JSONValue], url: String,
        htmlURL: String, iconURL: String) -> JSONValue {
        .object([
            (key: "id", value: .string(id)),
            (key: "title", value: .string(title)),
            (key: "categories", value: .array(categories)),
            (key: "url", value: .string(url)),
            (key: "htmlUrl", value: .string(htmlURL)),
            (key: "iconUrl", value: .string(iconURL)),
        ])
    }

    /// `subscriptionsResponse`: the list is built with `make` before it is written, so an empty
    /// document answers `[]` and not `null`.
    static func subscriptionsResponse(subscriptions: [JSONValue]) -> JSONValue {
        .object([(key: "subscriptions", value: .array(subscriptions))])
    }

    /// `quickAddResponse`: `numResults` has neither `omitempty` nor the string option, so it is
    /// written as a number even when it is 0, and the other three are written only when they have a
    /// value.
    static func quickAddResponse(numResults: Int, query: String = "", streamID: String = "",
        streamName: String = "") -> JSONValue {
        var pairs: [(key: String, value: JSONValue)] = [(key: "numResults", value: .integer(numResults))]
        if !query.isEmpty { pairs.append((key: "query", value: .string(query))) }
        if !streamID.isEmpty { pairs.append((key: "streamId", value: .string(streamID))) }
        if !streamName.isEmpty {
            pairs.append((key: "streamName", value: .string(streamName)))
        }
        return .object(pairs)
    }

    /// `tagsResponse`.
    static func tagsResponse(tags: [JSONValue]) -> JSONValue {
        .object([(key: "tags", value: .array(tags))])
    }

    /// `streamContentItemsResponse`: no field has `omitempty`, so every one is written, and the
    /// lists are written as `[]` when empty because the reference builds them with `make`.
    static func contentDocument(direction: String, id: String, title: String, selfHref: String,
        updated: Int, items: [JSONValue], author: String) -> JSONValue {
        .object([
            (key: "direction", value: .string(direction)),
            (key: "id", value: .string(id)),
            (key: "title", value: .string(title)),
            (key: "self", value: .array([contentHref(href: selfHref)])),
            (key: "updated", value: .integer(updated)),
            (key: "items", value: .array(items)),
            (key: "author", value: .string(author)),
        ])
    }

    /// `contentItem`: the fourteen fields are written in the order the struct declares them, and
    /// none has `omitempty`.
    static func contentItem(id: String, categories: [String], title: String, crawlTimeMsec: String,
        timestampUsec: String, published: Int, updated: Int, author: String,
        alternate: [JSONValue], summary: JSONValue, content: JSONValue, origin: JSONValue,
        enclosure: [JSONValue], canonical: [JSONValue]) -> JSONValue {
        .object([
            (key: "id", value: .string(id)),
            (key: "categories", value: .array(categories.map { .string($0) })),
            (key: "title", value: .string(title)),
            (key: "crawlTimeMsec", value: .string(crawlTimeMsec)),
            (key: "timestampUsec", value: .string(timestampUsec)),
            (key: "published", value: .integer(published)),
            (key: "updated", value: .integer(updated)),
            (key: "author", value: .string(author)),
            (key: "alternate", value: .array(alternate)),
            (key: "summary", value: summary),
            (key: "content", value: content),
            (key: "origin", value: origin),
            (key: "enclosure", value: .array(enclosure)),
            (key: "canonical", value: .array(canonical)),
        ])
    }

    /// `contentHREFType`: `href` then `type`, both written.
    static func contentHrefType(href: String, type: String) -> JSONValue {
        .object([(key: "href", value: .string(href)), (key: "type", value: .string(type))])
    }

    /// `contentHREF`, the shape `self` and `canonical` write.
    static func contentHref(href: String) -> JSONValue {
        .object([(key: "href", value: .string(href))])
    }

    /// `contentItemContent`: the direction and the content as stored.
    static func contentText(direction: String, content: String) -> JSONValue {
        .object([(key: "direction", value: .string(direction)),
            (key: "content", value: .string(content))])
    }

    /// `contentItemOrigin`, built from the feed row.
    static func contentOrigin(streamID: String, title: String, htmlURL: String) -> JSONValue {
        .object([(key: "streamId", value: .string(streamID)), (key: "title", value: .string(title)),
            (key: "htmlUrl", value: .string(htmlURL))])
    }

    /// `contentItemEnclosure`: the url and the type the row declares.
    static func contentEnclosure(url: String, type: String) -> JSONValue {
        .object([(key: "url", value: .string(url)), (key: "type", value: .string(type))])
    }
}
