import Foundation
import Testing
import RivuletCore

/// Setup shared by the fetch suites, so the fetch matrix and the address policy tests start from the
/// same rules: a server or proxy started for this test only, on port 0, and a fetcher that is closed
/// on both the success and the failure path.
enum FetchTestSupport {
    /// The options a fetch test uses, with the values it cares about named at the call site.
    static func options(
        maxBodySize: Int = 1024,
        maxRedirects: Int = 10,
        timeout: Duration = .seconds(5),
        decompression: Bool = true,
        proxyURL: String? = nil,
        allowPrivateNetworks: Bool = true
    ) -> FetcherOptions {
        FetcherOptions(
            timeout: timeout,
            userAgent: FetcherOptions.defaultUserAgent,
            acceptHeader: FetcherOptions.defaultAcceptHeader,
            maxBodySize: maxBodySize,
            maxRedirects: maxRedirects,
            decompression: decompression,
            ignoreHTTPCache: false,
            proxyURL: proxyURL,
            allowPrivateNetworks: allowPrivateNetworks
        )
    }

    /// Runs `body` against a server started for this test and stops it on both paths.
    static func withServer(
        behaviors: [String: StubFeedServer.Behavior],
        _ body: (StubFeedServer) async throws -> Void
    ) async throws {
        let server = try await StubFeedServer.start(behaviors: behaviors)
        do {
            try await body(server)
        } catch {
            try await server.stop()
            throw error
        }
        try await server.stop()
    }

    /// Runs `body` with a proxy started for this test and stops it on both paths.
    static func withProxy(response: Data, _ body: (StubProxy) async throws -> Void) async throws {
        let proxy = try await StubProxy.start(response: response)
        do {
            try await body(proxy)
        } catch {
            try await proxy.stop()
            throw error
        }
        try await proxy.stop()
    }

    /// Runs `body` with a fetcher and closes the clients it created.
    static func withFetcher(
        options: FetcherOptions,
        resolver: any AddressResolver = SystemAddressResolver(),
        _ body: (Fetcher) async throws -> Void
    ) async throws {
        let fetcher = Fetcher(options: options, resolver: resolver)
        do {
            try await body(fetcher)
        } catch {
            try? await fetcher.shutdown()
            throw error
        }
        try await fetcher.shutdown()
    }
}

/// Answers every lookup with one address and counts the calls.
actor CountingResolver: AddressResolver {
    private let answer: [NetworkAddress]
    private(set) var calls = 0

    init(answer: NetworkAddress) {
        self.answer = [answer]
    }

    func resolve(host: String) async throws -> [NetworkAddress] {
        calls += 1
        return answer
    }
}

/// Answers `host` from a table, records the hosts it was asked about, and answers with nothing for a
/// host the table does not cover.
actor SeededResolver: AddressResolver {
    private let answers: [String: [NetworkAddress]]
    private(set) var hosts: [String] = []

    init(answers: [String: [NetworkAddress]]) {
        self.answers = answers
    }

    func resolve(host: String) async throws -> [NetworkAddress] {
        hosts.append(host)
        return answers[host] ?? []
    }
}
