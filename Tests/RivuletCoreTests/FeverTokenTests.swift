import Testing
@testable import RivuletCore

/// The Fever `api_key` the reference derives: `internal/ui/integration_update.go` at `c4d54f87`
/// writes `fmt.Sprintf("%x", md5.Sum([]byte(fever_username + ":" + fever_password)))`. The goldens
/// below are that run's output, produced against the reference at the toolchain `go.mod` pins.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the two parts are
/// joined with the colon the reference joins them with, which a patch that drops the separator
/// fails — the value for `Fever1secret` is a different one; each part is used as read rather than
/// lowercased first, which a patch that lowercases either part before joining fails, because the
/// golden for `fever1:secret` differs from the one for `Fever1:secret` and the golden for
/// `userone:Secret` differs from the one for `userone:secret`; the digest is written as lowercase
/// hex, which a patch that writes it uppercase fails; and an empty part is still a part of the
/// join, which a patch that skips the empty password fails.
///
/// What they cannot fail on: the digest function itself — MD5 is the reference's choice, and a pin
/// can only read the value the same input produced upstream, which is what a golden is; that the
/// value is refreshed only when a password was supplied, which is the command's rule and is pinned
/// by `IntegrationCredentialsTests`; and the case-insensitive lookup the Fever router does with the
/// stored token, which arrives with that router.
@Suite struct FeverTokenTests {
    @Test func theTokenIsTheReferenceDigestOfTheJoin() throws {
        #expect(FeverToken.derive(username: "userone", password: "secret") ==
            "793454588f2d9b8298b1a4f8b5396e41", "the reference's output for the same join")

        // The separator. The reference joins the parts with a colon, so the value for the join
        // without it is a different string: `Fever1secret` gives 6b6fc7ae549fe59c0b560a4e2a736f77.
        #expect(FeverToken.derive(username: "Fever1", password: "secret") ==
            "71e9d7c8fd7d2b3dc94c3de389826bd8", "the join keeps the colon")
    }

    @Test func thePartsAreUsedAsReadNotLowercasedFirst() throws {
        // Upstream joins what the form submitted; only the printed digest is lowercased, so each
        // part keeps its own case.
        #expect(FeverToken.derive(username: "User123", password: "password1") ==
            "b2fa9fa5c101c56975f4181f885989e0", "the name as read")
        #expect(FeverToken.derive(username: "userone", password: "Secret") ==
            "d9f5f5a0f754db7b975106e22cb86178", "the password as read")
        #expect(FeverToken.derive(username: "Fever1", password: "secret") !=
            FeverToken.derive(username: "fever1", password: "secret"),
            "the two name forms are different values, so a patch that lowercases the name fails here")
        #expect(FeverToken.derive(username: "userone", password: "Secret") !=
            FeverToken.derive(username: "userone", password: "secret"),
            "the two password forms are different values, so a patch that lowercases it fails here")
    }

    @Test func theDigestIsWrittenAsLowercaseHex() throws {
        let token = FeverToken.derive(username: "bob", password: "newpass")
        #expect(token == "ca3c9f9982d0ecbb019392085546ad93", "the reference writes `%x`, lowercase")
        #expect(token.count == 32, "the hex form has 32 characters: \(token)")
        #expect(token == token.lowercased(), "no upper-case letter in the stored value: \(token)")
    }

    @Test func anEmptyPartIsStillPartOfTheJoin() throws {
        #expect(FeverToken.derive(username: "userone", password: "") ==
            "0f229a489c449d0c6a73fd62531f2f66", "the join of the name and an empty part")
        #expect(FeverToken.derive(username: "", password: "secret") ==
            "3fe1af802201354c73972b9492bb1069", "the join of an empty name and the password")
    }
}
