// Ported from Miniflux internal/api/feed_handlers.go and internal/api/icon_handlers.go
// (Apache-2.0); adapted for Swift/SQLite.

import RivuletCore
import Vapor

/// The handlers the routes give the eight feed paths this stage registers.
///
/// The order each handler runs in is the reference's: the segment read, the body read, the row read,
/// the rule block, the write, the document. The update handler reads the body before the row, which is
/// the opposite order from the category update, and the two suites pin the two orders. The three paths
/// that write without a document answer 204; the two write paths answer 201.
///
/// The rule names the answers carry are the names this port gives the rules; the reference's wording for
/// the segment and for a row its read does not find is the reference's own and is written here as it is
/// written there.
extension RestV1Handlers {
    /// `getFeedsHandler`: the read answers the order the reference's query builder sorts by, which is
    /// the parsing-error count descending with the lowercased title as the tiebreaker.
    func feeds(request: Request, userID: Int) async throws -> Response {
        let headers = RestV1Headers(lines: request.headers.map { (name: $0.name, value: $0.value) })

        let documents: [JSONValue]
        do {
            documents = try await storage.withConnection { connection in
                try await FeedRepository(connection)
                    .listSortedByErrorCountThenTitle(userID: userID)
                    .map { RestV1Shape.feedDocument($0) }
            }
        } catch {
            return answer(status: .internalServerError, message: String(describing: error),
                headers: headers)
        }
        return RestV1Response.response(status: .ok, document: .array(documents), headers: headers)
    }

    /// `getFeedHandler`: the segment is read before anything is read against the storage layer.
    func feed(request: Request, userID: Int) async throws -> Response {
        let headers = RestV1Headers(lines: request.headers.map { (name: $0.name, value: $0.value) })

        let feedID = RestV1RouteParam.integer(request.parameters.get("feedID") ?? "")
        if feedID == 0 {
            return answer(status: .badRequest, message: "invalid feed ID", headers: headers)
        }

        let feed: Feed?
        do {
            feed = try await storage.withConnection { connection in
                try await FeedRepository(connection).fetch(userID: userID, id: feedID)
            }
        } catch {
            return answer(status: .internalServerError, message: String(describing: error),
                headers: headers)
        }
        guard let feed else {
            return answer(status: .notFound, message: "resource not found", headers: headers)
        }
        return RestV1Response.response(status: .ok, document: RestV1Shape.feedDocument(feed),
            headers: headers)
    }

    /// `createFeedHandler`: the body is read, then the category fallback runs for a zero category, then
    /// the rule block, then the write. The reference fetches the feed before it writes it; this port
    /// writes the row without fetching, which `docs/parity.md` records as a divergence, so the document
    /// this path writes carries the values the create defaults gave rather than the values a fetch would
    /// have filled in.
    func createFeed(request: Request, userID: Int) async throws -> Response {
        let headers = RestV1Headers(lines: request.headers.map { (name: $0.name, value: $0.value) })

        let creation: RequestBody.FeedCreation
        do {
            creation = try RequestBody.feedCreation(request.body.string ?? "")
        } catch {
            return answer(status: .badRequest, message: String(describing: error), headers: headers)
        }

        // "Make the feed category optional for clients who don't support categories": the fallback runs
        // before the rule block, so a request that carries a zero category reaches the category rule with
        // the row the fallback read.
        var categoryID = creation.categoryID
        if categoryID == 0 {
            do {
                let fallback = try await storage.withConnection { connection in
                    try await CategoryRepository(connection).first(userID: userID)
                }
                categoryID = fallback?.id ?? 0
            } catch {
                return answer(status: .internalServerError, message: String(describing: error),
                    headers: headers)
            }
        }

        // The two reads the rule block consults are reached only by an input that passes the rules
        // before them, which is the reference's order: the mandatory guard, the absolute-URL rule, then
        // the duplicate read, then the category read.
        let url = creation.feedURL
        let resolvedCategoryID = categoryID
        var duplicate = false
        var categoryExists = false
        if !url.isEmpty && resolvedCategoryID > 0 && URLRules.isAbsoluteURL(url) {
            do {
                duplicate = try await storage.withConnection { connection in
                    try await FeedRepository(connection).feedURLExists(userID: userID, url: url)
                }
                if !duplicate {
                    categoryExists = try await storage.withConnection { connection in
                        try await CategoryRepository(connection).categoryExists(userID: userID,
                            categoryID: resolvedCategoryID)
                    }
                }
            } catch {
                return answer(status: .internalServerError, message: String(describing: error),
                    headers: headers)
            }
        }
        if let rule = FeedValidation.validate(url: url, categoryID: resolvedCategoryID,
            urlIsAbsolute: URLRules.isAbsoluteURL(url), feedURLExists: duplicate,
            categoryExists: categoryExists) {
            return answer(status: .badRequest, message: rule.rawValue, headers: headers)
        }

        let feed: Feed
        do {
            feed = try await storage.withConnection { connection in
                try await FeedRepository(connection).create(userID: userID,
                    categoryID: resolvedCategoryID, url: url)
            }
        } catch {
            return answer(status: .internalServerError, message: String(describing: error),
                headers: headers)
        }
        return RestV1Response.response(status: .created,
            document: RestV1Shape.feedCreationDocument(feed), headers: headers)
    }

