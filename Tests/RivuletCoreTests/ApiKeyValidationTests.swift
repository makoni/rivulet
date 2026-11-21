import Testing
@testable import RivuletCore

/// The two rules the reference's api-key validator has, pinned as pure logic over the values the
/// storage layer would have answered, so the read itself is not part of these pins.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the order, which a
/// patch that reads the duplicate answer before the empty rule fails on the input that fails both;
/// each rule alone; that the rule set has no character class, which a patch that reused the
/// user-name class fails on, and no length rule, which a patch that reused the password minimum
/// fails on. The length patch fires only the pin it names. The class patch is a rule added to the
/// same function, so it fires this pin and the order pin on the lines that read each rule alone,
/// because the input that fails the added rule reports the added rule, and the three command pins
/// whose description the added class rejects: the row, the printed value and the account. The
/// command pin that reads the flag gating the migrations names a rule this patch cannot reach,
/// because that pin reads the schema the run leaves rather than the run's outcome.
///
/// What they cannot fail on: the locale wording the reference attaches to each rule, which the port
/// does not carry — the two keys are recorded in `docs/reference-notes.md` — and the duplicate read
/// itself, which reaches this function as a value and is pinned by `ApiKeyRepositoryTests`,
/// including its per-user half and its single-row limit, which no patch can tell from a read that
/// fetched every match and so is stated in the repository comment.
///
@Suite struct ApiKeyValidationTests {
    @Test func theCreationRulesAreAppliedInTheReferenceOrder() {
        // The empty description is read first: an input that would fail both rules names the rule
        // the reference reaches first, so a patch that reads the duplicate answer before emptiness
        // fails this line.
        #expect(ApiKeyValidation.validateCreation(description: "", descriptionExists: true)
            == .mandatoryFields, "empty before the duplicate read")

        // Each rule alone.
        #expect(ApiKeyValidation.validateCreation(description: "phone app", descriptionExists: true)
            == .alreadyExists)
        #expect(ApiKeyValidation.validateCreation(description: "", descriptionExists: false)
            == .mandatoryFields)
        #expect(ApiKeyValidation.validateCreation(description: "phone app", descriptionExists: false)
            == nil, "an input that fails neither rule names no rule")
    }

    @Test func theRuleSetHasNoCharacterClassAndNoLengthRule() {
        // The reference's api-key validator has exactly two rules, which is what these inputs read:
        // a description the user-name class would reject and one shorter than the password minimum
        // both pass, so a patch that applied either of the user rules reports them.
        for description in ["phone app", "reader\u{200B}", "a", "\u{1F4F1}"] {
            #expect(ApiKeyValidation.validateCreation(description: description,
                descriptionExists: false) == nil, "\(description)")
        }
    }
}
