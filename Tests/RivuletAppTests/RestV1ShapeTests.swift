import Testing
@testable import RivuletApp
@testable import RivuletCore

/// The document this path writes for the account row, read as `internal/model/user.go` at
/// `c4d54f87` declares it.
///
/// What this pin can fail on, each shown by patching the rule and reverting it: the key set being
/// the three fields this port has columns for, which a patch that dropped one of them fires here;
/// the order the three are written in, which a patch that wrote `is_admin` before `username` fires
/// here; the hash not being written, which a patch that wrote the model's hash column fires here;
/// and the two value rules, a boolean written as `true` or `false` and a number written as a
/// number, which a patch that wrote either as a string fires here. Four patches reached this suite
/// and all four fired here alone in the round that showed these pins; the patch for the key order
/// also fires on the route suite's pins for the document as bytes and for the row the read
/// hands the handler, which is the round of the third slice.
///
/// The two documents the category half writes are pinned by 3 pins and 3 probes: the key order of the
/// category document, which a patch that wrote `hide_globally` before `title` fires on; the two counts
/// being written only for the half that reads them, which a patch that wrote them for a zero count
/// fires on; and the key order of the feed document, which a patch that dropped `description` fires
/// on. Each was seen to fail on the rule it names and to revert the file byte-identically. The counts
/// pins also fire on the route suite's pins that read a document this shape builds.
///
/// What this pin cannot fail on: the reference's other fields, which this port's schema has no
/// column for. Its struct declares 32 fields and one of them is not written at all, so the answer
/// carries 31 there and three here; no pin can read a field the schema has no column for, so the
/// difference is recorded in `docs/parity.md`. The three values this pin reads are the ones it put
/// into the model itself, so what reaches them from a stored row is read by no pin here: the row
/// read and the handler that answers it are the slice that registers the route.
@Suite struct RestV1ShapeTests {
    @Test func theCategoryDocumentCarriesTheKeysTheStructDeclares() {
        let category = Category()
        category.id = 4
        category.userID = 1
        category.title = "News"
        category.hideGlobally = false

        #expect(RestV1Shape.categoryDocument(category, counts: nil).written() ==
            "{\"id\":4,\"user_id\":1,\"title\":\"News\",\"hide_globally\":false}",
            "the four keys in the order the struct declares them, with the two counts left out")
    }

    @Test func theTwoCountsAreWrittenOnlyForTheHalfThatReadsThem() {
        let category = Category()
        category.id = 4
        category.userID = 1
        category.title = "News"
        category.hideGlobally = true

        // The reference's two count fields are pointers with `omitempty`: the half that reads them
        // writes them even for a zero, and the half that does not writes nothing. A patch that wrote
        // the counts for every document, or that skipped a zero, fires on one of the two assertions
        // here and not on the other.
        #expect(RestV1Shape.categoryDocument(category,
            counts: CategoryCounts(feedCount: 0, totalUnread: 0)).written() ==
            "{\"id\":4,\"user_id\":1,\"title\":\"News\",\"hide_globally\":true,"
            + "\"feed_count\":0,\"total_unread\":0}",
            "the counts are written for the half that read them, a zero included")
        #expect(RestV1Shape.categoryDocument(category, counts: nil).written() ==
            "{\"id\":4,\"user_id\":1,\"title\":\"News\",\"hide_globally\":true}",
            "and not for the half that did not")
    }

    @Test func theFeedDocumentCarriesTheKeySetTheSchemaHasColumnsFor() {
        let feed = Feed()
        feed.id = 3
        feed.userID = 1
        feed.url = "https://example.com/feed.xml"
        feed.siteURL = ""
        feed.title = "News"
        feed.feedDescription = ""
        feed.etag = ""
        feed.lastModified = ""
        feed.parsingErrorMessage = ""
        feed.parsingErrorCount = 2
        feed.userAgent = ""
        feed.disabled = false
        feed.ignoreHTTPCache = true
        feed.fetchViaProxy = false

        #expect(RestV1Shape.feedDocument(feed).written() ==
            "{\"id\":3,\"user_id\":1,\"feed_url\":\"https://example.com/feed.xml\","
            + "\"site_url\":\"\",\"title\":\"News\",\"description\":\"\","
            + "\"etag_header\":\"\",\"last_modified_header\":\"\","
            + "\"parsing_error_message\":\"\",\"parsing_error_count\":2,\"user_agent\":\"\","
            + "\"disabled\":false,\"ignore_http_cache\":true,\"fetch_via_proxy\":false}",
            "the fields the port has columns for, in the order the struct declares them")
    }

    @Test func theAccountDocumentCarriesTheKeySetTheSchemaHasColumnsFor() {
        let user = User()
        user.id = 7
        user.username = "alice"
        user.isAdmin = true
        user.passwordHash = "$2a$10$notwritten"

        #expect(RestV1Shape.userDocument(user).written() ==
            "{\"id\":7,\"username\":\"alice\",\"is_admin\":true}",
            "the three fields in the order the struct declares them, and the hash is left out")
    }
}
