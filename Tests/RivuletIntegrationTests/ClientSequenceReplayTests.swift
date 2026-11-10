import Foundation
import Testing
import Vapor
@testable import RivuletApp
@testable import RivuletCore

///The recorded calling sets read as data and replayed against the served app over a real socket.
///Each pin takes one recorded call and asserts what the port answers for it: the record names the
///call and the value the pin reads, so a pin is the replay half of the matrix rather than a
///restatement of the matrix's table. 9 pins and 10 probes, each seen to fail on the rule it names
///and to revert the file byte-identically; the login half has 2 probes and every other pin has 1.
///What each pin can fail on, with the input its probe crafts: - the recorded order is the order the
///set declares — a patch that swaps two entries of the record's own `source_order`. This is the
///only pin here that can fail on the record rather than on a rule, because nothing in the port
///reads an order; - the login half is the one route on this path that carries no transport read,
///and the value its answer carries is the value the later requests read as the token — a patch that
///wrapped the login route with the read, and a patch that wrote the stored value in the three lines
///instead of the value the row derives; - the token half the record names for each recorded call —
///a patch that read the field the record names for the login's own token call, because the read's
///decision by method is `GoogleReaderAuthTests`' pin with its own probe, and the transport read is
///the assumption every other pin here runs through, so no patch to it can fire one pin alone; - the
///guard for the call the record names with no add and no remove pair — a patch that dropped the
///guard; - the two item-id forms the same client sends in two different calls — a patch that read
///every value by the field-width rule; - the page size above the clamp against the page size the
///record names at the clamp — a patch that dropped the clamp; - the path no route registers — a
///patch that registered it; - the dispatch name the switch has no case for — a patch that gave it a
///case; - the prefix this port registers no route for — a patch that registered a route under it.
///What these pins cannot show: the `>50` guard NewsFlash applies before it sends, which is the
///client's own and fires before the request is sent, so no input reaches it; the values the records
///carry, which are placeholders, so no pin reads a value; the order a closed-source client reaches
///its calls at, which the record names as not read here; the app-level choice of which calls a
///library-based client makes, which is read at the library boundary; the page size as a row count,
///because the difference between a value above the clamp and a value at it is only visible above
///the clamp, which the gated corpus holds; and the page size for `stream/items/contents`, which
///this port reads no limit for at all.
@Suite struct ClientSequenceReplayTests {
    init() {
        TestLogging.bootstrapOnce()
    }

    private let name = "alice"
    private let password = "secret"
    private let storedHash = "$2a$10$hOrIpoEkDKAMFrOt2/k1yeyHBaZKOwK8zEg9JVchReOAtQZ5mEeFu"

