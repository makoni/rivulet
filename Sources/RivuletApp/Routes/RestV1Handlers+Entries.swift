// Ported from Miniflux internal/api/entry_handlers.go (Apache-2.0); adapted for Swift/SQLite.

import RivuletCore
import Vapor

/// The handlers the routes give the five entry paths this stage registers.
///
/// The order each handler runs in is the reference's: the segment read, the query rules, the two
/// guarded reads, the filter, the listing. The rule names the answers carry are the names this port
/// gives the rules; the wording for a segment and for a row its read does not find is the reference's
/// own and is written here as it is written there.
extension RestV1Handlers {
    /// `getEntriesHandler`: the path carries no segment, so the two ids the listing reads start at the
    /// value the guard reads as "unset".
    func entries(request: Request, userID: Int) async throws -> Response {
        try await findEntries(request: request, userID: userID, pathFeedID: 0, pathCategoryID: 0)
    }

    /// `getFeedEntriesHandler`: the segment is read before the query rules run, so a request that fails
    /// both answers the segment's answer.
    func feedEntries(request: Request, userID: Int) async throws -> Response {
        let headers = RestV1Headers(lines: request.headers.map { (name: $0.name, value: $0.value) })

        let feedID = RestV1RouteParam.integer(request.parameters.get("feedID") ?? "")
        if feedID == 0 {
            return answer(status: .badRequest, message: "invalid feed ID", headers: headers)
        }
        return try await findEntries(request: request, userID: userID, pathFeedID: feedID, pathCategoryID: 0)
    }

    /// `getEntryHandler` through `getEntryFromBuilder`: the segment is read before anything is read
    /// against the storage layer, and the read answers the 404 shape for a row it does not find.
    func entry(request: Request, userID: Int) async throws -> Response {
        let headers = RestV1Headers(lines: request.headers.map { (name: $0.name, value: $0.value) })

        let entryID = RestV1RouteParam.integer(request.parameters.get("entryID") ?? "")
        if entryID == 0 {
            return answer(status: .badRequest, message: "invalid entry ID", headers: headers)
        }

        let query = EntryQuery(userID: userID, entryIDs: [entryID])
        let rows: [Entry]
        do {
            rows = try await storage.withConnection { connection in
                try await EntryRepository(connection).list(query)
            }
        } catch {
            return answer(status: .internalServerError, message: String(describing: error), headers: headers)
        }

        guard let row = rows.first else {
            return answer(status: .notFound, message: "resource not found", headers: headers)
        }
        return RestV1Response.response(status: .ok, document: RestV1Shape.entryDocument(row),
            headers: headers)
    }

    /// `setEntryStatusAndStarredHandler`: the body is read before the rule block, and the block's rules
    /// are answered in the order the reference reads them. Each half of the request writes only when the
    /// request carried it, and the answer is 204 whatever the statements updated.
    func updateEntries(request: Request, userID: Int) async throws -> Response {
        let headers = RestV1Headers(lines: request.headers.map { (name: $0.name, value: $0.value) })

        let update: RequestBody.EntriesStatusUpdate
        do {
            update = try RequestBody.entriesStatusUpdate(request.body.string ?? "")
        } catch {
            return answer(status: .badRequest, message: String(describing: error), headers: headers)
        }

        if let rule = EntryValidation.validateStatusAndStarred(entryIDs: update.entryIDs,
            status: update.status, starred: update.starred) {
            return answer(status: .badRequest, message: rule.rawValue, headers: headers)
        }

        do {
            try await storage.withConnection { connection in
                let entries = EntryRepository(connection)
                // The block already admitted the value, so this is the check that the request carried the
                // field: an empty status answers nothing, and the write runs only for the half carried.
                if let status = EntryStatus(rawValue: update.status) {
                    try await entries.setStatus(userID: userID, entryIDs: update.entryIDs, status: status)
                }
                if let starred = update.starred {
                    try await entries.setStarred(userID: userID, entryIDs: update.entryIDs,
                        starred: starred)
                }
            }
        } catch {
            return answer(status: .internalServerError, message: String(describing: error), headers: headers)
        }
        return RestV1Response.noContent(headers: headers)
    }

