// Ported from Miniflux internal/fever/middleware.go (Apache-2.0); adapted for Swift/SQLite.

import RivuletCore
import Vapor

/// The transport this path reads — `Middleware` upstream.
///
/// The key is read through the merged form, which is what `r.FormValue` reads, whatever the method
/// is; the header this path's sibling reads is not read here. The read has no error half, and that
/// is the rule the answer follows from: `FormValue` discards what `ParseMultipartForm` reports, so
/// a body this read cannot read answers the empty value, the guard sees nothing, and the answer is
/// the failure document at 200 rather than the shape the sibling path answers for a form it
/// cannot parse.
///
/// What this read does not have: the `fever_enabled` gate and the `SetLastLogin` write the
/// reference makes after the read passes, because this port has no column for either, so neither
/// has anything to pin; the compare is the stored value as read, not a constant-time one; and the
/// single row the lookup reads is stated in ``UserRepository/userByFeverToken(_:)``.
struct FeverAuth: Sendable {
    private let storage: SQLiteStorage

    init(storage: SQLiteStorage) {
        self.storage = storage
    }

    /// The wrapper the reference's mux puts on this route. The handler is given the row id the read
    /// found, which is what `request.UserID` answers for it, and the form the read built, so the
    /// mark names are answered by the same read the key was.
    func withAuth(_ handler: @Sendable @escaping (Request, Int, FeverForm) async throws -> Response)
        -> @Sendable (Request) async throws -> Response {
        { request in
            let form = self.form(for: request)
            let key = form.value(named: "api_key")
            guard !key.isEmpty else { return Self.failure() }

            do {
                let user = try await self.storedUser(token: key)
                guard let user, let userID = user.id else { return Self.failure() }
                return try await handler(request, userID, form)
            } catch {
                // Upstream answers the same failure document for a read that fails, so the guard
                // and the failure have one answer here; nothing in these pins can trigger the
                // failing half.
                return Self.failure()
            }
        }
    }

    /// The merged form for this request, as `ParseForm` and `ParseMultipartForm` build it: the
    /// method decides whether an urlencoded body is part of the form, and the content type decides
    /// whether the body is a multipart one.
    func form(for request: Request) -> FeverForm {
        FeverForm(method: request.method.rawValue,
            contentType: request.headers.first(name: "Content-Type"),
            query: request.url.query, body: request.body.string)
    }

    /// The row the key finds, compared lowercase on both sides as the reference's lookup does. The
    /// `fever_enabled` half of that statement has no column here, so it is not a branch this
    /// read has.
    func storedUser(token: String) async throws -> User? {
        try await storage.withConnection { connection in
            try await UserRepository(connection).userByFeverToken(token)
        }
    }

    /// The answer for a run this read failed: the failure document, which is not the common-value
    /// document, at HTTP 200.
    private static func failure() -> Response {
        GoogleReaderResponse.json(FeverShape.authFailure())
    }
}
