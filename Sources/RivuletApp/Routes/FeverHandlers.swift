// Ported from Miniflux internal/fever/handler.go (Apache-2.0); adapted for Swift/SQLite.

import RivuletCore
import Vapor

/// The dispatch this path answers on: the switch of `serve` upstream.
///
/// The switch answers the first name it finds. The six read names are read from the URL query,
/// which is `r.URL.Query()` with its pair rules, and the three mark names from the merged form,
/// which is `r.FormValue` — so a name the body carries reaches the switch, which the query alone
/// would not. The last branch is the default answer, for a name the switch has no case for.
struct FeverHandlers: Sendable {
    /// Module-internal because the three handler files of this path use the same storage seam.
    let storage: SQLiteStorage

    init(storage: SQLiteStorage) {
        self.storage = storage
    }

    /// `serve`, called after the transport read has passed. The form is the one that read built, so
    /// the mark names are answered by the same read the key was.
    func serve(request: Request, userID: Int, form: FeverForm) async throws -> Response {
        let query = GoogleReaderQuery(query: request.url.query ?? "")

        switch true {
        case query.has(named: "groups"):
            return try await groupsDocument(userID: userID)
        case query.has(named: "feeds"):
            return try await feedsDocument(userID: userID)
        case query.has(named: "favicons"):
            return try await faviconsDocument(userID: userID)
        case query.has(named: "unread_item_ids"):
            return try await unreadDocument(userID: userID)
        case query.has(named: "saved_item_ids"):
            return try await savedDocument(userID: userID)
        case query.has(named: "items"):
            return try await itemsDocument(userID: userID, query: query)
        case form.value(named: "mark") == "item":
            return try await writeItem(form: form, userID: userID)
        case form.value(named: "mark") == "feed":
            return try await writeFeed(form: form, userID: userID)
        case form.value(named: "mark") == "group":
            return try await writeGroup(form: form, userID: userID)
        default:
            return GoogleReaderResponse.json(FeverShape.baseDocument(
                authenticated: 1, lastRefreshed: Self.now()))
        }
    }

    /// What the write guards answer. The reference returns before the response builder runs, so the
    /// body is empty and nothing else is written — not the content type and not the three headers
    /// the builder writes on every other answer of this path.
    static func guarded() -> Response {
        Response(status: .ok)
    }

    /// `SetCommonValues`: the instant the handler runs at, which no pin can read, so the pins read
    /// the field's position through the placeholder the request helper names.
    static func now() -> Int64 {
        Int64(Date.now.timeIntervalSince1970)
    }
}
