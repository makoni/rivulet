import Foundation
import Testing
import RivuletCore

/// The bodies the fetcher is given that it cannot read as written: a stream that inflates far past
/// the size it is stored in, and a stream that cannot be inflated at all.
///
/// The rule is which limit answers. The reference has one limit for the body — `MaxBytesReader`,
/// which wraps the reader the decompression produced, so the cap counts the bytes the decoder gives
/// rather than the bytes that arrived on the wire — and no limit on how far a stream may expand.
/// The port had a ratio guard of its own, which refused a body the reference would have read; that
/// guard is gone, so the cap is the only limit here, counted as upstream counts it. The pins read
/// the failure the fetcher reports for the body the decoder produced under the cap.
///
/// What these pins can fail on, each checked by patching the rule and reverting byte-identically,
/// with each probe named by what it flips — five probes for four pins: the ratio guard put back at
/// the ratio the pins read, which answered the size failure the first pin names with the network
/// category and the body the second pin reads with a failure; the cap read as larger than the body
/// the decoder produced, which answered the first pin with a body rather than the size failure; the
/// decompression read as always on, which answered the control reading the body as the server sent
/// it with the inflated bytes; the decompression read as always off, which flipped all four,
/// because nothing is inflated then — the first pin read a body rather than the failure, the second
/// and third read the other side of the same rule, and the last read a stream that the decoder can
/// finish; and the failure that prevented the stream from being inflated mapped to the size
/// category, which answered the last pin with the category the cap owns.
///
/// What these pins cannot fail on: that the cap counts the bytes the decoder produced rather than
/// the bytes on the wire, because no patch of this code can change which parts the accumulator is
/// given — the pipeline hands it the decompressed parts, so the pins read the rule through the
/// guard being absent, which is the only shape the code can express; the correctness of the fixture
/// encoder, which is checked against `gunzip` by hand and which no test here can prove; the wording
/// of the reported failure, which for an inflated stream is the client's; the stream that expands
/// past the cap but is read before the decoder reaches the end of it, which is the same failure the
/// accumulator reports for any body over the cap and is pinned by `FetcherTests`; the choice of
/// `gzip` as the encoding the request advertises, which `docs/reference-notes.md` records; the
/// category the reference gives a stream it cannot inflate — `error.http_body_read`, which is the
/// port's divergence recorded in `docs/reference-notes.md` — so the last pin reads the port's own
/// category rather than the reference's.
@Suite struct FetcherHostileInputTests {
    /// The fixture that inflates to 4129 bytes from a stream of 47, so the body is over the cap
    /// while the bytes on the wire are not.
    private let bombStream = GzipStream.inflating(matchCount: 16)
    private let inflatedBody = Data(repeating: 0x41, count: 4129)

    @Test func theSizeCapCountsTheBodyTheDecoderProducedRatherThanTheStreamThatArrived() async throws {
        try await FetchTestSupport.withServer(behaviors: [
            "/bomb": StubFeedServer.Behavior(headers: ["Content-Encoding": "gzip"], body: bombStream)
        ]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options(maxBodySize: 1024)) { fetcher in
                do {
                    _ = try await fetcher.fetch(FetchRequest(url: server.url("/bomb"), headers: [:]))
                    Issue.record("the fetch read a body over the cap the test named")
                } catch let error as FetchError {
                    guard case FetchError.bodyTooLarge(let limit) = error else {
                        Issue.record("expected the size failure the cap names, got: \(error)")
                        return
                    }
                    // The cap is the only limit that answers here, and the limit it names is the
                    // one the test gave, which the body the decoder produced reached.
                    #expect(limit == 1024)
                }
            }
        }
    }

    @Test func aBodyExpandingFurtherThanTheGuardTheReferenceDoesNotReadIsAcceptedUnderTheCap() async throws {
        // The same fixture with a cap the inflated body fits: the ratio this stream reaches is 88,
        // so a guard on the ratio is what would refuse it, and the reference has none.
        try await FetchTestSupport.withServer(behaviors: [
            "/expanding": StubFeedServer.Behavior(headers: ["Content-Encoding": "gzip"], body: bombStream)
        ]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options(maxBodySize: 8192)) { fetcher in
                let response = try await fetcher.fetch(FetchRequest(url: server.url("/expanding"), headers: [:]))
                #expect(response.status == 200)
                #expect(response.body == inflatedBody)
            }
        }
    }

    @Test func theBodyIsReadAsTheServerSentItWhenDecompressionIsOff() async throws {
        try await FetchTestSupport.withServer(behaviors: [
            "/as-sent": StubFeedServer.Behavior(headers: ["Content-Encoding": "gzip"], body: bombStream)
        ]) { server in
            try await FetchTestSupport.withFetcher(
                options: FetchTestSupport.options(maxBodySize: 8192, decompression: false)
            ) { fetcher in
                let response = try await fetcher.fetch(FetchRequest(url: server.url("/as-sent"), headers: [:]))
                #expect(response.body == bombStream)
            }
        }
    }

    @Test func aStreamTheDecoderCannotFinishIsReportedThroughTheCategoryTheSizeCapDoesNotOwn() async throws {
        // The stream is cut before the end of the block, so the decoder cannot reach the checksum,
        // and nothing over the cap is produced, so the size category cannot be the answer.
        let truncated = bombStream.prefix(30)
        try await FetchTestSupport.withServer(behaviors: [
            "/cut": StubFeedServer.Behavior(headers: ["Content-Encoding": "gzip"], body: Data(truncated))
        ]) { server in
            try await FetchTestSupport.withFetcher(options: FetchTestSupport.options(maxBodySize: 1024)) { fetcher in
                do {
                    _ = try await fetcher.fetch(FetchRequest(url: server.url("/cut"), headers: [:]))
                    Issue.record("expected the stream the decoder cannot finish to fail the fetch")
                } catch let error as FetchError {
                    guard case FetchError.network = error else {
                        Issue.record("expected the network category, got: \(error)")
                        return
                    }
                }
            }
        }
    }
}
