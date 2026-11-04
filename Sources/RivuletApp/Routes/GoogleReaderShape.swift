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

    /// `tagsResponse`.
    static func tagsResponse(tags: [JSONValue]) -> JSONValue {
        .object([(key: "tags", value: .array(tags))])
    }
}
