import Foundation
import Testing
import Vapor
@testable import RivuletApp
@testable import RivuletCore

/// The public icon route, ported from Miniflux `internal/ui/feed_icon.go` at `c4d54f87`: the answer
/// one icon row gets, read over a real socket. The rules the answer is built from — the ETag shape,
/// the `If-None-Match` read, the `Cache-Control` value and the `Expires` shape — are pinned as pure
/// logic by `CachingRulesTests`, so these pins read only what the route adds: which values it takes
/// from the row, which headers it writes on which branch, and the status the two branches answer.
/// The read itself is pinned as a read by `IconRepositoryTests`; a patch that changed which value
/// the route looks up by answers nothing for the row, which reaches the six pins that read the row
/// at once, so no probe here shows the lookup on its own.
///
/// What these pins can fail on, each checked by patching the rule and reverting: that the route
/// answers for a request that carries no token, which is the reference's public route; that the
/// content type is the value the row holds, which a patch that wrote one constant content type
/// fails on; that the content-security-policy line for untrusted content is written for this
/// answer; that the ETag header is built from the hash the row holds; that the caching headers are
/// the values the rules build for the bound the route is given and that `Expires` is written on
/// this path; that the match branch answers 304 with no body and without the headers the body
/// callback writes; and that a row the read does not find answers 404.
///
/// Five pins here are read by more than one patch, which is what the round expects for those rows.
/// Two pins name two rules and so have one patch per rule: the pin for the route answering without
/// a token (the token read not being run, and the answer carrying the bytes of the row) and the pin
/// for the caching headers (the bound the route is given, and `Expires` being written on this
/// path). The patch for the empty side of the guard reaches three pins at once — the token pin, the
/// content-type pin and the policy pin — because the branch the answer takes is chosen by that
/// read, which is the row the round records with four pins. The caching-headers pin is not reached,
/// because the headers it reads are written before that read runs. The match pin is read by its own
/// patch and by the patch that names which value the `ETag` is built from, because it reads the
/// header value the route builds from the row. Every other patch fires one pin, and the socket pins
/// read presence or which row value a header is built from rather than the output of a rule pinned
/// in the pure suite, so the patches for the pure rules reach only the pins that name them — the
/// guard patch is the exception, because it changes which branch the answer takes.
///
/// What these pins cannot fail on: the instant `Expires` is built from, which is the clock the run
/// reads and no test can name — the shape and the zone are pinned by `CachingRulesTests`, which
/// carries the whole string, so the shape cannot be read apart from the zone; the compression the
/// reference skips for a body that is not SVG, which this port has no middleware for at all, and
/// the `Vary` header the reference writes only above its compression threshold, which no answer of
/// this path reaches; the body half of the match pin, which cannot be shown because the framework
/// writes no body for a `304` answer, so a patch that writes the bytes on that branch still answers
/// an empty body — the pin reads it, and the probe for it is recorded as not biting; the HTML
/// shapes the reference answers for a missing row and for a storage failure, which this port has no
/// layer for — the pins read the status this port answers with, and the shape difference is
/// recorded in `docs/parity.md`; the three headers the builder writes on every answer, which are
/// the same rule as the one `GoogleReaderAuthTests` pins on that path, so a patch to them fires
/// that suite as well and this suite claims no single-firing for them; and the randomness of the
/// `external_id` the path is built from, which these pins read only as the value the row carries.
///
/// Routing is the framework's rule, not this file's: the reference registers the exact path before
/// its subtree pattern, and the port registers one path with the id segment required, which Vapor's
/// router answers as the most specific match. No pin here can show that, so nothing in this suite
/// claims single-firing for it.
///
/// The pins that read a response shape carry the token as the transport reads it for a GET, so the
/// patch for the unauthenticated rule fires only the pin that names it and leaves the others
/// passing. The token read itself is pinned by `GoogleReaderAuthTests`, and a patch to that read
/// reaches these pins too, so this suite claims no single-firing for it either.
@Suite struct IconRouteTests {
    @Test func theIconRouteAnswersForARequestThatCarriesNoToken() async throws {
        try await withServedApp { storage, app, base in
            let icon = try await seedIcon(storage, hash: "hash-a", mimeType: "image/png",
                content: Data([1, 2, 3]))
            let response = try await get(app, base, path: "/feed-icon/\(icon.externalID)")
            #expect(response.status == .ok, "the route is not behind the token read")
            #expect(try bytes(of: response) == [1, 2, 3], "the bytes the row holds")
        }
    }

