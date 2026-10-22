import Foundation

/// Fetcher options read from the environment.
///
/// Variable names mirror Miniflux where a single value maps cleanly: `HTTP_CLIENT_TIMEOUT`,
/// `HTTP_CLIENT_USER_AGENT`, `HTTP_CLIENT_MAX_BODY_SIZE`, `HTTP_CLIENT_PROXY` and
/// `FETCHER_ALLOW_PRIVATE_NETWORKS`. `FETCHER_IGNORE_HTTP_CACHE` is a Rivulet addition: the
/// reference has only the per-feed flag, so this is the application-wide default a feed overrides.
/// The reference also proxies from the environment (`ProxyFromEnvironment`), which Rivulet does not
/// read — recorded in `docs/reference-notes.md`. Parsing follows the upstream semantics
/// (`internal/config/options.go`): trimmed keys and values, an empty value falls back to the
/// default, booleans accept the same words, and both numeric options must be at least 1.
public struct FetcherOptions: Sendable, Equatable {
    /// The `Accept` value the reference sends when nothing else is set
    /// (`defaultAcceptHeader`, `internal/reader/fetcher/request_builder.go`).
    public static let defaultAcceptHeader =
        "application/xml,application/atom+xml,application/rss+xml,application/rdf+xml,application/feed+json,text/html,*/*;q=0.9"

    /// Rivulet's own user agent. The reference advertises Miniflux; advertising Rivulet is a
    /// documented deviation.
    public static var defaultUserAgent: String {
        "Mozilla/5.0 (compatible; Rivulet/\(RivuletCore.version); +https://github.com/makoni/rivulet)"
    }

    /// Upstream `defaultHTTPClientTimeout`, the deadline one `fetch` shares across its hops.
    public static let defaultTimeout: Duration = .seconds(20)

    /// The time to establish a connection. Upstream's transport uses the same 10 seconds in its dialer
    /// (`internal/reader/fetcher/request_builder.go`), which is also AsyncHTTPClient's default.
    public static let defaultConnectTimeout: Duration = .seconds(10)

    /// Upstream `HTTP_CLIENT_MAX_BODY_SIZE` default, in bytes (15 MiB).
    public static let defaultMaxBodySize: Int = 15 * 1024 * 1024

    /// The redirect cap. Go's default `CheckRedirect` stops after 10 requests, so it follows at most 9
    /// redirects; Rivulet counts the hops it follows, which is one hop more at the boundary — recorded
    /// in `docs/reference-notes.md`.
    public static let defaultMaxRedirects: Int = 10

    /// Total request timeout (`HTTP_CLIENT_TIMEOUT`).
    public let timeout: Duration

    /// Advertised user agent (`HTTP_CLIENT_USER_AGENT`).
    public let userAgent: String

    /// The `Accept` header value.
    public let acceptHeader: String

    /// Response body cap in bytes (`HTTP_CLIENT_MAX_BODY_SIZE`).
    public let maxBodySize: Int

    /// Maximum number of followed redirects.
    public let maxRedirects: Int

    /// Whether a compressed response is accepted. AsyncHTTPClient does not decompress by
    /// default, so decompression is enabled explicitly when this is true.
    public let decompression: Bool

    /// Application-wide "ignore HTTP cache" default (Rivulet's addition, `FETCHER_IGNORE_HTTP_CACHE`);
    /// a feed overrides it.
    public let ignoreHTTPCache: Bool

    /// Application-wide proxy (`HTTP_CLIENT_PROXY`), none by default.
    public let proxyURL: String?

    /// Escape hatch for private-network targets (`FETCHER_ALLOW_PRIVATE_NETWORKS`).
    /// It is off by default and exists for tests.
    public let allowPrivateNetworks: Bool

    /// The options used when the environment says nothing.
    public static let defaults = FetcherOptions(
        timeout: defaultTimeout,
        userAgent: defaultUserAgent,
        acceptHeader: defaultAcceptHeader,
        maxBodySize: defaultMaxBodySize,
        maxRedirects: defaultMaxRedirects,
        decompression: true,
        ignoreHTTPCache: false,
        proxyURL: nil,
        allowPrivateNetworks: false
    )

    /// Creates fetcher options.
    public init(
        timeout: Duration,
        userAgent: String,
        acceptHeader: String,
        maxBodySize: Int,
        maxRedirects: Int,
        decompression: Bool,
        ignoreHTTPCache: Bool,
        proxyURL: String?,
        allowPrivateNetworks: Bool
    ) {
        self.timeout = timeout
        self.userAgent = userAgent
        self.acceptHeader = acceptHeader
        self.maxBodySize = maxBodySize
        self.maxRedirects = maxRedirects
        self.decompression = decompression
        self.ignoreHTTPCache = ignoreHTTPCache
        self.proxyURL = proxyURL
        self.allowPrivateNetworks = allowPrivateNetworks
    }

    /// Loads the fetcher options from an environment dictionary.
    ///
    /// - Throws: ``ConfigError`` when a numeric option is not a positive integer or a boolean
    ///   is not one of the accepted words.
    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> FetcherOptions {
        // The default is a whole number of seconds, so `components.seconds` is exact here. A sub-second
        // default would truncate, and the fetcher's own conversion is the one that keeps fractions.
        let seconds = try Config.parseInteger(
            variable: "HTTP_CLIENT_TIMEOUT",
            rawValue: environment["HTTP_CLIENT_TIMEOUT"],
            fallback: Int(defaultTimeout.components.seconds),
            minimum: 1
        )
        let megabytes = try Config.parseInteger(
            variable: "HTTP_CLIENT_MAX_BODY_SIZE",
            rawValue: environment["HTTP_CLIENT_MAX_BODY_SIZE"],
            fallback: defaultMaxBodySize / (1024 * 1024),
            minimum: 1
        )

        var userAgent = defaultUserAgent
        if let value = environment["HTTP_CLIENT_USER_AGENT"], !value.trimmingCharacters(in: .whitespaces).isEmpty {
            userAgent = value.trimmingCharacters(in: .whitespaces)
        }

        var proxyURL: String?
        if let value = environment["HTTP_CLIENT_PROXY"], !value.trimmingCharacters(in: .whitespaces).isEmpty {
            proxyURL = value.trimmingCharacters(in: .whitespaces)
        }

        return FetcherOptions(
            timeout: .seconds(seconds),
            userAgent: userAgent,
            acceptHeader: defaultAcceptHeader,
            maxBodySize: megabytes * 1024 * 1024,
            maxRedirects: defaultMaxRedirects,
            decompression: true,
            ignoreHTTPCache: try Config.parseBoolean(
                variable: "FETCHER_IGNORE_HTTP_CACHE",
                value: environment["FETCHER_IGNORE_HTTP_CACHE"],
                fallback: defaults.ignoreHTTPCache
            ),
            proxyURL: proxyURL,
            allowPrivateNetworks: try Config.parseBoolean(
                variable: "FETCHER_ALLOW_PRIVATE_NETWORKS",
                value: environment["FETCHER_ALLOW_PRIVATE_NETWORKS"],
                fallback: defaults.allowPrivateNetworks
            )
        )
    }
}
