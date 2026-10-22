# Stage 2 — Feed fetching (HTTP)

**Goal:** robust conditional HTTP fetching of feed documents.
**Status:** in progress. **Effort:** M. **Depends on:** Stage 1.

## Scope

- [x] `Fetcher` over Vapor's HTTP client (AsyncHTTPClient): GET with configurable `User-Agent`,
      `Accept`, timeouts, response size cap, redirect limit, and **explicitly enabled**
      decompression (`.decompression = .enabled(limit:)` — AHC does not decompress by default).
      We advertise `Accept-Encoding: gzip`; brotli is deferred and documented as a deviation
      (the reference sends `br,gzip`).
- [x] Conditional requests: send `If-None-Match`/`If-Modified-Since` from feed state;
      handle `304` (no body, no error, no re-parse).
- [ ] Error recording with reference semantics: a failed fetch increments
      `parsing_error_count` and stores the message; there is **no backoff and no jitter** (parity —
      see `docs/reference-notes.md`); at the error limit the scheduler excludes the feed until a
      forced refresh succeeds. The repository side exists (stage 1); the wiring belongs to the
      refresh path, which needs parsing.
- [x] Per-feed overrides: custom user agent, "ignore HTTP cache", proxy. The application proxy is
      attached only to feeds that ask for it (`fetch_via_proxy`), as upstream does; a per-feed proxy
      URL and the proxy list are deferred.
- [x] Security: SSRF protection without relying on a connect-time hook (AsyncHTTPClient has none):
      resolve the host with the system resolver through an injectable `AddressResolver` seam, reject
      the request if **any** resolved address is private/loopback/link-local/multicast/unspecified or
      in the RFC 6598 range, then connect through a client pinned to the validated address
      (`dnsOverride`, one short-TTL client per host). The fetcher follows redirects itself so the
      policy runs on every hop, as the reference's dialer does. A host is resolved once through the
      seam and the client connects to that validated address, so a later lookup cannot change the
      target — the DNS-rebinding case the reference closes with its dialer; the tests show one lookup
      through the seam and that the connection goes to the validated address. Escape hatch:
      `FETCHER_ALLOW_PRIVATE_NETWORKS=true` (tests only). A proxied request is not pinned — the proxy
      resolves the target — so the policy is skipped for that hop, which is what upstream does with an
      explicitly configured proxy.

## Implementation notes

- Reference: `miniflux/internal/reader/fetcher` (`request_builder.go`, `response_handler.go`) and
  `miniflux/internal/urllib`. Note: `internal/http` is the integrations/REST client, not the feed
  fetcher.
- The fetcher is parsing-agnostic: it returns raw bytes + headers; parsing is stage 3.

## Tests

### Unit

- Request header construction; conditional headers derived from stored state; error classification
  mapping (for status/logging only); `FetchResponse.header(_:)` reads a name in any case; the proxy
  ports assumed when a proxy URL gives none.

### Integration (stub server)

- 200 with body; 304 revalidation; redirect chains (301 → 302 → 200); redirect loops capped; only the
  statuses the reference follows are followed (301, 302, 303, 307, 308 — a 300 with `Location` is an
  ordinary response); an unparseable `Location` is a fetch error.
- gzip decoding works and is actually enabled; chunked responses decode correctly.
- Oversized body rejected with a clear error; a slow response hits the timeout, and the timeout is one
  deadline shared by the hops and covers body reading, not only the response head.
- `ETag` and `Last-Modified` round-trip: the second request carries the validators.
- 4xx and 5xx and a connection closed by the peer classified as fetch errors: the stub covers 404, 429 and
  a connection it closes, the other status wordings are pinned by the unit test; what fails before anything
  connects (a scheme the client refuses when the URL is turned into a request) is mapped like any other
  client error. The counter and the message are recorded through `FeedRepository.recordParsingError` (the
  refresh path wires them together).
- SSRF guard: private targets refused unless explicitly allowed — both halves of the switch are tested;
  the pinned address is used without a second lookup; every redirect hop goes through the resolver seam
  before connecting — the test proves the seam is consulted for the hop and that a hop the seam cannot
  answer stops the fetch. A refusal at a hop is not observable in a hermetic test, because the only
  address the first hop could reach is the stub, which a denying policy would itself refuse.
- A proxied request reaches the proxy (a stub proxy answers `CONNECT`) and the address check is
  skipped for that hop; the same private target without the flag is refused.
- The cache keeps a client per host and proxy decision, and one that a request is using is not pruned:
  a fetch whose body the stub is holding survives the evictions that other fetches trigger meanwhile.

## Exit criteria

- [ ] Fetch matrix green; fetch results persist validators and error state into feed state.
