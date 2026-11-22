// Ported from Miniflux internal/api/middleware.go (Apache-2.0); adapted for Swift/SQLite.

/// What the read answers for one request, before the transport turns it into a response.
///
/// The response shapes and the status each answer gets are pinned as pure logic by
/// `RestV1ResponseTests`; this is the decision the pins read as data.
enum RestV1AuthOutcome: Equatable, Sendable {
    /// The half read found the account, and the handler is given the row id, which is what
    /// `request.UserID` answers upstream.
    case authenticated(userID: Int)

    /// The request fails, with the rule it failed on.
    case unauthorized(rule: RestV1AuthRule)

    /// A read that fails, which upstream answers with the JSON 500 shape.
    case storageFailure(rule: RestV1AuthRule)
}
