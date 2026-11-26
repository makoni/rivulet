// Ported from Miniflux internal/api/category_handlers.go (Apache-2.0); adapted for Swift/SQLite.

import RivuletCore
import Vapor

/// The handlers the routes give the six category paths this stage registers.
///
/// The order each handler runs in is the reference's: the segment read, the row read, the body read,
/// the rule block, the write. Two handlers answer a request that fails two halves with the answer of
/// the half that runs first, so the order is what the pins read. The rule names the answers carry are
/// the names this port gives the rules; the reference's wording for the segment and for a row its read
/// does not find is the reference's own and is written here as it is written there.
extension RestV1Handlers {
    /// `getCategoriesHandler`: the query name decides which read runs, and the two reads answer
    /// different documents because the counts are pointers with `omitempty`.
    func categories(request: Request, userID: Int) async throws -> Response {
        let headers = RestV1Headers(lines: request.headers.map { (name: $0.name, value: $0.value) })
        let counts = RestV1Query.boolean(named: "counts", default: false, from: request.url.query ?? "")

        let documents: [JSONValue]?
        do {
            documents = try await storage.withConnection { connection in
                let categories = CategoryRepository(connection)
                if counts {
                    // The reference reads the account row first, for the order the user row carries,
                    // and this port has no column for that order, so it answers the reference's
                    // default order.
                    guard let user = try await UserRepository(connection).fetch(id: userID),
                        let readID = user.id else {
                        return nil
                    }
                    return try await categories.listWithCounts(userID: readID).map {
                        RestV1Shape.categoryDocument($0.category, counts: $0.counts)
                    }
                }
                return try await categories.listByTitle(userID: userID).map {
                    RestV1Shape.categoryDocument($0, counts: nil)
                }
            }
        } catch {
            return answer(status: .internalServerError, message: String(describing: error),
                headers: headers)
        }

        guard let documents else {
            return answer(status: .notFound, message: "resource not found", headers: headers)
        }
        return RestV1Response.response(status: .ok, document: .array(documents), headers: headers)
    }

    /// `createCategoryHandler`: the body is read before the rule block, and the block's first rule is
    /// answered before the duplicate read runs.
    func createCategory(request: Request, userID: Int) async throws -> Response {
        let headers = RestV1Headers(lines: request.headers.map { (name: $0.name, value: $0.value) })

        let creation: RequestBody.CategoryCreation
        do {
            creation = try RequestBody.categoryCreation(request.body.string ?? "")
        } catch {
            return answer(status: .badRequest, message: String(describing: error), headers: headers)
        }

        // The read is reached only by an input that passes the block's first rule, which is what the
        // pin that names both rules reads.
        var duplicate = false
        if !creation.title.isEmpty {
            do {
                duplicate = try await storage.withConnection { connection in
                    try await CategoryRepository(connection).titleExists(userID: userID,
                        title: creation.title)
                }
            } catch {
                return answer(status: .internalServerError, message: String(describing: error),
                    headers: headers)
            }
        }
        if let rule = CategoryValidation.validate(title: creation.title, titleIsDuplicate: duplicate) {
            return answer(status: .badRequest, message: rule.rawValue, headers: headers)
        }

        let document: JSONValue
        do {
            document = try await storage.withConnection { connection in
                RestV1Shape.categoryDocument(try await CategoryRepository(connection)
                    .create(userID: userID, title: creation.title, hideGlobally: creation.hideGlobally),
                    counts: nil)
            }
        } catch {
            return answer(status: .internalServerError, message: String(describing: error),
                headers: headers)
        }
        return RestV1Response.response(status: .created, document: document, headers: headers)
    }

