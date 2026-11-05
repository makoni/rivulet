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
/// The content document adds three rules of its own: every one of its fourteen item fields is
/// written because no field of that document has `omitempty`, the key order is the order the struct
/// declares them in, and the lists the reference builds with `make` — `items` and `enclosure` — are
/// `[]` when empty. The goldens for these are the reference's own output above.
///
/// What these pins cannot fail on: which document a handler builds for which endpoint, which is the
/// handler's choice, and the values that reach the fields, which are the storage reads. The
/// `direct` stream ids and the timestamp of `itemRef` are written only by the document rule here,
/// because the item-ids read builds the document with the id alone; that half is pinned as the
/// writer's rule. For the content document the same applies to the values: the entry url is written
/// in two places by the handler, and the two parts that hold the entry content are the same value
/// twice, which is the handler's choice rather than the document's.
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

    @Test func theContentDocumentWritesEveryFieldInDeclaredOrder() {
        // No field of the item document has `omitempty`, so the golden is written from the document
        // rule alone; the key order is the order `response.go` declares the fields in.
        let item = GoogleReaderShape.contentItem(
            id: "tag:google.com,2005:reader/item/000000000000002a",
            categories: ["user/7/state/com.google/reading-list", "user/7/label/Tech",
                "user/7/state/com.google/read", "user/7/state/com.google/starred"],
            title: "Hello", crawlTimeMsec: "1700000100000", timestampUsec: "1700000000000000",
            published: 1700000000, updated: 1700000200, author: "Entry Author",
            alternate: [GoogleReaderShape.contentHrefType(href: "https://example.com/item",
                type: "text/html")],
            summary: GoogleReaderShape.contentText(direction: "ltr", content: "<p>Hello</p>"),
            content: GoogleReaderShape.contentText(direction: "ltr", content: "<p>Hello</p>"),
            origin: GoogleReaderShape.contentOrigin(streamID: "feed/3", title: "Feed Title",
                htmlURL: "https://example.com"),
            enclosure: [GoogleReaderShape.contentEnclosure(url: "https://example.com/a.mp3",
                type: "audio/mpeg")],
            canonical: [GoogleReaderShape.contentHref(href: "https://example.com/item")]
        )
        #expect(GoogleReaderShape.contentDocument(direction: "ltr",
            id: "user/-/state/com.google/reading-list", title: "Reading List",
            selfHref: "https://example.org/reader/api/0/stream/items/contents",
            updated: 1700000300, items: [item], author: "alice").written() ==
            "{\"direction\":\"ltr\",\"id\":\"user/-/state/com.google/reading-list\",\"title\":\"Reading List\",\"self\":[{\"href\":\"https://example.org/reader/api/0/stream/items/contents\"}],\"updated\":1700000300,\"items\":[{\"id\":\"tag:google.com,2005:reader/item/000000000000002a\",\"categories\":[\"user/7/state/com.google/reading-list\",\"user/7/label/Tech\",\"user/7/state/com.google/read\",\"user/7/state/com.google/starred\"],\"title\":\"Hello\",\"crawlTimeMsec\":\"1700000100000\",\"timestampUsec\":\"1700000000000000\",\"published\":1700000000,\"updated\":1700000200,\"author\":\"Entry Author\",\"alternate\":[{\"href\":\"https://example.com/item\",\"type\":\"text/html\"}],\"summary\":{\"direction\":\"ltr\",\"content\":\"\\u003cp\\u003eHello\\u003c/p\\u003e\"},\"content\":{\"direction\":\"ltr\",\"content\":\"\\u003cp\\u003eHello\\u003c/p\\u003e\"},\"origin\":{\"streamId\":\"feed/3\",\"title\":\"Feed Title\",\"htmlUrl\":\"https://example.com\"},\"enclosure\":[{\"url\":\"https://example.com/a.mp3\",\"type\":\"audio/mpeg\"}],\"canonical\":[{\"href\":\"https://example.com/item\"}]}],\"author\":\"alice\"}",
            "the fourteen fields in the order the document declares them")

        // A patch that added `omitempty` to any field would answer a document without it, so the
        // same document built from empty values is what the rule reads.
        let emptyItem = GoogleReaderShape.contentItem(
            id: "tag:google.com,2005:reader/item/0000000000000007", categories: ["user/7/state/com.google/reading-list"], title: "T",
            crawlTimeMsec: "1000", timestampUsec: "2000000", published: 2, updated: 3, author: "",
            alternate: [GoogleReaderShape.contentHrefType(href: "u", type: "text/html")],
            summary: GoogleReaderShape.contentText(direction: "ltr", content: ""),
            content: GoogleReaderShape.contentText(direction: "ltr", content: ""),
            origin: GoogleReaderShape.contentOrigin(streamID: "feed/1", title: "", htmlURL: ""),
            enclosure: [], canonical: [GoogleReaderShape.contentHref(href: "u")]
        )
        #expect(GoogleReaderShape.contentDocument(direction: "ltr",
            id: "user/-/state/com.google/reading-list", title: "Reading List",
            selfHref: "https://example.org/reader/api/0/stream/items/contents",
            updated: 1700000300, items: [emptyItem], author: "alice").written() ==
            "{\"direction\":\"ltr\",\"id\":\"user/-/state/com.google/reading-list\",\"title\":\"Reading List\",\"self\":[{\"href\":\"https://example.org/reader/api/0/stream/items/contents\"}],\"updated\":1700000300,\"items\":[{\"id\":\"tag:google.com,2005:reader/item/0000000000000007\",\"categories\":[\"user/7/state/com.google/reading-list\"],\"title\":\"T\",\"crawlTimeMsec\":\"1000\",\"timestampUsec\":\"2000000\",\"published\":2,\"updated\":3,\"author\":\"\",\"alternate\":[{\"href\":\"u\",\"type\":\"text/html\"}],\"summary\":{\"direction\":\"ltr\",\"content\":\"\"},\"content\":{\"direction\":\"ltr\",\"content\":\"\"},\"origin\":{\"streamId\":\"feed/1\",\"title\":\"\",\"htmlUrl\":\"\"},\"enclosure\":[],\"canonical\":[{\"href\":\"u\"}]}],\"author\":\"alice\"}",
            "the empty values are written, and an empty enclosure list is `[]`")

        #expect(GoogleReaderShape.contentDocument(direction: "ltr",
            id: "user/-/state/com.google/reading-list", title: "Reading List",
            selfHref: "https://example.org/reader/api/0/stream/items/contents",
            updated: 1700000300, items: [], author: "alice").written() ==
            "{\"direction\":\"ltr\",\"id\":\"user/-/state/com.google/reading-list\",\"title\":\"Reading List\",\"self\":[{\"href\":\"https://example.org/reader/api/0/stream/items/contents\"}],\"updated\":1700000300,\"items\":[],\"author\":\"alice\"}",
            "the items list built with `make` is `[]` when the page is empty")
    }
}
