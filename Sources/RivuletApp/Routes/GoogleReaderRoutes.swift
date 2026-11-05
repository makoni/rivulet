// Ported from Miniflux internal/googlereader/handler.go (Apache-2.0); adapted for Swift/SQLite.

import RivuletCore
import Vapor

/// The routes this path answers on: `ClientLogin`, the token endpoint, and the catch-all answer for
/// an endpoint the reference has not implemented.
public enum GoogleReaderRoutes {
    /// Registers the routes on the application.
    ///
    /// `GoogleReaderAuth` is the wrapper the reference's mux puts on every route of this path
    /// except `ClientLogin`, so it is applied per route rather than as application middleware that
    /// would cover `/healthz` too.
    public static func register(on application: Application, storage: SQLiteStorage,
        hasher: BcryptHasher) {
        let auth = GoogleReaderAuth(storage: storage)
        let handlers = GoogleReaderHandlers(storage: storage)

        application.post("accounts", "ClientLogin") { request in
            try await Self.clientLogin(request, auth: auth, hasher: hasher)
        }

        let protected = application.grouped("reader", "api", "0")

        // `tokenHandler` writes the value the transport read gave, as bare text. Its own
        // `IsAuthenticated` guard is the answer the auth path already gives, so it is not repeated
        // here.
        protected.get("token", use: auth.withAuth { _, _, token in
            GoogleReaderResponse.text(token)
        })

        // The reference registers the exact paths it implements before its subtree pattern, so the
        // most specific pattern wins. The handler names the endpoints this piece implements.
        protected.post("edit-tag", use: auth.withAuth { request, userID, _ in
            try await handlers.editTag(form: try auth.form(for: request), userID: userID)
        })
        protected.post("rename-tag", use: auth.withAuth { request, userID, _ in
            try await handlers.renameTag(form: try auth.form(for: request), userID: userID)
        })
        protected.post("disable-tag", use: auth.withAuth { request, userID, _ in
            try await handlers.disableTag(form: try auth.form(for: request), userID: userID)
        })
        protected.get("tag", "list", use: auth.withAuth { request, userID, _ in
            try await handlers.tagList(query: request.url.query ?? "", userID: userID)
        })
        protected.get("user-info", use: auth.withAuth { _, userID, _ in
            try await handlers.userInfo(userID: userID)
        })
        protected.get("stream", "items", "ids", use: auth.withAuth { request, userID, _ in
            try await handlers.streamItemIDs(query: request.url.query ?? "", userID: userID)
        })
        protected.post("mark-all-as-read", use: auth.withAuth { request, userID, _ in
            try await handlers.markAllAsRead(form: try auth.form(for: request), userID: userID)
        })

        // The catch-all answer for an endpoint that is not implemented. The exact path is matched
        // on its own, and the subpath match is what the reference's subtree pattern answers for, as
        // `docs/parity.md` records.
        protected.on(.GET, "**", use: auth.withAuth { _, _, _ in GoogleReaderResponse.json(.array([])) })
        protected.on(.POST, "**", use: auth.withAuth { _, _, _ in GoogleReaderResponse.json(.array([])) })
        protected.on(.GET, use: auth.withAuth { _, _, _ in GoogleReaderResponse.json(.array([])) })
        protected.on(.POST, use: auth.withAuth { _, _, _ in GoogleReaderResponse.json(.array([])) })
    }

    // MARK: - Handlers

    /// `clientLoginHandler`: the fields are read from the form, and an empty one ends the run
    /// before the read — which `GoogleReaderAuthTests` shows with a row whose name is the empty
    /// string.
    private static func clientLogin(_ request: Request, auth: GoogleReaderAuth, hasher: BcryptHasher)
        async throws -> Response {
        let form: GoogleReaderForm
        do {
            form = try auth.form(for: request)
        } catch {
            return GoogleReaderResponse.unauthorizedJSON()
        }

        let name = form.value(named: "Email")
        let password = form.value(named: "Passwd")
        guard !name.isEmpty, !password.isEmpty else {
            return GoogleReaderResponse.unauthorizedJSON()
        }

        let storedUser = try await auth.storedUser(name: name)
        guard let storedHash = storedUser?.googleReaderPasswordHash else {
            return GoogleReaderResponse.unauthorizedJSON()
        }

        // Upstream reports any failure of the compare as an error and the handler answers
        // unauthorized for any error, so a stored value the compare cannot read answers the same
        // here rather than reaching the error path.
        guard (try? hasher.verify(password, hash: storedHash)) ?? false else {
            return GoogleReaderResponse.unauthorizedJSON()
        }

        // The name in the token is the stored value, which for this path is the name that was read.
        let token = GoogleReaderToken.derive(username: name, storedHash: storedHash)
        guard form.value(named: "output") == "json" else {
            return GoogleReaderResponse.text(Self.loginLines(token))
        }
        return GoogleReaderResponse.json(GoogleReaderResponse.loginDocument(token))
    }

    /// `loginResponse.String()`: the three lines, each ending with its own newline.
    private static func loginLines(_ token: String) -> String {
        "SID=\(token)\nLSID=\(token)\nAuth=\(token)\n"
    }
}
