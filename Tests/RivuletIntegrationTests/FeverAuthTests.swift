import Foundation
import Testing
import Vapor
import RivuletApp
@testable import RivuletCore

/// The transport this path reads, over a real socket: `internal/fever/middleware.go` at `c4d54f87`.
/// The goldens are the reference's own answers for these inputs at the toolchain `go.mod` pins.
///
/// What these pins can fail on, each checked by patching the rule and reverting (3 pins, 5 probes:
/// 3 on the failure-document pin, 2 on the merged-form pin): the answer for a run the read failed
/// is the failure document at HTTP 200, which a patch that wrote the common values for it — auth 1
/// and the run's instant — fails on, and a patch that answered 401 fails on too; that the key is
/// read through the merged form and not through the header this path's sibling reads, which a patch
/// that read the `Authorization` header fails on; and the order the merged form answers in for a
/// name both halves carry, which a patch that read the multipart part first fails on, and that a
/// body this read cannot read adds nothing to the form rather than reporting a failure, so for a
/// name only the body carries the guard sees the empty value and the answer is the failure
/// document, not a 400, while the pairs the query half put in the form survive that failure, which
/// a patch that answered the whole form as nothing on a failed body read fails on.
///
/// The `HEAD` pin has no patch, because nothing it reads can fail on one. The port registers the
/// method, but Vapor forwards a `HEAD` request to the `GET` route when no `HEAD` route is
/// registered, so taking the registration away changes nothing the pin can read — the reference's
/// pattern answers any method, and the port names the three the client uses, recorded in
/// `docs/parity.md`. The pin reads that the method reaches the handler, that the answer it reaches
/// is the same handler's answer, and that the answer is read through the framing name, because no
/// bytes are written for this method. The length cannot fail either: the failure document and the
/// common-value document are the same length, because only the digits of two values differ, so that
/// assertion reads the framing name rather than the document, and the failure document is named as
/// a literal because it is the only one whose length can be stated without the clock field.
///
/// What these pins cannot show: the port's own `HEAD` registration, because Vapor forwards a `HEAD`
/// request to the `GET` route when no `HEAD` route is registered, so taking the registration away
/// changes nothing a pin can read — the reference's pattern answers any method, and the port names
/// the three the client uses, recorded in `docs/parity.md`; the value of the clock field, which is
/// the instant the handler runs at, so the pins read the field's position through the placeholder
/// the request helper names; the three headers the response builder writes on every response of
/// this path, which `GoogleReaderAuthTests` pins for the same builder; the `SetLastLogin` write the
/// reference's middleware makes after the read passes, which this port has no column for and so
/// nothing can pin; and the constant-time form of the compare, which this read does not have — it
/// compares the stored value as read; and the bytes this method does not write, which is the
/// transport's rule and not one a patch can change, so the pin reads the answer for it as the empty
/// value rather than probing it.
@Suite struct FeverAuthTests {
    init() {
        TestLogging.bootstrapOnce()
    }

    @Test func noKeyAnswersTheFailureDocumentAtTwoHundredAndTheHeaderIsNotReadHere() async throws {
        try await withServedApp { storage, app, base in
            let requests = FeverRequests(app, base)
            let (_, token) = try await requests.seed(storage, name: "alice", password: "secret")

            // A patch that ran the common-value rule for this answer answered auth 1 with the run's
            // instant, and a patch that answered the status the sibling path answers with
            // failed here.
            let response = try await requests.get("api")
            #expect(response.status == .ok, "the failure answer is 200, not 401")
            #expect(requests.contentType(of: response) == "application/json", "the JSON shape")
            #expect(requests.body(of: response) ==
                "{\"api_version\":3,\"auth\":0,\"last_refreshed_on_time\":0}", "the two zeros")
            #expect(response.headers.first(name: "X-Content-Type-Options") == "nosniff",
                "the three headers the response builder writes are written on this path too")

