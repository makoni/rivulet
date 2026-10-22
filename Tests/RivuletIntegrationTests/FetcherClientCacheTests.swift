import Foundation
import Testing
@testable import RivuletCore

/// The client cache. A client is never pruned while a request is using it — only `shutdown()` closes
/// everything — because closing one cancels the request it is serving, which is the failure the first test
/// pins. The second pins what `shutdown()` leaves observable: a second call has nothing to close, and the
/// next fetch builds a client again.
@Suite struct FetcherClientCacheTests {
    /// Answers every name with the loopback address, so one stub can serve several host names.
    private struct LoopbackResolver: AddressResolver {
        func resolve(host: String) async throws -> [NetworkAddress] {
            [.ipv4([127, 0, 0, 1])]
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aClientInFlightIsNotClosedToMakeRoomInTheCache() async throws {
        // The regression: a second fetch could prune the cache while the first was waiting for its body,
        // close the client the first was using, and fail that request with a cancellation. The stub holds
        // the body for a second so that request is still in flight while the eight fillers run; if they
        // took longer than that it would have finished and the test would pass without exercising the bug,
        // which is the margin those eight local round trips have. The wait has no bound of its own — a fetch
        // that never reached the stub would hang the job — and the fetch is local with a valid URL, so the
        // head always arrives.
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

    @Test func aSecondShutdownDoesNothingAndTheFetcherWorksAgain() async throws {
        // `shutdown()` takes the entries out of the cache before closing them, so the second call finds
        // nothing to close. Only the observable half of that is asserted here: no error on a second call,
        // and a fetch after it builds a client again. That a call overlapping the first cannot close the
        // same client twice is a property of taking the entries out before the first await; it cannot be
        // reproduced without a client-creation seam the plan does not have, and a test that depended on the
        // two calls interleaving would pass by luck, which `docs/testing.md` forbids.
        try await FetchTestSupport.withServer(behaviors: [
            "/one": StubFeedServer.Behavior(body: Data("one".utf8)),
        ]) { server in
            try await FetchTestSupport.withFetcher(
                options: FetchTestSupport.options(),
                resolver: LoopbackResolver()
            ) { fetcher in
                let url = URL(string: "http://example:\(server.port)/one")!
                _ = try await fetcher.fetch(FetchRequest(url: url, headers: [:]))

                try await fetcher.shutdown()
                try await fetcher.shutdown()

                let response = try await fetcher.fetch(FetchRequest(url: url, headers: [:]))
                #expect(response.body == Data("one".utf8))
            }
        }
    }
}