    @Test func theContentTypeWrittenIsTheValueTheRowHolds() async throws {
        try await withServedApp { storage, app, base in
            let icon = try await seedIcon(storage, hash: "hash-b", mimeType: "image/svg+xml",
                content: Data([9]))
            let response = try await getWithToken(app, base, storage: storage,
                path: "/feed-icon/\(icon.externalID)")
            // A patch that wrote one constant content type answered `image/png` here, which is the
            // value the other pins' rows hold and not this row's.
            #expect(response.headers.first(name: "Content-Type") == "image/svg+xml",
                "the content type the row carries, not a constant")
        }
    }

    @Test func theUntrustedContentPolicyIsWrittenForThisAnswer() async throws {
        try await withServedApp { storage, app, base in
            let icon = try await seedIcon(storage, hash: "hash-c", mimeType: "image/png",
                content: Data([1]))
            let response = try await getWithToken(app, base, storage: storage,
                path: "/feed-icon/\(icon.externalID)")
            #expect(response.headers.first(name: "Content-Security-Policy") ==
                "default-src 'none'; form-action 'none'; sandbox;", "the policy the reference names")
        }
    }

    @Test func theETagWrittenCarriesTheHashTheRowHolds() async throws {
        try await withServedApp { storage, app, base in
            let icon = try await seedIcon(storage, hash: "hash-d", mimeType: "image/png",
                content: Data([1]))
            let response = try await getWithToken(app, base, storage: storage,
                path: "/feed-icon/\(icon.externalID)")
            // This pin reads which value the header is built from, not the shape the rule adds to
            // it: a patch that wrote the external id or the row's content type answered a value
            // that does not carry the hash. The shape is pinned by `CachingRulesTests`, so the
            // patch that names it leaves this pin passing.
            #expect(try #require(response.headers.first(name: "ETag")).range(of: icon.hash) != nil,
                "the hash the row holds")
        }
    }

    @Test func theCachingHeadersWrittenAreTheValuesTheRulesBuildForTheBound() async throws {
        try await withServedApp { storage, app, base in
            let icon = try await seedIcon(storage, hash: "hash-e", mimeType: "image/png",
                content: Data([1]))
            let response = try await getWithToken(app, base, storage: storage,
                path: "/feed-icon/\(icon.externalID)")
            // The bound is the one the reference gives the builder (72h), read as the seconds the
            // value carries. A patch that passed a different bound or wrote the header as a
            // constant failed here, and a patch that stopped writing `Expires` failed here too. The
            // order the directives are written in and the shape of the `Expires` value are pinned
            // where the rules live, so the patches that name them leave this pin passing.
            #expect(try #require(response.headers.first(name: "Cache-Control"))
                .range(of: "max-age=259200") != nil, "the bound the route gives the rule")
            #expect(response.headers.first(name: "Expires") != nil, "the header is written on this path")
        }
    }

    @Test func theMatchBranchAnswers304WithNoBodyAndWithoutTheCallbackHeaders() async throws {
        try await withServedApp { storage, app, base in
            let icon = try await seedIcon(storage, hash: "hash-f", mimeType: "image/png",
                content: Data([1, 2]))
            let quoted = "\"\(icon.hash)\""
            // The token is carried so that the patch which names the unauthenticated rule does not
            // reach this pin: the pin that names that rule is the one that sends no token.
            let response = try await getWithToken(app, base, storage: storage,
                path: "/feed-icon/\(icon.externalID)", ifNoneMatch: quoted)
            #expect(response.status == .notModified, "the match branch answers 304")
            #expect((response.body ?? ByteBuffer()).readableBytes == 0, "with no body")
            // The caching headers are written before the read runs, so they are on the answer even
            // when the callback that writes the content type and the policy does not run. A patch
            // that wrote those two outside the callback answered them here as well. The two caching
            // assertions read that the headers are there, not the values the rules build, which are
            // pinned by the pins that name those rules: a patch to either rule reaches this pin
            // too.
            #expect(response.headers.first(name: "ETag") != nil, "the caching headers stay")
            #expect(response.headers.first(name: "Cache-Control") != nil,
                "and the caching header stays")
            #expect(response.headers.first(name: "Content-Type") == nil,
                "the content type is written by the callback, which does not run here")
            #expect(response.headers.first(name: "Content-Security-Policy") == nil,
                "and the policy is written by the callback too")
        }
    }

    @Test func aRowTheReadDoesNotFindAnswers404() async throws {
        try await withServedApp { storage, app, base in
            let response = try await getWithToken(app, base, storage: storage,
                path: "/feed-icon/no-such-row")
            #expect(response.status == .notFound, "the read finds no row")
        }
    }

    // MARK: - Seeds and requests

    /// Inserts the row through the repository, so a pin that reads an answer built from a row reads
    /// a row the repository wrote rather than one the test filled in by hand.
    private func seedIcon(_ storage: SQLiteStorage, hash: String, mimeType: String, content: Data)
        async throws -> Icon {
        try await storage.withConnection { connection in
            try await IconRepository(connection).insert(hash: hash, mimeType: mimeType, content: content)
        }
    }

    /// The request as the transport reads it for a GET. The token is carried so that a patch which
    /// puts this path behind the token read leaves these pins passing: the value is the one a valid
    /// read answers for the row this helper seeds, so the request reaches the handler under the
    /// patch. The pin that names that rule is the one that sends no token.
    private func getWithToken(_ app: Application, _ base: String, storage: SQLiteStorage, path: String,
        ifNoneMatch: String? = nil) async throws -> ClientResponse {
        let name = "alice"
        let storedHash = "stored-hash"
        _ = try await GoogleReaderRequests(app, base).seedIntegrationUser(storage, name: name,
            storedHash: storedHash)
        return try await get(app, base, path: path,
            token: GoogleReaderToken.derive(username: name, storedHash: storedHash),
            ifNoneMatch: ifNoneMatch)
    }

    private func get(_ app: Application, _ base: String, path: String, token: String? = nil,
        ifNoneMatch: String? = nil) async throws -> ClientResponse {
        try await app.client.get(URI(string: base + path)) { request in
            if let token {
                request.headers.add(name: "Authorization", value: "GoogleLogin auth=\(token)")
            }
            if let ifNoneMatch {
                request.headers.add(name: "If-None-Match", value: ifNoneMatch)
            }
        }
    }

    private func bytes(of response: ClientResponse) throws -> [UInt8] {
        Array((try #require(response.body)).readableBytesView)
    }
}
