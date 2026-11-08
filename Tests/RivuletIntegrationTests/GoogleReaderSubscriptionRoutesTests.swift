import Testing
import RivuletApp
@testable import RivuletCore

/// The three subscription routes over a real socket, read as the endpoints the reference
/// registers: `subscriptionListHandler`, `editSubscriptionHandler` and `quickAddHandler` of
/// `internal/googlereader/handler.go` at `c4d54f87`, each on the method its route names.  What
/// these pins can fail on, each checked by patching the rule and reverting (2 pins, 4 probes):
/// that the three paths answer the handlers rather than the catch-all document, which a patch
/// that registered none of them fails on; and which of the three applies the output check — a
/// patch that applied it to all three answered the check's wording on the two that do not, so
/// each of the three is read on an input where the handler's own rule answers instead.  What
/// these pins cannot show: the handler's own answer for a form the read cannot parse, which the
/// transport reports as 401 first, and the method mismatch, where the reference answers 405 and
/// this port answers Vapor's 404 — the row `docs/parity.md` already records for this path.
@Suite struct GoogleReaderSubscriptionRoutesTests {
    private let routes = "/reader/api/0/subscription/"

    @Test func theThreeRoutesAnswerTheHandlersAndNotTheCatchAll() async throws {
        try await withServedApp { storage, app, base in
            let socket = try await SubscriptionSocket.session(requests: GoogleReaderRequests(app, base),
                storage: storage, routes: routes)

            // A patch that registered none of the three answered the catch-all document for all of
            // them, which is the answer for an endpoint this port does not have.
            #expect(try await socket.get("list?output=json") == "{\"subscriptions\":[]}",
                "the document this handler builds, not the empty list the catch-all writes")

            // Each of the three is read on a value its own guard answers, so the pin names the
            // handler.
            #expect(try await socket.answer("edit", pairs: ["s=bogus"]) ==
                "{\"error_message\":\"googlereader: no valid stream IDs provided\"}",
                "the guard this handler writes")
            #expect(try await socket.answer("quickadd", pairs: ["quickadd=/only-a-path"]) ==
                "{\"error_message\":\"googlereader: invalid URL: /only-a-path\"}",
                "and the guard that one writes")
        }
    }

    @Test func listAppliesTheOutputCheckAndTheOtherTwoDoNot() async throws {
        try await withServedApp { storage, app, base in
            let socket = try await SubscriptionSocket.session(requests: GoogleReaderRequests(app, base),
                storage: storage, routes: routes)

            // The check is read through the query for the GET and through the merged form for the
            // POST.
            #expect(try await socket.get("list?output=atom") ==
                "{\"error_message\":\"googlereader: only json output is supported\"}",
                "the endpoint that reads it")

            // The other two are read on an input where the handler's own rule answers, so a patch
            // that applied the check everywhere changed the answer rather than leaving it.
            #expect(try await socket.answer("edit",
                pairs: ["s=feed/999", "ac=edit", "t=Title", "output=atom"]) ==
                "{\"error_message\":\"googlereader: feed not found\"}",
                "the answer the handler's own read gives, so the check did not run first")
            #expect(try await socket.answer("quickadd", pairs: ["quickadd=not-a-url", "output=atom"]) ==
                "{\"error_message\":\"googlereader: invalid URL: not-a-url\"}", "and neither does this one")
        }
    }
}
