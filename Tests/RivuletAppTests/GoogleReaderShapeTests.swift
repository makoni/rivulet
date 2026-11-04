import Testing
@testable import RivuletApp

/// The documents this path writes, read as `encoding/json` writes them — the struct tags of
/// `internal/googlereader/response.go` at `c4d54f87`. The goldens are the reference's own output
/// for these documents at the toolchain `go.mod` pins.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the key order,
/// which is the order the document declares its fields in — for `streamIDResponse` that is
/// `itemRefs` before `continuation`, which a patch that wrote them the other way fails; the fields
/// written without `omitempty`, which a patch that added it fails on the input where the value is
/// empty, so `id` of `itemRef` and all four fields of the user document are written even when
/// empty; the fields written with `omitempty`, which a patch that always wrote them fails on the
/// same input; that an empty list is written as `[]` and not `null`, because the reference builds
/// the slice with `make` before it writes it, which a patch that wrote `null` for an empty document
/// fails; and the two halves of the `continuation` rule, which is written as a JSON string by the
/// document's `,string` option and omitted when it is 0 — a patch that wrote it as a number, or
/// that wrote the zero, fails.
///
/// What these pins cannot fail on: which document a handler builds for which endpoint, which is the
/// handler's choice, and the values that reach the fields, which are the storage reads. The
/// `direct` stream ids and the timestamp of `itemRef` are written only by the document rule here,
/// because the item-ids read builds the document with the id alone; that half is pinned as the
/// writer's rule.
@Suite struct GoogleReaderShapeTests {
    @Test func theItemRefWritesTheIdAndOmitsTheFieldsThatAreEmpty() {
        // `id` has no `omitempty`, so an empty one is still written; the other two are omitted when
        // empty, which is the difference the pins read.
        #expect(GoogleReaderShape.itemRef(id: "1").written() == "{\"id\":\"1\"}", "the item-ids read")
        #expect(GoogleReaderShape.itemRef(id: "").written() == "{\"id\":\"\"}",
            "the field without omitempty is written when empty")
        #expect(GoogleReaderShape.itemRef(id: "1", directStreamIDs: "a,b", timestampUsec: "123").written() ==
            "{\"id\":\"1\",\"directStreamIds\":\"a,b\",\"timestampUsec\":\"123\"}",
            "the three fields in the order the document declares them")
    }

    @Test func theStreamIDResponseWritesTheArrayAndOmitsAZeroContinuation() {
        // The reference builds the slice with `make` before it writes it, so an empty document
        // answers `[]`, not `null`.
        #expect(GoogleReaderShape.streamIDResponse(itemRefs: [], continuation: 0).written() ==
            "{\"itemRefs\":[]}", "the empty list, and the omitted zero")

        // `continuation` has `,string`, so a value that is written is written as a string.
        #expect(GoogleReaderShape.streamIDResponse(itemRefs: [GoogleReaderShape.itemRef(id: "7")],
            continuation: 5).written() == "{\"itemRefs\":[{\"id\":\"7\"}],\"continuation\":\"5\"}",
            "the string form, and the order the document declares")

        // The two halves are separate rules: an empty list with a value still writes the value.
        #expect(GoogleReaderShape.streamIDResponse(itemRefs: [], continuation: 3).written() ==
            "{\"itemRefs\":[],\"continuation\":\"3\"}", "the list rule does not depend on the value")
    }

    @Test func theUserDocumentWritesAllFourFieldsEvenWhenEmpty() {
        // None of these fields has `omitempty`, so the empty values are written as empty strings,
        // and the order is the document's.
        #expect(GoogleReaderShape.userInfoResponse(userID: "1", userName: "alice",
            userProfileID: "1", userEmail: "alice").written() ==
            "{\"userId\":\"1\",\"userName\":\"alice\",\"userProfileId\":\"1\",\"userEmail\":\"alice\"}",
            "the four fields in the order the document declares them")
        #expect(GoogleReaderShape.userInfoResponse(userID: "", userName: "", userProfileID: "",
            userEmail: "").written() ==
            "{\"userId\":\"\",\"userName\":\"\",\"userProfileId\":\"\",\"userEmail\":\"\"}",
            "a patch that added omitempty failed here")
    }

    @Test func theCategoryDocumentOmitsLabelAndTypeWhenTheyAreEmpty() {
        // The starred entry the tag list writes first has only its id; the categories carry the
        // other two, which are written only when they have a value.
        #expect(GoogleReaderShape.categoryResponse(id: "user/7/state/com.google/starred").written() ==
            "{\"id\":\"user/7/state/com.google/starred\"}", "the entry with nothing else")
        #expect(GoogleReaderShape.categoryResponse(id: "user/7/label/Tech", label: "Tech",
            type: "folder").written() ==
            "{\"id\":\"user/7/label/Tech\",\"label\":\"Tech\",\"type\":\"folder\"}",
            "the three fields in the order the document declares them")

        // The document's own field is `tags`, written first and as `[]` when the list is empty.
        #expect(GoogleReaderShape.tagsResponse(tags: []).written() == "{\"tags\":[]}", "the empty list")
        #expect(GoogleReaderShape.tagsResponse(tags: [GoogleReaderShape.categoryResponse(
            id: "user/7/label/Tech", label: "Tech", type: "folder")]).written() ==
            "{\"tags\":[{\"id\":\"user/7/label/Tech\",\"label\":\"Tech\",\"type\":\"folder\"}]}",
            "and the list in the order it is built in")
    }
}
