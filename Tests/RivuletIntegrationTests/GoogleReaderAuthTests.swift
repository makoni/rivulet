import Foundation
import SQLKit
import Testing
import Vapor
import RivuletApp
@testable import RivuletCore

/// The Google Reader auth path over a real socket: `internal/googlereader/middleware.go` and the
/// `clientLoginHandler` of `internal/googlereader/handler.go` at `c4d54f87`.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the login reads
/// the field names the reference reads (`Email`, `Passwd`, `output`), which a patch that read the
/// account name instead fails on; the text shape by default and JSON only when `output` says
/// `json`, which a patch that wrote JSON always fails on; the compare against the stored value,
/// which a patch that compared the submitted value as the stored value fails on, and the rule that
/// a stored value the compare cannot read answers the same as a mismatch, which a patch that
/// reported it as an error fails on; the guard that an empty field ends the login before the read,
/// shown with a row the right password would answer for; the token source chosen by method, which a
/// patch that read whichever side was present fails on; the merged form, where the body pair comes
/// before the query pair and the first pair on a side is the one read, where a multipart body is
/// not part of the form, where the media type is read as `mime.ParseMediaType` reads it, and where
/// a `+` is a space while `%2B` is the character; the two cases Go reports as an error for the
/// whole form, shown with a readable value in another pair; the header shape rules, each with an
/// input a wrong read answers differently, including the second field being split on exactly one
/// equals sign; the structure rule, which a patch that stopped at the first two parts fails on; and
/// the two 401 shapes, which differ between the login path and the protected path.
///
/// What these pins cannot fail on: the constant-time form of the compare, which the reference uses
/// (`crypto/subtle`); that a name the form does not carry and a name whose value is empty answer
/// the same, which is why the guards read the answer rather than the presence; that Go reports the
/// `;` error at the end of the read and keeps the pairs read before it; the half of the structure
/// rule that a value with one part is not the structure, which answers 401 for every input this
/// suite can build and is pinned by `GoogleReaderTokenTests`; the rule that a pair with no `=` is a
/// name with an empty value, which answers 401 for every input this suite can build and is stated
/// in the code comment; the reference's `SetLastLogin`, for which this port has no column, and its
/// two-row read, which is the same single row here; the login handler's own guard, which the
/// middleware answers before it; and the whole-token form of the compare, because the name part is
/// also what finds the row. The storage read these paths use is pinned by `ClientAuthTests`. The
/// tokens these pins hand to the routes come from the port's own derivation, so these pins read the
/// transport, the shapes and the compare, not the digest; the digest is pinned by
/// `GoogleReaderTokenTests` against the reference's output. The catch-all is answered only on its
/// exact path: the subpath match, the redirect the reference's mux writes when the request path has
/// no trailing slash, and the 405 for a method the pattern does not register are router behavior
/// that follows with the router piece, so nothing here sends a request that would show them.
@Suite struct GoogleReaderAuthTests {
    init() {
        TestLogging.bootstrapOnce()
    }

    private let storedHash = "$2a$10$hOrIpoEkDKAMFrOt2/k1yeyHBaZKOwK8zEg9JVchReOAtQZ5mEeFu"
    private let password = "secret"

    /// The catch-all pattern's exact path, as the reference registers it.
    private let catchAll = "/reader/api/0/"

    @Test func theLoginWritesTheThreeTextLinesAndReadsItsOwnFieldNames() async throws {
        try await withServedApp { storage, app, base in
            try await seed(storage, name: "userone", storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "userone", storedHash: storedHash)

            let response = try await login(app, base, fields: ["Email": "userone", "Passwd": password])
            #expect(response.status == .ok, "the login path answers 200")
            #expect(contentType(of: response) == "text/plain; charset=utf-8",
                "the reference writes the three lines as text")
            #expect(try body(of: response) == "SID=\(token)\nLSID=\(token)\nAuth=\(token)\n",
                "the three lines, each with the same value, and the trailing newline")

            // The field names are the reference's own: a patch that read the account name from
            // another field answers nothing here, because the guard ends the run before the read.
            let wrongNames = try await login(app, base, fields: ["EmailX": "userone", "Passwd": password])
            #expect(wrongNames.status == .unauthorized, "the login reads `Email` and `Passwd`")

