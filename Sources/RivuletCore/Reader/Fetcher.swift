import AsyncHTTPClient
import Foundation
import NIOCore
import NIOHTTP1

/// Fetches feed documents.
///
/// Ported from Miniflux `internal/reader/fetcher` (Apache-2.0); adapted for Swift. The differences
/// from the reference are deliberate and recorded in `docs/reference-notes.md`: the body cap is
/// enforced through the response accumulator, because AsyncHTTPClient has no `MaxBytesReader`
/// equivalent; the private-network check runs on the address we resolved and pinned rather than in a
/// dialer callback, which removes the time-of-check window; and redirects are followed hop by hop so
/// the check runs on every hop, as the reference's dialer does.
public actor Fetcher {
    /// A client is reused for this long. Its configuration carries the pin, so a client is never
    /// shared between hosts, and a stale pin cannot outlive the cache.
    static let clientTTL: Duration = .seconds(60)

    /// How many clients are kept at once.
    static let maxCachedClients = 8

    private let options: FetcherOptions
    private let resolver: any AddressResolver
    private var clients: [String: PinnedClient] = [:]

    private struct PinnedClient {
        let client: HTTPClient
        let expiresAt: Int
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
    /// A conditional hit comes back as a response with status 304 and no body. A failure throws
    /// ``FetchError`` with the reference wording.
    ///
    /// Redirects are followed hop by hop instead of by the client, because the address policy has to
    /// run on every hop: upstream checks the address on each dial, and a client that follows
    /// redirects resolves the next host itself, outside the policy.
    public func fetch(_ request: FetchRequest) async throws -> FetchResponse {
        var hop = request
        var followed = 0
        // The reference computes one deadline for the whole call — connection, redirects and body
        // reading together — so the hops share it rather than each starting a fresh timeout.
        let deadline = NIODeadline.now() + amount(options.timeout)

        while true {
            let response = try await send(hop, deadline: deadline)

            // Upstream follows 301, 302, 303, 307 and 308, and it counts requests, so it refuses the
            // hop that would make the count reach the limit; here the limit is the hops followed. A
            // redirect status with no usable `Location` is the response, as Go's `do` returns it.
            guard isRedirect(response.status), let location = response.header("Location"), !location.isEmpty else {
                return response
            }
            guard followed < options.maxRedirects else {
                throw FetchError.redirectLimit(options.maxRedirects)
            }
            guard let target = URL(string: location, relativeTo: hop.url) else {
                throw FetchError.redirectTargetUnparseable(location)
            }

            followed += 1
            hop = FetchRequest(url: target.absoluteURL, headers: request.headers, proxyURL: request.proxyURL)
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

        var ahcRequest = try HTTPClient.Request(url: request.url, method: .GET)
        for (name, value) in request.headers {
            ahcRequest.headers.add(name: name, value: value)
        }
        let accumulator = ResponseAccumulator(request: ahcRequest, maxBodySize: options.maxBodySize)

        let response: HTTPClient.Response
        do {
            response = try await client.execute(request: ahcRequest, delegate: accumulator, deadline: deadline)
                .futureResult
                .get()
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
    private func isRedirect(_ status: Int) -> Bool {
        [301, 302, 303, 307, 308].contains(status)
    }

    /// Closes the cached clients. The fetcher cannot be used after this.
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
        let key = cacheKey(host: host, proxyURL: request.proxyURL)
        try await pruneClients()

        if let cached = clients[key], cached.expiresAt > now() {
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
        configuration.timeout = .init(connect: amount(FetcherOptions.defaultConnectTimeout))
        if let proxyURL = request.proxyURL {
            configuration.proxy = proxyTarget(from: proxyURL)
        }

        let client = HTTPClient(configuration: configuration)
        clients[key] = PinnedClient(client: client, expiresAt: now() + Int(Self.clientTTL.components.seconds))
        return client
    }

    /// Clients are keyed by host and proxy, so a proxied request never reuses a direct client and
    /// the pin stored in a client's configuration is never applied to another host.
    private func cacheKey(host: String, proxyURL: URL?) -> String {
        "\(host)|\(proxyURL?.absoluteString ?? "direct")"
    }

    /// Closes expired clients, and the oldest one when the cache is full, so a long-lived fetcher
    /// does not keep clients for every host it ever saw.
    private func pruneClients() async throws {
        for (key, entry) in clients where entry.expiresAt <= now() {
            try await entry.client.shutdown()
            clients.removeValue(forKey: key)
        }
        guard clients.count >= Self.maxCachedClients else {
            return
        }
        let oldest = clients.values.map { $0.expiresAt }.min()
        for (key, entry) in clients where entry.expiresAt == oldest {
            try await entry.client.shutdown()
            clients.removeValue(forKey: key)
        }
    }

    /// Proxy target, with the ports upstream assumes when the URL gives none.
    ///
    /// Deviation: AsyncHTTPClient connects to the proxy in plain HTTP, so an `https` proxy URL does
    /// not reach the proxy over TLS the way the reference does.
    private func proxyTarget(from url: URL) -> HTTPClient.Configuration.Proxy {
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
    /// redirects, so the limit is reported by the hop loop in `fetch`.
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
        return Data(buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes) ?? [])
    }

    private func now() -> Int {
        Int(Date.now.timeIntervalSince1970)
    }

    /// A `TimeAmount` from a Duration. `components.seconds` alone would drop a sub-second duration,
    /// which the timeout tests depend on.
    private func amount(_ duration: Duration) -> TimeAmount {
        TimeAmount.nanoseconds(Int64(duration.attoseconds / 1_000_000_000))
    }
}
