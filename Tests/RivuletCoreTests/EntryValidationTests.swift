import Testing
@testable import RivuletCore

/// The entry rules the listing and the write paths run before their reads and writes.
///
/// What these pins can fail on, each shown by patching the rule and reverting it: the two statuses the
/// status rule admits, the two columns the order rule admits, the two values the direction rule admits,
/// the three rules of the range block and the order they are read in, and the order between the first
/// two rules of the write block, read on an input that fails both.
///
/// What these pins cannot show: the wording the answer writes for a rule, which is the reference's plain
/// error — this port names the rule, as `CategoryValidationRule` does, and that is recorded in
/// `docs/reference-notes.md`; the reference's nine order names, which this port has no columns to order
/// by, so the pin reads the answer the port gives for one of them; the two rules of the range block
/// that read a negative value, which the query read answers the default for, so no request reaches them
/// with a negative input — they are pinned here as pure logic, where the values are reachable; and the
/// order between the either-field rule and the status rule, which no input can fail both, because the
/// first answers only for an empty status and the second only for a non-empty one.
@Suite struct EntryValidationTests {
    @Test func theStatusRuleAdmitsTheTwoStatusesTheReferenceAdmits() {
        #expect(EntryValidation.validate(status: "read") == nil, "the first status")
        #expect(EntryValidation.validate(status: "unread") == nil, "the second status")
        #expect(EntryValidation.validate(status: "archived") == .statusInvalid,
            "anything else fails the rule")
    }

    @Test func theOrderRuleAdmitsTheTwoColumnsThisPortOrdersBy() {
        #expect(EntryValidation.validate(order: "published_at") == nil, "the default order")
        #expect(EntryValidation.validate(order: "id") == nil, "the other column this port has")
        #expect(EntryValidation.validate(order: "title") == .orderInvalid,
            "a name the reference admits and this port has no column for")
    }

    @Test func theDirectionRuleAdmitsTheTwoValuesTheReferenceAdmits() {
        #expect(EntryValidation.validate(direction: "asc") == nil, "the default direction")
        #expect(EntryValidation.validate(direction: "desc") == nil, "the other value")
        #expect(EntryValidation.validate(direction: "sideways") == .directionInvalid,
            "anything else fails the rule")
    }

    @Test func theRangeBlockAnswersTheRuleTheInputFailsOnFirst() {
        #expect(EntryValidation.validate(offset: -1, limit: -1) == .offsetNegative,
            "the offset rule, read before the two limit rules")
        #expect(EntryValidation.validate(offset: 0, limit: -1) == .limitNegative,
            "the lower bound, read before the upper bound")
        #expect(EntryValidation.validate(offset: 0, limit: 1001) == .limitTooLarge,
            "the upper bound, read last: an input that fails both bounds answers the lower one")
        #expect(EntryValidation.validate(offset: 0, limit: 1000) == nil,
            "the maximum itself passes the block")
    }

    @Test func theWriteBlockAnswersTheRuleTheInputFailsOnFirst() {
        #expect(EntryValidation.validateStatusAndStarred(entryIDs: [], status: "", starred: nil)
            == .entryIDsEmpty, "the order, read on an input that fails the empty-list rule and the either-field rule")
        #expect(EntryValidation.validateStatusAndStarred(entryIDs: [], status: "bad", starred: nil)
            == .entryIDsEmpty, "the empty-list rule, for an input that fails only it")
        #expect(EntryValidation.validateStatusAndStarred(entryIDs: [1], status: "", starred: nil)
            == .statusOrStarredRequired, "the either-field rule, for an input that fails only it")
        #expect(EntryValidation.validateStatusAndStarred(entryIDs: [1], status: "bad", starred: nil)
            == .statusInvalid, "the status rule, for an input that fails only it")
        #expect(EntryValidation.validateStatusAndStarred(entryIDs: [1], status: "", starred: true) == nil,
            "a request that carries only the flag fails no rule")
    }
}
