import Vapor

/// Liveness probe.
///
/// Ported from Miniflux `internal/http/server/healthcheck.go` (Apache-2.0); adapted for
/// Swift. Like upstream `/healthz`, this is a liveness probe: it answers `OK` whenever the
/// process serves requests and deliberately does not touch the database. (Upstream also has
/// a `/readiness` probe that pings the database; it arrives together with the client APIs.)
enum HealthRoutes {
    /// Registers the routes on the application.
    static func register(on application: Application) {
        application.get("healthz") { _ in "OK" }
    }
}
