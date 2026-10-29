import Foundation
import Testing
@testable import RivuletCore

/// The field read the JSON Feed adapter reads through: the shapes `json.go` declares, filled
/// by the walk `d.object` does over the members the tree keeps. Each case states the value
/// the reference produces, because the reference has no code for this layer of its own.
///
/// Three rules are the field read's rather than the machine's: a value is read against
/// the type the field is, which is where `UnmarshalTypeError` comes from; `null`
/// sets a collection to empty but leaves a string, a bool, an int64 or a struct field
/// as it started; and a key the document writes twice is the two members the tree
/// kept, so the last assignment the field's type accepts is the one the shape holds.
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

    /// The reference folds a repeated key into one map entry holding the last
    /// assignment, so the walk over the members the tree keeps ends at the same value.
    @Test func lastEffectiveAssignmentWins() throws {
        #expect(try feed("{\"title\": \"a\", \"title\": \"b\"}").title == "b")
    }

    /// `literalStore` ignores null for a primitive or a string field, so the field
    /// keeps what the shape started with, which is what a repeated key separates here.
    @Test func nullAssignsNothingToAStringField() throws {
        #expect(try feed("{\"title\": null}").title == "")
        #expect(try feed("{\"title\": \"a\", \"title\": null}").title == "a")
    }

    /// A struct field is not in `literalStore`'s `SetZero` list either, so null
    /// leaves it as it started, which is what a repeated key separates here.
    @Test func nullLeavesAStructFieldAsItStarted() throws {
        #expect(try feed("{\"author\": { \"name\": \"Ann\" }, \"author\": null}").author.name == "Ann")
    }

    /// Traced: `JSONAuthors.UnmarshalJSON` returns without assigning when neither branch can read
    /// the value, so a second key the field read cannot accept leaves the earlier assignment.
    @Test func anUnreadableValueLeavesTheFieldAsItStarted() throws {
        #expect(try feed("{\"authors\": [ { \"name\": \"Ann\" } ], \"authors\": \"not an author\"}")
            .authors.first?.name == "Ann")
    }

    /// For a slice target null is not ignored: `SetZero` is what the field gets, so
    /// an earlier assignment is cleared — for `authors` through the array branch of
    /// the leniency, which reads null as a successful `Unmarshal` of an empty slice.
    @Test func nullSetsACollectionFieldToEmpty() throws {
        #expect(try item("{\"tags\": [\"a\"], \"tags\": null}").tags.isEmpty)
        #expect(try feed("{\"items\": [ { } ], \"items\": null}").items.isEmpty)
        #expect(try feed("{\"authors\": [ { \"name\": \"Ann\" } ], \"authors\": null}").authors.isEmpty)
    }

    /// Traced: the array branch is one `Unmarshal` call, so a bad element — or a field inside
    /// an element whose type does not match, including one the adapter writes nothing with —
    /// fails the whole attempt, and the single-object attempt fails too, so nothing is assigned.
    @Test func aBadElementFailsTheWholeArrayAttempt() throws {
        #expect(try feed("{\"authors\": [ { \"name\": \"Ann\" }, \"not an author\" ]}").authors.isEmpty)
        #expect(try feed("{\"authors\": [ { \"name\": \"Ann\", \"avatar\": 1 } ]}").authors.isEmpty)
    }

    /// Traced: a null element is read against the element type, which is a struct or a
    /// string here, so it is ignored for that element rather than for the whole collection.
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

    /// Traced: an int64 field does not keep the literal, it converts it through `ParseInt`, so
    /// the word the reference reports for a number it cannot read is the literal as it was read.
    @Test func int64FieldReadsTheLiteralThroughParseInt() throws {
        #expect(try attachment("{\"size_in_bytes\": 123456}").size == 123456)
        #expect(throws: JSONError.unmarshalTypeError(value: "number 1e3", target: "int64")) {
            try attachment("{\"size_in_bytes\": 1e3}")
        }
        #expect(throws: JSONError.unmarshalTypeError(value: "number 9223372036854775808",
            target: "int64")) {
            try attachment("{\"size_in_bytes\": 9223372036854775808}")
        }
    }

    /// Traced: `author` is a struct field, so a value that is not an
    /// object is the failure the field read reports against the struct
    /// type, which is what the leniency for `authors` does not do.
    @Test func structFieldIsReadAgainstTheStructType() {
        #expect(throws: JSONError.unmarshalTypeError(value: "array", target: "json.JSONAuthor")) {
            try author("[{ \"name\": \"A\" }]")
        }
    }

    // MARK: - The order the walk fails at

    /// Traced: `saveError` keeps the first failure, and the walk visits the members in
    /// the order the document wrote them, descending into a value when it reaches it,
    /// so the failure is the first member the field type cannot accept rather than the
    /// first field the table has. The two documents put a later field first, and the
    /// two targets are different types, so the assertion can tell the two orders apart.
    @Test func firstFailureIsTheFirstMemberInDocumentOrder() {
        #expect(throws: JSONError.unmarshalTypeError(value: "number", target: "bool")) {
            try feed("{\"expired\": 1, \"title\": 2}")
        }
        #expect(throws: JSONError.unmarshalTypeError(value: "number", target: "json.JSONHub")) {
            try feed("{\"hubs\": [1], \"title\": 2}")
        }
    }

    // MARK: - The top-level value

    /// Traced: the document itself is read against the shape, which is the target `Decode`
    /// passes to `d.value`, and null is the answer that leaves the shape as it started.
    @Test func topLevelValueIsReadAgainstTheShape() throws {
        #expect(try feed("null").title == "")
        #expect(throws: JSONError.unmarshalTypeError(value: "number", target: "json.JSONFeed")) {
            try feed("1")
        }
        #expect(throws: JSONError.unmarshalTypeError(value: "array", target: "json.JSONFeed")) {
            try feed("[]")
        }
    }

    // MARK: - What the shape keeps

    /// Traced as a deviation, recorded in `docs/parity.md`: the reference
    /// also accepts a name that folds to the tag through `foldName`,
    /// so `{"Title": "x"}` matches `title` there and nothing here.
    @Test func nameMatchIsExact() throws {
        #expect(try feed("{\"Title\": \"x\"}").title == "")
    }

    /// Traced: the shape declares every field `json.go` has, so a value whose
    /// type does not match a field the adapter writes nothing with is still
    /// the failure the reference reports. These are the fields the model has no
    /// place for: `version`, `expired`, a hub element, and an author's avatar.
    @Test func fieldTableIsWhatTheStructDeclares() {
        #expect(throws: JSONError.unmarshalTypeError(value: "number", target: "string")) {
            try feed("{\"version\": 1, \"items\": []}")
        }
        #expect(throws: JSONError.unmarshalTypeError(value: "string", target: "bool")) {
            try feed("{\"expired\": \"true\", \"items\": []}")
        }
        #expect(throws: JSONError.unmarshalTypeError(value: "number", target: "json.JSONHub")) {
            try feed("{\"hubs\": [1], \"items\": []}")
        }
        #expect(throws: JSONError.unmarshalTypeError(value: "number", target: "string")) {
            try feed("{\"author\": { \"avatar\": 1 }, \"items\": []}")
        }
        #expect(throws: JSONError.unmarshalTypeError(value: "number 1e3", target: "int")) {
            try feed("{\"items\": [ { \"attachments\": [ { \"duration_in_seconds\": 1e3 } ] } ] }")
        }
    }

    /// Traced: a name the shape has no field for is not a failure,
    /// which is what `d.object` does when the field map has no match.
    @Test func keyWithNoFieldIsIgnored() throws {
        #expect(try feed("{\"unknown\": [1, 2], \"items\": []}").title == "")
    }
}
