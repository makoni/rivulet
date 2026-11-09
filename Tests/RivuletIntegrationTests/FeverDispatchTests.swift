import Foundation
import Testing
@testable import RivuletApp
@testable import RivuletCore

/// The dispatch this path answers on, over a real socket: the switch of `internal/fever/handler.go`
/// at `c4d54f87`. The goldens are the reference's own answers for these inputs at the toolchain
/// `go.mod` pins.
///
/// What these pins can fail on, each checked by patching the rule and reverting (2 pins, 6 probes):
/// the switch answers the first name it finds, so a request that carries every name answers the
/// groups document and each request that drops one name answers the next document — 2 probes, one
/// that moved the groups branch past the feeds branch fails the pair that names groups, and one
/// that moved the mark branch before the items branch fails the pair that reads the name from the
/// form; that the presence test reads the name as present whatever its value is — 2 probes, on the
/// case test and on the presence helper; that the mark name is read from the merged form, which a
/// patch that read it from the query alone fails on — 1 probe; and the default branch, which a
/// patch that answered a document for a name the switch does not have fails on — 1 probe.
///
/// What these pins cannot show: the values that reach the documents, which the read suites pin; the
/// subtree pattern of the reference's mux, which answers for any path under this route while Vapor
/// matches the registered path only, so the pins read the registered path; the XML shape the
/// reference's documentation names, which the handler has no branch for; and the clock field, read
/// as the placeholder the request helper names.
@Suite struct FeverDispatchTests {
    init() {
        TestLogging.bootstrapOnce()
    }

    @Test func theSwitchAnswersTheFirstNameItFinds() async throws {
        try await withServedApp { storage, app, base in
            let requests = FeverRequests(app, base)
            let (userID, token) = try await requests.seed(storage, name: "alice", password: "secret")
            // The key is carried as a query pair on every request here, so the transport read
            // passes and the pins read the switch alone. The group document carries the default
            // "All" row the create path writes with the account, so the golden names its id.
            let key = "api&api_key=\(token)"
            let all = FeverShape.group(id: try await requests.categoryID(storage,
                userID: userID, title: "All"), title: "All")

            // Each row drops the name the row before it answered for, so each pair of neighbours is
            // read on its own. A patch that moved one branch past another fails that row alone.
            #expect(requests.document(of: try await requests.get(
                "\(key)&groups&feeds&favicons&unread_item_ids&saved_item_ids&items&mark=item")) ==
                FeverShape.groupsDocument(groups: [all], feedsGroups: [], lastRefreshed: 0).written(),
                "groups is the first branch")
            #expect(requests.document(of: try await requests.get(
                "\(key)&feeds&favicons&unread_item_ids&saved_item_ids&items&mark=item")) ==
                FeverShape.feedsDocument(feeds: [], feedsGroups: [], lastRefreshed: 0).written(),
                "feeds is the second")
            #expect(requests.document(of: try await requests.get(
                "\(key)&favicons&unread_item_ids&saved_item_ids&items&mark=item")) ==
                FeverShape.faviconsDocument(favicons: [], lastRefreshed: 0).written(),
                "and favicons the third")
            #expect(requests.document(of: try await requests.get(
                "\(key)&unread_item_ids&saved_item_ids&items&mark=item")) ==
                FeverShape.unreadDocument(ids: "", lastRefreshed: 0).written(), "and the ids documents next")
            #expect(requests.document(of: try await requests.get(
                "\(key)&saved_item_ids&items&mark=item")) ==
                FeverShape.savedDocument(ids: "", lastRefreshed: 0).written(),
                "in the order the switch reads them")
            #expect(requests.document(of: try await requests.get("\(key)&items&mark=item")) ==
                FeverShape.itemsDocument(items: [], total: 0, lastRefreshed: 0).written(), "then items")

            // The mark branch is reached through the form, and the guard for an id the read cannot
            // read answers nothing at all, because the handler returns before the response
            // builder runs.
            let mark = try await requests.get("\(key)&mark=item&id=0")
            #expect(mark.status == .ok, "the mark branch is reached at all")
            #expect(requests.body(of: mark) == "", "and the guard writes nothing")
        }
    }

    @Test func presenceIsWhatTheDispatchReadsAndTheMarkNameComesFromTheMergedForm() async throws {
        try await withServedApp { storage, app, base in
            let requests = FeverRequests(app, base)
            let (userID, token) = try await requests.seed(storage, name: "alice", password: "secret")
            let key = "api&api_key=\(token)"
            let all = FeverShape.group(id: try await requests.categoryID(storage,
                userID: userID, title: "All"), title: "All")

            // `HasQueryParam` looks at the map, so a name with an empty value is present: this
            // request answers the groups document, while a patch that required a value answered the
            // base one.
            #expect(requests.document(of: try await requests.get("\(key)&groups=")) ==
                FeverShape.groupsDocument(groups: [all], feedsGroups: [], lastRefreshed: 0).written(),
                "the name is present with an empty value")

            // The mark name is read through `r.FormValue`, which is the merged form, so a pair the
            // body carries reaches the switch although the query names nothing for it.
            let markFromBody = try await requests.post(key, raw: "mark=item&id=0")
            #expect(requests.body(of: markFromBody) == "", "a name the body carries reaches the switch")

            // The default branch: a name the switch has no case for, including the value the
            // reference's documentation names for XML.
            #expect(requests.document(of: try await requests.get("api=xml&api_key=\(token)")) ==
                FeverShape.baseDocument(authenticated: 1, lastRefreshed: 0).written(),
                "the default branch answers the base document")
        }
    }
}
