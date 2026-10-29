import Foundation
import Testing
@testable import RivuletCore

/// The field read the JSON Feed adapter reads through: the shapes `json.go` declares, filled by the
/// walk `d.object` does over the members the tree keeps. Each case states the value the reference
/// produces, because the reference has no code for this layer of its own.
///
/// Three rules are the field read's rather than the machine's: a value is read against the type the
/// field is, which is where `UnmarshalTypeError` comes from; `null` assigns nothing to a string or
/// an int64 field, while it sets a collection to empty; and a key the document writes twice is the
/// two members the tree kept, so the last assignment the field's type accepts is the one the shape
/// holds.
@Suite struct JSONFieldReadTests {
    private func feed(_ document: String) throws -> JSONFieldRead.Feed {
        try JSONFieldRead.read(Data(document.utf8))
    }

    private func item(_ document: String) throws -> JSONFieldRead.Item {
        try #require(feed("{\"items\": [ \(document) ]}").items.first)
    }

    private func author(_ document: String) throws -> JSONFieldRead.Author {
        try feed("{\"author\": \(document)}").author
    }

    private func attachment(_ document: String) throws -> JSONFieldRead.Attachment {
        try #require(item("{\"attachments\": [ \(document) ]}").attachments.first)
    }

    // MARK: - What a field keeps

    /// The reference folds a repeated key into one map entry holding the last assignment, so the
    /// walk over the members the tree keeps ends at the same value.
    @Test func lastEffectiveAssignmentWins() throws {
        #expect(try feed("{\"title\": \"a\", \"title\": \"b\"}").title == "b")
    }

    /// `literalStore` ignores null for a primitive or a string field, so the field keeps what the
    /// shape started with, which is what a repeated key separates here.
    @Test func nullAssignsNothingToAStringField() throws {
        #expect(try feed("{\"title\": null}").title == "")
        #expect(try feed("{\"title\": \"a\", \"title\": null}").title == "a")
    }

    /// For a slice target null is not ignored: `SetZero` is what the field gets, so an earlier
    /// assignment is cleared.
    @Test func nullSetsACollectionFieldToEmpty() throws {
        #expect(try item("{\"tags\": [\"a\"], \"tags\": null}").tags.isEmpty)
        #expect(try feed("{\"items\": [ { } ], \"items\": null}").items.isEmpty)
    }

    /// Traced: a null element is read against the element type, which is a struct or a string here,
    /// so it is ignored for that element rather than for the whole collection.
    @Test func nullElementKeepsTheElementAsItStarted() throws {
        #expect(try item("{\"tags\": [null, \"a\"]}").tags == ["", "a"])

        let document = try feed("{\"items\": [null]}")
        #expect(document.items.count == 1)
        #expect(try #require(document.items.first).id == "")
    }

    // MARK: - The type a value is read against

    @Test(arguments: [
        ("number", "{\"title\": 1}", "number"),
        ("bool", "{\"title\": true}", "bool"),
        ("array", "{\"title\": []}", "array"),
        ("object", "{\"title\": {}}", "object"),
    ]) func aValueThatIsNotTheFieldTypeFails(name: String, document: String, valueWord: String) {
        #expect(throws: JSONError.unmarshalTypeError(value: valueWord, target: "string")) {
            try feed(document)
        }
    }

    /// Traced: an int64 field does not keep the literal, it converts it through `ParseInt`, so the
    /// word the reference reports for a number it cannot read is the literal as it was read.
    @Test func int64FieldReadsTheLiteralThroughParseInt() throws {
        #expect(try attachment("{\"size_in_bytes\": 123456}").size == 123456)
        #expect(throws: JSONError.unmarshalTypeError(value: "number 1e3", target: "int64")) {
            try attachment("{\"size_in_bytes\": 1e3}")
        }
        #expect(throws: JSONError.unmarshalTypeError(value: "number 9223372036854775808", target: "int64")) {
            try attachment("{\"size_in_bytes\": 9223372036854775808}")
        }
    }

    /// Traced: `author` is a struct field, so a value that is not an object is the failure the
    /// field read reports against the struct type, which is what the leniency for `authors` does
    /// not do.
    @Test func structFieldIsReadAgainstTheStructType() {
        #expect(throws: JSONError.unmarshalTypeError(value: "array", target: "json.JSONAuthor")) {
            try author("[{ \"name\": \"A\" }]")
        }
    }

    // MARK: - The order the walk fails at

    /// Traced: `saveError` keeps the first failure, and the walk visits the members in the order
    /// the document wrote them, descending into a value when it reaches it, so the failure is the
    /// first member the field type cannot accept rather than the first field the adapter reads.
    @Test func firstFailureIsTheFirstMemberInDocumentOrder() {
        #expect(throws: JSONError.unmarshalTypeError(value: "number", target: "string")) {
            try feed("{\"title\": 1, \"description\": 2}")
        }
        #expect(throws: JSONError.unmarshalTypeError(value: "number", target: "string")) {
            try feed("{\"items\": [ { \"url\": 1 } ], \"title\": 2}")
        }
    }

    // MARK: - The top-level value

    /// Traced: the document itself is read against the shape, which is the target `Decode` passes
    /// to `d.value`, and null is the answer that leaves the shape as it started.
    @Test func topLevelValueIsReadAgainstTheShape() throws {
        #expect(try feed("null").title == "")
        #expect(throws: JSONError.unmarshalTypeError(value: "number", target: "json.JSONFeed")) {
            try feed("1")
        }
        #expect(throws: JSONError.unmarshalTypeError(value: "array", target: "json.JSONFeed")) {
            try feed("[]")
        }
    }

    // MARK: - Where the field table stops

    /// Traced as a deviation, recorded in `docs/parity.md`: the reference also accepts a name that
    /// folds to the tag through `foldName`, so `{"Title": "x"}` matches `title` there and nothing
    /// here.
    @Test func nameMatchIsExact() throws {
        #expect(try feed("{\"Title\": \"x\"}").title == "")
    }

    /// Traced as a deviation, recorded in `docs/parity.md`: the field table here is the fields the
    /// adapter reads, so a value whose type does not match a field the adapter does not read is a
    /// failure in the reference — `json: cannot unmarshal number into Go value of type string` for
    /// `version` — and nothing here.
    @Test func fieldTableStopsAtWhatTheAdapterReads() throws {
        let document = try feed("{\"version\": 1, \"expired\": \"true\", \"hubs\": [1], "
            + "\"user_comment\": \"x\", \"items\": []}")
        #expect(document.title == "")
        #expect(document.items.isEmpty)
    }

    /// Traced: a name the shape has no field for is not a failure, which is what `d.object` does
    /// when the field map has no match.
    @Test func keyWithNoFieldIsIgnored() throws {
        #expect(try feed("{\"unknown\": [1, 2], \"items\": []}").title == "")
    }
}
