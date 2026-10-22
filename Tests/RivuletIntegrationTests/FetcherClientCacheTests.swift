import Foundation
import Testing
@testable import RivuletCore

/// The client cache. A client is never closed while a request is using it: closing one cancels the
/// request it is serving, which is the failure this suite pins.
@Suite struct FetcherClientCacheTests {
    /// Answers every name with the loopback address, so one stub can serve several host names.
    private struct LoopbackResolver: AddressResolver {
        func resolve(host: String) async throws -> [NetworkAddress] {
            [.ipv4([127, 0, 0, 1])]
        }
    }

    @Test func aClientInFlightIsNotClosedToMakeRoomInTheCache() async throws {
        // The regression: a second fetch could prune the cache while the first was waiting for its body,
        // close the client the first was using, and fail that request with a cancellation. The stub holds
        // the body for a second; the pass condition is that the eight local round trips that fill the
        // cache finish inside that second, so the first request is still in flight when they run.
        try await FetchTestSupport.withServer(behaviors: [
            "/slow": StubFeedServer.Behavior(body: Data("slow".utf8), bodyDelay: .seconds(1)),
            "/fast": StubFeedServer.Behavior(body: Data("fast".utf8)),
        ]) { server in
            try await FetchTestSupport.withFetcher(
                options: FetchTestSupport.options(),
                resolver: LoopbackResolver()
            ) { fetcher in
                let slow = Task {
                    try await fetcher.fetch(
                        FetchRequest(url: URL(string: "http://slow.example:\(server.port)/slow")!, headers: [:])
                    )
                }

                // The request is on the wire only after the client was taken from the cache, so waiting for
                // the head means the cache is holding that client while the fillers run. Waiting on the
                // server is what keeps the ordering deterministic without a sleep.
                await server.waitForRequest(for: "/slow")

                for index in 0..<Fetcher.maxCachedClients {
                    let url = URL(string: "http://filler\(index).example:\(server.port)/fast")!
                    _ = try await fetcher.fetch(FetchRequest(url: url, headers: [:]))
                }

                let response = try await slow.value
                #expect(response.status == 200)
                #expect(response.body == Data("slow".utf8))
            }
        }
    }
}
