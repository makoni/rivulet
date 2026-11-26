// Ported from Miniflux internal/http/response and internal/api/middleware.go's CORS half
// (Apache-2.0); adapted for Swift/SQLite.

import Vapor

/// The answer this path writes for the read: the status each rule gets, the document it writes, and
/// the names this path adds, the three CORS names on every answer and `WWW-Authenticate` for a
/// request whose token value was empty.
///
/// The document builder and the three builder headers are `GoogleReaderResponse`, which is the
/// builder this path reads through rather than a shape of its own; the status mapping, the
/// `WWW-Authenticate` value and the CORS names are what this path adds. The pins read them through
/// `answer(for:headers:)`.
struct RestV1Response {
    /// `generateJSONError`, through the builder both client paths write documents with.
    static func errorDocument(_ message: String) -> JSONValue {
        GoogleReaderResponse.errorDocument(message)
    }

    /// `withCORSHeaders`: the three names the reference writes before the read runs, so the answer
    /// the read gives carries them. `Access-Control-Max-Age` belongs to the reference's OPTIONS
    /// branch, which stays in stage 9, so nothing here writes it.
    static func corsHeaders() -> HTTPHeaders {
        var headers = HTTPHeaders()
        headers.add(name: "Access-Control-Allow-Origin", value: "*")
        headers.add(name: "Access-Control-Allow-Methods", value: "GET, POST, PUT, DELETE, OPTIONS")
        headers.add(name: "Access-Control-Allow-Headers",
            value: "X-Auth-Token, Authorization, Content-Type, Accept")
        return headers
    }

    /// `validateBasicAuth`'s write, which runs after the check that the request is already
    /// authenticated and before that half's guards, so the name is on the answer for a request that
    /// passed the half too. Which half a request reaches is the guard the token value answers, so
    /// the write reads that guard.
    static func writesAuthenticateHeader(headers: RestV1Headers) -> Bool {
        headers.value(named: "X-Auth-Token").isEmpty
    }

    /// The status each rule gets, as `internal/http/response/json.go` answers it.
    static func status(for rule: RestV1AuthRule) -> HTTPStatus {
        rule.answersServerError ? .internalServerError : .unauthorized
    }

    /// The document each rule answers with: the reference's wording for a guard, and the rule name
    /// for a failure this port names.
    static func document(for rule: RestV1AuthRule) -> JSONValue {
        errorDocument(rule.answersServerError ? rule.rawValue : "access unauthorized")
    }

    /// An assembled answer for one rule.
    static func answer(for rule: RestV1AuthRule, headers: RestV1Headers) -> Response {
        Self.response(status: Self.status(for: rule), document: Self.document(for: rule),
            headers: headers)
    }

    /// `response.NoContent`: the builder writes the names every answer of this path carries and the
    /// three it writes for every answer, but no `Content-Type`, because the body is nothing.
    static func noContent(headers: RestV1Headers) -> Response {
        var responseHeaders = GoogleReaderResponse.securityHeaders()
        for line in corsHeaders() { responseHeaders.add(name: line.name, value: line.value) }
        if Self.writesAuthenticateHeader(headers: headers) {
            responseHeaders.add(name: "WWW-Authenticate", value: "Basic realm=\"Restricted\"")
        }
        return Response(status: .noContent, headers: responseHeaders)
    }

    /// An assembled answer, with the names every answer of this path carries.
    static func response(status: HTTPStatus, document: JSONValue,
        headers: RestV1Headers) -> Response {
        var responseHeaders = GoogleReaderResponse.securityHeaders()
        for line in corsHeaders() { responseHeaders.add(name: line.name, value: line.value) }
        if Self.writesAuthenticateHeader(headers: headers) {
            responseHeaders.add(name: "WWW-Authenticate", value: "Basic realm=\"Restricted\"")
        }
        responseHeaders.add(name: "Content-Type", value: "application/json")
        return Response(status: status, headers: responseHeaders,
            body: Response.Body(string: document.written()))
    }
}
