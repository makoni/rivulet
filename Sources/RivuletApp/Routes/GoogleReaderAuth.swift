// Ported from Miniflux internal/googlereader/middleware.go (Apache-2.0); adapted for Swift/SQLite.

import RivuletCore
import Vapor

/// The transport the protected Google Reader routes read — `serveValidated` upstream.
///
/// Which side the token comes from is decided by method, exactly as the reference reads it: POST
/// reads the `T` field of the merged form, every other method reads the `Authorization` header as
/// Go's `strings.Fields` splits it. The value is then read as `name/hash`, the row is found by the
/// name part — compared as read, which `ClientAuthTests` pins — and the whole token is compared
/// with the value that same row derives. A request that fails any of these rules answers the text
/// 401 shape with `X-Reader-Google-Bad-Token: true`, which is not the JSON shape `ClientLogin`
/// answers with.
///
/// What the suite names as not falsifiable is named in `GoogleReaderAuthTests`: the constant-time
/// form of the compare, the rule that a name the form does not carry answers the same as an empty
/// value, and the login guard's password half, which has nothing to fail on because an empty
/// password matches no stored hash.
struct GoogleReaderAuth: Sendable {
    private let storage: SQLiteStorage

    init(storage: SQLiteStorage) {
        self.storage = storage
    }

    /// `withApiKeyAuth`: the wrapper the reference's mux puts on every route of this path, which is
    /// why it is applied per route here rather than as application middleware that would cover
    /// `/healthz`.
    func withAuth(_ handler: @Sendable @escaping (Request, String) async throws -> Response)
        -> @Sendable (Request) async throws -> Response {
        { request in
            let token: String?
            do {
                token = try self.token(for: request)
            } catch {
                // A form this read cannot parse ends the request, as upstream reports the error for
                // the whole form, so a readable value in another pair does not save the request.
                return GoogleReaderResponse.unauthorizedText()
            }

            guard let token, let name = GoogleReaderToken.name(ofToken: token) else {
                return GoogleReaderResponse.unauthorizedText()
            }
            guard let storedHash = try await self.storedHash(name: name) else {
                return GoogleReaderResponse.unauthorizedText()
            }

            // Upstream compares against the token the stored name and the stored value build; here
            // the stored name is the one the read matched, so it is the same value.
            let expected = GoogleReaderToken.derive(username: name, storedHash: storedHash)
            guard GoogleReaderToken.matches(expected: expected, given: token) else {
                return GoogleReaderResponse.unauthorizedText()
            }

            return try await handler(request, token)
        }
    }

    /// The merged form for this request, as Go's `ParseForm` builds it. The body is part of the
    /// form only for the methods Go reads a body for — this path reads it on the POST half — and
    /// only when the media type is `application/x-www-form-urlencoded`, read with its parameters
    /// ignored as Go's `mime.ParseMediaType` does, which `GoogleReaderAuthTests` pins with a
    /// charset parameter and with the type written in upper case. `ClientLogin` reads its fields
    /// through this same read.
    func form(for request: Request) throws -> GoogleReaderForm {
        let body = request.headers.contentType == .urlEncodedForm ? request.body.string : nil
        return try GoogleReaderForm(query: request.url.query, body: body)
    }

    // MARK: - Rules

    /// Which side the token comes from, chosen by method. The empty form value ends the run for
    /// POST as the reference's own guard does; for the header path an empty value is caught by the
    /// structure rule instead, which is why the two paths read the answer differently.
    private func token(for request: Request) throws -> String? {
        if request.method == .POST {
            let value = try form(for: request).value(named: "T")
            return value.isEmpty ? nil : value
        }
        return Self.headerToken(request.headers.first(name: "Authorization"))
    }

    /// `strings.Fields` on the header, which collapses the whitespace between the fields: exactly
    /// two fields, the first `GoogleLogin`, the second `auth=<token>`, split on one equals sign
    /// with the empty part kept.
    private static func headerToken(_ header: String?) -> String? {
        guard let header, !header.isEmpty else { return nil }
        let fields = header.split(whereSeparator: \.isWhitespace)
        guard fields.count == 2, fields.first == "GoogleLogin" else { return nil }
        let parts = fields[1].split(separator: "=", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.first == "auth" else { return nil }
        return String(parts[1])
    }

    /// The stored hash for the row the name part finds. Upstream reads the integration row and then
    /// the user row by id; here that is one row, and the answer for no row is the rule
    /// `ClientAuthTests` pins. `ClientLogin` reads the same row for the same name.
    func storedHash(name: String) async throws -> String? {
        try await storage.withConnection { connection in
            try await UserRepository(connection).googleReaderPasswordHash(username: name)
        }
    }
}
