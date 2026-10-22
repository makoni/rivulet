import AsyncHTTPClient
import Foundation
import NIOCore
import NIOHTTP1

/// Fetches feed documents.
///
/// Ported from Miniflux `internal/reader/fetcher` (Apache-2.0); adapted for Swift, with the
/// differences recorded in `docs/reference-notes.md`: the body cap goes through the response
/// accumulator, which counts the same bytes the reference's `MaxBytesReader` counts; the
/// private-network check runs on the address resolved through the resolver seam and pinned, which
/// closes the time-of-check window the reference's dialer leaves; and redirects are followed hop by
/// hop so the check runs on every hop, as the reference's dialer does.
public actor Fetcher {
    /// A client is reused for this long. Its configuration carries the pin, and the cache key is
    /// `host|proxyURL`, so a pin is never used for another host or for a proxied request, and a stale
    /// pin cannot outlive the cache.
    static let clientTTL: Duration = .seconds(60)

    /// How many clients are kept at once.
    static let maxCachedClients = 8

    /// The clock the TTL is measured on. A monotonic clock, so a step in the wall clock — an NTP
    /// adjustment — cannot make a client live for years or expire at once.
    private static let clock = ContinuousClock()

    private let options: FetcherOptions
    private let resolver: any AddressResolver
    private var clients: [String: PinnedClient] = [:]

    private struct PinnedClient {
        let client: HTTPClient
        let expiresAt: ContinuousClock.Instant
    }

    /// Creates a fetcher.
    ///
    /// - Parameters:
    ///   - options: Timeouts, size cap, redirect limit and the flags the request is built from.
    ///   - resolver: The address resolver seam; the system resolver applies when it is omitted.
    public init(options: FetcherOptions, resolver: any AddressResolver = SystemAddressResolver()) {
        self.options = options
        self.resolver = resolver
    }

    /// Fetches one document and returns the response as the reference handler would see it.
    ///
    /// A conditional hit comes back as a response with status 304 and no body. A transport or limit failure
    /// throws ``FetchError`` — the reference's wording where the reference writes one, the client's wording
    /// for a failure the mapping does not classify; an HTTP status does not throw, it is a response whose
    /// ``FetchResponse/error()`` reports the failure, so the status stays visible.
    ///
    /// Redirects are followed hop by hop instead of by the client, because the address policy has to
    /// run on every hop: upstream checks the address on each dial, and a client that follows
    /// redirects resolves the next host itself, outside the policy.
    public func fetch(_ request: FetchRequest) async throws -> FetchResponse {
        var hop = request
        var followed = 0
        // The reference computes one deadline for the whole call — connection, redirects and body
        // reading together — so the hops share it rather than each starting a fresh timeout.
        let deadline = NIODeadline.now() + Self.amount(for: options.timeout)

        while true {
            let response = try await send(hop, deadline: deadline)

            // Upstream follows 301, 302, 303, 307 and 308, and it counts requests, so it refuses the
            // hop that would make the count reach the limit; here the limit is the hops followed. A
            // redirect status with no usable `Location` is the response, as Go's `do` returns it.
            guard Self.isRedirect(response.status), let location = response.header("Location"), !location.isEmpty else {
                return response
            }
            guard followed < options.maxRedirects else {
                throw FetchError.redirectLimit(options.maxRedirects)
            }
            guard let target = URL(string: location, relativeTo: hop.url) else {
                throw FetchError.redirectTargetUnparseable(location)
            }

            followed += 1
            hop = FetchRequest(url: target.absoluteURL, headers: hop.headers, proxyURL: request.proxyURL)
        }
    }

    /// Sends one hop: the address for that hop is validated and pinned, then the request goes out with
    /// the deadline the whole fetch shares.
    private func send(_ request: FetchRequest, deadline: NIODeadline) async throws -> FetchResponse {
        guard let host = request.url.host else {
            throw FetchError.invalidURL(request.url.absoluteString)
        }

        // A proxied hop is answered by the proxy, which resolves the target itself, so there is
        // nothing to pin: upstream treats an explicitly configured proxy as a trusted hop and keeps
        // the private-network check for direct connections.
        let pinned = request.proxyURL == nil ? try await resolveAndPin(host: host) : nil
        let client = try await client(for: request, host: host, pinned: pinned)

        // Everything the client can fail with is mapped here, including what fails before a connection:
        // turning the URL into a client request refuses a scheme it will not serve.
        let response: HTTPClient.Response
        do {
            var ahcRequest = try HTTPClient.Request(url: request.url, method: .GET)
            for (name, value) in request.headers {
                ahcRequest.headers.add(name: name, value: value)
            }
            response = try await client.execute(
                request: ahcRequest,
                delegate: ResponseAccumulator(request: ahcRequest, maxBodySize: options.maxBodySize),
                deadline: deadline
            ).futureResult.get()
        } catch {
            throw mapError(error)
        }

        var headers: [String: String] = [:]
        for (name, value) in response.headers {
            headers[name] = value
        }

        return FetchResponse(
            status: Int(response.status.code),
            headers: headers,
            body: bytes(from: response.body),
            effectiveURL: request.url
        )
    }

    /// The redirect statuses upstream follows.
    private static func isRedirect(_ status: Int) -> Bool {
        switch status {
        case 301, 302, 303, 307, 308:
            return true
        default:
            return false
        }
    }

    /// Closes the cached clients.
    ///
    /// Call it when no `fetch` is in flight: the fetcher has no record of in-flight requests, so closing a
    /// client another task is using fails that request — the client cancels a connection it is holding,
    /// which arrives as `HTTPClientError.cancelled` and Rivulet reports it as ``FetchError/network(_:)``;
    /// a request that reaches a client already shut down is refused with the client's own wording. A second
    /// call does nothing.
    /// After this the fetcher still works, it is simply empty: the next fetch builds a client again.
    public func shutdown() async throws {
        for entry in clients.values {
            try await entry.client.shutdown()
        }
        clients.removeAll()
    }

    /// Resolves `host` once, refuses any non-public address, and returns the address the client is
    /// pointed at. Because the client is configured with this address, no second lookup happens:
    /// a resolver that would answer with a private address later cannot change the target — the
    /// DNS-rebinding case upstream guards with its dialer.
    ///
    /// `host` here is what `URL.host` gives, which is the address without its brackets for an IPv6 URL,
    /// and that is also the key AsyncHTTPClient looks up in `dnsOverride`, so the pin and the key agree.
    func resolveAndPin(host: String) async throws -> NetworkAddress {
        let policy = NetworkAddressPolicy(allowPrivateNetworks: options.allowPrivateNetworks)

        // An address host is classified directly: there is nothing to look up.
        if let address = NetworkAddress.parse(host) {
            guard policy.allows(address) else {
                throw FetchError.privateNetworkHost(host)
            }
            return address
        }

        let answers = try await resolver.resolve(host: host)
        guard !answers.isEmpty else {
            throw FetchError.hostnameResolution(host)
        }
        // Rivulet is stricter than upstream here, and the difference is recorded in
        // `docs/reference-notes.md`: upstream checks the address it dials one attempt at a time, so a
        // private answer later in the list is never reached when a public answer connects first.
        // Rivulet refuses the request when any answer is non-public.
        for answer in answers where !policy.allows(answer) {
            throw FetchError.privateNetworkHost(host)
        }
        return answers[0]
    }

    // MARK: - Client

    /// Client for one host and one proxy decision, reused for ``clientTTL``.
    private func client(for request: FetchRequest, host: String, pinned: NetworkAddress?) async throws -> HTTPClient {
        let key = Self.cacheKey(host: host, proxyURL: request.proxyURL)
        try await pruneClients()

        if let cached = clients[key], cached.expiresAt > Self.clock.now {
            return cached.client
        }

        var configuration = HTTPClient.Configuration()
        if let pinned {
            configuration.dnsOverride = [host: pinned.text]
        }
        // Redirects are left to `fetch`, which validates the address for every hop. Cycles are allowed
        // up to the limit, as upstream does: its CheckRedirect counts requests rather than refusing a
        // repeated URL.
        configuration.redirectConfiguration = .disallow
        configuration.decompression = options.decompression ? .enabled(limit: .ratio(25)) : .disabled
        // Only the connect timeout is a separate limit: the request deadline is the one the whole fetch
        // shares, passed to `execute` per hop, the way the reference's client timeout covers the whole
        // call including redirects.
        configuration.timeout = .init(connect: Self.amount(for: FetcherOptions.defaultConnectTimeout))
        if let proxyURL = request.proxyURL {
            configuration.proxy = Self.proxyTarget(from: proxyURL)
        }

        let client = HTTPClient(configuration: configuration)
        clients[key] = PinnedClient(client: client, expiresAt: Self.clock.now + Self.clientTTL)
        return client
    }

    /// Clients are keyed by host and proxy, so a proxied request never reuses a direct client and
    /// the pin stored in a client's configuration is never applied to another host. Internal so the
    /// key itself can be tested — the guarantee is a property of the key, not of a connection.
    static func cacheKey(host: String, proxyURL: URL?) -> String {
        "\(host)|\(proxyURL?.absoluteString ?? "direct")"
    }

    /// Closes the expired clients, then one more when the cache is full: the entry whose expiry comes
    /// first. This is an expiry-based cache, not an LRU — a client used often is not kept longer — and
    /// when several entries expire at the same instant the first one found is closed.
    ///
    /// The keys are collected before anything is closed, because closing awaits: removing an entry while
    /// the dictionary is being read would let a reentrant call act on a client that is already closed.
    private func pruneClients() async throws {
        let expired = clients.filter { $0.value.expiresAt <= Self.clock.now }.map(\.key)
        for key in expired {
            guard let entry = clients.removeValue(forKey: key) else {
                continue
            }
            try await entry.client.shutdown()
        }

        guard clients.count >= Self.maxCachedClients,
            let oldest = clients.min(by: { $0.value.expiresAt < $1.value.expiresAt })
        else {
            return
        }
        if let entry = clients.removeValue(forKey: oldest.key) {
            try await entry.client.shutdown()
        }
    }

    /// The proxy target, with the ports upstream assumes when the URL gives none.
    ///
    /// Deviation: AsyncHTTPClient connects to the proxy in plain HTTP, so an `https` proxy URL does
    /// not reach the proxy over TLS the way the reference does.
    ///
    /// Internal rather than private so the port defaults can be tested: a stub proxy on port 0 cannot
    /// show them, because the proxy URL would have to name a fixed port, which `docs/testing.md`
    /// forbids.
    static func proxyTarget(from url: URL) -> HTTPClient.Configuration.Proxy {
        let host = url.host ?? ""
        switch url.scheme?.lowercased() {
        case "socks5", "socks5h":
            return .socksServer(host: host, port: url.port ?? 1080)
        case "https":
            return .server(host: host, port: url.port ?? 443)
        default:
            return .server(host: host, port: url.port ?? 80)
        }
    }

    // MARK: - Errors and bytes

    /// Maps a client failure to the fetcher's error, using the categories the reference reports.
    ///
    /// The redirect limit is not part of this mapping: the client is configured not to follow
    /// redirects, so the limit is reported by the hop loop in `fetch`. Everything the client can fail
    /// with is mapped here, including what fails before a connection.
    ///
    /// A client error with no category here is reported as a network failure with the client's wording.
    /// The reference puts the same failure in its network category as well — `isNetworkError` is true for
    /// `*url.Error`, which is how Go wraps a client failure — so the difference is the wording only: Go
    /// prints its `url.Error` wrapper, Rivulet prints what the client said.
    ///
    /// Two categories are reachable on one side only. The reference's `error.http_client_error` is reached
    /// only when the error is not a `*url.Error`; and `isNetworkError` is tested before `os.IsTimeout`, so
    /// a timeout Go's client wraps comes out as a network error there — its timeout category is
    /// effectively unreachable, while Rivulet's reports a deadline.
    private func mapError(_ error: any Error) -> FetchError {
        if let clientError = error as? HTTPClientError {
            switch clientError {
            case HTTPClientError.deadlineExceeded,
                HTTPClientError.readTimeout,
                HTTPClientError.connectTimeout:
                return .timeout
            case HTTPClientError.remoteConnectionClosed:
                return .network("connection closed by the peer")
            default:
                return .network(String(describing: error))
            }
        }
        if error is ResponseAccumulator.ResponseTooBigError {
            return .bodyTooLarge(options.maxBodySize)
        }
        return .network(String(describing: error))
    }

    private func bytes(from buffer: ByteBuffer?) -> Data {
        guard let buffer else {
            return Data()
        }
        return Data(buffer.readableBytesView)
    }

    /// A `TimeAmount` from a Duration. `components.seconds` alone would drop a sub-second duration,
    /// which the timeout tests depend on. The value is clamped because `attoseconds` is Int128 and the
    /// conversion to Int64 traps above it — an environment value can be that large — and half of
    /// `Int64.max` leaves room for `NIODeadline.now()` to add the amount without overflowing either.
    /// Internal so the guard can be tested.
    static func amount(for duration: Duration) -> TimeAmount {
        let nanoseconds = duration.attoseconds / 1_000_000_000
        let cap = Int64.max / 2
        return TimeAmount.nanoseconds(nanoseconds > Int128(cap) ? cap : Int64(nanoseconds))
    }
}
