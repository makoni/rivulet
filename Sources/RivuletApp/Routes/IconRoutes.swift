// Ported from Miniflux internal/ui/feed_icon.go (Apache-2.0); adapted for Swift/SQLite.

import Foundation
import RivuletCore
import Vapor

/// The public icon route: the answer one icon row gets.
///
/// Upstream keeps this path out of the auth read — `isStaticAssetRoute` answers true for the
/// `/feed-icon/` prefix — so the route is registered on the application without the wrapper
/// `GoogleReaderAuth` puts on the Google Reader routes, and a request that carries no token reaches
/// the handler. The reference registers the exact path with its own pattern; here the id segment is
/// part of the registration, which is what Vapor's router answers as the most specific match.
///
/// What the reference has and this port does not: `WithoutCompression` for a body that is not SVG,
/// because there is no compression middleware here, and the HTML shapes for a missing row and for a
/// storage failure, which are not this port's — it answers the shape its client APIs answer with,
/// and `docs/parity.md` records that. The `Vary` header the builder writes only above its
/// compression threshold cannot appear on an answer of this path.
enum IconRoutes {
    /// The bound `showFeedIcon` gives the builder: 72h, as the reference counts it.
    static let iconBound: TimeInterval = 72 * 3_600

    /// `ContentSecurityPolicyForUntrustedContent`, the policy the body callback writes for this
    /// answer.
    static let untrustedContentPolicy = "default-src 'none'; form-action 'none'; sandbox;"

    /// Registers the route on the application.
    static func register(on application: Application, storage: SQLiteStorage) {
        application.get("feed-icon", ":externalID") { request in
            let externalID = request.parameters.get("externalID") ?? ""
            let icon = try await storage.withConnection { connection in
                try await IconRepository(connection).fetch(externalID: externalID)
            }
            guard let icon else {
                return GoogleReaderResponse.notFound()
            }
            return Self.answer(for: request, icon: icon)
        }
    }

    /// `WithCaching`: the caching headers are written before the match read runs, which is what
    /// lets the match branch answer 304 with no body and without the headers the body callback
    /// writes.
    private static func answer(for request: Request, icon: Icon) -> Response {
        let etag = CachingRules.etag(icon.hash)
        var headers = GoogleReaderResponse.securityHeaders()
        headers.add(name: "ETag", value: etag)
        headers.add(name: "Cache-Control", value: CachingRules.cacheControl(iconBound))
        headers.add(name: "Expires", value: CachingRules.expires(now: Date.now, duration: iconBound))

        let incoming = request.headers.first(name: "If-None-Match") ?? ""
        if CachingRules.matchesNoneMatch(headerValue: incoming, etag: etag) {
            return Response(status: .notModified, headers: headers)
        }

        // The callback half, which runs only on the answer that carries a body.
        headers.add(name: "Content-Security-Policy", value: untrustedContentPolicy)
        headers.add(name: "Content-Type", value: icon.mimeType)
        return Response(status: .ok, headers: headers, body: Response.Body(data: icon.content))
    }
}