    /// `toggleStarredHandler`: the segment is read before the statement runs, and the answer is the one
    /// the reference's builder writes for a statement that updated nothing.
    func toggleStarred(request: Request, userID: Int) async throws -> Response {
        let headers = RestV1Headers(lines: request.headers.map { (name: $0.name, value: $0.value) })

        let entryID = RestV1RouteParam.integer(request.parameters.get("entryID") ?? "")
        if entryID == 0 {
            return answer(status: .badRequest, message: "invalid entry ID", headers: headers)
        }

        do {
            _ = try await storage.withConnection { connection in
                try await EntryRepository(connection).toggleStarred(userID: userID, entryID: entryID)
            }
        } catch {
            return answer(status: .internalServerError, message: String(describing: error), headers: headers)
        }
        return RestV1Response.noContent(headers: headers)
    }

    /// `findEntries`: the four rules in the order the reference reads them, then the two guarded reads,
    /// then the filter the consumer sends, then the listing and the count.
    ///
    /// The filter block reads only the name the consumer sends. The reference's block reads nine names,
    /// and the `changed_at` pair among them has no field in this port's query, so the consumer's
    /// `changed_after` has nothing here to be applied to; `docs/parity.md` records both.
    private func findEntries(request: Request, userID: Int, pathFeedID: Int, pathCategoryID: Int)
        async throws -> Response {
        let headers = RestV1Headers(lines: request.headers.map { (name: $0.name, value: $0.value) })
        let query = GoogleReaderQuery(query: request.url.query ?? "")

        for status in query.list(named: "status") {
            if let rule = EntryValidation.validate(status: status) {
                return answer(status: .badRequest, message: rule.rawValue, headers: headers)
            }
        }

        let order = query.string(named: "order", default: "published_at")
        if let rule = EntryValidation.validate(order: order) {
            return answer(status: .badRequest, message: rule.rawValue, headers: headers)
        }

        let direction = query.string(named: "direction", default: "asc")
        if let rule = EntryValidation.validate(direction: direction) {
            return answer(status: .badRequest, message: rule.rawValue, headers: headers)
        }

        let limit = query.integer(named: "limit", default: 100)
        let offset = query.integer(named: "offset", default: 0)
        if let rule = EntryValidation.validate(offset: offset, limit: limit) {
            return answer(status: .badRequest, message: rule.rawValue, headers: headers)
        }

        // The two guards, in the reference's order, each reading the account the handler was given.
        let categoryID = query.integer(named: "category_id", default: pathCategoryID)
        if categoryID > 0 {
            let found: Bool
            do {
                found = try await storage.withConnection { connection in
                    try await CategoryRepository(connection).categoryExists(userID: userID,
                        categoryID: categoryID)
                }
            } catch {
                return answer(status: .internalServerError, message: String(describing: error),
                    headers: headers)
            }
            if !found {
                return answer(status: .badRequest, message: "invalid category ID", headers: headers)
            }
        }

        let feedID = query.integer(named: "feed_id", default: pathFeedID)
        if feedID > 0 {
            let found: Bool
            do {
                found = try await storage.withConnection { connection in
                    try await FeedRepository(connection).feedExists(userID: userID, id: feedID)
                }
            } catch {
                return answer(status: .internalServerError, message: String(describing: error),
                    headers: headers)
            }
            if !found {
                return answer(status: .badRequest, message: "invalid feed ID", headers: headers)
            }
        }

        var entryQuery = EntryQuery(
            userID: userID,
            feedID: feedID == 0 ? nil : feedID,
            categoryID: categoryID == 0 ? nil : categoryID,
            statuses: query.list(named: "status").compactMap { EntryStatus(rawValue: $0) },
            sort: EntrySort(field: order == "id" ? .id : .publishedAt,
                direction: direction == "desc" ? .descending : .ascending),
            limit: limit,
            offset: offset
        )

        // `configureFilters` applies the filter only when the name is present and the value parses, so
        // a value the parse fails on applies nothing rather than the default.
        if query.has(named: "starred"), let starred = RestV1Query.optionalBoolean(named: "starred",
            from: request.url.query ?? "") {
            entryQuery.starred = starred
        }

        // Bound as a constant before the read, because the read runs in concurrently-executing code.
        let built = entryQuery

        let page: (total: Int, rows: [Entry])
        do {
            page = try await storage.withConnection { connection in
                let entries = EntryRepository(connection)
                let rows = try await entries.list(built)
                return (try await entries.count(built), rows)
            }
        } catch {
            return answer(status: .internalServerError, message: String(describing: error),
                headers: headers)
        }

        return RestV1Response.response(status: .ok,
            document: RestV1Shape.entriesPageDocument(total: page.total, entries: page.rows),
            headers: headers)
    }
}
