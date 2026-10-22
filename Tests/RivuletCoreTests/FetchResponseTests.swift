import Foundation
import Testing
@testable import RivuletCore

/// Response handling. Ported from Miniflux `internal/reader/fetcher/response_handler.go`
/// (ported tests: `TestIsModified`, `TestRetryDelay`, `TestExpiresInMinutes`,
/// `TestCacheControlMaxAgeInMinutes`, `TestIsCloudflareChallenge`).
@Suite struct FetchResponseTests {
    private let now = 1_750_000_000
    private let url = URL(string: "https://example.com/feed.xml")!

    private func response(
        _ status: Int,
        headers: [String: String] = [:],
        body: Data = Data("<rss></rss>".utf8)
    ) -> FetchResponse {
        FetchResponse(status: status, headers: headers, body: body, effectiveURL: url)
    }

    private func state(etag: String = "", lastModified: String = "") -> FeedFetchState {
        FeedFetchState(feedID: 1, url: url, etag: etag, lastModified: lastModified)
    }

    // MARK: - Modified / not modified

    @Test func conditionalHitIsNotModifiedAndProducesNoError() {
        let cachedLastModified = "Sun, 15 Jun 2025 15:06:40 GMT"
        let response = response(
            304,
            headers: ["ETag": "abc123", "Last-Modified": cachedLastModified],
            body: Data()
        )
        #expect(!response.isModified(against: state(etag: "abc123", lastModified: cachedLastModified)))
        #expect(response.error() == nil)
    }

    @Test func storedValidatorsThatMatchAreNotModified() {
        let cachedLastModified = "Sun, 15 Jun 2025 15:06:40 GMT"
        let response = response(
            200,
            headers: ["ETag": "abc123", "Last-Modified": cachedLastModified]
        )
        #expect(!response.isModified(against: state(etag: "abc123", lastModified: cachedLastModified)))
    }

    @Test func etagTakesPrecedenceOverLastModified() {
        // RFC 9110 §8.8.1: when the response carries an ETag, that is what is compared.
        let cachedLastModified = "Sun, 15 Jun 2025 15:06:40 GMT"
        let lastModifiedOnly = response(
            200,
            headers: ["ETag": "abc123", "Last-Modified": "Mon, 16 Jun 2025 15:06:40 GMT"]
        )
        #expect(!lastModifiedOnly.isModified(against: state(etag: "abc123", lastModified: cachedLastModified)))

        let etagOnly = response(200, headers: ["ETag": "xyz789", "Last-Modified": cachedLastModified])
        #expect(etagOnly.isModified(against: state(etag: "abc123", lastModified: cachedLastModified)))

        let bothChanged = response(
            200,
            headers: ["ETag": "xyz789", "Last-Modified": "Mon, 16 Jun 2025 15:06:40 GMT"]
        )
        #expect(bothChanged.isModified(against: state(etag: "abc123", lastModified: cachedLastModified)))
    }

    @Test func noValidatorsAtAllMeansModified() {
        #expect(response(200).isModified(against: state()))
    }

    // MARK: - Caching headers

    @Test func cachingHeadersAreIgnoredWhenTheResponseForbidsCache() {
        let response = response(200, headers: ["Expires": "0", "ETag": "abc123", "Last-Modified": "x"])
        #expect(response.etag == "")
        #expect(response.lastModified == "")
    }

    @Test func cachingHeadersAreReadOtherwise() {
        let response = response(200, headers: ["Expires": "Wed, 16 Sep 2026 12:00:00 GMT", "ETag": "abc123"])
        #expect(response.etag == "abc123")

        // `header(_:)` reads a name in whatever case the server used, and nil for a name the response
        // does not have.
        #expect(response.header("ETag") == "abc123")
        #expect(response.header("etag") == "abc123")
        #expect(response.header("last-modified") == nil)
    }

    @Test func expiresRoundsUpToTheNextMinute() {
        #expect(response(200).expires(now: now) == .zero)

        // Upstream truncates to a minute and then adds one: a value 599 seconds ahead becomes
        // 10 minutes, the same result the reference test expects.
        let ahead = response(200, headers: ["Expires": "Sun, 15 Jun 2025 15:16:39 GMT"])
        #expect(ahead.expires(now: now) == .seconds(600))

        #expect(response(200, headers: ["Expires": "invalid-date"]).expires(now: now) == .zero)

        // A date already past still yields one minute, because the truncation rounds toward zero.
        let past = response(200, headers: ["Expires": "Sun, 15 Jun 2025 15:06:10 GMT"])
        #expect(past.expires(now: now) == .seconds(60))

        // A past value that truncates to exactly the previous minute yields nothing — 100 seconds past
        // becomes -60, and the minute added on top cancels it. That is what Go's `Truncate` does too, and
        // it is why the rule is "the minute the value falls in", not "any past value".
        let wholeMinutePast = response(200, headers: ["Expires": "Sun, 15 Jun 2025 15:05:00 GMT"])
        #expect(wholeMinutePast.expires(now: now) == .zero)

        // Further past, the truncation lands beyond the previous minute and the delay goes negative: 220
        // seconds past becomes -180, and a minute on top leaves -120. Upstream returns the same negative
        // value — its handler is what absorbs it, taking `max(feed TTL, max-age, expires)`.
        let furtherPast = response(200, headers: ["Expires": "Sun, 15 Jun 2025 15:03:00 GMT"])
        #expect(furtherPast.expires(now: now) == .seconds(-120))
    }