    /// `updateCategoryHandler`: the row is read before the body, so a request that fails both answers
    /// the row's answer. The patch writes only the fields the request carried.
    func updateCategory(request: Request, userID: Int) async throws -> Response {
        let headers = RestV1Headers(lines: request.headers.map { (name: $0.name, value: $0.value) })

        let categoryID = RestV1RouteParam.integer(request.parameters.get("categoryID") ?? "")
        if categoryID == 0 {
            return answer(status: .badRequest, message: "invalid category ID", headers: headers)
        }

        let category: Category?
        do {
            category = try await storage.withConnection { connection in
                try await CategoryRepository(connection).fetch(userID: userID, id: categoryID)
            }
        } catch {
            return answer(status: .internalServerError, message: String(describing: error),
                headers: headers)
        }
        guard let category, let categoryID = category.id else {
            return answer(status: .notFound, message: "resource not found", headers: headers)
        }

        let modification: RequestBody.CategoryModification
        do {
            modification = try RequestBody.categoryModification(request.body.string ?? "")
        } catch {
            return answer(status: .badRequest, message: String(describing: error), headers: headers)
        }

        // The block runs only when the request carries a title, and the empty check runs before the
        // duplicate read, so the read is reached only by an input that passes the first rule.
        var duplicate = false
        if let title = modification.title, !title.isEmpty {
            do {
                duplicate = try await storage.withConnection { connection in
                    try await CategoryRepository(connection).anotherTitleExists(userID: userID,
                        categoryID: categoryID, title: title)
                }
            } catch {
                return answer(status: .internalServerError, message: String(describing: error),
                    headers: headers)
            }
        }
        if let rule = CategoryValidation.validate(title: modification.title,
            titleIsDuplicate: duplicate) {
            return answer(status: .badRequest, message: rule.rawValue, headers: headers)
        }

        // `Patch`: a field the request did not carry is left as the row has it, and the document is
        // written from the patched row, not from the row as it was read.
        if let title = modification.title { category.title = title }
        if let hideGlobally = modification.hideGlobally { category.hideGlobally = hideGlobally }

        let document: JSONValue
        do {
            try await storage.withConnection { connection in
                try await CategoryRepository(connection).update(userID: userID, id: categoryID,
                    title: category.title, hideGlobally: category.hideGlobally)
            }
            document = RestV1Shape.categoryDocument(category, counts: nil)
        } catch {
            return answer(status: .internalServerError, message: String(describing: error),
                headers: headers)
        }
        return RestV1Response.response(status: .created, document: document, headers: headers)
    }

    /// `removeCategoryHandler`: the pair is read before the write, and the write answers 204.
    func removeCategory(request: Request, userID: Int) async throws -> Response {
        let headers = RestV1Headers(lines: request.headers.map { (name: $0.name, value: $0.value) })

        let categoryID = RestV1RouteParam.integer(request.parameters.get("categoryID") ?? "")
        if categoryID == 0 {
            return answer(status: .badRequest, message: "invalid category ID", headers: headers)
        }

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
        guard found else {
            return answer(status: .notFound, message: "resource not found", headers: headers)
        }

        do {
            try await storage.withConnection { connection in
                try await CategoryRepository(connection).delete(userID: userID, id: categoryID)
            }
        } catch {
            return answer(status: .internalServerError, message: String(describing: error),
                headers: headers)
        }
        return RestV1Response.noContent(headers: headers)
    }

    /// `getCategoryFeedsHandler`: the row is read before the feeds, so a request that names a row that
    /// is not there answers the row's answer before the feeds read runs.
    func categoryFeeds(request: Request, userID: Int) async throws -> Response {
        let headers = RestV1Headers(lines: request.headers.map { (name: $0.name, value: $0.value) })

        let categoryID = RestV1RouteParam.integer(request.parameters.get("categoryID") ?? "")
        if categoryID == 0 {
            return answer(status: .badRequest, message: "invalid category ID", headers: headers)
        }

        let documents: [JSONValue]?
        do {
            documents = try await storage.withConnection { connection in
                let categories = CategoryRepository(connection)
                guard try await categories.fetch(userID: userID, id: categoryID) != nil else {
                    return nil
                }
                return try await FeedRepository(connection)
                    .listByCategorySortedByErrorCountThenTitle(userID: userID, categoryID: categoryID)
                    .map { RestV1Shape.feedDocument($0) }
            }
        } catch {
            return answer(status: .internalServerError, message: String(describing: error),
                headers: headers)
        }

        guard let documents else {
            return answer(status: .notFound, message: "resource not found", headers: headers)
        }
        return RestV1Response.response(status: .ok, document: .array(documents), headers: headers)
    }
}
