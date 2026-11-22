// Ported from Miniflux internal/api/middleware.go (Apache-2.0); adapted for Swift/SQLite.

/// Which rule of the read answered for a request.
///
/// The names are the port's own, because upstream answers the same status for several of them: a
/// name with no row and a name whose stored hash does not match are the same 401 there, so the pins
/// read which branch fired rather than an answer a client could tell apart.
enum RestV1AuthRule: String, CaseIterable, Sendable {
    /// `parseBasicAuth` did not read the value — no `Authorization` name, or a value that is not
    /// the Basic form, which is what `authOK` says upstream.
    case noAuthorizationValue

    /// `validateBasicAuth`'s guard: an empty name or an empty password ends the read before the
    /// storage layer is read at all.
    case emptyNameOrPassword

    /// The password does not match the stored hash, which is what `CheckPassword` reports.
    case passwordMismatch

    /// The account read answered nothing for the name the compare ran on.
    case noUserRow

    /// The key read answered nothing for the value the token half read.
    case noApiKeyRow

    /// A read that fails, which the middleware answers with the JSON 500 shape. No input this suite
    /// can build triggers it, so the pins name it as not falsifiable.
    case apiKeyReadFailed

    /// The same answer for the account read.
    case userReadFailed
}
