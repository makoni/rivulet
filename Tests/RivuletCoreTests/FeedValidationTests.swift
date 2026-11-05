import Testing
@testable import RivuletCore

/// The rules `rivulet add` fails on, ported from Miniflux `internal/validator/feed.go` at commit
/// `c4d54f87` (Apache-2.0). The three reads the rules consult are handed in as values, because the
/// storage layer answers them: `FeedManagementReadsTests` pins the duplicate read, and the command
/// that applies the order is pinned by `FeedCommandTests`.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the order the four
/// rules are applied in — the mandatory guard, then the absolute-URL rule, then the duplicate read,
/// then the category read — which a patch that put the duplicate read before the URL rule fails on
/// the input that fails both, and a patch that put the category read before the duplicate read
/// fails on the input that fails both; that the guard has two halves, so an input that is empty and
/// names no category answers the guard rather than either later rule; and that the guard reads the
/// category as a positive number, so `0` and a negative value answer it while the id the command
/// resolves for a named title does not.
///
/// What these pins cannot fail on: the locale wording the reference attaches to each rule, which
/// the port does not carry — these pins name the rule, and the words a command prints from it are
/// its own, while what `FeedCommandTests` reads is the rule name written; the reads themselves,
/// which reach this function as values; and the order the reference's discovery path applies the
/// last two rules in, which is the other way round and is recorded in `docs/reference-notes.md`.
@Suite struct FeedValidationTests {
    @Test func theRulesAreAppliedInThisOrder() {
        // Each input fails two rules, so the rule named is the one that runs first.
        #expect(FeedValidation.validate(url: "", categoryID: 1, urlIsAbsolute: false,
            feedURLExists: true, categoryExists: true) == .mandatoryFields,
            "the guard runs before the duplicate read")
        #expect(FeedValidation.validate(url: "", categoryID: 0, urlIsAbsolute: false,
            feedURLExists: true, categoryExists: false) == .mandatoryFields,
            "and before the category read")
        #expect(FeedValidation.validate(url: "example.com/feed.xml", categoryID: 1,
            urlIsAbsolute: false, feedURLExists: true, categoryExists: false) == .invalidURL,
            "the URL rule runs before the duplicate read")
        #expect(FeedValidation.validate(url: "https://example.com/feed.xml", categoryID: 1,
            urlIsAbsolute: true, feedURLExists: true, categoryExists: false) == .alreadyExists,
            "the duplicate read runs before the category read")
    }

    @Test func eachRuleIsNamedForTheInputThatFailsOnlyIt() {
        // One rule at a time, so a patch that dropped a rule would still answer the others.
        #expect(FeedValidation.validate(url: "", categoryID: 1, urlIsAbsolute: true,
            feedURLExists: false, categoryExists: true) == .mandatoryFields, "the empty url")
        #expect(FeedValidation.validate(url: "https://example.com/feed", categoryID: 0,
            urlIsAbsolute: true, feedURLExists: false, categoryExists: false) == .mandatoryFields,
            "and the category that is not a positive number")
        #expect(FeedValidation.validate(url: "https://example.com/feed", categoryID: -1,
            urlIsAbsolute: true, feedURLExists: false, categoryExists: false) == .mandatoryFields,
            "the same half read with a negative id, so the rule is not the zero test")
        #expect(FeedValidation.validate(url: "https://example.com/feed", categoryID: 1,
            urlIsAbsolute: false, feedURLExists: false, categoryExists: true) == .invalidURL,
            "the url that is not absolute")
        #expect(FeedValidation.validate(url: "https://example.com/feed", categoryID: 1,
            urlIsAbsolute: true, feedURLExists: true, categoryExists: true) == .alreadyExists,
            "the duplicate answer")
        #expect(FeedValidation.validate(url: "https://example.com/feed", categoryID: 1,
            urlIsAbsolute: true, feedURLExists: false, categoryExists: false) == .categoryNotFound,
            "the category the account has no row for")
        // The control: an input that fails none of the four answers nil.
        #expect(FeedValidation.validate(url: "https://example.com/feed", categoryID: 1,
            urlIsAbsolute: true, feedURLExists: false, categoryExists: true) == nil,
            "an input that fails no rule")
    }
}
