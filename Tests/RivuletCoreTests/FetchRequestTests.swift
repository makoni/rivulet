import Foundation
import Testing
@testable import RivuletCore

/// Request building, ported from Miniflux `internal/reader/fetcher/request_builder.go`
/// (ported tests: `TestRequestBuilder_WithETag`, `TestRequestBuilder_WithLastModified`,
/// `TestRequestBuilder_WithUserAgent`).
///
/// The two tests for the path a URL without feed state takes can fail on the rules they name:
/// the encoding follows the option, the accept header is the option's, the user agent is the
/// option's when no feed value is read, and the scheme guard refuses a URL the fetcher does not
/// dial. That the path sends no conditional headers cannot fail, because there are no stored
/// validators on it to send; it is stated in ``FetchRequestBuilder/build(url:)``.
@Suite struct FetchRequestTests {
    private let options = FetcherOptions.defaults

    private func state(
        _ url: String,
        etag: String = "",
        lastModified: String = "",
        userAgent: String = "",
        ignoreHTTPCache: Bool = false,
        fetchViaProxy: Bool = false
    ) -> FeedFetchState {
        FeedFetchState(
            feedID: 1,
            url: URL(string: url)!,
            etag: etag,
            lastModified: lastModified,
            userAgent: userAgent,
            ignoreHTTPCache: ignoreHTTPCache,
            fetchViaProxy: fetchViaProxy
        )
    }

    @Test func defaultHeadersFollowTheReference() throws {
        let request = try FetchRequestBuilder(options: options).build(feed: state("https://example.com/feed.xml"))

        #expect(request.url == URL(string: "https://example.com/feed.xml"))
        #expect(request.headers["User-Agent"] == FetcherOptions.defaultUserAgent)
        #expect(request.headers["Accept"] == FetcherOptions.defaultAcceptHeader)
        // Rivulet advertises gzip only — brotli is deferred (see docs/reference-notes.md).
        #expect(request.headers["Accept-Encoding"] == "gzip")
        // The reference sends `Connection: close`; Rivulet keeps its connection pool, so it
        // does not — a deliberate deviation recorded in the reference notes.
        #expect(request.headers["Connection"] == nil)
    }

    @Test func identityEncodingIsAdvertisedWhenCompressionIsOff() throws {
        let options = FetcherOptions(
            timeout: .seconds(20),
            userAgent: FetcherOptions.defaultUserAgent,
            acceptHeader: FetcherOptions.defaultAcceptHeader,
            maxBodySize: 15 * 1024 * 1024,
            maxRedirects: 10,
            decompression: false,
            ignoreHTTPCache: false,
            proxyURL: nil,
            allowPrivateNetworks: false
        )
        let request = try FetchRequestBuilder(options: options).build(feed: state("https://example.com/feed.xml"))
        #expect(request.headers["Accept-Encoding"] == "identity")
    }

    @Test func conditionalHeadersAreSentOnlyWhenStored() throws {
        let builder = FetchRequestBuilder(options: options)

        let withBoth = try builder.build(
            feed: state("https://example.com/feed.xml", etag: "test-etag", lastModified: "Wed, 21 Oct 2026 07:28:00 GMT")
        )
        #expect(withBoth.headers["If-None-Match"] == "test-etag")
        #expect(withBoth.headers["If-Modified-Since"] == "Wed, 21 Oct 2026 07:28:00 GMT")

        // Upstream sets these headers only when the stored value is not empty.
        let withoutEtag = try builder.build(feed: state("https://example.com/feed.xml", lastModified: "x"))
        #expect(withoutEtag.headers["If-None-Match"] == nil)
        #expect(withoutEtag.headers["If-Modified-Since"] == "x")
    }

    @Test func cacheValidatorsAreSkippedForAForcedRefreshOrAnIgnoringFeed() throws {
        let builder = FetchRequestBuilder(options: options)
        let feed = state("https://example.com/feed.xml", etag: "test-etag", lastModified: "x", ignoreHTTPCache: true)

        let forced = try builder.build(feed: feed, forceRefresh: true)
        #expect(forced.headers["If-None-Match"] == nil)
        #expect(forced.headers["If-Modified-Since"] == nil)

        let ignoring = try builder.build(feed: feed)
        #expect(ignoring.headers["If-None-Match"] == nil)

        // The same feed still sends validators when the refresh is not forced.
        let normal = try builder.build(feed: state("https://example.com/feed.xml", etag: "test-etag"))
        #expect(normal.headers["If-None-Match"] == "test-etag")
    }

