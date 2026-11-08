import Testing
import RivuletApp
@testable import RivuletCore

/// The listing endpoint over a real socket: `subscriptionListHandler` of
/// `internal/googlereader/handler.go` at `c4d54f87`, read as the reference's own answer for
/// these inputs. The document shapes themselves are pinned by `GoogleReaderShapeTests`; the
/// order the listing read builds is pinned as a read by `FeedRepositoryTests`.  What these pins
/// can fail on, each checked by patching the rule and reverting (4 pins, 6 probes): that the
/// answer is the order the sort expression builds rather than the id order; the six fields of
/// the subscription document as the values this handler writes, including the label being the
/// category title and not the feed title; the `omitempty` half of the category document on a
/// category whose title is empty, which a patch that always wrote the label fails on; the two
/// branches of the icon link, which a patch that wrote the link for any icon row fails on; and
/// the base the link is built from, which a patch that took it from the host the request came
/// in on fails on.  What these pins cannot show: the columns the listing read selects, which no
/// answer here can distinguish from a read that selected all of them; the order between rows
/// sharing one parsing-error count, which SQL does not fix; the `hide_globally` field the
/// reference reads on the same row, which this port's schema does not have; and the one read
/// the reference's category pair answers the same as.
@Suite struct GoogleReaderSubscriptionListTests {
    private let routes = "/reader/api/0/subscription/"

    @Test func listAnswersTheSortTheReadBuildsAndNotTheIdOrder() async throws {
        try await withServedApp { storage, app, base in
            let socket = try await SubscriptionSocket.session(requests: GoogleReaderRequests(app, base),
                storage: storage, routes: routes)
            let all = try await socket.categoryID("All")

            // The two orders are different answers on this data: the row with the error count
            // is the second row, and the alphabetically first title is the first one.
            let first = try await socket.seedFeed(all, "https://e/1", "Aardvark", "https://s1", 0)
            let second = try await socket.seedFeed(all, "https://e/2", "Zebra", "https://s2", 3)
            #expect(first < second, "the id order is not the answer")

            #expect(try await socket.get("list?output=json") == "{\"subscriptions\":["
                + document(second, "Zebra", "https://e/2", "https://s2", socket) + ","
                + document(first, "Aardvark", "https://e/1", "https://s1", socket) + "]}",
                "the order the sort expression answers in")
        }
    }

    @Test func theSubscriptionDocumentCarriesTheValuesTheHandlerWrites() async throws {
        try await withServedApp { storage, app, base in
            let socket = try await SubscriptionSocket.session(requests: GoogleReaderRequests(app, base),
                storage: storage, routes: routes)
            let tech = try await socket.seedCategory("Tech")
            let feed = try await socket.seedFeed(tech, "https://e/1", "Feed title", "https://s", 0)

            // The label is the category title, not the feed title, and its id is the prefix
            // with it. A patch that wrote the feed title as the label answered this pin
            // differently.
            #expect(try await socket.get("list?output=json") == "{\"subscriptions\":["
                + document(feed, "Feed title", "https://e/1", "https://s", socket, category: "Tech") + "]}",
                "the six fields in the order the document declares them")
        }
    }

    @Test func theCategoryDocumentOmitsAnEmptyLabelButWritesItsId() async throws {
        try await withServedApp { storage, app, base in
            let socket = try await SubscriptionSocket.session(requests: GoogleReaderRequests(app, base),
                storage: storage, routes: routes)
            let blank = try await socket.seedCategory("")
            let row = try await socket.seedFeed(blank, "https://e/2", "", "", 0)

            // A patch that always wrote the label answered `"label":""` here. The pin above reads
            // the same document with a title, so the two halves of the rule are read apart.
            #expect(try await socket.get("list?output=json") == "{\"subscriptions\":["
                + document(row, "", "https://e/2", "", socket, category: "") + "]}",
                "the field the document omits")
        }
    }

    @Test func iconLinkIsWrittenOnlyForAnIconWithAnExternalIdAndFromTheConfiguredBase() async throws {
        try await withServedApp { storage, app, base in
            let socket = try await SubscriptionSocket.session(requests: GoogleReaderRequests(app, base),
                storage: storage, routes: routes)
            #expect(base.hasPrefix("http://127.0.0.1"), "the request host is not the configured base")
            let all = try await socket.categoryID("All")

            // Three branches: a feed with no icon row, an icon row with nothing to write, and one
            // with a value. A patch that wrote the link for any icon row, or that read the hash as
            // the external id, answered the first two differently. The rows answer in the order the
            // sort read builds them, which the pin above pins; only the middle one has a link to
            // write.
            let none = try await socket.seedFeed(all, "https://e/1", "a", "", 0)
            let blank = try await socket.seedFeed(all, "https://e/2", "b", "", 1,
                icon: try await socket.seedIcon("h1", ""))
            let filled = try await socket.seedFeed(all, "https://e/3", "c", "", 2,
                icon: try await socket.seedIcon("h2", "ext-7"))

            #expect(try await socket.get("list?output=json") == "{\"subscriptions\":["
                + document(filled, "c", "https://e/3", "", socket,
                    icon: "http://localhost/feed-icon/ext-7") + ","
                + document(blank, "b", "https://e/2", "", socket) + ","
                + document(none, "a", "https://e/1", "", socket) + "]}",
                "the link, and the base it is built from")
        }
    }

    /// One subscription document, as the reference's encoder writes it for the values this handler
    /// gives.
    private func document(_ id: Int, _ title: String, _ url: String, _ html: String,
        _ socket: SubscriptionSocket, category: String = "All", icon: String = "") -> String {
        let label = category.isEmpty ? "" : ",\"label\":\"\(category)\""
        let part = "{\"id\":\"user/\(socket.userID)/label/\(category)\"\(label),\"type\":\"folder\"}"
        return "{\"id\":\"feed/\(id)\",\"title\":\"\(title)\",\"categories\":[\(part)],"
            + "\"url\":\"\(url)\",\"htmlUrl\":\"\(html)\",\"iconUrl\":\"\(icon)\"}"
    }
}
