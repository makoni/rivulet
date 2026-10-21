import Foundation

/// Builds the outgoing fetch request.
///
/// Ported from Miniflux `internal/reader/fetcher/request_builder.go` (Apache-2.0); adapted for
/// Swift. Two deliberate deviations, recorded in `docs/reference-notes.md`: the reference
/// advertises `br,gzip` — Rivulet advertises `gzip` because AsyncHTTPClient decompresses gzip
/// and deflate only — and the reference sets `Connection: close`, which Rivulet does not send
/// because it keeps a connection pool.
public struct FetchRequestBuilder: Sendable {
    /// Options the request is built from.
    public let options: FetcherOptions

    /// Creates a builder for the given options.
    public init(options: FetcherOptions) {
        self.options = options
    }

    /// Builds the request for one feed.
    ///
    /// - Parameters:
    ///   - feed: The stored feed state.
    ///   - forceRefresh: A forced refresh sends no conditional headers, like the reference's
    ///     `forceRefresh` (`internal/reader/handler/handler.go`).
    /// - Returns: The URL and the headers to send. Headers whose value would be empty are
    ///   omitted, as upstream.
    /// - Throws: ``FetchError/invalidURL(_:)`` when the URL is not an `http` or `https` URL
    ///   with a host.
    public func build(feed: FeedFetchState, forceRefresh: Bool = false) throws -> FetchRequest {
        guard
            let scheme = feed.url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            feed.url.host != nil
        else {
            throw FetchError.invalidURL(feed.url.absoluteString)
        }

        var headers = [
            "User-Agent": feed.userAgent.isEmpty ? options.userAgent : feed.userAgent,
            "Accept": options.acceptHeader,
            "Accept-Encoding": options.decompression ? "gzip" : "identity",
        ]

        // Upstream: per-feed setting first, then the global default, and a forced refresh
        // always skips the validators.
        if !feed.ignoreHTTPCache && !options.ignoreHTTPCache && !forceRefresh {
            if !feed.etag.isEmpty {
                headers["If-None-Match"] = feed.etag
            }
            if !feed.lastModified.isEmpty {
                headers["If-Modified-Since"] = feed.lastModified
            }
        }

        return FetchRequest(url: feed.url, headers: headers)
    }
}
