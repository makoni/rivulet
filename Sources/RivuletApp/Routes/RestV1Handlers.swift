// Ported from Miniflux internal/api/user_handlers.go's currentUserHandler (Apache-2.0);
// adapted for Swift/SQLite.

import RivuletCore
import Vapor

///The handler the route gives the one path this stage registers.  The read runs before the handler,
///as the reference's chain runs before its mux, so the handler is reached only by a request the
///read answered, and it is given the row id the read found, which is what `request.UserID` answers
///upstream.
struct RestV1Handlers: Sendable {
    /// Internal because the handlers for each path half live in their own file, as the shape and the
    /// response types do.
    let storage: SQLiteStorage

    /// The half the refresh path runs through. It is a seam rather than the pipeline itself so the pin
    /// that reads the order between the pair read and the fetch can name it without a socket; the
    /// application hands the pipeline, which is the production caller.
    let runner: FeedRefreshRunner

    init(storage: SQLiteStorage, runner: FeedRefreshRunner) {
        self.storage = storage
        self.runner = runner
    }

    /// The answer a handler writes for a rule: the status the reference's builder writes for it and the
    /// document the error builder writes with the message the rule carries.
    func answer(status: HTTPStatus, message: String, headers: RestV1Headers) -> Response {
        RestV1Response.response(status: status, document: RestV1Response.errorDocument(message),
            headers: headers)
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
