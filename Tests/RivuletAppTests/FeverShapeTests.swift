import Testing
@testable import RivuletApp

/// The documents this path writes, read as `encoding/json` writes them — the struct tags of
/// `internal/fever/response.go` at `c4d54f87`. The goldens are the reference's own output for these
/// documents at the toolchain `go.mod` pins.
///
/// What these pins can fail on, each checked by patching the rule and reverting (5 pins, 8 probes:
/// 3 on the base and failure document pin, 2 on the item document pin, 1 each on the value
/// documents, the feed document and the empty list): the three fields of `baseResponse` are written
/// before the document's own fields, which a patch that wrote them after fails on; the version this
/// path reports and the auth flag for a run the transport read passed, which a patch that wrote 2
/// or 0 fails on; and the failure document's two zeros, which a patch that ran the common-value
/// rule for it fails on. The field order each value document writes is read on the group document,
/// which a patch that swapped its two fields fails on. Every field of the item document is written
/// because no field of this path's documents has `omitempty`, so `is_saved` before `is_read` is
/// read on an input where the two differ, and `total_items` is written as a number rather than as
/// the string of one. `favicon_id` is written as the zero for a feed row with no icon, which a
/// patch that added `omitempty` fails on. And an empty list is `[]`, which for `items`, `feeds` and
/// `feeds_groups` is what the reference writes too because it builds those slices with `make`, and
/// for `groups` and `favicons` is this port's divergence — the reference's build path leaves those
/// nil and writes `null`, which Newsflash's deserializer refuses, so the row in `docs/parity.md`
/// names it.
///
/// What these pins cannot show: the value the handler gives for the clock field, which is the
/// instant the handler runs at, so every pin here reads the field's position rather than its value;
/// which document a handler builds for which request, which is the handler's choice and is read
/// over a socket by `FeverDispatchTests`; the `is_spark` value, which this handler writes as 0 for
/// every row whatever the reference's model carries; and the storage values that reach the fields,
/// which the read suites pin.
@Suite struct FeverShapeTests {
    @Test func theBaseDocumentWritesTheThreeFieldsFirstAndTheFailureDocumentWritesTheZeros() {
        // The embedded struct is written first by Go's encoder, so the three fields come before the
        // document's own; `SetCommonValues` is the rule that writes the version and the flag.
        #expect(FeverShape.baseDocument(authenticated: 1, lastRefreshed: 0).written() ==
            "{\"api_version\":3,\"auth\":1,\"last_refreshed_on_time\":0}",
            "the three fields in the order the struct declares them")
        #expect(FeverShape.authFailure().written() ==
            "{\"api_version\":3,\"auth\":0,\"last_refreshed_on_time\":0}",
            "the failure document keeps the version and writes the zero for both")

        // The order is what a patch that wrote the base after the document's fields fails on.
        #expect(FeverShape.groupsDocument(groups: [FeverShape.group(id: 7, title: "Tech")],
            feedsGroups: [], lastRefreshed: 0).written() ==
            "{\"api_version\":3,\"auth\":1,\"last_refreshed_on_time\":0,\"groups\":[{\"id\":7,\"title\":\"Tech\"}],"
                + "\"feeds_groups\":[]}",
            "the document's own fields after the base")
    }

    @Test func theItemDocumentWritesAllNineFieldsInDeclaredOrder() {
        // `is_saved` before `is_read`, read on an input where the two differ: a patch that swapped
        // the two fields, or that added `omitempty` to any of them, answered a different
        // document here.
        #expect(FeverShape.itemsDocument(items: [FeverShape.item(id: 42, feedID: 3, title: "Hello",
            author: "Author", html: "<p>Hello</p>", url: "https://example.com/item",
            isSaved: 1, isRead: 0, createdOnTime: 1_700_000_000)], total: 1, lastRefreshed: 0).written() ==
            "{\"api_version\":3,\"auth\":1,\"last_refreshed_on_time\":0,\"items\":[{\"id\":42,\"feed_id\":3,"
                + "\"title\":\"Hello\",\"author\":\"Author\",\"html\":\"\\u003cp\\u003eHello\\u003c/p\\u003e\","
                + "\"url\":\"https://example.com/item\","
                + "\"is_saved\":1,\"is_read\":0,\"created_on_time\":1700000000}],\"total_items\":1}",
            "the nine fields in the order the struct declares them")
    }

    @Test func theFeedDocumentWritesFaviconIdAsTheZeroForARowWithNoIcon() {
        // `is_spark` is the value this handler writes for every row, and `favicon_id` is written
        // even when the row has no icon, because no field of this path has `omitempty`.
        #expect(FeverShape.feedsDocument(feeds: [FeverShape.feed(id: 9, faviconID: 0,
            title: "Feed", url: "https://example.com/feed.xml", siteURL: "https://example.com",
            lastUpdated: 1_700_000_100)], feedsGroups: [FeverShape.feedsGroup(groupID: 4,
            feedIDs: "9")], lastRefreshed: 0).written() ==
            "{\"api_version\":3,\"auth\":1,\"last_refreshed_on_time\":0,\"feeds\":[{\"id\":9,"
                + "\"favicon_id\":0,\"title\":\"Feed\",\"url\":\"https://example.com/feed.xml\","
                + "\"site_url\":\"https://example.com\",\"is_spark\":0,\"last_updated_on_time\":1700000100}],"
                + "\"feeds_groups\":[{\"group_id\":4,\"feed_ids\":\"9\"}]}",
            "the seven fields in the order the struct declares them, and the two of the group row")
    }

    @Test func theValueDocumentsWriteEveryFieldTheyDeclare() {
        // The group document, the favicon document, and the two id documents: the field names are
        // the struct tags, and the id string documents carry the comma-joined list as one value.
        #expect(FeverShape.groupsDocument(groups: [FeverShape.group(id: 4, title: "Tech")],
            feedsGroups: [FeverShape.feedsGroup(groupID: 4, feedIDs: "9,11")], lastRefreshed: 0).written() ==
            "{\"api_version\":3,\"auth\":1,\"last_refreshed_on_time\":0,\"groups\":[{\"id\":4,\"title\":\"Tech\"}],"
                + "\"feeds_groups\":[{\"group_id\":4,\"feed_ids\":\"9,11\"}]}",
            "the two fields of each")
        #expect(FeverShape.faviconsDocument(favicons: [FeverShape.favicon(id: 2,
            data: "image/png;base64,AAA=")], lastRefreshed: 0).written() ==
            "{\"api_version\":3,\"auth\":1,\"last_refreshed_on_time\":0,\"favicons\":[{\"id\":2,"
                + "\"data\":\"image/png;base64,AAA=\"}]}",
            "the two fields of the favicon document")
        #expect(FeverShape.unreadDocument(ids: "1,2", lastRefreshed: 0).written() ==
            "{\"api_version\":3,\"auth\":1,\"last_refreshed_on_time\":0,\"unread_item_ids\":\"1,2\"}",
            "the single field after the base")
        #expect(FeverShape.savedDocument(ids: "", lastRefreshed: 0).written() ==
            "{\"api_version\":3,\"auth\":1,\"last_refreshed_on_time\":0,\"saved_item_ids\":\"\"}",
            "and the empty list written as the empty string the read joins")
    }

    @Test func anEmptyListIsWrittenAsAnArrayOnEveryDocumentOfThisPath() {
        // `items`, `feeds` and `feeds_groups` are what the reference writes too, because it builds
        // those slices with `make` before it writes the document. For `groups` and `favicons` the
        // reference writes `null` for the nil slice its build path leaves, which is the divergence
        // the row in `docs/parity.md` records — Newsflash's deserializer refuses `null` for those
        // two. The patch that wrote `null` for an empty document fired on the favicons
        // assertion below; the other three read the lists the reference builds with `make`, so they
        // answer the same on both sides and no patch can part them.
        #expect(FeverShape.itemsDocument(items: [], total: 0, lastRefreshed: 0).written() ==
            "{\"api_version\":3,\"auth\":1,\"last_refreshed_on_time\":0,\"items\":[],\"total_items\":0}",
            "the list the handler builds with make, and the count written as a number")
        #expect(FeverShape.feedsDocument(feeds: [], feedsGroups: [], lastRefreshed: 0).written() ==
            "{\"api_version\":3,\"auth\":1,\"last_refreshed_on_time\":0,\"feeds\":[],\"feeds_groups\":[]}",
            "the same rule, on two lists the reference builds with make too")
        #expect(FeverShape.groupsDocument(groups: [], feedsGroups: [], lastRefreshed: 0).written() ==
            "{\"api_version\":3,\"auth\":1,\"last_refreshed_on_time\":0,\"groups\":[],\"feeds_groups\":[]}",
            "the accepted row, read on the groups document")
        #expect(FeverShape.faviconsDocument(favicons: [], lastRefreshed: 0).written() ==
            "{\"api_version\":3,\"auth\":1,\"last_refreshed_on_time\":0,\"favicons\":[]}",
            "and the same row on the favicons document")
    }
}