    @Test func cacheControlMaxAgeIsTheFirstMatchingDirective() {
        #expect(response(200).cacheControlMaxAge == .zero)
        #expect(response(200, headers: ["Cache-Control": "max-age=600"]).cacheControlMaxAge == .seconds(600))
        #expect(response(200, headers: ["Cache-Control": "max-age=invalid"]).cacheControlMaxAge == .zero)
        #expect(
            response(200, headers: ["Cache-Control": "no-cache, max-age=300"]).cacheControlMaxAge
                == .seconds(300)
        )
    }

    @Test func retryAfterAcceptsSecondsAndHttpDate() {
        #expect(response(200).retryAfter(now: now) == .zero)
        #expect(response(429, headers: ["Retry-After": "42"]).retryAfter(now: now) == .seconds(42))

        let date = response(429, headers: ["Retry-After": "Sun, 15 Jun 2025 15:07:22 GMT"])
        #expect(date.retryAfter(now: now) == .seconds(42))

        // Upstream does not clamp a date in the past: the delay is negative.
        let past = response(429, headers: ["Retry-After": "Sun, 15 Jun 2025 15:06:30 GMT"])
        #expect(past.retryAfter(now: now) == .seconds(-10))

        #expect(response(429, headers: ["Retry-After": "soon"]).retryAfter(now: now) == .zero)
    }

    @Test func httpDateNeedsTheWeekdayAndTheCommaLikeTheReferenceLayout() {
        // Rivulet's own test — the reference has no test for its date parser. It pins what Go's
        // `time.Parse` accepts with `time.RFC1123` ("Mon, 02 Jan 2006 15:04:05 MST"): the weekday with
        // its comma is part of the format, so the comma-less form is not an HTTP-date and yields no
        // delay, and a zone name other than GMT/UTC is not read at all (recorded deviation — Go applies
        // its zone table, so `EST` would shift the time).
        #expect(HTTPDate.parse("Sun, 15 Jun 2025 15:07:22 GMT") != nil)
        #expect(HTTPDate.parse("Sun 15 Jun 2025 15:07:22 GMT") == nil)
        #expect(HTTPDate.parse("Sun, 15 Jun 2025 15:07:22 EST") == nil)
        // The layout reads the day as two digits, so a single digit is not an HTTP-date either.
        #expect(HTTPDate.parse("Sun, 2 Jan 2025 15:07:22 GMT") == nil)
        // Go looks the weekday up in its day-name table and range-checks the fields, so a made-up
        // weekday or an out-of-range clock is not an HTTP-date either, and the year is four digits.
        #expect(HTTPDate.parse("Xyz, 15 Jun 2025 07:28:00 GMT") == nil)
        #expect(HTTPDate.parse("Sun, 32 Jun 2025 07:28:00 GMT") == nil)
        #expect(HTTPDate.parse("Sun, 15 Jun 2025 25:70:80 GMT") == nil)
        #expect(HTTPDate.parse("Sun, 15 Jun 20156 07:28:00 GMT") == nil)
        // Go consumes exactly three characters for the weekday, so a long name is not this layout, and
        // the minute and second are fixed at two digits while the hour is not.
        #expect(HTTPDate.parse("Monday, 15 Jun 2025 07:28:00 GMT") == nil)
        #expect(HTTPDate.parse("Wed, 15 Jun 2025 7:28:00 GMT") != nil)
        #expect(HTTPDate.parse("Wed, 15 Jun 2025 7:28:0 GMT") == nil)
        #expect(HTTPDate.parse("Wed, 15 Jun 2025 07:2:00 GMT") == nil)
        // Go validates the day against the month after parsing, so 31 February is not a date.
        #expect(HTTPDate.parse("Sun, 31 Feb 2025 07:28:00 GMT") == nil)

        // Rivulet splits the value on spaces, so it reads the padded ends. Go rejects a leading space
        // before the weekday and any leftover after the zone, though a run of spaces in the middle counts as
        // one separator, so the doubled space parses upstream as well. Leftover text that is not spaces is
        // rejected here too, as it is upstream. Rivulet does not read a fractional second, which Go accepts
        // after the seconds field.
        #expect(HTTPDate.parse("Sun,  15 Jun 2025 07:28:00 GMT") != nil)
        #expect(HTTPDate.parse(" Sun, 15 Jun 2025 07:28:00 GMT") != nil)
        #expect(HTTPDate.parse("Sun, 15 Jun 2025 07:28:00 GMT x") == nil)
        #expect(HTTPDate.parse("Sun, 15 Jun 2025 07:28:00,500 GMT") == nil)

        // Rivulet is stricter at the boundary than Go's numeric path, which reads fixed-width two-digit
        // fields and allows an hour of 24 and a minute of 60 (`hr > 24`, `mm > 60`): `+2400` and `+0360`
        // parse under Go's RFC1123Z. The four-digit form is Rivulet's addition relative to RFC1123 — that
        // layout reads a zone name, and a signed hour there goes through `parseSignedOffset`, which
        // rejects `+0730`.
        #expect(HTTPDate.parse("Sun, 15 Jun 2025 07:28:00 +2400") == nil)
        #expect(HTTPDate.parse("Sun, 15 Jun 2025 07:28:00 +0360") == nil)
        #expect(HTTPDate.parse("Sun, 15 Jun 2025 07:28:00 +2359") != nil)

        let withoutComma = response(429, headers: ["Retry-After": "Sun 15 Jun 2025 15:07:22 GMT"])
        #expect(withoutComma.retryAfter(now: now) == .zero)
    }

    @Test func anOffsetIsADifferenceInSecondsNotItsDigits() throws {
        // The regression: 07:28 at +0200 is 05:28 UTC, so the instant is 7200 seconds earlier than the
        // same clock time read at GMT. Reading the four-digit offset is Rivulet's own addition, so this
        // is Rivulet's own contract — Go's `RFC1123` layout would not read the offset at all, and an
        // offset applied in the units of its digits (120 instead of 7200) shifts the time by hours.
        let utc = try #require(HTTPDate.parse("Sun, 15 Jun 2025 07:28:00 GMT"))
        #expect(HTTPDate.parse("Sun, 15 Jun 2025 07:28:00 +0200") == utc - 7_200)
        #expect(HTTPDate.parse("Sun, 15 Jun 2025 07:28:00 -0230") == utc + 9_000)
    }

    @Test func rateLimitedStatusIsRecognised() {
        #expect(response(429).isRateLimited)
        #expect(!response(200).isRateLimited)
    }

    // MARK: - Cloudflare challenges

    @Test func cloudflareChallengeNeedsTheSignalAndHtml() {
        let challenge = response(
            403,
            headers: ["Cf-Mitigated": "challenge", "Content-Type": "text/html; charset=UTF-8"]
        )
        #expect(challenge.isCloudflareChallenge)

        // The reference relies on `Cf-Mitigated: challenge` only: a Cloudflare `Server` or
        // `Cf-Ray` header with HTML is not a challenge.
        for status in [200, 500, 503] {
            let lookalike = response(
                status,
                headers: ["Server": "cloudflare", "Cf-Ray": "8abc123def456-IAD", "Content-Type": "text/html"]
            )
            #expect(!lookalike.isCloudflareChallenge, "status \(status)")
        }
        #expect(
            !response(403, headers: ["Cf-Mitigated": "challenge", "Content-Type": "application/json"])
                .isCloudflareChallenge
        )
        #expect(
            !response(200, headers: ["Cf-Mitigated": "challenge", "Content-Type": "text/html"])
                .isCloudflareChallenge
        )
    }

    // MARK: - Status classification

    @Test func statusMessagesFollowTheReference() throws {
        let expected: [(Int, String)] = [
            (401, "fetcher: access unauthorized (401 status code)"),
            (403, "fetcher: access forbidden (403 status code)"),
            (429, "fetcher: too many requests (429 status code)"),
            (404, "fetcher: resource not found (404 status code)"),
            (410, "fetcher: resource not found (410 status code)"),
            (500, "fetcher: remote server error (500 status code)"),
            (502, "fetcher: bad gateway (502 status code)"),
            (503, "fetcher: service unavailable (503 status code)"),
            (504, "fetcher: gateway timeout (504 status code)"),
            (418, "fetcher: unexpected status code (418 status code)"),
        ]
        for (status, message) in expected {
            let error = try #require(response(status).error())
            #expect(error == .status(status), Comment("\(status)"))
            #expect(String(describing: error) == message, Comment("\(status)"))
        }
    }

    @Test func challengeStatusIsReportedAsAChallenge() throws {
        let error = try #require(
            response(403, headers: ["Cf-Mitigated": "challenge", "Content-Type": "text/html"]).error()
        )
        #expect(error == .cloudflareChallenge(403))
        #expect(String(describing: error) == "fetcher: blocked by Cloudflare challenge (403 status code)")
    }

    @Test func emptyBodyIsAnErrorExceptForAConditionalHit() throws {
        let empty = try #require(response(200, body: Data()).error())
        #expect(String(describing: empty) == "fetcher: empty response body")
        #expect(response(304, body: Data()).error() == nil)
        #expect(response(200, body: Data("<rss></rss>".utf8)).error() == nil)
    }

    @Test func effectiveURLIsStoredRatherThanDerivedFromTheRequest() throws {
        // The fetcher builds a response with the URL it actually served, and the value is kept as
        // given, not worked out from the request. The redirect path that makes it the last hop is
        // proven in `Tests/RivuletIntegrationTests/FetcherTests.swift`.
        let target = URL(string: "https://cdn.example.com/feed.xml")!
        let response = FetchResponse(status: 200, headers: [:], body: Data("x".utf8), effectiveURL: target)
        #expect(response.effectiveURL == target)
        #expect(response.contentType == "")
    }
}