    ///The order the record declares, read as data: the set that names the order as declared has to
    ///be the order the pins replay, and the set that names it as a call graph has to cover the same
    ///calls.
    @Test func theRecordedOrderIsTheOrderTheSetDeclares() throws {
        for set in try CallingSets.all() {
            if set.sequenceKind.hasPrefix("not read here") {
                #expect(set.sourceOrder.isEmpty && set.declaredOrder.isEmpty,
                    "\(set.client): the record names the order as not read here and still records one")
                continue
            }

            if set.sequenceKind.contains("declares") {
                #expect(set.sourceOrder == set.declaredOrder,
                    "\(set.client): the recorded order is not the order the source declares")
            } else {
                #expect(Set(set.sourceOrder) == Set(set.declaredOrder),
                    "\(set.client): the runtime order and the declared order do not cover the same calls")
            }

            #expect(Set(set.calls.map(\.key)) == Set(set.declaredOrder),
                "\(set.client): the calls the set records do not cover the order it declares")
        }
    }

    ///The login half, as the record names it: the one route on this path that carries no transport
    ///read, and the answer it carries is the value the later requests read as the token. A pair
    ///with no `=` is the form the read reports, so the two 401 shapes say which piece ran — the
    ///login guard's own shape is the JSON one, and the wrapper's is the text one. 2 probes: the
    ///first patches the write so the three lines carry the stored value instead of the value the
    ///row derives, the second patches the route so the wrapper covers the login too.
    @Test func theLoginHalfCarriesNoWrapperAndCarriesTheValueTheLaterReadsCompare() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            try await requests.seed(storage, name: name, storedHash: storedHash)

            let login = try CallingSets.set("NetNewsWire").call("accounts/ClientLogin")
            #expect(login?.names == ["Email", "Passwd"], "the record names the fields the login reads")
            #expect(login?.auth == "none", "the record names the login half as carrying no token")

            // A pair with no `=` is the form the read cannot parse: the answer is the guard's own
            // shape, which is what this route gives because the wrapper is not on it.
            let reported = try await requests.post("/accounts/ClientLogin", raw: "Email")
            #expect(reported.status == .unauthorized, "the guard ends the login before the read")
            #expect(requests.contentType(of: reported) == "application/json",
                "the login guard's own shape, not the shape the wrapper answers with")

            let token = GoogleReaderToken.derive(username: name, storedHash: storedHash)
            let body = try requests.body(of: try await requests.login(
                fields: ["Email": name, "Passwd": password]))
            #expect(body == "SID=\(token)\nLSID=\(token)\nAuth=\(token)\n",
                "the three lines carry the value the read compares, each with the same value")
        }
    }

    ///Which side the read takes the token from is the field the record names for each call, and the
    ///pin reads that field for every call every set records. The read's own decision by method is
    ///`GoogleReaderAuthTests`' pin with its own probe, so this pin's probe is the record's field:
    ///the only input the pin can fail on, and the socket half shows the two fields agree.
    @Test func theTokenHalfIsTheHalfTheReadReadsForEachMethod() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            try await requests.seed(storage, name: name, storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: name, storedHash: storedHash)

            for set in try CallingSets.all() {
                for call in set.calls where call.auth != "none" {
                    #expect(call.auth == (call.method == "GET" ? "header" : "form"),
                        "\(set.client)/\(call.key): the read for a \(call.method) route reads the \(call.auth) half")
                }
            }

            let readByHeader = try await requests.get("/reader/api/0/token", header: "GoogleLogin auth=\(token)")
            #expect(readByHeader.status == .ok, "the record names this call as the header half")

            // The same call answered with the other half: the read does not look at the header for
            // POST and does not look at the form for GET, so each answer is the read finding
            // nothing.
            let postReadByHeader = try await requests.post("/reader/api/0/edit-tag", raw: "",
                header: "GoogleLogin auth=\(token)")
            #expect(postReadByHeader.status == .unauthorized, "a POST reads the form half, not the header half")

            let postReadByForm = try await requests.post("/reader/api/0/edit-tag",
                form: ["T": token, "i": "1", "a": "user/-/state/com.google/starred"])
            #expect(postReadByForm.status == .ok, "the form half reaches the handler for a POST")
        }
    }

    ///The call the record names with no add and no remove pair is FeedFlow's folder delete, which
    ///sends the stream value and the token only, so the guard is what answers for it.
    @Test func theGuardAnswersForTheCallWithNoAddAndNoRemovePair() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            try await requests.seed(storage, name: name, storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: name, storedHash: storedHash)

            let call = try CallingSets.set("FeedFlow").call("reader/api/0/edit-tag#disable-tag")
            #expect(call?.names == ["s", "T"], "the record names the pair the client sends, with no add or remove")

            let response = try await requests.post("/reader/api/0/edit-tag",
                form: ["T": token, "s": "user/-/label/notes"])
            #expect(response.status == .internalServerError, "the guard is what answers for this call")

            // The wording is the guard's own, and it is the answer the handler builds for it: the
            // read that reports a form it cannot parse answers 401 before the guard, so this is the
            // guard's answer rather than the read's.
            #expect(try requests.body(of: response) ==
                GoogleReaderResponse.errorDocument(
                    "googlreader: add or/and remove tags should be supplied").written(),
                "the guard's own wording")
        }
    }

    ///The same client sends the item id in two forms, in two different calls, and the read keeps
    ///what it read for each: the field-width rule answers the padded form, and the decimal read
    ///reports the unpadded one.
    @Test func theTwoItemIDFormsOfTheSameClient() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            try await requests.seed(storage, name: name, storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: name, storedHash: storedHash)
            let set = try CallingSets.set("NetNewsWire")

            #expect(set.call("reader/api/0/edit-tag")?.idForm == "padded",
                "the record names the state call as the padded form")
            #expect(set.call("reader/api/0/stream/items/contents")?.idForm == "unpadded",
                "the record names the contents call as the unpadded form")

            let padded = try await requests.post("/reader/api/0/edit-tag",
                form: ["T": token, "i": "00000000000004d2", "a": "user/-/state/com.google/starred"])
            #expect(padded.status == .ok, "the padded value reaches the write as the field-width rule reads it")

            let unpadded = try await requests.post("/reader/api/0/stream/items/contents",
                form: ["T": token, "i": "4d2", "output": "json"])
            #expect(unpadded.status == .badRequest, "the unpadded value is not the value the read can answer")
            #expect(try requests.body(of: unpadded) == GoogleReaderResponse.errorDocument(
                "googlereader: failed to parse item ID 4d2: failed to parse decimal item ID 4d2: "
                    + "strconv.ParseInt: parsing \"4d2\": invalid syntax").written(),
                "the read reports the value it was given as the decimal read, not as the hex scan")
        }
    }

    ///The two page sizes the records name: the one above the clamp reaches the clamp, and the one
    ///at the clamp is the value the read answers. Read as the read answers it, because the
    ///difference between the two is only visible above the clamp.
    @Test func thePageSizeAboveTheClampAgainstTheValueAtTheClamp() throws {
        let above = try CallingSets.set("FeedFlow").call("reader/api/0/stream/items/ids")?.pageSize
        let at = try CallingSets.set("NetNewsWire").call("reader/api/0/stream/items/ids")?.pageSize
        #expect(above == "15000" && at == "1000", "the records name the two page sizes the pins read")

        #expect(EntryQuery(userID: 1, limit: Int(above ?? "0")).effectiveLimit == EntryQuery.maximumLimit,
            "the value above the clamp reaches the storage layer as the clamp")
        #expect(EntryQuery(userID: 1, limit: Int(at ?? "0")).effectiveLimit == 1000,
            "the value at the clamp is the value the read answered, not the clamp reading it as above itself")
    }

    ///The path no route registers is FeedFlow's item read: the subpath answer is what both sides
    ///give, and the record names the class that says so.
    @Test func theCatchAllAnswerForThePathNoRouteRegisters() async throws {
        try await withServedApp { storage, app, base in
            let requests = GoogleReaderRequests(app, base)
            try await requests.seed(storage, name: name, storedHash: storedHash)
            let token = GoogleReaderToken.derive(username: name, storedHash: storedHash)

            let call = try CallingSets.set("FeedFlow").call("reader/api/0/stream/contents")
            #expect(call != nil, "the record names the call the pin reads")

            let answer = try await requests.get("/reader/api/0/stream/contents?output=json",
                header: "GoogleLogin auth=\(token)")
            #expect(try requests.body(of: answer) == "[]", "the catch-all answer is what this path gives")
            #expect(try requests.body(of: try await requests.get("/reader/api/0/tag/list?output=json",
                header: "GoogleLogin auth=\(token)")) != "[]",
                "a path the port registers answers its own handler, not the catch-all")
        }
    }

    ///The name the switch has no case for is the one NewsFlash calls, and the name is read from the
    ///record's own key: the answer is the base document, which is what the record names as the
    ///branch.
    @Test func theDispatchNameTheSwitchHasNoCaseFor() async throws {
        try await withServedApp { storage, app, base in
            let requests = FeverRequests(app, base)
            let (_, token) = try await requests.seed(storage, name: "feveruser", password: "secret")
            let set = try CallingSets.set("NewsFlash")
            let noCase = try #require(set.call("fever/links")?.key.split(separator: "/").last)
            let hasCase = try #require(set.call("fever/groups")?.key.split(separator: "/").last)

            #expect(set.call("fever/links")?.dispatch == "default",
                "the record names the branch the switch has no case for")
            #expect(set.call("fever/groups")?.dispatch == "case",
                "the record names the branch the switch has a case for")

            let shape = FeverShape.baseDocument(authenticated: 1, lastRefreshed: 0).written()
            #expect(requests.document(of: try await requests.get("\(noCase)&api_key=\(token)")) ==
                shape, "the default branch answers the base document for a name with no case")
            #expect(requests.document(of: try await requests.get("\(hasCase)&api_key=\(token)")) !=
                shape, "a name the switch has a case for answers its own document")
        }
    }

    ///The prefix this port registers no route for is the half the record names as answering nothing
    ///here: the record names two halves for lire, and the one that reaches no route is the REST
    ///half.
    @Test func thePrefixThisPortRegistersNoRouteFor() async throws {
        try await withServedApp { _, app, base in
            let set = try CallingSets.set("lire")
            let partial = set.halves.filter { $0.answeredHere == "no route here" }
            #expect(partial.count == 1 && partial[0].prefix == "/v1",
                "the record names exactly one half as answering nothing here")

            let servedHalf = try await app.client.get(URI(string: base + "/fever?api_key=x"))
            #expect(servedHalf.status != .notFound, "the half the record names as served here answers the read")

            let partialHalf = try await app.client.get(URI(string: base + partial[0].prefix + "/me"))
            #expect(partialHalf.status == .notFound,
                "the prefix the record names as answering nothing here is Vapor's 404")
        }
    }
}
