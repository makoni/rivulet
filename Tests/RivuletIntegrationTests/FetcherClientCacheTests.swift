import Foundation
import Testing
@testable import RivuletCore

/// The client cache. A client is never pruned while a request is using it — only `shutdown()`
/// closes everything — because closing one cancels the request it is serving, which is the failure
/// the first test pins. The second pins what `shutdown()` leaves observable: a second call has
/// nothing to close, and the next fetch builds a client again.
///
/// The two pins the security checklist adds read the trim: the cache staying at the cap after a
/// checkout that goes over it, and the entry it closes being the one whose expiry comes first — 2
/// pins and 2 probes, each checked by patching the rule and reverting byte-identically: the trim
/// guard never firing, which answered the count as nine entries and left the first host in the
/// cache, and the expiry read in the other direction, which closed the newest entry and flipped the
/// second pin alone. Both read the cache through an internal accessor, because closing a client
/// changes nothing a fetch can answer: the next request for that host builds a client again and
/// gets the same response. What these pins cannot show: that the entry the accessor no longer lists
/// was actually closed rather than dropped; the order between the expired sweep and the trim, which
/// no input separates because every entry here is idle and not expired at the read; and a tie
/// between entries expiring at the same instant, which the code resolves as the first one found and
/// which no test can fix without a clock seam the plan does not have; the count is read against the
/// cap value the code holds, so a patch of the cap itself cannot fail it; and on this input every
/// entry is idle and created in order, so the earliest expiry is also the first created, which an
/// LRU would answer the same way — the pin names the expiry order the code reads, not a use order.
@Suite struct FetcherClientCacheTests {
    /// Answers every name with the loopback address, so one stub can serve several host names.
    private struct LoopbackResolver: AddressResolver {
        func resolve(host: String) async throws -> [NetworkAddress] {
            [.ipv4([127, 0, 0, 1])]
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aClientInFlightIsNotClosedToMakeRoomInTheCache() async throws {
        // The regression: a second fetch could prune the cache while the first was waiting for its
        // body, close the client the first was using, and fail that request with a cancellation.
        // The stub holds the body for a second so that request is still in flight while the eight
        // fillers run; if they took longer than that it would have finished and the test would pass
        // without exercising the bug, which is the margin those eight local round trips have. The
        // wait has no bound of its own, so the test carries a one-minute `timeLimit`: a fetch that
        // never reached the stub fails at the limit instead of hanging the job. The fetch is local
        // with a valid URL, so the head arrives well inside the margin.
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

                // The request is on the wire only after the client was taken from the cache, so
                // waiting for the head means the cache is holding that client while the fillers
                // run. Waiting on the server is what keeps the ordering deterministic without a
                // sleep.
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

    @Test(.timeLimit(.minutes(1)))
    func theCacheStaysAtTheCapAfterACheckoutThatGoesOverIt() async throws {
        // Nine hosts under a cap of eight, which is the security half of the cache: without the
        // trim the number of entries grows with every name a fetch is given, and nothing bounds it.
        // The trim runs at a checkout, so the ninth request is the one that trims, and the count is
        // what the pin reads — a closed client cannot be seen through a fetch, because the response
        // the next request for that host gets is the same whether its entry was closed or kept.
        try await FetchTestSupport.withServer(behaviors: [
            "/fast": StubFeedServer.Behavior(body: Data("fast".utf8)),
        ]) { server in
            try await FetchTestSupport.withFetcher(
                options: FetchTestSupport.options(),
                resolver: LoopbackResolver()
            ) { fetcher in
                for index in 0..<9 {
                    let url = URL(string: "http://host\(index).example:\(server.port)/fast")!
                    _ = try await fetcher.fetch(FetchRequest(url: url, headers: [:]))
                }

                let keys = await fetcher.cachedKeys
                #expect(keys.count == Fetcher.maxCachedClients)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func theTrimClosesTheEntryWhoseExpiryComesFirst() async throws {
        // Which entry the trim picks is only readable through the cache itself, for the same reason
        // the count is: nothing a fetch answers changes when a different entry is closed. This is
        // an expiry cache, not an LRU, so the entry closed is the one created first here — each
        // entry is created by its own request, and the `await` in the loop keeps that order.
        try await FetchTestSupport.withServer(behaviors: [
            "/fast": StubFeedServer.Behavior(body: Data("fast".utf8)),
        ]) { server in
            try await FetchTestSupport.withFetcher(
                options: FetchTestSupport.options(),
                resolver: LoopbackResolver()
            ) { fetcher in
                for index in 0..<9 {
                    let url = URL(string: "http://host\(index).example:\(server.port)/fast")!
                    _ = try await fetcher.fetch(FetchRequest(url: url, headers: [:]))
                }

                // The first host is the one whose entry was closed, so the keys left are the eight
                // created after it, read in the form the cache keys them in.
                let kept = (1...8).map { Fetcher.cacheKey(host: "host\($0).example", proxyURL: nil) }.sorted()
                let keys = await fetcher.cachedKeys
                #expect(keys == kept)
            }
        }
    }

    @Test func aSecondShutdownDoesNothingAndTheFetcherWorksAgain() async throws {
        // `shutdown()` takes the entries out of the cache before closing them, so the second call
        // finds nothing to close. Only the observable half is asserted here, and it is the failure
        // mode the change is about: an implementation that left closed entries in the cache would
        // close the same client twice and fail this second call with AsyncHTTPClient's
        // `alreadyShutdown`, and the fetch after it would fail if a closed client were still in the
        // cache. That the entries are taken out before anything is awaited is not asserted — it
        // needs a client-creation seam the plan does not have — so the ordering is documented
        // rather than tested.
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
