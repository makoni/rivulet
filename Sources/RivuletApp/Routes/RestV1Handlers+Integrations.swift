// Ported from Miniflux internal/api/user_handlers.go's `getIntegrationsStatusHandler` (Apache-2.0);
// adapted for Swift/SQLite.

import RivuletCore
import Vapor

extension RestV1Handlers {
    /// `getIntegrationsStatusHandler`: the account row is read, and the one-key document is the answer.
    ///
    /// The reference's rule reads the eleven flags of the `integrations` table, which this port has no
    /// table for: the credential pairs live on the account row and no save integration runs here, so the
    /// answer is false for every account, which `docs/parity.md` records. The pin reads the answer the
    /// port gives for an account that carries a credential pair.
    func integrationsStatus(request: Request, userID: Int) async throws -> Response {
        let headers = RestV1Headers(lines: request.headers.map { (name: $0.name, value: $0.value) })

        let found: Bool
        do {
            found = try await storage.withConnection { connection in
                try await UserRepository(connection).fetch(id: userID) != nil
            }
        } catch {
            return answer(status: .internalServerError, message: String(describing: error), headers: headers)
        }

        // The reference answers the 404 shape for a row its own read does not find. No request this
        // suite can build reaches it, because the read that hands the handler the id read the same row,
        // so the branch is stated here rather than pinned.
        guard found else {
            return answer(status: .notFound, message: "resource not found", headers: headers)
        }
        return RestV1Response.response(status: .ok,
            document: RestV1Shape.integrationsStatusDocument(false), headers: headers)
    }
}
