import Foundation
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
/// reported it as an error fails on; the guard that an empty name ends the login before the read,
/// shown with a row the right password would answer for; the token source chosen by method, which a
/// patch that read whichever side was present fails on; the merged form, where the body pair comes
/// before the query pair and the first pair on a side is the one read, where a multipart body is
/// not part of the form, where the media type is read as `mime.ParseMediaType` reads it, and where
/// a `+` is a space while `%2B` is the character; the two pair-level errors Go reports for the
/// whole form, shown with a readable value in another pair; the header shape rules, each with an
/// input a wrong read answers differently, including the second field being split on exactly one
/// equals sign; the structure rule, which a patch that stopped at the first two parts fails on; the
/// two 401 shapes, which differ between the login path and the protected path; the three headers
/// the response builder writes on every response of this path, which a write that set only the
/// content type fails on; and the no-slash path, which reaches the same handler here, where the
/// reference's mux writes its redirect before the auth middleware — read as the handler's answer,
/// because the pin fails on a patch that reads the trailing slash and cannot read the redirect
/// itself, which Vapor's client follows.
///
/// What these pins cannot fail on: the constant-time form of the compare, which the reference uses
/// (`crypto/subtle`); that a name the form does not carry and a name whose value is empty answer
/// the same, which is why the guards read the answer rather than the presence, and the guard's
/// password half, which answers 401 for every input this suite can build because an empty password
/// matches no stored hash; that Go reports the `;` error at the end of the read and keeps the pairs
/// read before it; the half of the structure rule that a value with one part is not the structure,
/// which answers 401 for every input this suite can build and is pinned by
/// `GoogleReaderTokenTests`; the rule that a pair with no `=` is a name with an empty value, which
/// answers 401 for every input this suite can build and is stated in the code comment; the
/// builder's `Vary` header, which appears only above its compression threshold and none of these
/// bodies reach it; the reference's `SetLastLogin`, for which this port has no column, and its
/// two-row read, which is the same single row here; the token endpoint's own `IsAuthenticated`
/// guard, which the transport answers before it; and the whole-token form of the compare, because
/// the name part is also what finds the row. The storage read these paths use is pinned by
/// `ClientAuthTests`. The tokens these pins hand to the routes come from the port's own derivation,
/// so these pins read the transport, the shapes and the compare, not the digest; the digest is
/// pinned by `GoogleReaderTokenTests` against the reference's output. The subpath match and the 405
/// for a method the pattern does not register are the router's own behavior and follow with the
/// router piece, so nothing here sends a request for them.
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
            let requests = GoogleReaderRequests(app, base)
            try await requests.seed(storage, name: "userone", storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "userone", storedHash: storedHash)

            let response = try await requests.login(fields: ["Email": "userone", "Passwd": password])
            #expect(response.status == .ok, "the login path answers 200")
            #expect(requests.contentType(of: response) == "text/plain; charset=utf-8",
                "the reference writes the three lines as text")
            #expect(try requests.body(of: response) == "SID=\(token)\nLSID=\(token)\nAuth=\(token)\n",
                "the three lines, each with the same value, and the trailing newline")

            // The field names are the reference's own: a patch that read the account name from
            // another field answers nothing here, because the guard ends the run before the read.
            let wrongNames = try await requests.login(fields: ["EmailX": "userone", "Passwd": password])
            #expect(wrongNames.status == .unauthorized, "the login reads `Email` and `Passwd`")

            // The golden is the reference's own output for this join, so the value written in the
            // three lines is pinned end to end, not only against the port's own derivation.
            #expect(token == "userone/cb4f382fa4467e865dd77085df73ec241fc2c74b54adbff3b7df9aeed53ad4f1",
                "the reference's value for the same join")
        }
    }

    @Test func theTextShapeIsTheDefaultAndJSONOnlyWhenOutputAsksForIt() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            try await requests.seed(storage, name: "userone", storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "userone", storedHash: storedHash)

            let json = try await requests.login(
                fields: ["Email": "userone", "Passwd": password, "output": "json"])
            #expect(requests.contentType(of: json) == "application/json", "the reference switches shape")
            #expect(try requests.body(of: json) ==
                "{\"SID\":\"\(token)\",\"LSID\":\"\(token)\",\"Auth\":\"\(token)\"}",
                "the three fields in the order the reference declares them")

            // Only the value `json` switches it: any other value keeps the text lines, so a patch
            // that read `output` as "anything not empty" fails here.
            let other = try await requests.login(
                fields: ["Email": "userone", "Passwd": password, "output": "atom"])
            #expect(requests.contentType(of: other) == "text/plain; charset=utf-8",
                "a value that is not `json` keeps the text shape")
            #expect(try requests.body(of: other) == "SID=\(token)\nLSID=\(token)\nAuth=\(token)\n",
                "and the default is the text shape")
        }
    }

    @Test func theCompareReadsTheStoredHashNotTheSubmittedValue() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            try await requests.seed(storage, name: "userone", storedHash: storedHash)

            // The reference compares with bcrypt, so submitting the stored string itself is not a
            // match for it. A patch that compared the submitted value against the stored value as
            // read would answer 200 for this request.
            let asRead = try await requests.login(fields: ["Email": "userone", "Passwd": storedHash])
            #expect(asRead.status == .unauthorized,
                "the stored value is not read as the submitted value")

            let compared = try await requests.login(fields: ["Email": "userone", "Passwd": password])
            #expect(compared.status == .ok, "the compare is the bcrypt one")

            // For a name with no row the login answers the JSON shape, without the header the
            // protected path writes: the two 401 answers are different, and both are pinned.
            let noRow = try await requests.login(fields: ["Email": "nobody", "Passwd": password])
            #expect(noRow.status == .unauthorized, "the read answers nothing")
            #expect(requests.contentType(of: noRow) == "application/json", "the login answers JSON")
            #expect(noRow.headers.first(name: "X-Reader-Google-Bad-Token") == nil,
                "the login path does not write that header")
        }
    }

    @Test func aStoredValueTheCompareCannotReadAnswersTheSameAsAMismatch() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            // A row whose stored value is not a bcrypt hash: upstream's compare reports that as an
            // error, and the handler answers unauthorized for any error, so the value being read as
            // it is written does not make the request pass. A patch that reported the error as a
            // server error answers 500 here.
            try await requests.seed(storage, name: "plainrow", storedHash: "plain-text")

            let response = try await requests.login(fields: ["Email": "plainrow", "Passwd": "plain-text"])
            #expect(response.status == .unauthorized, "the compare cannot read the stored value")
            #expect(try requests.body(of: response) == "{\"error_message\":\"access unauthorized\"}",
                "the reference's error document")
        }
    }

    @Test func anEmptyFieldGuardRunsBeforeTheRead() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            // A row whose integration name is the empty string, which is what upstream's form
            // writes for a blank field. This is what makes the guard falsifiable: a patch that ran
            // the read first would answer the login for this row, because the password is right for
            // it.
            try await requests.seed(storage, name: "seed", storedHash: storedHash)
            try await requests.seed(storage, name: "emptyrow", storedHash: storedHash, googleName: "")

            let emptyName = try await requests.login(fields: ["Email": "", "Passwd": password])
            #expect(emptyName.status == .unauthorized,
                "the guard runs before the read: a patch that read first answered 200 here")
            #expect(try requests.body(of: emptyName) == "{\"error_message\":\"access unauthorized\"}",
                "the reference's error document")

            let emptyPassword = try await requests.login(fields: ["Email": "emptyrow", "Passwd": ""])
            #expect(emptyPassword.status == .unauthorized, "an empty password ends the login")

            // The password half of the guard has nothing to fail on: an empty password never
            // matches the compare, so a patch that dropped the guard answers 401 through the
            // compare for this request too. Only the name half is falsifiable, by the row above.

            // A name the form does not carry answers the same as an empty one, which is why the
            // guard reads the answer and not the presence — the pin for that rule is the answer
            // itself.
            let noField = try await requests.login(fields: ["Passwd": password])
            #expect(noField.status == .unauthorized, "a name the form does not carry answers the same")
        }
    }

    @Test func theTokenSourceIsChosenByMethodNotByWhichSideIsPresent() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            try await requests.seed(storage, name: "userone", storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "userone", storedHash: storedHash)

            // GET reads the header, and the token endpoint writes the value as bare text.
            let byHeader = try await requests.get("/reader/api/0/token",
                header: "GoogleLogin auth=\(token)")
            #expect(byHeader.status == .ok, "the GET route reads the header")
            #expect(requests.contentType(of: byHeader) == "text/plain; charset=utf-8",
                "the token endpoint writes bare text")
            #expect(try requests.body(of: byHeader) == token, "the same value the login wrote")
            #expect(byHeader.headers.first(name: "X-Reader-Google-Bad-Token") == nil,
                "an authenticated request does not write the bad-token header")

            // The same value in the form field is not read on a GET.
            let formOnGet = try await requests.get("/reader/api/0/token?T=\(token)")
            #expect(formOnGet.status == .unauthorized, "the GET route does not read the form field")

            // POST reads the form field, and the shape is the catch-all answer.
            let byForm = try await requests.post(catchAll, form: ["T": token])
            #expect(byForm.status == .ok, "the POST route reads the form field")
            #expect(try requests.body(of: byForm) == "[]", "the unimplemented endpoint answers the empty list")
            #expect(requests.contentType(of: byForm) == "application/json", "and answers it as JSON")

            // The header is not read on a POST, so a patch that read whichever side was present
            // fails on these two requests.
            let headerOnPost = try await requests.post(catchAll, form: [:],
                header: "GoogleLogin auth=\(token)")
            #expect(headerOnPost.status == .unauthorized, "the POST route does not read the header")
            #expect(try requests.body(of: headerOnPost) == "Unauthorized", "and answers the protected shape")
        }
    }

    @Test func thePostFormReadsTheBodyPairBeforeTheQueryPair() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            try await requests.seed(storage, name: "userone", storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "userone", storedHash: storedHash)
            let wellFormedButWrong =
                "userone/0000000000000000000000000000000000000000000000000000000000000000"

            // The query alone is part of the form for a POST, so a patch that read only the body
            // fails.
            let queryOnly = try await requests.post(catchAll, raw: "", query: "T=\(token)")
            #expect(queryOnly.status == .ok, "the query is part of the form for a POST")

            // Go copies the body pairs into `r.Form` before the query pairs, so the body value is
            // the one `Get` reads when both carry the name; a patch that preferred the query
            // answers nothing here.
            let both = try await requests.post(catchAll, raw: "T=\(wellFormedButWrong)",
                query: "T=\(token)")
            #expect(both.status == .unauthorized, "the body pair is the one read first")
            #expect(both.headers.first(name: "X-Reader-Google-Bad-Token") == "true",
                "and the answer is the protected shape")

            // Within one side the first pair with the name is the one `Get` reads; a patch that
            // took the last one answered 200 for this input.
            let firstPair = try await requests.post(catchAll,
                raw: "T=\(wellFormedButWrong)&T=\(token)", query: "")
            #expect(firstPair.status == .unauthorized, "the first pair on that side is the one read")
        }
    }

    @Test func theBodyIsPartOfTheFormOnlyWhenTheMediaTypeIsUrlencoded() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            try await requests.seed(storage, name: "userone", storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "userone", storedHash: storedHash)

            // `mime.ParseMediaType` reads the type with its parameters ignored, so a charset
            // parameter still makes the body part of the form.
            let withCharset = try await requests.post(catchAll, form: ["T": token],
                contentType: "application/x-www-form-urlencoded; charset=UTF-8")
            #expect(withCharset.status == .ok, "the parameters are not part of the media type")

            // The type is compared lowercased, so the upper-case form still reads the body.
            let upperCase = try await requests.post(catchAll, form: ["T": token],
                contentType: "application/X-WWW-FORM-URLENCODED")
            #expect(upperCase.status == .ok, "the media type is read as it is parsed, not as written")

            // A multipart body is not part of the form for `ParseForm`: a patch that read it
            // answers 200 for the same token.
            let multipart = try await requests.post(catchAll,
                raw: "--boundary\r\nContent-Disposition: form-data; name=\"T\"\r\n\r\n\(token)\r\n",
                contentType: "multipart/form-data; boundary=boundary")
            #expect(multipart.status == .unauthorized,
                "the reference does not read multipart parts here")

            // And a body whose media type is not a form is not read at all.
            let textBody = try await requests.post(catchAll, raw: "T=\(token)",
                contentType: "text/plain")
            #expect(textBody.status == .unauthorized, "a body that is not a form is not part of the form")
        }
    }

    @Test func aFormThisReadCannotParseEndsTheWholeRequest() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            try await requests.seed(storage, name: "userone", storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "userone", storedHash: storedHash)

            // Go reports a `;` as an error for the whole form, so a readable token in another pair
            // does not save the request: a patch that treated `;` as a pair separator answered 200
            // here.
            let semicolon = try await requests.post(catchAll,
                raw: "T=\(token)&x=;", query: "")
            #expect(semicolon.status == .unauthorized,
                "a semicolon is the error the read reports for the whole form")

            // The same for a `%` that is not a two-digit escape: the rule is the whole form
            // failing, not one pair being skipped, so a patch that skipped the bad pair answered
            // 200 here.
            let badEscape = try await requests.post(catchAll,
                raw: "T=\(token)&x=%zz", query: "")
            #expect(badEscape.status == .unauthorized,
                "a malformed escape is the error the read reports for the whole form")

            // And the login path answers its own shape for the same failure.
            let loginFailure = try await requests.post("/accounts/ClientLogin",
                raw: "Email=userone&Passwd=secret&x=%zz", query: "")
            #expect(loginFailure.status == .unauthorized, "the login ends for the same failure")
            #expect(try requests.body(of: loginFailure) == "{\"error_message\":\"access unauthorized\"}",
                "with the JSON shape, not the protected path's text")
        }
    }

    @Test func thePlusInAFormValueIsReadAsASpace() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            // A row whose name carries the plus: the reference reads `+` as a space, so the name
            // the read gives is the one with the space, which matches no row. A patch that read `+`
            // as itself found this row and answered 200 for the same bytes.
            try await requests.seed(storage, name: "plusrow", storedHash: storedHash, googleName: "a+b")
            let token = GoogleReaderToken.derive(username: "a+b", storedHash: storedHash)

            let response = try await requests.post(catchAll, raw: "T=\(token)", query: "")
            #expect(response.status == .unauthorized, "the plus is read as a space, so no row matches")

            // The percent form of the plus is the escape for the character itself, so it stays a
            // plus, which is the other half of the rule: this read decodes it and finds the row, so
            // a patch that read a space for `%2B` as well failed here.
            let escaped = try await requests.post(catchAll,
                raw: "T=\(token.replacingOccurrences(of: "+", with: "%2B"))", query: "")
            #expect(escaped.status == .ok, "a percent escape is the character, not a space")
        }
    }

    @Test func theHeaderShapeRulesAreReadFieldByField() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            try await requests.seed(storage, name: "userone", storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "userone", storedHash: storedHash)

            // Each rule has an input a wrong read answers differently, so each can fail on its own.
            #expect((try await requests.get("/reader/api/0/token",
                header: "Bearer \(token)")).status == .unauthorized,
                "the first field must be `GoogleLogin`, not just any scheme")
            #expect((try await requests.get("/reader/api/0/token",
                header: "GoogleLogin \(token)")).status == .unauthorized,
                "the second field must be `auth=<token>`, not the token on its own")
            #expect((try await requests.get("/reader/api/0/token",
                header: "GoogleLogin auth=\(token) extra")).status == .unauthorized,
                "the header is read as exactly two fields")

            // `strings.Fields` collapses the whitespace between the two fields, so the double space
            // still reads the token; a patch that split on single spaces would read three fields
            // and fail here.
            #expect((try await requests.get("/reader/api/0/token",
                header: "GoogleLogin  auth=\(token)")).status == .ok,
                "the two fields are read as `Fields` splits them")

            // The second field is split on one equals sign: Go's `strings.Split` gives three parts
            // for a value that carries another, so this ends the run even though the row the name
            // part finds is the one that would answer — a patch that split on the first equals sign
            // only answered 200.
            let nameWithEquals = GoogleReaderToken.derive(username: "a=b", storedHash: storedHash)
            try await requests.seed(storage, name: "equalsrow", storedHash: storedHash, googleName: "a=b")
            #expect((try await requests.get("/reader/api/0/token",
                header: "GoogleLogin auth=\(nameWithEquals)")).status == .unauthorized,
                "the second field is split on exactly one equals sign")
        }
    }

    @Test func theStructureRuleReadsExactlyTwoParts() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            try await requests.seed(storage, name: "userone", storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "userone", storedHash: storedHash)

            // The same name with a third part is not the structure the reference reads: a patch
            // that stopped at the first two parts read this row's name and digest and answered 200
            // here. A value with one part answers 401 for every input this suite can build, so that
            // half of the rule is pinned by `GoogleReaderTokenTests` instead.
            #expect((try await requests.get("/reader/api/0/token",
                header: "GoogleLogin auth=\(token)/extra")).status == .unauthorized,
                "three parts are not the structure")
        }
    }

    @Test func everyShapeOnThisPathCarriesTheThreeBuilderHeaders() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            try await requests.seed(storage, name: "userone", storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "userone", storedHash: storedHash)

            // `writeHeaders` writes these three on every response of this path, so each shape
            // carries them, including both 401 shapes. A patch that wrote only the content type
            // fails here.
            let shapes: [(Comment, ClientResponse)] = [
                ("the login text lines", try await requests.login(
                    fields: ["Email": "userone", "Passwd": password])),
                ("the login JSON document", try await requests.login(
                    fields: ["Email": "userone", "Passwd": password, "output": "json"])),
                ("the token endpoint", try await requests.get("/reader/api/0/token",
                    header: "GoogleLogin auth=\(token)")),
                ("the catch-all answer", try await requests.post(catchAll, form: ["T": token])),
                ("the protected 401", try await requests.get("/reader/api/0/token",
                    header: "GoogleLogin \(token)")),
                ("the login 401", try await requests.login(fields: ["Email": "nobody",
                    "Passwd": password])),
            ]
            for (shape, response) in shapes {
                #expect(response.headers.first(name: "X-Content-Type-Options") == "nosniff", shape)
                #expect(response.headers.first(name: "X-Frame-Options") == "DENY", shape)
                #expect(response.headers.first(name: "Referrer-Policy") == "no-referrer", shape)
            }
        }
    }

    @Test func theNoSlashPathAnswersTheCatchAllHereWhereTheReferenceRedirects() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            try await requests.seed(storage, name: "userone", storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: "userone", storedHash: storedHash)

            // The reference's mux reads the pattern as a subtree and writes a 307 for the path
            // without the trailing slash, before its auth middleware. This port's router has no
            // rule that distinguishes the trailing slash, so both paths answer the same handler,
            // which is the divergence `docs/parity.md` records. This pin fails on a patch that
            // reads the trailing slash, because that patch answers 404 for the path without one; it
            // cannot fail on a patch that writes the redirect itself, because Vapor's client
            // follows a redirect and reports the answer after the follow.
            let noSlash = try await requests.get("/reader/api/0", header: "GoogleLogin auth=\(token)")
            #expect(noSlash.status == .ok, "the no-slash path reaches the same handler")
            #expect(try requests.body(of: noSlash) == "[]", "and the same answer")

            // The same path unauthenticated answers the protected 401 here, where the reference
            // answers the redirect, because the reference's redirect happens before its middleware.
            // The same patch fails this half too.
            let unauthenticated = try await requests.get("/reader/api/0")
            #expect(unauthenticated.status == .unauthorized, "no redirect is written here")
            #expect(unauthenticated.headers.first(name: "Location") == nil,
                "and no location for one")
        }
    }

    @Test func theProtectedPathAnswersThePlainTextShapeWithTheBadTokenHeader() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            try await requests.seed(storage, name: "userone", storedHash: storedHash)

            // A well-formed token whose digest does not match: the compare is what ends the run.
            let wrongDigest =
                "userone/0000000000000000000000000000000000000000000000000000000000000000"
            let response = try await requests.get("/reader/api/0/token",
                header: "GoogleLogin auth=\(wrongDigest)")
            #expect(response.status == .unauthorized, "the compare is what ends the run")
            #expect(requests.contentType(of: response) == "text/plain; charset=utf-8", "the shape is text")
            #expect(try requests.body(of: response) == "Unauthorized", "with the reference's body")
            #expect(response.headers.first(name: "X-Reader-Google-Bad-Token") == "true",
                "and the header the reference writes")

            // The same shape for a name that matches no row, which is the storage read's answer.
            let noRow = try await requests.get("/reader/api/0/token",
                header: "GoogleLogin auth=nobody/" +
                    "0000000000000000000000000000000000000000000000000000000000000000")
            #expect(noRow.status == .unauthorized, "no row answers the same shape")
        }
    }
}
