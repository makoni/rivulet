import Testing
import Vapor
@testable import RivuletApp

/// The output read the handlers of this path apply — `checkOutputFormat`
/// (`internal/googlereader/handler.go` at `c4d54f87`) — and the wording the read reports. The
/// goldens are the reference's own output at the toolchain `go.mod` pins.
///
/// What these pins can fail on, each checked by patching the rule and reverting: which side is read
/// is decided by method, which a patch that read whichever side was present fails on — a GET with
/// the value in the body is not read, and a POST reads the merged form with the body pair before
/// the query pair; that POST reads through the form read while the query read skips a pair it
/// cannot parse, which a patch that used one read for both fails on the input that puts the
/// readable value in one pair and the failure in another; that only the value `json` passes, which
/// a patch that read "anything not empty" fails on `atom`; that the value is compared as read,
/// which a patch that trimmed it first fails on; and the wordings, including the escape the form
/// read names — the pair substring from the percent cut to three characters, which a patch that
/// named the whole pair fails on.
///
/// What these pins cannot fail on: which endpoints apply this check, which is the handler's choice
/// and lands with the handlers — the reference applies it to four endpoints and not to `user-info`
/// or the token endpoint, and nothing here can show a choice; the status the answer writes for this
/// error, which is the response builder's; and that Go writes the escape with `%q`, which is the
/// quoting divergence `docs/parity.md` already records — the pins read the cases where quoting
/// makes no difference.
@Suite struct GoogleReaderOutputTests {
    @Test func theMethodDecidesWhichSideIsRead() throws {
        // A POST reads the merged form, where the value for a name both sides carry is the body
        // one, so the readable value in the query does not save the request; a patch that preferred
        // the query answered `json` here and passed the check.
        #expect(checked(method: .POST, query: "output=json", body: "output=atom") ==
            "googlereader: only json output is supported", "the body pair is the one read first")

        // A GET does not read the body at all: a patch that read whichever side was present passed
        // the check for this request.
        #expect(checked(method: .GET, query: "", body: "output=json") ==
            "googlereader: only json output is supported", "the GET half reads the query")

        // The query is part of the form for a POST, so a patch that read only the body failed here.
        #expect(checked(method: .POST, query: "output=json", body: "") == nil,
            "the query is part of the form for a POST")
    }

    @Test func POSTReportsThePairErrorForTheWholeFormAndTheQueryReadSkipsIt() throws {
        // Go reports the `;` as an error for the whole form, so a readable value in another pair
        // does not save the request; for the query read the same pair is skipped and the answer for
        // the name is the default. A patch that used one read for both failed one of these two.
        #expect(checked(method: .POST, query: "output=;", body: "output=json") ==
            "invalid semicolon separator in query", "the whole form is what POST reports")
        #expect(checked(method: .GET, query: "output=;x=y") ==
            "googlereader: only json output is supported", "the pair the query read skips is not read")

        // The escape is the same pair-level rule on both reads, and the form read names the escape
        // as Go names it: the substring from the percent, cut to three characters. A patch that
        // named the whole pair, or that did not cut it, failed here.
        #expect(checked(method: .POST, query: "", body: "output=%zz") == "invalid URL escape \"%zz\"",
            "the escape the form read names")
        #expect(checked(method: .POST, query: "", body: "output=abc%zz") == "invalid URL escape \"%zz\"",
            "the substring starts at the percent, not at the pair")
        #expect(checked(method: .POST, query: "", body: "output=%zzz") == "invalid URL escape \"%zz\"",
            "and it is cut to three characters")
        #expect(checked(method: .POST, query: "", body: "output=%aXb") == "invalid URL escape \"%aX\"",
            "the cut is three characters whatever the characters are")
        #expect(checked(method: .POST, query: "", body: "output=%a") == "invalid URL escape \"%a\"",
            "a part shorter than the cut is named as it is")
        #expect(checked(method: .POST, query: "", body: "output=%") == "invalid URL escape \"%\"",
            "and a percent with nothing after it is named as the percent")
        #expect(checked(method: .GET, query: "output=%zz") ==
            "googlereader: only json output is supported", "and the query read skips that pair")
    }

    @Test func OnlyTheValueJSONPassesAndItIsComparedAsRead() throws {
        // The reference compares the value against `json`, so any other value — including one that
        // looks like an output format — is the error. A patch that read "anything not empty" failed
        // here.
        #expect(checked(method: .GET, query: "output=json", body: nil) == nil, "the value that passes")
        #expect(checked(method: .GET, query: "output=atom", body: nil) ==
            "googlereader: only json output is supported", "another value is the error")
        #expect(checked(method: .GET, query: "", body: nil) ==
            "googlereader: only json output is supported", "a name the query does not carry is the default")

        // The value is compared as the read gives it: a leading space is not the value, so a patch
        // that trimmed it first passed this request.
        #expect(checked(method: .POST, query: "", body: "output=%20json") ==
            "googlereader: only json output is supported", "the value is compared as it is read")

        // A `+` is the space the pair read gives, which is the other form of the same rule.
        #expect(checked(method: .POST, query: "", body: "output=atom+x") ==
            "googlereader: only json output is supported", "and the plus is the space the read gives")
    }

    /// What the read answers: nothing when the value passes, and the wording when it does not.
    private func checked(method: HTTPMethod, query: String, body: String? = nil) -> String? {
        do {
            try GoogleReaderOutput.check(method: method, query: query, body: body)
            return nil
        } catch {
            return String(describing: error)
        }
    }
}
