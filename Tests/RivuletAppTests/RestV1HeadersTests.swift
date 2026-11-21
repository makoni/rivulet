import Foundation
import Testing
@testable import RivuletApp

/// The header block as Go's `net/http` reads it for this path: `Header.Get` for one name, and
/// `Request.BasicAuth` for the value it reads at `Authorization` (Apache-2.0 reference behavior,
/// `parseBasicAuth`). The read is pinned here as pure logic; the half that uses it to decide which
/// answer a request gets is pinned by `RestV1AuthTests`, and the status and the `WWW-Authenticate`
/// value the transport writes for that answer belong to the route half.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the name being
/// read whatever case it comes in, which a patch that compared the name case-sensitively fails on;
/// the first value winning for a name the request carries twice, which a patch that took the last
/// value fails on, with the two cases of the same name counting as one name; a name the request
/// does not carry answering the empty value, which is what the guard reads; the prefix being
/// compared case-insensitively, which a patch that compared it as written fails on; a value shorter
/// than the prefix, which is not read; the whole rest after the prefix being the value read, so a
/// second space is part of it and fails the decode; a character the alphabet does not have, which
/// fails the read; a decoded value with no colon, which is not read; the pair being split at the
/// first colon; and the last quantum shorter than four characters being read as this read's decoder
/// reads it, which a patch that applied the reference's group-length rule fails on. The case patch
/// for the name fires the basic pin as well, because the basic half reads its value through the
/// same read; each other patch fires only the line it names.
///
/// What they cannot fail on: the reference's answer for the quantum rule this read has as the
/// port's own, recorded in `docs/parity.md` — a pin can read what this read answers for a last
/// quantum shorter than four characters, but the reference's answer for the same input is not data
/// this suite has; for a value whose padding is not at the end both sides answer nothing, so no
/// input tells the two readings apart; the canonical form of a name written with a lowercase letter
/// after a dash, which Go's `textproto` fixes and this read does not, and which changes nothing for
/// the two names this path reads; and the character set the decoded value is read as, which Go
/// reads as bytes and Swift as a String — an invalid UTF-8 sequence would be a value that matches
/// no stored name here, so the difference cannot be reached.
@Suite struct RestV1HeadersTests {
    @Test func theNameIsReadWhateverCaseItComesInAndTheFirstValueWins() {
        #expect(RestV1Headers(lines: [("X-Auth-Token", "first"), ("x-auth-token", "second")])
            .value(named: "X-Auth-Token") == "first",
            "the first value of the name, with the two cases counting as one name")
        #expect(RestV1Headers(lines: [("x-auth-token", "token-value")])
            .value(named: "X-Auth-Token") == "token-value", "the name read case-insensitively")
        #expect(RestV1Headers(lines: [("Authorization", "Basic Og==")])
            .value(named: "X-Auth-Token") == "", "a name the request does not carry")
    }

    @Test func theBasicReadFollowsGo() {
        // The prefix compared case-insensitively, as `ascii.EqualFold` reads it.
        let lower = RestV1Headers(lines: [("authorization", "basic YWxpY2U6cGFzcw==")])
            .basicCredentials()
        #expect(lower.read && lower.name == "alice" && lower.password == "pass",
            "the prefix is read whatever case it is written in")

        // The pair split at the first colon.
        let first = RestV1Headers(lines: [("Authorization", "Basic YWxpY2U6cGFzczo=")])
            .basicCredentials()
        #expect(first.read && first.name == "alice" && first.password == "pass:",
            "the first colon is the split")

        // The whole rest after the prefix is the value read, so a second space is part of it and
        // the alphabet does not have it.
        #expect(!RestV1Headers(lines: [("Authorization", "Basic  YWxpY2U6cGFzcw==")])
            .basicCredentials().read, "a second space is part of the value read")

        // A value shorter than the prefix, a value the decoder cannot read, and a decoded value
        // with no colon are each not read.
        #expect(!RestV1Headers(lines: [("Authorization", "Basic")]).basicCredentials().read,
            "shorter than the prefix")
        #expect(!RestV1Headers(lines: [("Authorization", "Basic YWxpY2U6cGFzcw!=")])
            .basicCredentials().read, "a character the alphabet does not have")
        #expect(!RestV1Headers(lines: [("Authorization", "Basic YWxpY2U=")])
            .basicCredentials().read, "no colon in the decoded value")

        // The last quantum shorter than four characters is read as this read's decoder reads it,
        // which is the port's own rule: the reference reports such a value as an error, which is
        // the parity row, so what the pin can read is the pair this read answers.
        let partial = RestV1Headers(lines: [("Authorization", "Basic YWxpY2U6cGFz==")])
            .basicCredentials()
        #expect(partial.read && partial.name == "alice" && partial.password == "pas",
            "a last quantum of two characters is read here")

        // Padding that is not at the end is an error on both sides, so this pin can read only that
        // the read answers nothing: the two readings are not told apart by any input.
        #expect(!RestV1Headers(lines: [("Authorization", "Basic YWxpY2U6cGFz=cw==")])
            .basicCredentials().read, "padding not at the end")

        // The empty pair is read, which is what lets the guard read it as an empty value before the
        // storage layer is read at all.
        let empty = RestV1Headers(lines: [("Authorization", "Basic Og==")]).basicCredentials()
        #expect(empty.read && empty.name == "" && empty.password == "",
            "the read answers the empty pair; the guard is the half that decides what it means")
    }
}
