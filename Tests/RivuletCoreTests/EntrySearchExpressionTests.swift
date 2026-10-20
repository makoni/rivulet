import Testing
@testable import RivuletCore

/// Translation of user search text into FTS5 `MATCH` expressions.
///
/// The integration suite (``EntrySearchTests``) pins the observable matching
/// behaviour; these unit tests pin the translation itself, which is the seam
/// that keeps FTS5 syntax out of user input.
@Suite struct EntrySearchExpressionTests {
    @Test func bareWordsBecomeQuotedTermsJoinedByAnd() {
        #expect(EntryQuery.ftsExpression(for: "swift vapor") == "\"swift\" AND \"vapor\"")
        #expect(EntryQuery.ftsExpression(for: "  swift \n vapor  ") == "\"swift\" AND \"vapor\"")
    }

    @Test func doubleQuotesGroupAPhrase() {
        #expect(
            EntryQuery.ftsExpression(for: "\"server side\" rendering")
                == "\"server side\" AND \"rendering\""
        )
        #expect(EntryQuery.ftsExpression(for: "\"server side\"") == "\"server side\"")
    }

    @Test func ftsSyntaxIsTreatedAsText() {
        #expect(
            EntryQuery.ftsExpression(for: "AND OR NOT NEAR -foo *")
                == "\"AND\" AND \"OR\" AND \"NOT\" AND \"NEAR\" AND \"-foo\" AND \"*\""
        )
    }

    @Test func inputWithoutSearchableTermsProducesNil() {
        #expect(EntryQuery.ftsExpression(for: "") == nil)
        #expect(EntryQuery.ftsExpression(for: "   ") == nil)
        #expect(EntryQuery.ftsExpression(for: "\"") == nil)
        #expect(EntryQuery.ftsExpression(for: "\"\"") == nil)
    }
}
