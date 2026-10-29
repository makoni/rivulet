import Foundation
import Testing
@testable import RivuletCore

/// The tree the reader builds out of the tokens. The reference decodes the top-level value into
/// `map[string]any` (`objectInterface` in `decode.go`), which keeps no order and folds a repeated
/// key, so the order and the repeated key pins here describe our shape rather than the reference's;
/// the rule the adapters read through it — the last effective assignment wins — is pinned in the
/// adapter PR.
@Suite struct JSONReaderTests {
    private func read(_ document: String) throws -> JSONValue {
        try JSONReader.read(Data(document.utf8))
    }

    // MARK: - Order

    /// Our shape keeps the members as they appear in the document, which is what the field read
    /// walks; the reference's map has no order to keep.
    @Test func objectMembersStayInDocumentOrder() throws {
        let tree = try read(#"{"b":1,"a":2}"#)
        #expect(tree == .object(members: [
            JSONMember(key: "b", value: .number(text: "1")),
            JSONMember(key: "a", value: .number(text: "2")),
        ]))
    }

    /// A repeated key is not folded: the tree keeps both assignments in the order the document
    /// wrote them, which is where the last-wins rule the field read applies comes from.
    @Test func aRepeatedKeyStaysTwoMembersInOrder() throws {
        let tree = try read(#"{"a":1,"a":2}"#)
        #expect(tree == .object(members: [
            JSONMember(key: "a", value: .number(text: "1")),
            JSONMember(key: "a", value: .number(text: "2")),
        ]))
    }

    // MARK: - Keys

    /// Traced: the key is read by `d.string`, the same production that reads a string value, so an
    /// escape in a key is decoded rather than kept as the bytes the document wrote.
    @Test func aKeyIsDecodedThroughTheSameRulesAsAValue() throws {
        let tree = try read(#"{"a\nb":1}"#)
        #expect(tree == .object(members: [JSONMember(key: "a\nb", value: .number(text: "1"))]))
    }

    /// Traced: `unquote` coerces the bytes to well-formed UTF-8 on the key path as well, so a key
    /// that is not valid UTF-8 is the replacement character rather than the input bytes.
    @Test func invalidUTF8InAKeyIsTheReplacementCharacter() throws {
        let tree = try JSONReader.read(Data([0x7B, 0x22, 0x61, 0xC0, 0x80, 0x22, 0x3A, 0x31, 0x7D]))
        #expect(tree == .object(members: [JSONMember(key: "a\u{FFFD}\u{FFFD}", value: .number(text: "1"))]))
    }

    // MARK: - What the tree is

    /// Traced: `Decode` reads one top-level value and breaks at `scanEnd`, so the tree is that
    /// value and nothing after it is read — not even a byte the machine would have rejected there.
    /// The byte that ends a top-level scalar is read, because the machine cannot know the literal
    /// has ended until it sees a byte that cannot continue it.
    @Test func theTreeIsTheFirstTopLevelValue() throws {
        #expect(try read("1 garbage") == .number(text: "1"))
        #expect(try read("[1]}garbage") == .array(values: [.number(text: "1")]))
        #expect(try read(#"{"a":1}garbage"#) == .object(members: [
            JSONMember(key: "a", value: .number(text: "1")),
        ]))

        #expect(throws: JSONError.unexpectedCharacter(character: 0x67, context: "after top-level value")) {
            _ = try read("1garbage")
        }
    }

    /// Traced: the number keeps the literal as the scanner read it, because the conversion is per
    /// target type and belongs to the field read rather than to the tree.
    @Test func aNumberIsKeptAsWritten() throws {
        let tree = try read(#"{"a":1e5}"#)
        #expect(tree == .object(members: [JSONMember(key: "a", value: .number(text: "1e5"))]))
    }

    /// Traced: `null` is a value for `d.value`, so it is a member of the tree. The rule that a
    /// `null` leaves a string field as it was is the field read's, and is pinned in the adapter PR.
    @Test func nullIsAValueInTheTree() throws {
        #expect(try read("[null]") == .array(values: [.null]))
        #expect(try read(#"{"a":null}"#) == .object(members: [JSONMember(key: "a", value: .null)]))
    }

    /// Traced: `arrayInterface` returns an empty non-nil slice and `objectInterface` an empty
    /// non-nil map, so an empty container is a value rather than an error.
    @Test func anEmptyContainerIsAValue() throws {
        #expect(try read("{}") == .object(members: []))
        #expect(try read("[ ]") == .array(values: []))
    }

    /// Nesting is the tree one level at a time, with each level keeping its own order.
    @Test func nestingKeepsEachLevelInOrder() throws {
        let tree = try read(#"{"a":{"b":[1,{"c":true}]}}"#)
        let inner = JSONMember(key: "b", value: .array(values: [
            .number(text: "1"),
            .object(members: [JSONMember(key: "c", value: .boolean(true))]),
        ]))
        #expect(tree == .object(members: [JSONMember(key: "a", value: .object(members: [inner]))]))
    }

    // MARK: - Input the reference cannot read

    /// Traced: `Decode` on empty input fails with `io.EOF`, the only place the reference
    /// distinguishes an end of input from an incomplete value; our model reports both as one
    /// failure, which is recorded in `docs/parity.md`.
    @Test func emptyInputIsAnError() throws {
        #expect(throws: JSONError.unexpectedEnd) { _ = try JSONReader.read(Data()) }
    }

    /// A value that ends before it is closed is the same failure, at the point the reader stops.
    @Test func anIncompleteValueIsAnError() throws {
        #expect(throws: JSONError.unexpectedEnd) { _ = try read(#"{"a":1"#) }
        #expect(throws: JSONError.unexpectedEnd) { _ = try read(#"{"a":"b"#) }
    }
}
