import Foundation
import Testing
@testable import RivuletCore

/// The response an icon URL answers with, read as the icon the storage layer stores. Ported from
/// `internal/reader/icon/finder.go` (`downloadIcon`); the upstream file has no test for this
/// half, so these pins are the port's own, each one naming a rule the reference states.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the checksum
/// covers the body bytes, not the response as a whole and not the URL — a patch that hashes the
/// URL or the content type fails the pins that name the bytes; the content is the bytes as the
/// fetcher read them; the content type is the header as it was read, with its parameters,
/// because the reference compares the whole value against the known icon types — a patch that
/// drops the parameter before comparing fails the case that says so; the status failure and the
/// empty-body failure are read in that order, so a patch that returns the empty body for a
/// status response fails the case that names the order; the icon path refuses an empty body for a
/// conditional hit, which the feed path accepts, so a patch that reuses the feed response's error
/// as it is fails that pin; and the Cloudflare case is read through the response's own rule rather
/// than decided here, so a patch that compares only the status fails it.
///
/// What they cannot fail on: the checksum function, which is the port's SHA-256 and not the
/// reference's `crypto.HashFromBytes` (FNV-128a), recorded in `docs/parity.md` and pinned as a
/// value by `HashTests` for the entry path; the size cap, which the fetcher applies before this
/// layer sees the bytes and is pinned by the fetch suite alone — nothing here reads an icon body
/// past the cap; the basis the empty-body rule measures, which `docs/parity.md` records; and the
/// reference's error wording, which this port keeps as typed cases.
@Suite struct IconDownloadTests {
    @Test func theChecksumCoversTheBodyBytes() throws {
        // The pins compare the port's SHA-256 over the decoded bytes; `HashesTests` pins
        // the function.
        let body = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let candidate = try IconDownload.candidate(from: response(status: 200,
            headers: ["Content-Type": "image/png"], body: body))
        #expect(candidate.content == body)
        #expect(candidate.mimeType == "image/png")
        #expect(candidate.hash ==
            "4c4b6a3be1314ab86138bef4314dde022e600960d8689a2c8f8631802d20dab6")
    }

    @Test func contentTypeIsKeptAsItWasReadIncludingItsParameter() throws {
        // `normalizeMimeType` in the storage layer compares the whole value, so a content type that
        // carries a parameter is not one of the known icon types and is stored as
        // `image/x-icon`. This layer hands the value on as the header gave it; the
        // storage half is pinned by `IconRepositoryTests`.
        let candidate = try IconDownload.candidate(from: response(status: 200,
            headers: ["Content-Type": "image/png; charset=utf-8"], body: Data([1, 2, 3])))
        #expect(candidate.mimeType == "image/png; charset=utf-8")
    }

    @Test func anEmptyBodyIsAFailureEvenForAConditionalHit() throws {
        // The reference checks the status first and then reads the body, which reports
        // an empty buffer for any response. The feed path accepts a `304` because there
        // is nothing to re-parse; the icon path has no such exception.
        #expect(throws: FetchError.emptyBody) {
            try IconDownload.candidate(from: response(status: 304, body: Data()))
        }
    }

    @Test func aStatusFailureIsReportedBeforeTheEmptyBody() throws {
        // Both rules hold for this response, and the reference reports the status
        // because its handler reads the error before the body.
        #expect(throws: FetchError.status(404)) {
            try IconDownload.candidate(from: response(status: 404, body: Data()))
        }
    }

    @Test func aCloudflareChallengeIsTheFailureTheFetchResponseNames() throws {
        // The same order, read through the response's own rule, which this layer does
        // not re-implement.
        let body = Data("<html>challenge</html>".utf8)
        #expect(throws: FetchError.cloudflareChallenge(403)) {
            try IconDownload.candidate(from: response(status: 403,
                headers: ["Content-Type": "text/html", "Cf-Mitigated": "Challenge"], body: body))
        }
    }

    private func response(status: Int, headers: [String: String] = [:], body: Data)
        -> FetchResponse {
        FetchResponse(status: status, headers: headers, body: body,
            effectiveURL: URL(string: "https://example.org/icon.png")!)
    }
}
