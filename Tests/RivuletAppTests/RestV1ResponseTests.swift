import Testing
import Vapor
@testable import RivuletApp

/// The answer this path writes for the read, pinned as pure logic: the status each rule gets, the
/// document it writes, and the names the transport adds. The status mapping is what
/// `internal/http/response/json.go` at `c4d54f87` answers for the guards and for a read that fails,
/// and the document builder is `GoogleReaderResponse`, which `GoogleReaderResponseStatusTests`
/// pins.
///
/// What these pins can fail on, each shown by patching the rule and reverting it, with the pin and
/// the assertion each patch fired on: the status each rule gets, which a patch that answered every
/// guard as 400 and a patch that answered the storage failure as 401 fire here; the document being
/// the same builder the Google Reader path pins, which a patch that replaced the builder with a
/// shape of its own fires here on all three of its assertions, and the wording being the
/// reference's for a guard and the rule name for a failure this port names, which a patch that
/// wrote the rule name for both fires here on the two wording assertions; the patch that classified
/// the storage rules as the guard shape fires here and on the status pin, being the only patch this
/// round saw reach two pins; the rule that decides whether `WWW-Authenticate` is written, whose
/// three halves are three patches: the one that wrote the name for every request fired the
/// assertion for a request carrying a value and the one that reads the assembled answer, the one
/// that wrote it for none fired the two assertions for requests carrying nothing, and the one that
/// wrote it only for a 401 answer fired the assembled answer alone, being the only half of the rule
/// that cannot be read through the rule itself, since the rule is given the headers and not the
/// answer; the three CORS names, each shown by a patch that dropped that one name and fired on its
/// own assertion, and by a patch that wrote `Access-Control-Max-Age` on every answer, which fired
/// on the assertion that reads its absence; the three names the builder writes, which a patch that
/// replaced them with a write setting only its content type fired on the three name assertions, and
/// which the content type itself is shown by a patch that wrote the framework's charset. Fifteen
/// patches reached this suite: fourteen fired, one of them on two pins, and one fired nothing — the
/// patch that changed the realm, which is the value no pin here reads.
///
/// What these pins cannot fail on: the value of `WWW-Authenticate`, which the patch that changed
/// the realm altered here without any pin firing, because these pins read the rule that decides
/// whether the name is written and not what it carries; the reference's wording for a storage
/// failure, which is the text of the error the read reports and which this suite cannot trigger;
/// the `Vary` name the reference's builder writes only above its compression threshold, which no
/// body here reaches; and the 404 answer for a row the read does not find, which no request this
/// suite sends reaches.
@Suite struct RestV1ResponseTests {
    @Test func theStatusEachRuleGets() {
        for rule in guardRules {
            #expect(RestV1Response.status(for: rule) == .unauthorized,
                "the reference answers 401 for every guard of this read")
        }

        for rule in storageRules {
            #expect(RestV1Response.status(for: rule) == .internalServerError,
                "the reference answers 500 for a read that fails")
        }
    }

    @Test func theDocumentIsTheSharedBuilderAndKeepsTheReferenceWording() {
        #expect(RestV1Response.document(for: .noApiKeyRow).written() ==
            "{\"error_message\":\"access unauthorized\"}",
            "a guard answer writes the reference's wording, not the rule it names")

        // The port has no error object to write for a read that fails, so the answer is the rule
        // name, as the category rules are recorded in `docs/parity.md`.
        #expect(RestV1Response.document(for: .apiKeyReadFailed).written() ==
            "{\"error_message\":\"apiKeyReadFailed\"}",
            "the port's own wording for a failure it names")

        #expect(RestV1Response.errorDocument("x").written() ==
            GoogleReaderResponse.errorDocument("x").written(),
            "the same builder, not a shape of its own")
    }

    @Test func theAuthenticateHeaderIsWrittenForEveryRequestWhoseTokenValueWasEmpty() {
        // The reference writes the name after the check that the request is already authenticated
        // and before that half's guards, so the answer a request that passed that half carries it
        // too. Which half a request reaches is the guard the token value answers, so the write
        // reads that guard.
        #expect(RestV1Response.writesAuthenticateHeader(headers: RestV1Headers(lines: [])),
            "no token value, so the basic half ran")
        #expect(RestV1Response.writesAuthenticateHeader(
            headers: RestV1Headers(lines: [("X-Auth-Token", "")])),
            "the value is empty, so the basic half ran")
        #expect(!RestV1Response.writesAuthenticateHeader(
            headers: RestV1Headers(lines: [("X-Auth-Token", "a-key")])),
            "the key half answered, and it writes nothing")
        let keyed = RestV1Headers(lines: [("X-Auth-Token", "a-key")])
        #expect(RestV1Response.answer(for: .noUserRow, headers: keyed)
            .headers.first(name: "WWW-Authenticate") == nil,
            "the write rule reads the token value, so a request carrying one gets nothing")
    }

    @Test func corsNamesAreCarriedByTheAnswerTheReadGives() {
        let response = RestV1Response.answer(for: .noAuthorizationValue,
            headers: RestV1Headers(lines: []))
        #expect(response.headers.first(name: "Access-Control-Allow-Origin") == "*",
            "the origin name, read on its own")
        #expect(response.headers.first(name: "Access-Control-Allow-Methods") ==
            "GET, POST, PUT, DELETE, OPTIONS",
            "the methods name, read on its own")
        #expect(response.headers.first(name: "Access-Control-Allow-Headers") ==
            "X-Auth-Token, Authorization, Content-Type, Accept",
            "the headers name, read on its own")
        #expect(response.headers.first(name: "Access-Control-Max-Age") == nil,
            "the reference writes that name only on its OPTIONS branch, which stays in stage 9")
    }

    @Test func theBuilderHeadersStayOnEveryAnswer() {
        for response in [RestV1Response.answer(for: .noUserRow, headers: RestV1Headers(lines: [])),
            RestV1Response.answer(for: .apiKeyReadFailed, headers: RestV1Headers(lines: []))] {
            #expect(response.headers.first(name: "X-Content-Type-Options") == "nosniff",
                "the first of the three names the builder writes on every answer")
            #expect(response.headers.first(name: "X-Frame-Options") == "DENY",
                "the second of the three names the builder writes")
            #expect(response.headers.first(name: "Referrer-Policy") == "no-referrer",
                "the third of the three names the builder writes")
            #expect(response.headers.first(name: "Content-Type") == "application/json",
                "the value the reference's JSON builder writes with no charset")
        }
    }

    // MARK: - The rules, named here rather than read through the answer

    /// The guards, which answer 401.
    private let guardRules: [RestV1AuthRule] = [.noAuthorizationValue, .emptyNameOrPassword,
        .passwordMismatch, .noUserRow, .noApiKeyRow]

    /// The rules the read answers when its storage layer fails, which answer 500.
    private let storageRules: [RestV1AuthRule] = [.apiKeyReadFailed, .userReadFailed]
}
