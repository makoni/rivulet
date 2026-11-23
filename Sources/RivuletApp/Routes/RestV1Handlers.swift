// Ported from Miniflux internal/api/user_handlers.go's currentUserHandler (Apache-2.0);
// adapted for Swift/SQLite.

import RivuletCore
import Vapor

///The handler the route gives the one path this stage registers.  The read runs before the handler,
///as the reference's chain runs before its mux, so the handler is reached only by a request the
///read answered, and it is given the row id the read found, which is what `request.UserID` answers
///upstream.
struct RestV1Handlers: Sendable {
    private let storage: SQLiteStorage

    init(storage: SQLiteStorage) {
        self.storage = storage
    }

    ///`currentUserHandler`: the row is read by the id the read handed, and the document is the
    ///shape this path writes for an account.
    func me(request: Request, userID: Int) async throws -> Response {
        let headers = RestV1Headers(lines: request.headers.map { (name: $0.name, value: $0.value) })
        let user: User?
        do {
            user = try await storage.withConnection { connection in
                try await UserRepository(connection).fetch(id: userID)
            }
        } catch {
            return RestV1Response.answer(for: .userReadFailed, headers: headers)
        }

        // The reference answers the 404 shape for a row its own read does not find. No request this
        // suite can build reaches it, because the read that hands the handler the id read the same
        // row, so the branch is stated here rather than pinned.
        guard let user else {
            return RestV1Response.response(status: .notFound,
                document: RestV1Response.errorDocument("resource not found"), headers: headers)
        }
        return RestV1Response.response(status: .ok, document: RestV1Shape.userDocument(user),
            headers: headers)
    }
}