    /// `updateFeedHandler`: the segment, then the body, then the row, then the rule block, then the
    /// patch and the reset, then the write, then the row is read again for the document.
    func updateFeed(request: Request, userID: Int) async throws -> Response {
        let headers = RestV1Headers(lines: request.headers.map { (name: $0.name, value: $0.value) })

        let feedID = RestV1RouteParam.integer(request.parameters.get("feedID") ?? "")
        if feedID == 0 {
            return answer(status: .badRequest, message: "invalid feed ID", headers: headers)
        }

        let modification: RequestBody.FeedModification
        do {
            modification = try RequestBody.feedModification(request.body.string ?? "")
        } catch {
            return answer(status: .badRequest, message: String(describing: error), headers: headers)
        }

        let feed: Feed?
        do {
            feed = try await storage.withConnection { connection in
                try await FeedRepository(connection).fetch(userID: userID, id: feedID)
            }
        } catch {
            return answer(status: .internalServerError, message: String(describing: error),
                headers: headers)
        }
        guard let feed else {
            return answer(status: .notFound, message: "resource not found", headers: headers)
        }

        var duplicate = false
        if let url = modification.feedURL, !url.isEmpty {
            do {
                duplicate = try await storage.withConnection { connection in
                    try await FeedRepository(connection).anotherFeedURLExists(userID: userID,
                        feedID: feedID, url: url)
                }
            } catch {
                return answer(status: .internalServerError, message: String(describing: error),
                    headers: headers)
            }
        }

        // The category read is reached only for a field the request carried, which is what the rule
        // block's shape means: a field the request did not carry is nothing, not a value to read for.
        var categoryExists = true
        if let categoryID = modification.categoryID {
            do {
                categoryExists = try await storage.withConnection { connection in
                    try await CategoryRepository(connection).categoryExists(userID: userID,
                        categoryID: categoryID)
                }
            } catch {
                return answer(status: .internalServerError, message: String(describing: error),
                    headers: headers)
            }
        }

        if let rule = FeedValidation.validateModification(feedURL: modification.feedURL,
            siteURL: modification.siteURL, title: modification.title,
            categoryID: modification.categoryID,
            feedURLIsAbsolute: URLRules.isAbsoluteURL(modification.feedURL ?? ""),
            siteURLIsAbsolute: URLRules.isAbsoluteURL(modification.siteURL ?? ""),
            anotherFeedURLExists: duplicate, categoryExists: categoryExists) {
            return answer(status: .badRequest, message: rule.rawValue, headers: headers)
        }

        // `Patch`: a field the request did not carry is left as the row has it, and the reset runs
        // before the write, so the document reads the values the reset left.
        if let url = modification.feedURL { feed.url = url }
        if let siteURL = modification.siteURL { feed.siteURL = siteURL }
        if let title = modification.title { feed.title = title }
        if let categoryID = modification.categoryID { feed.categoryID = categoryID }
        feed.resetErrorCounter()

        let document: JSONValue
        do {
            // The reference reads the row again after the write and answers that read, so the document
            // is built from the row as it is after the write.
            document = try await storage.withConnection { connection in
                let repository = FeedRepository(connection)
                try await repository.save(feed: feed)
                let written = try await repository.fetch(userID: userID, id: feedID)
                guard let written else {
                    return RestV1Shape.feedDocument(feed)
                }
                return RestV1Shape.feedDocument(written)
            }
        } catch {
            return answer(status: .internalServerError, message: String(describing: error),
                headers: headers)
        }
        return RestV1Response.response(status: .created, document: document, headers: headers)
    }

