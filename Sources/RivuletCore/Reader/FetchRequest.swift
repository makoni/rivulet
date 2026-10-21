import Foundation

/// A fetch request ready to send: the URL and the headers the fetcher will use.
public struct FetchRequest: Sendable, Equatable {
    /// Request target.
    public let url: URL

    /// Headers sent with the request.
    public let headers: [String: String]

    /// Creates a request.
    public init(url: URL, headers: [String: String]) {
        self.url = url
        self.headers = headers
    }
}