            // The golden is the reference's own output for this join, so the value written in the
            // three lines is pinned end to end, not only against the port's own derivation.
            #expect(token == "userone/cb4f382fa4467e865dd77085df73ec241fc2c74b54adbff3b7df9aeed53ad4f1",
                "the reference's value for the same join")
        }
    }

    @Test func theTextShapeIsTheDefaultAndJSONOnlyWhenOutputAsksForIt() async throws {
        try await withServedApp { storage, app, base in
            try await seed(storage, name: "userone", storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "userone", storedHash: storedHash)

            let json = try await login(app, base,
                fields: ["Email": "userone", "Passwd": password, "output": "json"])
            #expect(contentType(of: json) == "application/json", "the reference switches shape")
            #expect(try body(of: json) ==
                "{\"SID\":\"\(token)\",\"LSID\":\"\(token)\",\"Auth\":\"\(token)\"}",
                "the three fields in the order the reference declares them")

            // Only the value `json` switches it: any other value keeps the text lines, so a patch
            // that read `output` as "anything not empty" fails here.
            let other = try await login(app, base,
                fields: ["Email": "userone", "Passwd": password, "output": "atom"])
            #expect(contentType(of: other) == "text/plain; charset=utf-8",
                "a value that is not `json` keeps the text shape")
            #expect(try body(of: other) == "SID=\(token)\nLSID=\(token)\nAuth=\(token)\n",
                "and the default is the text shape")
        }
    }

    @Test func theCompareReadsTheStoredHashNotTheSubmittedValue() async throws {
        try await withServedApp { storage, app, base in
            try await seed(storage, name: "userone", storedHash: storedHash)

            // The reference compares with bcrypt, so submitting the stored string itself is not a
            // match for it. A patch that compared the submitted value against the stored value as
            // read would answer 200 for this request.
            let asRead = try await login(app, base, fields: ["Email": "userone", "Passwd": storedHash])
            #expect(asRead.status == .unauthorized,
                "the stored value is not read as the submitted value")

            let compared = try await login(app, base, fields: ["Email": "userone", "Passwd": password])
            #expect(compared.status == .ok, "the compare is the bcrypt one")

            // For a name with no row the login answers the JSON shape, without the header the
            // protected path writes: the two 401 answers are different, and both are pinned.
            let noRow = try await login(app, base, fields: ["Email": "nobody", "Passwd": password])
            #expect(noRow.status == .unauthorized, "the read answers nothing")
            #expect(contentType(of: noRow) == "application/json", "the login answers JSON")
            #expect(noRow.headers.first(name: "X-Reader-Google-Bad-Token") == nil,
                "the login path does not write that header")
        }
    }

    @Test func aStoredValueTheCompareCannotReadAnswersTheSameAsAMismatch() async throws {
        try await withServedApp { storage, app, base in
            // A row whose stored value is not a bcrypt hash: upstream's compare reports that as an
            // error, and the handler answers unauthorized for any error, so the value being read as
            // it is written does not make the request pass. A patch that reported the error as a
            // server error answers 500 here.
            try await seed(storage, name: "plainrow", storedHash: "plain-text")

            let response = try await login(app, base, fields: ["Email": "plainrow", "Passwd": "plain-text"])
            #expect(response.status == .unauthorized, "the compare cannot read the stored value")
            #expect(try body(of: response) == "{\"error_message\":\"access unauthorized\"}",
                "the reference's error document")
        }
    }

    @Test func anEmptyFieldGuardRunsBeforeTheRead() async throws {
        try await withServedApp { storage, app, base in
            // A row whose integration name is the empty string, which is what upstream's form
            // writes for a blank field. This is what makes the guard falsifiable: a patch that ran
            // the read first would answer the login for this row, because the password is right for
            // it.
            try await seed(storage, name: "seed", storedHash: storedHash)
            try await seed(storage, name: "emptyrow", storedHash: storedHash, googleName: "")

            let emptyName = try await login(app, base, fields: ["Email": "", "Passwd": password])
            #expect(emptyName.status == .unauthorized,
                "the guard runs before the read: a patch that read first answered 200 here")
            #expect(try body(of: emptyName) == "{\"error_message\":\"access unauthorized\"}",
                "the reference's error document")

            let emptyPassword = try await login(app, base, fields: ["Email": "emptyrow", "Passwd": ""])
            #expect(emptyPassword.status == .unauthorized, "an empty password ends the login")

            // A name the form does not carry answers the same as an empty one, which is why the
            // guard reads the answer and not the presence — the pin for that rule is the answer
            // itself.
            let noField = try await login(app, base, fields: ["Passwd": password])
            #expect(noField.status == .unauthorized, "a name the form does not carry answers the same")
        }
    }

    @Test func theTokenSourceIsChosenByMethodNotByWhichSideIsPresent() async throws {
        try await withServedApp { storage, app, base in
            try await seed(storage, name: "userone", storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "userone", storedHash: storedHash)

            // GET reads the header, and the token endpoint writes the value as bare text.
            let byHeader = try await get(app, base, "/reader/api/0/token",
                header: "GoogleLogin auth=\(token)")
            #expect(byHeader.status == .ok, "the GET route reads the header")
            #expect(contentType(of: byHeader) == "text/plain; charset=utf-8",
                "the token endpoint writes bare text")
            #expect(try body(of: byHeader) == token, "the same value the login wrote")
            #expect(byHeader.headers.first(name: "X-Reader-Google-Bad-Token") == nil,
                "an authenticated request does not write the bad-token header")

            // The same value in the form field is not read on a GET.
            let formOnGet = try await get(app, base, "/reader/api/0/token?T=\(token)")
            #expect(formOnGet.status == .unauthorized, "the GET route does not read the form field")

            // POST reads the form field, and the shape is the catch-all answer.
            let byForm = try await formPost(app, base, catchAll, form: ["T": token])
            #expect(byForm.status == .ok, "the POST route reads the form field")
            #expect(try body(of: byForm) == "[]", "the unimplemented endpoint answers the empty list")
            #expect(contentType(of: byForm) == "application/json", "and answers it as JSON")

            // The header is not read on a POST, so a patch that read whichever side was present
            // fails on these two requests.
            let headerOnPost = try await formPost(app, base, catchAll, form: [:],
                header: "GoogleLogin auth=\(token)")
            #expect(headerOnPost.status == .unauthorized, "the POST route does not read the header")
            #expect(try body(of: headerOnPost) == "Unauthorized", "and answers the protected shape")
        }
    }

    @Test func thePostFormReadsTheBodyPairBeforeTheQueryPair() async throws {
        try await withServedApp { storage, app, base in
            try await seed(storage, name: "userone", storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "userone", storedHash: storedHash)
            let wellFormedButWrong =
                "userone/0000000000000000000000000000000000000000000000000000000000000000"

            // The query alone is part of the form for a POST, so a patch that read only the body
            // fails.
            let queryOnly = try await rawFormPost(app, base, catchAll, raw: "", query: "T=\(token)")
            #expect(queryOnly.status == .ok, "the query is part of the form for a POST")

            // Go copies the body pairs into `r.Form` before the query pairs, so the body value is
            // the one `Get` reads when both carry the name; a patch that preferred the query
            // answers nothing here.
            let both = try await rawFormPost(app, base, catchAll, raw: "T=\(wellFormedButWrong)",
                query: "T=\(token)")
            #expect(both.status == .unauthorized, "the body pair is the one read first")
            #expect(both.headers.first(name: "X-Reader-Google-Bad-Token") == "true",
                "and the answer is the protected shape")

            // Within one side the first pair with the name is the one `Get` reads; a patch that
            // took the last one answered 200 for this input.
            let firstPair = try await rawFormPost(app, base, catchAll,
                raw: "T=\(wellFormedButWrong)&T=\(token)", query: "")
            #expect(firstPair.status == .unauthorized, "the first pair on that side is the one read")
        }
    }

    @Test func theBodyIsPartOfTheFormOnlyWhenTheMediaTypeIsUrlencoded() async throws {
        try await withServedApp { storage, app, base in
            try await seed(storage, name: "userone", storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "userone", storedHash: storedHash)

            // `mime.ParseMediaType` reads the type with its parameters ignored, so a charset
            // parameter still makes the body part of the form.
            let withCharset = try await formPost(app, base, catchAll, form: ["T": token],
                contentType: "application/x-www-form-urlencoded; charset=UTF-8")
            #expect(withCharset.status == .ok, "the parameters are not part of the media type")

            // The type is compared lowercased, so the upper-case form still reads the body.
            let upperCase = try await formPost(app, base, catchAll, form: ["T": token],
                contentType: "application/X-WWW-FORM-URLENCODED")
            #expect(upperCase.status == .ok, "the media type is read as it is parsed, not as written")

            // A multipart body is not part of the form for `ParseForm`: a patch that read it
            // answers 200 for the same token.
            let multipart = try await rawFormPost(app, base, catchAll,
                raw: "--boundary\r\nContent-Disposition: form-data; name=\"T\"\r\n\r\n\(token)\r\n",
                contentType: "multipart/form-data; boundary=boundary")
            #expect(multipart.status == .unauthorized,
                "the reference does not read multipart parts here")

            // And a body whose media type is not a form is not read at all.
            let textBody = try await rawFormPost(app, base, catchAll, raw: "T=\(token)",
                contentType: "text/plain")
            #expect(textBody.status == .unauthorized, "a body that is not a form is not part of the form")
        }
    }

    @Test func aFormThisReadCannotParseEndsTheWholeRequest() async throws {
        try await withServedApp { storage, app, base in
            try await seed(storage, name: "userone", storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "userone", storedHash: storedHash)

            // Go reports a `;` as an error for the whole form, so a readable token in another pair
            // does not save the request: a patch that treated `;` as a pair separator answered 200
            // here.
            let semicolon = try await rawFormPost(app, base, catchAll,
                raw: "T=\(token)&x=;", query: "")
            #expect(semicolon.status == .unauthorized,
                "a semicolon is the error the read reports for the whole form")

            // The same for a `%` that is not a two-digit escape: the rule is the whole form
            // failing, not one pair being skipped, so a patch that skipped the bad pair answered
            // 200 here.
            let badEscape = try await rawFormPost(app, base, catchAll,
                raw: "T=\(token)&x=%zz", query: "")
            #expect(badEscape.status == .unauthorized,
                "a malformed escape is the error the read reports for the whole form")

            // And the login path answers its own shape for the same failure.
            let loginFailure = try await rawFormPost(app, base, "/accounts/ClientLogin",
                raw: "Email=userone&Passwd=secret&x=%zz", query: "")
            #expect(loginFailure.status == .unauthorized, "the login ends for the same failure")
            #expect(try body(of: loginFailure) == "{\"error_message\":\"access unauthorized\"}",
                "with the JSON shape, not the protected path's text")
        }
    }

    @Test func thePlusInAFormValueIsReadAsASpace() async throws {
        try await withServedApp { storage, app, base in
            // A row whose name carries the plus: the reference reads `+` as a space, so the name
            // the read gives is the one with the space, which matches no row. A patch that read `+`
            // as itself found this row and answered 200 for the same bytes.
            try await seed(storage, name: "plusrow", storedHash: storedHash, googleName: "a+b")
            let token = GoogleReaderToken.derive(username: "a+b", storedHash: storedHash)

            let response = try await rawFormPost(app, base, catchAll, raw: "T=\(token)", query: "")
            #expect(response.status == .unauthorized, "the plus is read as a space, so no row matches")

            // The percent form of the plus is the escape for the character itself, so it stays a
            // plus, which is the other half of the rule: this read decodes it and finds the row, so
            // a patch that read a space for `%2B` as well failed here.
            let escaped = try await rawFormPost(app, base, catchAll,
                raw: "T=\(token.replacingOccurrences(of: "+", with: "%2B"))", query: "")
            #expect(escaped.status == .ok, "a percent escape is the character, not a space")
        }
    }

    @Test func theHeaderShapeRulesAreReadFieldByField() async throws {
        try await withServedApp { storage, app, base in
            try await seed(storage, name: "userone", storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "userone", storedHash: storedHash)

            // Each rule has an input a wrong read answers differently, so each can fail on its own.
            #expect((try await get(app, base, "/reader/api/0/token",
                header: "Bearer \(token)")).status == .unauthorized,
                "the first field must be `GoogleLogin`, not just any scheme")
            #expect((try await get(app, base, "/reader/api/0/token",
                header: "GoogleLogin \(token)")).status == .unauthorized,
                "the second field must be `auth=<token>`, not the token on its own")
            #expect((try await get(app, base, "/reader/api/0/token",
                header: "GoogleLogin auth=\(token) extra")).status == .unauthorized,
                "the header is read as exactly two fields")

            // `strings.Fields` collapses the whitespace between the two fields, so the double space
            // still reads the token; a patch that split on single spaces would read three fields
            // and fail here.
            #expect((try await get(app, base, "/reader/api/0/token",
                header: "GoogleLogin  auth=\(token)")).status == .ok,
                "the two fields are read as `Fields` splits them")

            // The second field is split on one equals sign: Go's `strings.Split` gives three parts
            // for a value that carries another, so this ends the run even though the row the name
            // part finds is the one that would answer — a patch that split on the first equals sign
            // only answered 200.
            let nameWithEquals = GoogleReaderToken.derive(username: "a=b", storedHash: storedHash)
            try await seed(storage, name: "equalsrow", storedHash: storedHash, googleName: "a=b")
            #expect((try await get(app, base, "/reader/api/0/token",
                header: "GoogleLogin auth=\(nameWithEquals)")).status == .unauthorized,
                "the second field is split on exactly one equals sign")
        }
    }

    @Test func theStructureRuleReadsExactlyTwoParts() async throws {
        try await withServedApp { storage, app, base in
            try await seed(storage, name: "userone", storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "userone", storedHash: storedHash)

            // The same name with a third part is not the structure the reference reads: a patch
            // that stopped at the first two parts read this row's name and digest and answered 200
            // here. A value with one part answers 401 for every input this suite can build, so that
            // half of the rule is pinned by `GoogleReaderTokenTests` instead.
            #expect((try await get(app, base, "/reader/api/0/token",
                header: "GoogleLogin auth=\(token)/extra")).status == .unauthorized,
                "three parts are not the structure")
        }
    }

    @Test func theProtectedPathAnswersThePlainTextShapeWithTheBadTokenHeader() async throws {
        try await withServedApp { storage, app, base in
            try await seed(storage, name: "userone", storedHash: storedHash)

            // A well-formed token whose digest does not match: the compare is what ends the run.
            let wrongDigest =
                "userone/0000000000000000000000000000000000000000000000000000000000000000"
            let response = try await get(app, base, "/reader/api/0/token",
                header: "GoogleLogin auth=\(wrongDigest)")
            #expect(response.status == .unauthorized, "the compare is what ends the run")
            #expect(contentType(of: response) == "text/plain; charset=utf-8", "the shape is text")
            #expect(try body(of: response) == "Unauthorized", "with the reference's body")
            #expect(response.headers.first(name: "X-Reader-Google-Bad-Token") == "true",
                "and the header the reference writes")

            // The same shape for a name that matches no row, which is the storage read's answer.
            let noRow = try await get(app, base, "/reader/api/0/token",
                header: "GoogleLogin auth=nobody/" +
                    "0000000000000000000000000000000000000000000000000000000000000000")
            #expect(noRow.status == .unauthorized, "no row answers the same shape")
        }
    }

    // MARK: - Requests

    private func login(_ app: Application, _ base: String, fields: [String: String]) async throws
        -> ClientResponse {
        try await formPost(app, base, "/accounts/ClientLogin", form: fields)
    }

    private func get(_ app: Application, _ base: String, _ pathAndQuery: String,
        header: String? = nil) async throws -> ClientResponse {
        try await app.client.get(URI(string: base + pathAndQuery)) { request in
            if let header {
                request.headers.add(name: "Authorization", value: header)
            }
        }
    }

    private func formPost(_ app: Application, _ base: String, _ path: String, form: [String: String],
        contentType: String? = nil, header: String? = nil) async throws -> ClientResponse {
        try await rawFormPost(app, base, path, raw: form.map {
            "\($0.key)=\(escape($0.value))" }.joined(separator: "&"),
            contentType: contentType ?? "application/x-www-form-urlencoded", header: header)
    }

    /// Sends the body bytes exactly as they are given, so a rule about what the form read sees is
    /// shown by the bytes rather than by an encoding the client added.
    private func rawFormPost(_ app: Application, _ base: String, _ pathAndQuery: String, raw: String,
        query: String = "", contentType: String = "application/x-www-form-urlencoded",
        header: String? = nil) async throws -> ClientResponse {
        let path = pathAndQuery + (query.isEmpty ? "" : "?\(query)")
        let allocator = ByteBufferAllocator()
        return try await app.client.post(URI(string: base + path)) { request in
            request.headers.add(name: "Content-Type", value: contentType)
            if let header {
                request.headers.add(name: "Authorization", value: header)
            }
            request.body = allocator.buffer(string: raw)
        }
    }

    /// Percent-encoding for a form value, so a token with a slash in it reaches the handler as the
    /// reference reads it.
    private func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }

    private func body(of response: ClientResponse) throws -> String {
        let body = try #require(response.body)
        return String(decoding: body.readableBytesView, as: UTF8.self)
    }

    private func contentType(of response: ClientResponse) -> String {
        response.headers.first(name: "Content-Type") ?? ""
    }

    /// Seeds a row through SQL, as the other storage pins do: the account name is stored lowercase
    /// and the integration name as it is given.
    private func seed(_ storage: SQLiteStorage, name: String, storedHash: String,
        googleName: String? = nil) async throws {
        try await storage.withConnection { connection in
            let sql = try sqlDatabase(connection)
            try await sql.raw("""
                INSERT INTO users (username, password_hash, is_admin, google_reader_username,
                    google_reader_password_hash, created_at, updated_at)
                VALUES (\(bind: name), \(bind: "seed-hash"), \(bind: 0),
                    \(bind: googleName ?? name), \(bind: storedHash),
                    \(bind: 1_000_000_000), \(bind: 1_000_000_000))
                """).run()
        }
    }
}
