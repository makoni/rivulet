// Ported from Miniflux internal/api/api.go's mux (Apache-2.0); adapted for Swift/SQLite.

import RivuletCore
import Vapor

/// The route this path answers on.
public enum RestV1Routes {
    ///Registers the route on the application.  `RestV1Auth` is the wrapper the reference's chain
    ///puts on every route of this path, so it is applied per route rather than as application
    ///middleware that would cover `/healthz` too.  The reference's mux has one pattern per path
    ///with the method written on it, and this stage registers the one path its scope has:
    ///`GET /v1/me`. The answer for another method and the answer for a path no pattern registers
    ///are recorded in `docs/parity.md`, and the pin for this prefix reads the router's answer for
    ///a path with no pattern.
    ///pattern.
    public static func register(on application: Application, storage: SQLiteStorage,
        hasher: BcryptHasher) {
        let auth = RestV1Auth(storage: storage, hasher: hasher)
        let handlers = RestV1Handlers(storage: storage)

        application.grouped("v1").get("me", use: auth.withAuth { request, userID in
            try await handlers.me(request: request, userID: userID)
        })
    }
}
