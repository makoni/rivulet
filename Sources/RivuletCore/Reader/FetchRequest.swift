import Foundation

/// A fetch request ready to send: the URL, the headers the fetcher will use, and the proxy to send
/// it through when the feed asks for one.
public struct FetchRequest: Sendable, Equatable {
    /// Request target.
    public let url: URL

    /// Headers sent with the request.
    public let headers: [String: String]

    /// Proxy to send this request through, resolved by the builder; nil means a direct request.
    public let proxyURL: URL?

    /// Creates a request.
    public init(url: URL, headers: [String: String], proxyURL: URL? = nil) {
        self.url = url
        self.headers = headers
        self.proxyURL = proxyURL
    }
}
