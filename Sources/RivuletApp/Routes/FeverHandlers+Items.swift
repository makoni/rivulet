// Ported from Miniflux internal/fever/handler.go (Apache-2.0); adapted for Swift/SQLite.

import RivuletCore
import Vapor

extension FeverHandlers {
    /// `handleItems`: the page the read is given is 50, and the count is read on a query that does
    /// not carry it. The three forms of the selection answer in the order the switch reads them.
    func itemsDocument(userID: Int, query: GoogleReaderQuery) async throws -> Response {
        let selection = itemSelection(userID: userID, query: query)

        do {
            let (entries, total) = try await storage.withConnection { connection -> ([Entry], Int) in
                let entries = EntryRepository(connection)
                let rows = try await entries.list(selection)
                return (rows, try await entries.count(EntryQuery(userID: userID)))
            }

            let items = entries.compactMap { entry in
                entry.id.map { FeverShape.item(id: $0, feedID: entry.feedID, title: entry.title,
                    author: entry.author, html: entry.content, url: entry.url,
                    isSaved: entry.starred ? 1 : 0, isRead: entry.status == .read ? 1 : 0,
                    createdOnTime: Int64(entry.publishedAt)) }
            }
            return GoogleReaderResponse.json(FeverShape.itemsDocument(items: items, total: total,
                lastRefreshed: Self.now()))
        } catch {
            return GoogleReaderResponse.serverError(String(describing: error))
        }
    }

    /// The branch switch that chooses the storage filters, in the order the reference reads them.
    private func itemSelection(userID: Int, query: GoogleReaderQuery) -> EntryQuery {
        var selection = EntryQuery(userID: userID, limit: 50)

        if query.has(named: "since_id") {
            let sinceID = Self.queryInt64(query.value(named: "since_id"))
            if sinceID > 0 {
                selection.afterID = Int(sinceID)
                selection.sort = EntrySort(field: .id, direction: .ascending)
            }
        } else if query.has(named: "max_id") {
            let maxID = Self.queryInt64(query.value(named: "max_id"))
            // The two halves of the branch are the zero, which takes the most recent rows, and a
            // positive value, which is a bound. A negative value is one of the three paths that
            // answer the default, so it is the zero half here rather than a bound.
            if maxID >= 0 { selection.sort = EntrySort(field: .id, direction: .descending) }
            if maxID > 0 { selection.beforeID = Int(maxID) }
        } else if query.has(named: "with_ids") {
            let value = query.value(named: "with_ids")
            if !value.isEmpty { selection.entryIDs = itemIDs(value) }
        }

        return selection
    }

    /// The item ids the list read answers: every piece of the value, trimmed with Go's
    /// `unicode.IsSpace`, and a piece this read cannot read is the zero rather than something
    /// skipped — which is what makes `with_ids=x` select nothing here, because the port applies a
    /// set id literally. Empty pieces are kept, as `strings.SplitSeq` keeps them.
    private func itemIDs(_ value: String) -> [Int] {
        value.split(separator: ",", omittingEmptySubsequences: false).map { piece in
            let trimmed = piece.trimmingCharacters(in: GoSpace.characters)
            return Int((try? GoParseInt.parse(trimmed)) ?? 0)
        }
    }

    /// `request.QueryInt64Param` with the default 0: the default for a value that is empty,
    /// unparseable, or negative. The three paths are the ones the shared read has too, so the
    /// sign is not part of the value this branch reads; the write path's `FormInt64Value` is the
    /// read that keeps the sign, and that one is `FeverForm`'s.
    private static func queryInt64(_ value: String, default defaultValue: Int64 = 0) -> Int64 {
        guard !value.isEmpty, let parsed = try? GoParseInt.parse(value), parsed >= 0 else {
            return defaultValue
        }
        return parsed
    }
}
