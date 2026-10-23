import AsyncHTTPClient
import Foundation
import NIOCore
import NIOHTTP1

/// Fetches feed documents.
///
/// Ported from Miniflux `internal/reader/fetcher` (Apache-2.0); adapted for Swift, with the
/// differences recorded in `docs/reference-notes.md`: the body cap goes through the response
/// accumulator, which counts the same bytes the reference's `MaxBytesReader` counts; the
/// private-network check runs on the address the fetcher gets for a direct hop: the seam's answers
/// for a name, or the URL's own address when it is already one, and the client is pinned with
/// `dnsOverride` to an address validated when it was built, so a later lookup cannot steer the
/// connection — the guarantee the reference's dialer `Control` callback gives it, by another
/// mechanism; and redirects are followed hop by hop so the check runs on every direct hop, as the
/// reference's dialer does — which also skips it for the dial to an explicitly configured proxy.
public actor Fetcher {
    /// A client is reused for this long. Its configuration carries the pin, and the cache key is
    /// `host|proxyURL`, so a pin is never used for another host or for a proxied request; an expired entry
    /// is not reused, and the next prune closes it once no request is using it.
    static let clientTTL: Duration = .seconds(60)

    /// The soft cap on idle clients: a checkout closes one idle entry while the cache holds this many and
    /// never closes a client a request is using, so a burst of new hosts can leave the cache a few entries
    /// over the cap until a later checkout trims it. The expired sweep runs on every checkout whatever the
    /// count is.
    static let maxCachedClients = 8

    /// The clock the TTL is measured on. A monotonic clock, so a step in the wall clock — an NTP
    /// adjustment — cannot make a client live for years or expire at once.
    private static let clock = ContinuousClock()

    private let options: FetcherOptions
    private let resolver: any AddressResolver
    /// Entries are keyed by an id rather than by `host|proxy`, because two clients for the same key can
    /// exist while one of them is in use and expired: the new one is created, the old one stays until its
    /// request finishes, and a key-keyed dictionary would overwrite it and lose the count.
    private var clients: [Int: PinnedClient] = [:]
    private var nextClientID = 0

    private struct PinnedClient {
        let id: Int
        let key: String
        let client: HTTPClient
        let expiresAt: ContinuousClock.Instant
        var inFlight: Int
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
    /// run on every direct hop: upstream checks the address on each direct dial, and a client that follows
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

    /// Sends one hop: its address is checked — the seam's answers for a name, or the URL's own
    /// address when it is already one — and the request goes out on the client for this host and
    /// proxy decision, one built from a validated address or a cached one that keeps the address
    /// it was built with, under the deadline the whole fetch shares. A proxied hop is answered by
    /// the proxy, which resolves the target itself, so nothing is checked or pinned for it.
    private func send(_ request: FetchRequest, deadline: NIODeadline) async throws -> FetchResponse {
        guard let host = request.url.host else {
            throw FetchError.invalidURL(request.url.absoluteString)
        }

        // A proxied hop is answered by the proxy, which resolves the target itself, so there is
        // nothing to pin: upstream treats an explicitly configured proxy as a trusted hop and keeps
        // the private-network check for direct connections.
        let pinned = request.proxyURL == nil ? try await resolveAndPin(host: host) : nil
        let checkout = try await client(for: request, host: host, pinned: pinned)
        // The entry stays marked in use until the body has been read or the send fails, so the pruner
        // cannot close a client that is serving this request.
        defer { release(checkout.id) }
        let client = checkout.client

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
    /// Call it when no `fetch` is in flight. Pruning and eviction leave a client that a request is using
    /// alone, but `shutdown` closes every client regardless of use — it is the caller's way to stop the
    /// fetcher, so knowing that nothing is running is the caller's part. Closing a client a request is
    /// using fails that request — the client cancels the connection it is holding, which arrives as
    /// `HTTPClientError.cancelled` and Rivulet reports it as ``FetchError/network(_:)``; a request that
    /// reaches a client already shut down is refused with the client's own wording.
    ///
    /// A second call does nothing, whether it follows the first or overlaps it: the entries are taken out
    /// of the cache before any of them is closed. If one client fails to close, the rest are still closed
    /// and the first failure is rethrown, so the cache is empty either way. A client a fetch creates while
    /// the loop is running is not closed, which is what the contract above rules out. After this the
    /// fetcher still works: the next fetch builds a client again.
    public func shutdown() async throws {
        let closing = Array(clients.values)
        clients.removeAll()
        var failure: (any Error)?
        for entry in closing {
            do {
                try await entry.client.shutdown()
            } catch {
                failure = failure ?? error
            }
        }
        if let failure {
            throw failure
        }
    }

    /// Resolves `host`, or classifies it when it is already an address, refuses any non-public
    /// answer, and returns the address a new client is pinned to. The client connects to that
    /// address through `dnsOverride`, so a lookup that answers differently later cannot change the
    /// target — the DNS-rebinding case upstream guards with its dialer. A cached client keeps the
    /// address it was built with; the answers found here are what the policy checks on this hop
    /// either way.
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

    /// A client for one host and one proxy decision, reused for ``clientTTL``, with the cache entry it
    /// came from. The caller releases the entry when the request is done; until then the entry is in use
    /// and the pruner leaves it alone.
    private func client(
        for request: FetchRequest,
        host: String,
        pinned: NetworkAddress?
    ) async throws -> (id: Int, client: HTTPClient) {
        let key = Self.cacheKey(host: host, proxyURL: request.proxyURL)
        try await pruneClients()

        if var entry = clients.values.first(where: { $0.key == key && $0.expiresAt > Self.clock.now }) {
            entry.inFlight += 1
            clients[entry.id] = entry
            return (entry.id, entry.client)
        }

        var configuration = HTTPClient.Configuration()
        if let pinned {
            configuration.dnsOverride = [host: pinned.text]
        }
        // Redirects are left to `fetch`, which validates the address for every direct hop. Cycles are
        // allowed up to the limit, as upstream does: its CheckRedirect counts requests rather than
        // refusing a repeated URL.
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
        let id = nextClientID
        nextClientID += 1
        clients[id] = PinnedClient(
            id: id,
            key: key,
            client: client,
            expiresAt: Self.clock.now + Self.clientTTL,
            inFlight: 1
        )
        return (id, client)
    }

    /// Marks the entry idle again. The pruner leaves it alone between the checkout and the release, so it
    /// is still here unless the fetcher was shut down meanwhile, which is why a missing entry is tolerated.
    private func release(_ id: Int) {
        guard var entry = clients[id] else {
            return
        }
        entry.inFlight -= 1
        clients[id] = entry
    }

    /// Clients are keyed by host and proxy, so a proxied request never reuses a direct client and
    /// the pin stored in a client's configuration is never applied to another host. Internal so the
    /// key itself can be tested — the guarantee is a property of the key, not of a connection.
    static func cacheKey(host: String, proxyURL: URL?) -> String {
        "\(host)|\(proxyURL?.absoluteString ?? "direct")"
    }

    /// Closes the expired clients that are idle, then one more idle one when the cache is full: the entry
    /// whose expiry comes first. This is an expiry-based cache, not an LRU — a client used often is not
    /// kept longer — and when several entries expire at the same instant the first one found is closed.
    ///
    /// A client in use is never closed: closing one cancels the request it is serving. So an expired entry
    /// stays until its request finishes and the cache can hold a few entries above ``maxCachedClients``
    /// while that many requests overlap — the price of not failing a request to stay under the cap.
    ///
    /// The ids are collected before anything is closed, because closing awaits: removing an entry while the
    /// dictionary is being read would let a reentrant call act on a client that is already closed.
    private func pruneClients() async throws {
        let now = Self.clock.now
        let expired = clients.values.filter { $0.expiresAt <= now && $0.inFlight == 0 }.map(\.id)
        for id in expired {
            guard let entry = clients.removeValue(forKey: id) else {
                continue
            }
            try await entry.client.shutdown()
        }

        guard clients.count >= Self.maxCachedClients,
            let oldest = clients.values.filter({ $0.inFlight == 0 }).min(by: { $0.expiresAt < $1.expiresAt })
        else {
            return
        }
        if let entry = clients.removeValue(forKey: oldest.id) {
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
    /// A client error with no category here is reported as a network failure: Rivulet's own phrase with
    /// the client's wording after it. The reference puts the same failure in its network category as well —
    /// `isNetworkError` is true for `*url.Error`, which is what `net/http`'s `Client.do` wraps every
    /// failure in — so only the wording differs on that path: Go prints its `url.Error` wrapper.
    ///
    /// Three of the reference's categories are effectively unreachable, though not for one reason.
    /// `error.network_timeout` and `error.http_empty_response` sit behind `isNetworkError`, so what Rivulet
    /// reports as a timeout or as a connection closed by the peer is a network failure upstream; and
    /// `error.http_client_error` needs an error that is not a `*url.Error`, which the fetch path does not
    /// produce. Rivulet therefore reports a deadline itself instead of calling it a network failure.
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
    /// which the timeout tests depend on. The value is clamped at both ends because `attoseconds` is
    /// Int128 and the conversion to Int64 traps outside it — a public ``FetcherOptions`` takes any
    /// `Duration`, and an environment value can be that large. Half of `Int64.max` either way leaves room
    /// for `NIODeadline.now()` to add the amount without overflowing. A clamped-negative amount is a
    /// deadline already in the past — NIO clamps the deadline it computes to the start of its uptime — so
    /// the fetch times out at once instead of trapping.
    /// Internal so the guard can be tested.
    static func amount(for duration: Duration) -> TimeAmount {
        let nanoseconds = duration.attoseconds / 1_000_000_000
        let cap = Int128(Int64.max / 2)
        return TimeAmount.nanoseconds(Int64(min(max(nanoseconds, -cap), cap)))
    }
}
