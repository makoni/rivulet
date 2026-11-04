import Testing
@testable import RivuletApp

/// `json.Marshal`, as `internal/http/response.JSON` writes it. The goldens are the reference's own
/// output for the same documents at the toolchain `go.mod` pins.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the compact form
/// with no spaces, which a pretty-printing write fails on; the key order, which a write that sorted
/// the keys fails on — the document below is one where the two orders differ; the solidus written
/// as it is, which the standard Swift encoder escapes; the three HTML-sensitive characters and the
/// two line separators, which a write that left them as they are fails on; the three control
/// characters with their short forms, against the `\u00XX` form every other character below U+0020
/// gets; a valid replacement character written as it is; and the empty array written as `[]`, which
/// is what an empty slice gives rather than the `null` an unset one gives.
///
/// What these pins cannot fail on: the reference's case of an invalid byte becoming `\ufffd`,
/// because a Swift `String` cannot hold one — what is pinned is what the reference writes for a
/// valid replacement character, which is the only form this type can carry.
@Suite struct JSONValueTests {
    @Test func theDocumentIsWrittenCompactAndInDeclarationOrder() throws {
        let document = JSONValue.object([
            (key: "i", value: .integer(1000)),
            (key: "b", value: .boolean(true)),
            (key: "n", value: .null),
            (key: "s", value: .string("x")),
            (key: "a", value: .array([])),
        ])
        #expect(document.written() == "{\"i\":1000,\"b\":true,\"n\":null,\"s\":\"x\",\"a\":[]}",
            "the reference's output for the same document")
    }

    @Test func theKeyOrderIsTheOrderTheDocumentDeclaresThemIn() throws {
        // The two orders differ here, so a write that sorted the keys answers a different document.
        let document = JSONValue.object([(key: "zebra", value: .string("1")),
            (key: "apple", value: .string("2"))])
        #expect(document.written() == "{\"zebra\":\"1\",\"apple\":\"2\"}",
            "the order the reference's struct declares its fields in")
    }

    @Test func theSolidusIsWrittenAsItIs() throws {
        // The standard Swift encoder escapes this one, so a write that used it fails here.
        #expect(JSONValue.string("solidus/a").written() == "\"solidus/a\"",
            "the reference does not escape the solidus")
    }

    @Test func theQuoteAndTheBackslashAndTheHTMLClassAreEscaped() throws {
        #expect(JSONValue.string("a&b<c>d \"q\" \\ solidus/a").written() ==
            "\"a\\u0026b\\u003cc\\u003ed \\\"q\\\" \\\\ solidus/a\"",
            "the reference's output for the same string")
    }

    @Test func theThreeControlCharactersHaveTheirShortForms() {
        #expect(JSONValue.string("tab\t nl\n cr\r \u{0b} \u{01}").written() ==
            "\"tab\\t nl\\n cr\\r \\u000b \\u0001\"",
            "the three short forms against the escaped form the rest below U+0020 gets")
    }

    @Test func theLineSeparatorsAreEscaped() throws {
        #expect(JSONValue.string("\u{2028}\u{2029}").written() == "\"\\u2028\\u2029\"",
            "the reference writes them escaped, as it does the HTML class")
    }

    @Test func aValidReplacementCharacterIsWrittenAsItIs() throws {
        #expect(JSONValue.string("valid-FFFD-\u{FFFD}").written() == "\"valid-FFFD-\u{FFFD}\"",
            "the reference escapes only what it could not decode, which a Swift String cannot carry")
    }

    @Test func anEmptyArrayIsWrittenAsAnArrayAndAnEmptyObjectAsAnObject() throws {
        #expect(JSONValue.array([]).written() == "[]", "an empty slice, not the null an unset one gives")
        #expect(JSONValue.object([]).written() == "{}", "the empty object")
    }
}
