import Testing
@testable import RivuletCore

/// The document a request body carries, read for the two shapes this path declares. 7 pins and
/// 8 probes, every probe seen to fail on the rule it names and to revert the file byte-identically.
///
/// What these pins can fail on, each shown by patching the rule and reverting it: a body with no
/// value, which the reference's decoder answers as a failure rather than as an empty document; a byte
/// the position the machine is in cannot accept; a value that is not the type the field declares; a
/// field the document does not carry, which answers the zero value for the creation shape and nothing
/// for the modification shape; and `null`, which leaves a plain field at its zero value and answers
/// nothing for a pointer field. The two shapes are read through the same read, so the pin that names
/// the zero value fires on one shape and the pin that names nothing fires on the other.
///
/// What these pins cannot show: the wording the reference answers for a failure, which is the text its
/// decoder builds from the position it failed at and is recorded in `docs/parity.md`; the bytes after
/// the top-level value, which `Decode` does not read, so a document followed by bytes the machine
/// cannot read is read here as the same document; and the fields the port's shapes do not declare,
/// which the reference reads and this port answers nothing for.
@Suite struct RequestBodyTests {
    @Test func aBodyWithNoValueIsAFailureNotAnEmptyDocument() {
        #expect(throws: RequestBody.Rule.unexpectedEnd) {
            _ = try RequestBody.categoryCreation("")
        }
        #expect(throws: RequestBody.Rule.unexpectedEnd) {
            _ = try RequestBody.categoryCreation("{\"title\": \"News\",")
        }
    }

    @Test func aByteThePositionCannotAcceptIsAFailure() {
        #expect(throws: RequestBody.Rule.unexpectedCharacter) {
            _ = try RequestBody.categoryCreation("{\"title\": tru}")
        }
    }

    @Test func aFieldOfTheWrongTypeIsAFailureForBothShapes() {
        #expect(throws: RequestBody.Rule.unmarshalTypeError) {
            _ = try RequestBody.categoryCreation("{\"title\": 7}")
        }
        #expect(throws: RequestBody.Rule.unmarshalTypeError) {
            _ = try RequestBody.categoryModification("{\"hide_globally\": \"yes\"}")
        }
    }

    @Test func aFieldTheDocumentDoesNotCarryAnswersTheZeroValueForTheCreationShape() throws {
        let request = try RequestBody.categoryCreation("{}")
        #expect(request.title == "", "the string field is left at its zero value")
        #expect(request.hideGlobally == false, "and the boolean field is left at its zero value")
    }

    @Test func aFieldTheDocumentDoesNotCarryAnswersNothingForTheModificationShape() throws {
        let request = try RequestBody.categoryModification("{}")
        #expect(request.title == nil, "the pointer is not written by a document that does not carry it")
        #expect(request.hideGlobally == nil, "and neither is the other")
    }

    @Test func nullAnswersNothingForAPointerFieldAndTheZeroValueForAPlainField() throws {
        let document = "{\"title\": null, \"hide_globally\": null}"
        let pointer = try RequestBody.categoryModification(document)
        #expect(pointer.title == nil, "a null pointer field is nothing")
        #expect(pointer.hideGlobally == nil, "the same for the boolean pointer")

        let plain = try RequestBody.categoryCreation(document)
        #expect(plain.title == "", "a null on a plain field leaves it at its zero value, not a failure")
        #expect(plain.hideGlobally == false, "and the same for the plain boolean")
    }

    @Test func theFieldsTheDocumentCarriesAreReadAsTheTypesTheShapeDeclares() throws {
        let request = try RequestBody.categoryModification("{\"title\": \"News\", \"hide_globally\": true}")
        #expect(request.title == "News", "the string field, read as a string")
        #expect(request.hideGlobally == true, "the boolean field, read as a boolean")
    }
}
