import Foundation
import Testing
@testable import RivuletApp

/// The header block the auth read runs on: the name read as `textproto` canonicalizes it, the first
/// value of the name kept, and the pair `parseBasicAuth` reads from the value this read answers for
/// `Authorization`. The rules are pinned as pure logic, with no transport, so what the transport
/// writes for these answers — the status each one gets, the JSON error document, and the
/// `WWW-Authenticate` value the basic half writes before its guards — is the route half.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the name read
/// case-insensitively, which a patch that compared it as written fails on, and the first value of
/// the name being the one kept, which a patch that took the last fails on; that a name the request
/// does not carry answers the empty value, which a patch that answered something else fails on; the
/// prefix compared case-insensitively; the whole rest of the value being what is decoded; a
/// character outside the alphabet ending the read, which a patch that filtered such characters out
/// fails on; the pair split at the first colon; a decoded value with no colon not being read; a
/// value that does not end at a group boundary being read as this read's decoder reads it; and the
/// two newlines inside the value being skipped, which a patch that stopped filtering them fails on,
/// because this read's decoder refuses a value that carries one.
///
/// Two patches reach more than one pin: the patch for the name fires this suite's basic pin as
/// well, because the pair is read from the value this read answers for `Authorization`; and the
/// patch that answers something for a name the request does not carry fires its own line plus the
/// five `RestV1AuthTests` pins whose request reaches the basic half, because those requests carry
/// no `X-Auth-Token` and reach the pair through this read. Two patches fire the same line of the
/// basic pin — the one for the alphabet and the one for the trim — because both change how the
/// second space is read.
///
/// What they cannot fail on: the length guard for a value shorter than the prefix, which no patch
/// can show as an answer — taken away, the read traps on the short value before it can answer
/// anything, so the line that reads such a value as not read cannot flip; and the padding that is
/// not at the end of the value, which is an error on both sides, so no input tells the two readings
/// apart.
///
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

        // The value that does not end at a group boundary is read as this read's decoder reads it,
        // which is the port's own rule: the reference reports it as an error, which is the parity
        // row, so what this line can read is the pair the port answers.
        let partial = RestV1Headers(lines: [("Authorization", "Basic YWxpY2U6cGFz==")])
            .basicCredentials()
        #expect(partial.read && partial.name == "alice" && partial.password == "pas",
            "a last quantum of two characters is read here")

        // Padding that is not at the end is an error on both sides, so this pin can read only that
        // the read answers nothing: the two readings are not told apart by any input.
        #expect(!RestV1Headers(lines: [("Authorization", "Basic YWxpY2U6cGFz=cw==")])
            .basicCredentials().read, "padding not at the end")

        // The two newlines inside the value are the characters Go's decoder skips, and this read
        // skips them too: with the filter taken away the value is not in the alphabet and the pair
        // is not read, which is what this line can fail on.
        let newlines = RestV1Headers(lines: [("Authorization", "Basic YWxpY2U6cGFz\r\ncw==")])
            .basicCredentials()
        #expect(newlines.read && newlines.name == "alice" && newlines.password == "pass",
            "a CR and an LF inside the value are skipped")

        // The empty pair is read, which is what lets the guard read it as an empty value before the
        // storage layer is read at all.
        let empty = RestV1Headers(lines: [("Authorization", "Basic Og==")]).basicCredentials()
        #expect(empty.read && empty.name == "" && empty.password == "",
            "the read answers the empty pair; the guard is the half that decides what it means")
    }
}
