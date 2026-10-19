// Ported from Miniflux internal/http/server/healthcheck.go (Apache-2.0); adapted for Swift/SQLite.

import Vapor

/// Liveness probe.
///
/// Like upstream `/healthz`, this is a liveness probe: it answers `OK` whenever the process
/// serves requests and deliberately does not touch the database. Miniflux registers it on a
/// method-less mux pattern; the standard NIO method set is registered here to mirror that
/// (custom methods beyond the set still answer 404). (Upstream also has a `/readiness` probe
/// that pings the database; it arrives together with the client APIs.)
enum HealthRoutes {
    /// The methods the method-less upstream pattern matches (NIO's standard method set).
    private static let probeMethods: [HTTPMethod] = [
        .GET, .HEAD, .POST, .PUT, .PATCH, .DELETE, .OPTIONS, .TRACE, .CONNECT,
    ]

    /// Registers the routes on the application.
    static func register(on application: Application) {
        for method in Self.probeMethods {
            application.on(method, "healthz") { _ in "OK" }
        }
    }
}
