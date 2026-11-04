// Ported from Miniflux internal/http/response (Apache-2.0); adapted for Swift/SQLite.

import Vapor

/// The shapes this path writes, as the reference's response builder writes them.
///
/// The reference sets `Content-Type: application/json` with no charset and
/// `text/plain; charset=utf-8` for the text shapes, so both are written here rather than taken from
/// Vapor's default, which adds the charset to the JSON one. The document is written by `JSONValue`,
/// which is the reference's encoder rather than Swift's; the reference's error path for a document
/// it cannot encode has nothing to fail on here, because this type cannot hold a value its encoder
/// would refuse.
struct GoogleReaderResponse {
    /// `response.Text`: the body as text.
    static func text(_ body: String) -> Response {
        Self.make(status: .ok, contentType: "text/plain; charset=utf-8", body: body)
    }

    /// `response.JSON`.
    static func json(_ document: JSONValue, status: HTTPStatus = .ok) -> Response {
        Self.make(status: status, contentType: "application/json", body: document.written())
    }

    /// `generateJSONError`, the document the login path answers with.
    static func errorDocument(_ message: String) -> JSONValue {
        .object([(key: "error_message", value: .string(message))])
    }

    /// `response.JSONBadRequest`, the shape the handlers answer with for an input read error.
    static func badRequest(_ message: String) -> Response {
        Self.json(errorDocument(message), status: .badRequest)
    }

    /// `response.JSONServerError`, the shape the handlers answer with for a stream, tag, or storage
    /// read error.
    static func serverError(_ message: String) -> Response {
        Self.json(errorDocument(message), status: .internalServerError)
    }

    /// `response.JSONNotFound`, the shape the handler answers with when its storage read finds no
    /// row.
    static func notFound() -> Response {
        Self.json(errorDocument("resource not found"), status: .notFound)
    }

    /// `loginResponse`: the three fields in the order the reference declares them.
    static func loginDocument(_ token: String) -> JSONValue {
        .object([(key: "SID", value: .string(token)), (key: "LSID", value: .string(token)),
            (key: "Auth", value: .string(token))])
    }

    /// `sendUnauthorizedResponse`: the text shape with the header the auth path adds. The login
    /// path answers the JSON shape without that header, and `GoogleReaderAuthTests` pins the
    /// difference.
    static func unauthorizedText() -> Response {
        let response = Self.make(status: .unauthorized, contentType: "text/plain; charset=utf-8",
            body: "Unauthorized")
        response.headers.add(name: "X-Reader-Google-Bad-Token", value: "true")
        return response
    }

    /// `response.JSONUnauthorized`, the document the login path answers with.
    static func unauthorizedJSON() -> Response {
        Self.json(errorDocument("access unauthorized"), status: .unauthorized)
    }

    /// `writeHeaders`: the three headers the builder writes on every response of this path, plus
    /// the content type the caller chose. The builder's `Vary` header only appears above its
    /// compression threshold, which none of these bodies reach, so no pin can read it.
    private static func make(status: HTTPStatus, contentType: String, body: String) -> Response {
        var headers = HTTPHeaders()
        headers.add(name: "X-Content-Type-Options", value: "nosniff")
        headers.add(name: "X-Frame-Options", value: "DENY")
        headers.add(name: "Referrer-Policy", value: "no-referrer")
        headers.add(name: "Content-Type", value: contentType)
        return Response(status: status, headers: headers, body: Response.Body(string: body))
    }
}