            // The value the derivation gives authenticates when it is read through the form: the
            // same value in the header this path does not read answers the failure document.
            let header = try await app.client.get(URI(string: base + "/fever/?api")) { request in
                request.headers.add(name: "Authorization", value: "GoogleLogin auth=\(token)")
            }
            #expect(requests.body(of: header) ==
                "{\"api_version\":3,\"auth\":0,\"last_refreshed_on_time\":0}",
                "the header is not this path's read")
            let form = try await requests.post("api", raw: "api_key=\(token)")
            #expect(requests.document(of: form) ==
                "{\"api_version\":3,\"auth\":1,\"last_refreshed_on_time\":0}", "the same value as a part of the form")
        }
    }

    @Test func theOrderForTheNameBothHalvesCarryIsTheQueryFirstAndAFailedBodyReadAddsNothingToTheForm() async throws {
        try await withServedApp { storage, app, base in
            let requests = FeverRequests(app, base)
            let (_, token) = try await requests.seed(storage, name: "alice", password: "secret")

            // The query pair comes before the part, so this request authenticates on the value the
            // query carries. The reverse — the value in the part and another in the query — answers
            // the failure document, which is what a patch that read the part first fails on.
            let queryWins = try await requests.get("api&api_key=\(token)",
                body: requests.multipart([(name: "api_key", value: "other")]))
            #expect(requests.document(of: queryWins) ==
                "{\"api_version\":3,\"auth\":1,\"last_refreshed_on_time\":0}", "the pair the read takes first")
            let partLoses = try await requests.get("api&api_key=other",
                body: requests.multipart([(name: "api_key", value: token)]))
            #expect(requests.body(of: partLoses) ==
                "{\"api_version\":3,\"auth\":0,\"last_refreshed_on_time\":0}", "the other way round")

            // A body this read cannot read adds nothing to the form, and that is the rule the guard
            // reads: for a name only the body carries, the guard sees the empty value and the
            // answer is the failure document at 200 — not the shape the sibling path answers for
            // a form it cannot parse. A patch that reported the read's failure as a 400 failed
            // here, and a patch that answered the whole form as nothing when the body read failed
            // answered the failure document on the first half, because `ParseForm` runs before the
            // body read and keeps the pairs the query carried.
            let broken = try await requests.get("api&api_key=\(token)",
                body: "--x\r\nContent-Disposition: form-data; name=api_key\r\n\r\nvalue\r\njunk")
            #expect(requests.document(of: broken) ==
                "{\"api_version\":3,\"auth\":1,\"last_refreshed_on_time\":0}",
                "the failed body read takes nothing from the half that was read")
            let nothing = try await requests.get("api",
                body: "--x\r\nContent-Disposition: form-data; name=api_key\r\n\r\n\(token)\r\njunk")
            #expect(nothing.status == .ok, "a body the read cannot read is not a failure")
            #expect(requests.body(of: nothing) ==
                "{\"api_version\":3,\"auth\":0,\"last_refreshed_on_time\":0}", "and the guard reads the empty value")
        }
    }

    @Test func headOnTheBaseRouteReachesTheSameHandlerThroughItsHeaders() async throws {
        try await withServedApp { storage, app, base in
            let requests = FeverRequests(app, base)
            let (_, token) = try await requests.seed(storage, name: "alice", password: "secret")
            let key = "api&api_key=\(token)"
            let failure = "{\"api_version\":3,\"auth\":0,\"last_refreshed_on_time\":0}"

            // The reference's pattern answers any method. The port registers this one, but Vapor
            // forwards a HEAD request to the GET route when no HEAD route is registered, so the
            // registration itself is not something a patch can show — see the suite header. What
            // this pin reads is that the method reaches the handler.
            let written = try await requests.get(key)
            let answered = try await requests.head(key)
            #expect(answered.status == .ok, "the method reaches the handler")
            #expect(requests.contentType(of: answered) == requests.contentType(of: written),
                "and the same response builder ran on it")

            // No bytes are written for this method, on either side, so the answer is read through
            // the length the transport keeps for it. The two assertions below read that length: one
            // against the GET half and one against the failure document as a literal, which is the
            // only document whose length can be stated without the clock field. Neither can fail on
            // a patch, because the failure document and the common-value document are the same
            // length — only the digits of two values differ — so these assertions read the framing
            // name rather than the document. This is the pin the suite header names as having
            // no patch.
            #expect(requests.body(of: answered) == "", "no bytes are written on this method")
            let length = requests.body(of: written).count
            #expect(requests.header(answered, "Content-Length") == String(length),
                "the framing headers advertise what the GET half answered")
            let failed = try await requests.head("api")
            #expect(requests.header(failed, "Content-Length") == String(failure.count),
                "the failure answer reaches this method too")
        }
    }
}