    /// `removeFeedHandler`: the pair is read before the write, and the write answers 204.
    func removeFeed(request: Request, userID: Int) async throws -> Response {
        let headers = RestV1Headers(lines: request.headers.map { (name: $0.name, value: $0.value) })

        let feedID = RestV1RouteParam.integer(request.parameters.get("feedID") ?? "")
        if feedID == 0 {
            return answer(status: .badRequest, message: "invalid feed ID", headers: headers)
        }

        let found: Bool
        do {
            found = try await storage.withConnection { connection in
                try await FeedRepository(connection).feedExists(userID: userID, id: feedID)
            }
        } catch {
            return answer(status: .internalServerError, message: String(describing: error),
                headers: headers)
        }
        guard found else {
            return answer(status: .notFound, message: "resource not found", headers: headers)
        }

        do {
            try await storage.withConnection { connection in
                try await FeedRepository(connection).delete(id: feedID, userID: userID)
            }
        } catch {
            return answer(status: .internalServerError, message: String(describing: error),
                headers: headers)
        }
        return RestV1Response.noContent(headers: headers)
    }

    /// `getIconByFeedIDHandler`: the pair is read through the mapping this port keeps, and the document
    /// is the three keys the reference's response struct declares.
    func feedIcon(request: Request, userID: Int) async throws -> Response {
        let headers = RestV1Headers(lines: request.headers.map { (name: $0.name, value: $0.value) })

        let feedID = RestV1RouteParam.integer(request.parameters.get("feedID") ?? "")
        if feedID == 0 {
            return answer(status: .badRequest, message: "invalid feed ID", headers: headers)
        }

        let icon: Icon?
        do {
            icon = try await storage.withConnection { connection in
                try await IconRepository(connection).iconForFeed(userID: userID, feedID: feedID)
            }
        } catch {
            return answer(status: .internalServerError, message: String(describing: error),
                headers: headers)
        }
        guard let icon else {
            return answer(status: .notFound, message: "resource not found", headers: headers)
        }
        return RestV1Response.response(status: .ok, document: RestV1Shape.feedIconDocument(icon),
            headers: headers)
    }

    /// `refreshFeedHandler`: the pair is read before the refresh half runs, and the half is the seam the
    /// pin names. The reference's answer for a refresh that fails is 500; this port answers the same
    /// status for the error the runner throws.
    func refreshFeed(request: Request, userID: Int) async throws -> Response {
        let headers = RestV1Headers(lines: request.headers.map { (name: $0.name, value: $0.value) })

        let feedID = RestV1RouteParam.integer(request.parameters.get("feedID") ?? "")
        if feedID == 0 {
            return answer(status: .badRequest, message: "invalid feed ID", headers: headers)
        }

        let found: Bool
        do {
            found = try await storage.withConnection { connection in
                try await FeedRepository(connection).feedExists(userID: userID, id: feedID)
            }
        } catch {
            return answer(status: .internalServerError, message: String(describing: error),
                headers: headers)
        }
        guard found else {
            return answer(status: .notFound, message: "resource not found", headers: headers)
        }

        do {
            _ = try await runner.run(userID: userID, feedID: feedID)
        } catch {
            return answer(status: .internalServerError, message: String(describing: error),
                headers: headers)
        }
        return RestV1Response.noContent(headers: headers)
    }

    /// `markFeedAsReadHandler`: the pair is read before the write, and the write answers 204.
    func markFeedAsRead(request: Request, userID: Int) async throws -> Response {
        let headers = RestV1Headers(lines: request.headers.map { (name: $0.name, value: $0.value) })

        let feedID = RestV1RouteParam.integer(request.parameters.get("feedID") ?? "")
        if feedID == 0 {
            return answer(status: .badRequest, message: "invalid feed ID", headers: headers)
        }

        let found: Bool
        do {
            found = try await storage.withConnection { connection in
                try await FeedRepository(connection).feedExists(userID: userID, id: feedID)
            }
        } catch {
            return answer(status: .internalServerError, message: String(describing: error),
                headers: headers)
        }
        guard found else {
            return answer(status: .notFound, message: "resource not found", headers: headers)
        }

        do {
            try await storage.withConnection { connection in
                try await EntryRepository(connection)
                    .markFeedAsRead(userID: userID, feedID: feedID,
                        before: Int(Date.now.timeIntervalSince1970))
            }
        } catch {
            return answer(status: .internalServerError, message: String(describing: error),
                headers: headers)
        }
        return RestV1Response.noContent(headers: headers)
    }
}
