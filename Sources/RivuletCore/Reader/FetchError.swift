import Foundation

/// Fetch failures. The wording follows the reference (`internal/reader/fetcher`).
public enum FetchError: Error, Sendable, Equatable {
    /// The URL is not an `http` or `https` URL with a host.
    case invalidURL(String)

    /// The resolved address is private, loopback or link-local, and private targets are not
    /// allowed (`FETCHER_ALLOW_PRIVATE_NETWORKS`).
    case privateNetworkHost(String)

    /// The response body exceeded the configured cap.
    case bodyTooLarge(Int)

    /// The response had no body.
    case emptyBody

    /// A status the reference treats as a fetch failure.
    case status(Int)

    /// The request timed out.
    case timeout

    /// The connection failed or was closed early.
    case network(String)

    /// Too many redirects.
    case redirectLimit(Int)
}

extension FetchError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidURL(let url):
            return "fetcher: \(url) is not an http(s) URL"
        case .privateNetworkHost(let host):
            return "fetcher: refusing to access private network host \(host)"
        case .bodyTooLarge(let limit):
            return "fetcher: response body too large: \(limit) bytes"
        case .emptyBody:
            return "fetcher: empty response body"
        case .status(let code):
            return "fetcher: unexpected status code (\(code) status code)"
        case .timeout:
            return "fetcher: request timed out"
        case .network(let detail):
            return "fetcher: network operation failed: \(detail)"
        case .redirectLimit(let limit):
            return "fetcher: redirect limit reached (\(limit) redirects)"
        }
    }
}