    @Test func perFeedUserAgentWinsOverTheDefault() throws {
        let request = try FetchRequestBuilder(options: options).build(
            feed: state("https://example.com/feed.xml", userAgent: "NetNewsWire/6")
        )
        #expect(request.headers["User-Agent"] == "NetNewsWire/6")
    }

    @Test func theApplicationProxyIsAttachedOnlyToFeedsThatAskForIt() throws {
        let proxied = FetcherOptions(
            timeout: FetcherOptions.defaultTimeout,
            userAgent: FetcherOptions.defaultUserAgent,
            acceptHeader: FetcherOptions.defaultAcceptHeader,
            maxBodySize: FetcherOptions.defaultMaxBodySize,
            maxRedirects: FetcherOptions.defaultMaxRedirects,
            decompression: true,
            ignoreHTTPCache: false,
            proxyURL: "http://proxy.example.com:3128",
            allowPrivateNetworks: false
        )
        let builder = FetchRequestBuilder(options: proxied)

        // Upstream: `UseCustomApplicationProxyURL(feed.FetchViaProxy)` — the configured proxy is
        // used for the feeds that ask for it, not for every feed.
        let throughProxy = try builder.build(feed: state("https://example.com/feed.xml", fetchViaProxy: true))
        #expect(throughProxy.proxyURL == URL(string: "http://proxy.example.com:3128"))

        let direct = try builder.build(feed: state("https://example.com/feed.xml"))
        #expect(direct.proxyURL == nil)

        // Nothing configured, nothing to attach.
        let withoutProxy = try FetchRequestBuilder(options: FetcherOptions.defaults).build(
            feed: state("https://example.com/feed.xml", fetchViaProxy: true)
        )
        #expect(withoutProxy.proxyURL == nil)
    }

    @Test func anUnreadableProxyURLIsAFetchErrorLikeUpstream() {
        let options = FetcherOptions(
            timeout: FetcherOptions.defaultTimeout,
            userAgent: FetcherOptions.defaultUserAgent,
            acceptHeader: FetcherOptions.defaultAcceptHeader,
            maxBodySize: FetcherOptions.defaultMaxBodySize,
            maxRedirects: FetcherOptions.defaultMaxRedirects,
            decompression: true,
            ignoreHTTPCache: false,
            proxyURL: "proxy without a scheme",
            allowPrivateNetworks: false
        )

        #expect(throws: FetchError.invalidProxyURL("proxy without a scheme")) {
            _ = try FetchRequestBuilder(options: options).build(
                feed: state("https://example.com/feed.xml", fetchViaProxy: true)
            )
        }
    }

    @Test func theURLPathSendsTheHeadersTheOptionsName() throws {
        // The icon path builds a request from a URL with no feed state, so the only
        // rules it reads are the ones the options name: the encoding the option asks
        // for, and the accept header. These are the builder's rules, shared with the
        // feed path through `headers(userAgent:)`.
        let off = FetcherOptions(
            timeout: FetcherOptions.defaultTimeout,
            userAgent: FetcherOptions.defaultUserAgent,
            acceptHeader: FetcherOptions.defaultAcceptHeader,
            maxBodySize: FetcherOptions.defaultMaxBodySize,
            maxRedirects: FetcherOptions.defaultMaxRedirects,
            decompression: false,
            ignoreHTTPCache: false,
            proxyURL: nil,
            allowPrivateNetworks: false
        )

        let offBuilder = FetchRequestBuilder(options: off)
        let identity = try offBuilder.build(url: "https://example.org/favicon.ico")
        #expect(identity.headers["Accept-Encoding"] == "identity")
        #expect(identity.headers["Accept"] == FetcherOptions.defaultAcceptHeader)

        let onBuilder = FetchRequestBuilder(options: options)
        let gzip = try onBuilder.build(url: "https://example.org/favicon.ico")
        #expect(gzip.headers["Accept-Encoding"] == "gzip")
        #expect(gzip.headers["User-Agent"] == FetcherOptions.defaultUserAgent)
    }

    @Test func aURLTheFetcherDoesNotDialIsTheInvalidURLRule() throws {
        // The same guard the feed path enforces, read here without a feed state.
        let builder = FetchRequestBuilder(options: options)
        #expect(throws: FetchError.invalidURL("ftp://example.org/icon.png")) {
            _ = try builder.build(url: "ftp://example.org/icon.png")
        }
        #expect(throws: FetchError.invalidURL("/icon.png")) {
            _ = try builder.build(url: "/icon.png")
        }
    }
}
