import Testing
@testable import RivuletCore

/// The rules a user name and a password are checked against, ported from Miniflux
/// `internal/validator/user.go` at commit `c4d54f87` (Apache-2.0). Each pin names the rule an input
/// must fail on, so the rule it names is the rule the pin can fail on.
///
/// (ported tests: `TestValidateUsername`, `TestValidatePassword`,
/// `internal/validator/user_test.go`.)
///
/// What these pins can fail on, each checked by patching the rule and reverting: the order the
/// creation rules are applied in, which a patch that reads existence before the empty-name rule, or
/// the character class before the length rule, fails, because the input named then names a
/// different rule; the character class itself, which a patch that admits a character the
/// reference's class excludes fails; and the class being read per Unicode scalar, which a patch
/// reading grapheme clusters fails on the case that separates the two — a letter followed by a
/// combining mark is one cluster but two scalars, and the reference rejects the mark as a
/// non-letter rune; and the password length counted as bytes, which a patch counting characters
/// fails on the one case that can tell the two readings apart.
///
/// What they cannot fail on: the locale wording the reference attaches to each rule, which the port
/// does not carry — these pins name the rule, and the message a command prints from it is its own;
/// the trimming the command applies before these rules run, which is the command's step and is
/// pinned by `CreateAdminTests`; and the existence read itself, which reaches this function as a
/// value, so what is pinned here is only its position in the order, while the read is pinned where
/// the storage layer answers it (`UserRepositoryTests`) and where the command uses it
/// (`CreateAdminTests`).
@Suite struct UserValidationTests {
    @Test func theCreationRulesAreAppliedInTheReferenceOrder() {
        // The empty name is read first: an input that would fail two rules names the rule the
        // reference reaches first, so a patch that reads existence before emptiness fails this
        // line.
        #expect(UserValidation.validateCreation(username: "", password: "secret", userExists: true)
            == .mandatoryFields, "empty before existence")

        // Existence before the character class: an existing name that the class would also reject.
        #expect(UserValidation.validateCreation(username: "bad name", password: "secret",
            userExists: true) == .alreadyExists, "existence before the class")

        // The class before the length: an input that fails both.
        #expect(UserValidation.validateCreation(username: "bad name", password: "short",
            userExists: false) == .invalidUsername, "the class before the length")

        // Each rule alone, and the input that fails none.
        #expect(UserValidation.validateCreation(username: "alice", password: "short",
            userExists: false) == .passwordMinLength)
        #expect(UserValidation.validateCreation(username: "bad name", password: "secret",
            userExists: false) == .invalidUsername)
        #expect(UserValidation.validateCreation(username: "", password: "short",
            userExists: false) == .mandatoryFields)
        #expect(UserValidation.validateCreation(username: "alice", password: "secret",
            userExists: false) == nil, "an input that satisfies every rule names no rule")
    }

    @Test func theUsernameClassAdmitsLettersNumbersAndTheFourNamedCharacters() {
        for name in ["userone", "user.name", "user@example.com", "john_doe", "john-doe", "User123"] {
            #expect(UserValidation.validateUsername(name) == nil, "\(name)")
        }
        for name in ["invalid username", "user/path", "user🙂", "user\u{200B}"] {
            #expect(UserValidation.validateUsername(name) == .invalidUsername, "\(name)")
        }
    }

    @Test func theClassIsReadPerUnicodeScalarNotPerGraphemeCluster() {
        // One cluster, two scalars: the reference reads the combining mark as its own rune and
        // rejects the name. A check reading clusters would call the whole cluster a letter and
        // admit it, so this line is what pins which reading the port uses.
        #expect(UserValidation.validateUsername("cafe\u{0301}") == .invalidUsername)
        // The same sound written as one precomposed scalar is a letter and passes.
        #expect(UserValidation.validateUsername("caf\u{E9}") == nil)
        // Numbers outside the ASCII digits are numbers to the reference as well.
        #expect(UserValidation.validateUsername("\u{2081}") == nil, "circled digit one, category No")
    }

    @Test func thePasswordLengthIsCountedInBytesOnBothSides() {
        // `len(password)` in Go is a byte count, so these cases are read as bytes.
        #expect(UserValidation.validatePassword("") == .passwordMinLength)
        #expect(UserValidation.validatePassword("short") == .passwordMinLength)  // 5 bytes
        #expect(UserValidation.validatePassword("secret") == nil)                // 6 bytes
        #expect(UserValidation.validatePassword("longpass") == nil)              // 8 bytes

        // The case that tells the two readings apart: three characters, six bytes. A patch counting
        // characters names the length rule here, so this line is what shows the count is bytes.
        #expect(UserValidation.validatePassword("\u{0430}\u{0430}\u{0430}") == nil,
            "three Cyrillic letters are six bytes")

        // The side both readings agree on: three characters that are also three bytes.
        #expect(UserValidation.validatePassword("aaa") == .passwordMinLength)
    }
}
