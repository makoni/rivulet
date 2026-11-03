import Testing
@testable import RivuletCore

/// The two duplicate-name rules of the integration path.
///
/// The order is the reference's: `internal/ui/integration_update.go` at `c4d54f87` reads the Fever
/// check first and the Google Reader check after it, and each check is guarded by the name not
/// being empty. Both answers are handed in as values, because the storage layer answers them: a
/// rule that read the database could not be pinned as a rule, so `UserRepositoryTests` pins the
/// reads and `IntegrationCredentialsTests` pins the command that uses them.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the order, which
/// an input that would fail both rules names the rule the reference reaches first; each rule naming
/// its own case, which a patch that answered the other one fails; and the guard that an empty name
/// is not checked at all, which a patch that checked an empty name against the storage answer fails
/// — the pin gives one side an empty name with the storage answer true and the other side a name
/// with the answer true, so only the guard can change which rule the run reports.
///
/// What they cannot fail on: which column each read looks at, which is the storage layer's rule and
/// is pinned by `UserRepositoryTests`; the wordings the command prints for a rule, which are the
/// port's own; and the reference's own field order, which a web form reads in an order this port's
/// console path does not have.
@Suite struct IntegrationValidationTests {
    @Test func theChecksAreReadInTheReferenceOrder() throws {
        // An input that would fail both rules: the answer names the rule the reference reaches
          // first.
        #expect(IntegrationValidation.validate(feverUsername: "bob", feverNameIsDuplicate: true,
            googleReaderUsername: "bob", googleReaderNameIsDuplicate: true) == .duplicateFeverUsername,
            "the Fever check is read first upstream")

        #expect(IntegrationValidation.validate(feverUsername: "bob", feverNameIsDuplicate: false,
            googleReaderUsername: "bob", googleReaderNameIsDuplicate: true) ==
            .duplicateGoogleReaderUsername, "the Fever check is not the only one")
    }

    @Test func eachCheckNamesItsOwnRule() throws {
        #expect(IntegrationValidation.validate(feverUsername: "bob", feverNameIsDuplicate: true,
            googleReaderUsername: "carol", googleReaderNameIsDuplicate: false) ==
            .duplicateFeverUsername)
        #expect(IntegrationValidation.validate(feverUsername: "bob", feverNameIsDuplicate: false,
            googleReaderUsername: "carol", googleReaderNameIsDuplicate: true) ==
            .duplicateGoogleReaderUsername)
        #expect(IntegrationValidation.validate(feverUsername: "bob", feverNameIsDuplicate: false,
            googleReaderUsername: "carol", googleReaderNameIsDuplicate: false) == nil,
            "an input that fails neither rule reports nothing")
    }

    @Test func anEmptyNameIsNotChecked() throws {
        // The Fever side: an empty name with the storage answer true, the other side a name with
        // the answer true. Only the guard can change which rule this reports, so a patch that
        // checked an empty name against the answer would report the Fever rule here.
        #expect(IntegrationValidation.validate(feverUsername: "", feverNameIsDuplicate: true,
            googleReaderUsername: "carol", googleReaderNameIsDuplicate: true) ==
            .duplicateGoogleReaderUsername, "an empty name is not read against the storage answer")

        #expect(IntegrationValidation.validate(feverUsername: "bob", feverNameIsDuplicate: true,
            googleReaderUsername: "", googleReaderNameIsDuplicate: true) == .duplicateFeverUsername,
            "the guard on the other side")

        #expect(IntegrationValidation.validate(feverUsername: "", feverNameIsDuplicate: true,
            googleReaderUsername: "", googleReaderNameIsDuplicate: true) == nil,
            "two empty names report nothing")
    }
}
