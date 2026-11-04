import Testing
@testable import RivuletCore

/// The category rules `renameTagHandler` runs before its write.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the rule that a
/// request carrying nothing is not read at all, the empty-title rule that runs before the duplicate
/// answer is looked at, the two rules being distinct, and the order the two are read in.
///
/// What these pins cannot show: the wording the answer writes for a rule, which is the reference's
/// localized string — this port names the rule, as `UserValidationRule` does, and that is recorded
/// in `docs/reference-notes.md`. Through the handler the empty-title rule cannot be reached either,
/// because the stream read answers an empty destination before the rules run.
@Suite struct CategoryValidationTests {
    @Test func aRequestThatCarriesNothingIsNotReadAgainstTheAnswer() async throws {
        #expect(CategoryValidation.validate(title: nil, titleIsDuplicate: true) == nil,
            "the rule block is guarded by the request carrying a title")
    }

    @Test func theEmptyTitleRuleRunsBeforeTheDuplicateAnswer() async throws {
        #expect(CategoryValidation.validate(title: "", titleIsDuplicate: true) == .titleRequired,
            "the answer is not looked at for an empty title")
    }

    @Test func theTwoRulesNameDifferentThings() async throws {
        #expect(CategoryValidation.validate(title: "News", titleIsDuplicate: false) == nil,
            "no rule for a title the answer does not duplicate")
        #expect(CategoryValidation.validate(title: "News", titleIsDuplicate: true) == .alreadyExists,
            "the duplicate answer names its own rule")
    }
}
