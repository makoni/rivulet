// Ported from Miniflux internal/http/server/routes.go, through the Fever handler and middleware
// (Apache-2.0); adapted for Swift/SQLite.

import RivuletCore
import Vapor

/// The route this path answers on.
public enum FeverRoutes {
    /// Registers the route on the application.
    ///
    /// `FeverAuth` is the wrapper the reference's mux puts on this route, so it is applied per
    /// route rather than as application middleware that would cover `/healthz` too.
    ///
    /// The reference's pattern is a subtree pattern that answers any method under it. Vapor matches
    /// per method, so the three methods the acceptance client uses are registered here: `GET` for
    /// the reads, `POST` for the write calls, and the `HEAD` its reachability check sends. The
    /// subtree half and the method mismatch — where the reference answers 405 and this port
    /// answers Vapor's 404 for a method not registered here — are recorded in `docs/parity.md`.
    public static func register(on application: Application, storage: SQLiteStorage) {
        let auth = FeverAuth(storage: storage)
        let handlers = FeverHandlers(storage: storage)
        let handle = auth.withAuth { request, userID, form in
            try await handlers.serve(request: request, userID: userID, form: form)
        }

        let route = application.grouped("fever")
        route.on(.GET, use: handle)
        route.on(.POST, use: handle)
        route.on(.HEAD, use: handle)
    }
}
