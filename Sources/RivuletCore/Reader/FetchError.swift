import Foundation

/// Fetch failures. The wording follows the reference (`internal/reader/fetcher`) where the
/// reference writes a message of its own; where the message comes from Go's standard library,
/// Rivulet uses the phrase the reference would print with it, without Go's `Get "url":` wrapper.
/// The phrases for an invalid URL, the redirect cap, a deadline, a connection closed by the peer
/// and an unclassifiable client failure are Rivulet's own: the reference has no error string of its
/// own for those, only locale keys into which Go's strings are interpolated, and whose strings
/// Rivulet does not reproduce.
///
/// A failure reaches the caller two ways, and the categories are the same either way:
/// ``Fetcher/fetch(_:)`` throws for a transport or limit failure, while an HTTP status is a
/// response the caller can inspect, so ``FetchResponse/error()`` returns ``FetchError/status(_:)``
/// rather than throwing — the reference keeps the response and the error together, and Rivulet does
/// the same.
///
/// Ported from Miniflux `internal/reader/fetcher` (Apache-2.0); adapted for Swift.
public enum FetchError: Error, Sendable, Equatable {
    /// The URL is not an `http` or `https` URL with a host.
    case invalidURL(String)

    /// The resolved address is private, loopback or link-local, and private targets are not allowed
    /// (`FETCHER_ALLOW_PRIVATE_NETWORKS`). The message is the reference's sentinel, with the host
    /// printed bare rather than quoted as the reference does with `%q`.
    case privateNetworkHost(String)

    /// The host did not resolve. The phrase is upstream's sentinel `ErrHostnameResolution`
    /// (`internal/reader/fetcher/request_builder.go:32`), which the reference never produces on the
    /// fetch path: a DNS failure there comes from Go's resolver inside `Get "url":` and is shown as
    /// a network failure, so this category is Rivulet's own, on the resolver seam upstream does not
    /// have. Recorded in `docs/reference-notes.md`.
    case hostnameResolution(String)

    /// A `Location` that cannot be parsed. The phrase is Go's — `net/http`'s `Client.do` writes
    /// `failed to parse Location header %q: %v` and wraps it in its `Get "url":` error, which is
    /// what the reference prints (`fetcher: %w`,
    /// `internal/reader/fetcher/response_handler.go:177`). Rivulet prints the phrase without that
    /// wrapper and without the parse error Go puts after the colon, because its URL parsing gives
    /// none. Recorded in `docs/reference-notes.md`.
    case redirectTargetUnparseable(String)

    /// A configured proxy URL that cannot be read, like upstream `fetcher: invalid feed proxy URL`.
    /// The parse error the reference appends after the colon is not part of the message, because
    /// Rivulet has no parse error to print.
    case invalidProxyURL(String)

    /// The response body exceeded the configured cap.
    case bodyTooLarge(Int)

    /// The response had no body.
    case emptyBody

    /// A status the reference treats as a fetch failure.
    case status(Int)

    /// A Cloudflare bot challenge, recognised from the response headers.
    case cloudflareChallenge(Int)

    /// The request timed out.
    case timeout

    /// The connection failed or was closed early.
    case network(String)

    /// Too many redirects.
    case redirectLimit(Int)
}

extension FetchError: CustomStringConvertible {
    /// The message as the reference would print it, with the `fetcher:` prefix Miniflux adds when
    /// it wraps the failure, without Go's `Get "url":` wrapper. Where the reference has no error
    /// string of its own — an invalid URL, the redirect cap, a deadline, a connection closed by the
    /// peer, an unclassifiable client failure — the phrase is Rivulet's, with the client's own
    /// wording after it for the network case; the strings Miniflux shows for those come from locale
    /// keys, which Rivulet does not reproduce. The two parse messages drop the parse error the
    /// reference prints after the colon, because Rivulet's URL parsing gives none; the cases say
    /// so.
    public var description: String {
        switch self {
        case .invalidURL(let url):
            return "fetcher: \(url) is not an http(s) URL"
        case .privateNetworkHost(let host):
            return "fetcher: refusing to access private network host \(host)"
        case .hostnameResolution(let host):
            return "fetcher: unable to resolve request hostname \(host)"
        case .redirectTargetUnparseable(let location):
            return "fetcher: failed to parse Location header \"\(location)\""
        case .invalidProxyURL(let value):
            return "fetcher: invalid feed proxy URL \"\(value)\""
        case .bodyTooLarge(let limit):
            return "fetcher: response body too large: \(limit) bytes"
        case .emptyBody:
            return "fetcher: empty response body"
        case .cloudflareChallenge(let status):
            return "fetcher: blocked by Cloudflare challenge (\(status) status code)"
        case .status(let status):
            return "fetcher: \(statusMessage(status)) (\(status) status code)"
        case .timeout:
            return "fetcher: network timeout"
        case .network(let detail):
            return "fetcher: network operation failed: \(detail)"
        case .redirectLimit(let limit):
            return "fetcher: redirect limit reached (\(limit) redirects)"
        }
    }

    /// The wording the reference uses for each status it names; everything else falls back to
    /// the generic one.
    private func statusMessage(_ status: Int) -> String {
        switch status {
        case 401: return "access unauthorized"
        case 403: return "access forbidden"
        case 429: return "too many requests"
        case 404, 410: return "resource not found"
        case 500: return "remote server error"
        case 502: return "bad gateway"
        case 503: return "service unavailable"
        case 504: return "gateway timeout"
        default: return "unexpected status code"
        }
    }
}
