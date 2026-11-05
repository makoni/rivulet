// Ported from Miniflux internal/googlereader/handler.go (Apache-2.0); adapted for Swift/SQLite.

import Foundation
import RivuletCore
import Vapor

extension GoogleReaderHandlers {
    /// `streamItemContentsHandler`.
    ///
    /// The order the handler runs in is what the pins read: the output check, then the merged form,
    /// then the stream read, then the item ids. The order parameter is read from the URL query, so
    /// the same name in a POST body is not read here, and the page size the read answers is not
    /// applied, because this handler's storage read has no `WithLimit` call. The document time is
    /// the time this handler runs at.
    ///
    /// The document `author` is the account name of the row the transport read found, which is a
    /// different value from the item's `author` — the entry's own. The document `id` is the literal
    /// generic prefix, while the categories carry the row id; the two forms are the same rule name.
    /// The reference rewrites the content and the attachment urls through its media proxy, which
    /// this port does not have, so the stored values pass through unchanged; `docs/parity.md`
    /// records that divergence.
    func contents(form: GoogleReaderForm, body: String?, query: String, userID: Int,
        baseURL: URL) async throws -> Response {
        do {
            try GoogleReaderOutput.check(method: .POST, query: query, body: body)
        } catch {
            return GoogleReaderResponse.badRequest(String(describing: error))
        }

        let modifiers: GoogleReaderRequestModifiers
        do {
            modifiers = try GoogleReaderRequestModifiers(query: GoogleReaderQuery(query: query),
                userID: userID)
        } catch {
            return GoogleReaderResponse.serverError(String(describing: error))
        }

        let itemIDs: [Int]
        do {
            itemIDs = try Self.itemIDs(from: form.values(named: "i"))
        } catch {
            return GoogleReaderResponse.badRequest(String(describing: error))
        }

        let entryQuery = EntryQuery(userID: userID, entryIDs: itemIDs,
            sort: EntrySort(field: .publishedAt, direction: Self.sortDirection(modifiers.sortDirection)))

        let (accountName, rows) = try await storage.withConnection { connection in
            let user = try await UserRepository(connection).fetch(id: userID)
            let rows = try await EntryRepository(connection).contents(entryQuery)
            return (user?.username ?? "unknown", rows)
        }

        let items = rows.map { Self.contentItem(from: $0, userID: userID) }
        return GoogleReaderResponse.json(GoogleReaderShape.contentDocument(direction: "ltr",
            id: Self.readingListStreamID, title: Self.readingListTitle,
            selfHref: baseURL.absoluteString + Self.contentsPath, updated: Int(Date.now.timeIntervalSince1970),
            items: items, author: accountName))
    }

    // MARK: - Handler rules

    /// One item document from one row, with the fields in the order the reference builds them.
    private static func contentItem(from row: EntryContents, userID: Int) -> JSONValue {
        GoogleReaderShape.contentItem(
            id: GoogleReaderItemID.longForm(entryID: Int64(row.entryID)),
            categories: GoogleReaderItemCategories.categories(userID: userID, status: row.status,
                starred: row.starred, categoryTitle: row.categoryTitle),
            title: row.title,
            crawlTimeMsec: String(row.createdAt * 1_000),
            timestampUsec: String(row.publishedAt * 1_000_000),
            published: row.publishedAt,
            updated: row.updatedAt,
            author: row.author,
            alternate: [GoogleReaderShape.contentHrefType(href: row.url, type: "text/html")],
            summary: GoogleReaderShape.contentText(direction: "ltr", content: row.content),
            content: GoogleReaderShape.contentText(direction: "ltr", content: row.content),
            origin: GoogleReaderShape.contentOrigin(streamID: "feed/\(row.feedID)",
                title: row.feedTitle, htmlURL: row.siteURL),
            enclosure: row.attachments.map {
                GoogleReaderShape.contentEnclosure(url: $0.url, type: $0.mimeType)
            },
            canonical: [GoogleReaderShape.contentHref(href: row.url)]
        )
    }

    /// The document `id` is the generic form written as a literal, while the categories carry the
    /// row id; the handler writes the two forms from these two rules.
    private static let readingListStreamID = "user/-/state/com.google/reading-list"
    private static let readingListTitle = "Reading List"
    private static let contentsPath = "/reader/api/0/stream/items/contents"
}
