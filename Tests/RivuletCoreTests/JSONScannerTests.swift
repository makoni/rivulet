import Foundation
import Testing
@testable import RivuletCore

/// The token machine the JSON reader reads through. The reference has no corpus for this layer:
/// Miniflux reads a JSON feed through `encoding/json` (Go 1.26, the version `go.mod` pins), so
/// every case here is traced against that source — `scanner.go`, `decode.go` and `stream.go` — and
/// states the value the reference produces on the path its JSON adapter takes, `Decoder.Decode`.
@Suite struct JSONScannerTests {
    private func tokens(_ data: Data) throws -> [JSONToken] {
        var scanner = JSONScanner(data)
        var read: [JSONToken] = []
        while let token = try scanner.nextToken() { read.append(token) }
        return read
    }

    private func tokens(_ document: String) throws -> [JSONToken] {
        try tokens(Data(document.utf8))
    }

    // MARK: - Separators

    /// Traced against `isSpace`: the four ASCII bytes are the separators, so this is the stream the
    /// reference reads.
    @Test func theFourASCIIWhitespacesSeparateTokens() throws {
        #expect(try tokens("{\n\"a\" :\t1 ,\r\"b\": 2}") == [
            .objectStart, .key("a"), .valueSeparator, .value(.number(text: "1")), .memberSeparator,
            .key("b"), .valueSeparator, .value(.number(text: "2")), .objectEnd,
        ])
    }

    /// Traced: `isSpace` requires one of the four bytes rather than any byte below the printable
    /// range, so a NUL between tokens is content the machine cannot accept at that position.
    @Test func aControlByteBelowTheSeparatorSetIsNotASeparator() throws {
        #expect(throws: JSONError.unexpectedCharacter(character: 0x00,
            context: "looking for beginning of value")) {
            _ = try tokens("{\"a\":\u{0000}1}")
        }
    }

    /// Traced: `isSpace` is an ASCII test, so a byte above the ASCII range is not a separator. The
    /// reference fails here where a reader that folds Unicode whitespace would not.
    @Test func aNonASCIIWhitespaceIsNotASeparator() throws {
        #expect(throws: JSONError.unexpectedCharacter(character: 0xC2,
            context: "looking for beginning of value")) {
            _ = try tokens("{\"a\":\u{00a0}1}")
        }
    }

    // MARK: - Positions the grammar names

    /// Traced: `stateBeginString` is the state after `{` and after a `,`, so a key position
    /// requires a string.
    @Test func aKeyPositionRequiresAString() throws {
        #expect(throws: JSONError.unexpectedCharacter(character: 0x31,
            context: "looking for beginning of object key string")) {
            _ = try tokens("{1:2}")
        }
    }

    /// Traced: `stateEndValue` names the context of the position the parse state is in.
    @Test(arguments: [
        (0x31, "after object key", "{\"a\"1}"),
        (0x32, "after array element", "[1 2]"),
    ]) func theGrammarPositionsAreReportedAsGoReportsThem(character: UInt8, context: String,
        document: String) throws {
        #expect(throws: JSONError.unexpectedCharacter(character: character, context: context)) {
            _ = try tokens(document)
        }
    }

    /// Traced: a comma at the end of an object or an array leaves the machine in the position it
    /// started from, so the closing byte is read as a key or a value rather than as a terminator.
    @Test(arguments: [
        (0x7D, "looking for beginning of object key string", "{\"a\":1,}"),
        (0x5D, "looking for beginning of value", "[1,]"),
    ]) func aTrailingCommaIsNotTheEndOfAValue(character: UInt8, context: String, document: String) throws {
        #expect(throws: JSONError.unexpectedCharacter(character: character, context: context)) {
            _ = try tokens(document)
        }
    }

    // MARK: - Literals

    /// Traced: `stateInStringEsc` accepts exactly these eight bytes plus `u`, and `unquoteBytes`
    /// writes each of them.
    @Test(arguments: [
        ("\"\\/\"", "/"),
        ("\"\\b\"", "\u{0008}"),
        ("\"\\f\"", "\u{000C}"),
        ("\"\\n\"", "\n"),
        ("\"\\r\"", "\r"),
        ("\"\\t\"", "\t"),
        ("\"\\\"\"", "\""),
        ("\"\\\\\"", "\\"),
        ("\"\\u0000\"", "\u{0000}"),
    ]) func stringEscapeBytesWriteTheCharacterGoWrites(escape: String, expected: String) throws {
        #expect(try tokens(escape) == [.value(.string(expected))])
    }

    /// Traced: `stateInStringEsc` has no branch for a byte outside the eight, so the error names
    /// the escape code.
    @Test func anEscapeOutsideTheSetIsRejected() throws {
        #expect(throws: JSONError.unexpectedCharacter(character: 0x78, context: "in string escape code")) {
            _ = try tokens("\"\\x\"")
        }
    }

    /// Traced: `stateInStringEscU` needs four hex digits, so an escape that ends early fails at the
    /// byte that is not a digit.
    @Test func aHexEscapeNeedsFourHexDigits() throws {
        #expect(throws: JSONError.unexpectedCharacter(character: 0x7D,
            context: "in \\u hexadecimal character escape")) {
            _ = try tokens("\"\\u12}\"")
        }
    }

    /// Traced: `stateInString` errors on any byte below `0x20`, which is why a raw newline inside a
    /// string is rejected while the escape for it is not.
    @Test func controlBytesInsideAStringLiteralAreRejected() throws {
        #expect(throws: JSONError.unexpectedCharacter(character: 0x0A, context: "in string literal")) {
            _ = try tokens("{\"a\":\"b\nc\"}")
        }
    }

    /// Traced: `unquoteBytes` combines a surrogate pair and writes U+FFFD for one that is not
    /// paired.
    @Test(arguments: [("\"\\uD83D\\uDE00\"", "😀"), ("\"\\uD800\"", "\u{FFFD}")])
    func surrogatePairCombinesAndAnUnpairedOneBecomesTheReplacementCharacter(escape: String,
        expected: String) throws {
        #expect(try tokens(escape) == [.value(.string(expected))])
    }

    /// Traced: `unquoteBytes` coerces the bytes to well-formed UTF-8, which is the reference's
    /// documented rule for invalid UTF-8 inside a string. `utf8.DecodeRune` reports one bad byte at
    /// a time, so a two-byte sequence that is not a valid encoding writes two replacement
    /// characters.
    @Test func invalidUTF8InsideAStringBecomesTheReplacementCharacter() throws {
        let data = Data([0x22, 0x61, 0xC0, 0x80, 0x22])
        #expect(try tokens(data) == [.value(.string("a\u{FFFD}\u{FFFD}"))])
    }

    // MARK: - Numbers and words

    /// Traced: the scanner reports the literal as the bytes it read, which is what `Number` keeps
    /// and what the decoder converts per target type.
    @Test(arguments: ["1", "1e5", "-0", "0.5", "1E+3", "12345678901234567890"])
    func numberLiteralIsKeptAsWritten(text: String) throws {
        #expect(try tokens(text) == [.value(.number(text: text))])
    }

    /// Traced: the number states reject a second digit after a leading zero, a dot with no digit
    /// after it, an exponent with no digit, and a sign that is not the leading hyphen.
    @Test(arguments: [
        (0x31, "after object key:value pair", "{\"a\":01}"),
        (0x7D, "after decimal point in numeric literal", "{\"a\":1.}"),
        (0x7D, "in exponent of numeric literal", "{\"a\":1e}"),
        (0x2B, "looking for beginning of value", "{\"a\":+1}"),
        (0x7D, "in numeric literal", "{\"a\":-}"),
    ]) func numberLiteralShapesAreRejected(character: UInt8, context: String, document: String) throws {
        #expect(throws: JSONError.unexpectedCharacter(character: character, context: context)) {
            _ = try tokens(document)
        }
    }

    /// Traced: `stateT`, `stateF` and `stateN` walk the word byte by byte, so a word that ends
    /// early is rejected at the byte that breaks it.
    @Test(arguments: [
        (0x7D, "in literal true (expecting 'e')", "{\"a\":tru}"),
        (0x7D, "in literal false (expecting 'e')", "{\"a\":fals}"),
        (0x7D, "in literal null (expecting 'l')", "{\"a\":nul}"),
    ]) func literalWordsAreExact(character: UInt8, context: String, document: String) throws {
        #expect(throws: JSONError.unexpectedCharacter(character: character, context: context)) {
            _ = try tokens(document)
        }
    }

    @Test(arguments: [("true", JSONValue.boolean(true)), ("false", JSONValue.boolean(false)),
        ("null", JSONValue.null)])
    func literalWordsReadAsValues(word: String, expected: JSONValue) throws {
        #expect(try tokens(word) == [.value(expected)])
    }

    // MARK: - Where the machine stops

    /// Traced against `readValue` in `stream.go`: `Decode` reads one value and breaks at the first
    /// `scanEnd`, so nothing after the top-level value is examined — not even a byte the machine
    /// would have rejected there. For a container the byte that closes it is the machine's last
    /// token, because `readValue` tests `scanEnd` against an invented space rather than against the
    /// byte after it, while for a scalar the byte that ends the literal has to be read, because it
    /// is what decides whether the literal had ended. `stateEndTop` reports `scanEnd` for whatever
    /// that byte is, so the machine stops there without a failure; the failure that state records
    /// is what `checkValid` reports, which `docs/parity.md` records as a difference.
    @Test func theMachineReadsOnlyTheFirstTopLevelValue() throws {
        #expect(try tokens("{\"a\":1} garbage") == [
            .objectStart, .key("a"), .valueSeparator, .value(.number(text: "1")), .objectEnd,
        ])
        #expect(try tokens("[1]}garbage") == [.arrayStart, .value(.number(text: "1")), .arrayEnd])
        #expect(try tokens("1 2") == [.value(.number(text: "1"))])
        #expect(try tokens("1garbage") == [.value(.number(text: "1"))])
    }

    /// Traced: the failure is the one the position the machine is in names, so a byte inside the
    /// top-level value is reported before the byte that ends it.
    @Test func theFirstFailureIsTheOneReported() throws {
        #expect(throws: JSONError.unexpectedCharacter(character: 0x7D, context: "after array element")) {
            _ = try tokens("[1}garbage")
        }
    }

    // MARK: - End of input

    /// Traced against `readValue` in `stream.go`: input that ends while a value is open is the
    /// failure `readValue` returns, `io.ErrUnexpectedEOF`, and an empty document is `io.EOF`; the
    /// model reports both as one failure, `unexpectedEnd`. The invented space the reference pushes
    /// through the machine only decides whether to break, so the contexts the states name are what
    /// `checkValid` reports, not what `Decode` reports — `docs/parity.md` records that.
    @Test(arguments: ["", "[1", "{\"a\":1", "\"a", "\"\\", "\"\\u1", "[", "{",
        "{\"a\":-", "{\"a\":1.", "{\"a\":1e", "t"])
    func anUnterminatedValueIsAnError(document: String) throws {
        #expect(throws: JSONError.unexpectedEnd) { _ = try tokens(document) }
    }

    // MARK: - Depth

    /// Traced: `pushParseState` stops at the depth Go limits to, so a value nested one deeper is an
    /// error rather than a stack the machine walks.
    @Test func theDepthLimitIsTheOneGoLimitsTo() throws {
        let opens = String(repeating: "[", count: 10_000)
        let closes = String(repeating: "]", count: 10_000)
        let atTheLimit = opens + "1" + closes
        let tokensAtTheLimit = try tokens(atTheLimit)
        #expect(tokensAtTheLimit.count == 20_001)

        let deeper = String(repeating: "[", count: 10_001) + "1"
        #expect(throws: JSONError.maxDepthExceeded) { _ = try tokens(deeper) }
    }
}
