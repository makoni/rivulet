# Stage 2 — Feed fetching (HTTP)

**Goal:** robust conditional HTTP fetching of feed documents.
**Status:** not started. **Effort:** M. **Depends on:** Stage 1.

## Scope

- [ ] `Fetcher` over Vapor's HTTP client (AsyncHTTPClient): GET with configurable `User-Agent`,
      `Accept`, timeouts, response size cap, redirect limit, and **explicitly enabled**
      decompression (`.decompression = .enabled(limit:)` — AHC does not decompress by default).
      We advertise `Accept-Encoding: gzip`; brotli is deferred and documented as a deviation
      (the reference sends `br,gzip`).
- [ ] Conditional requests: send `If-None-Match`/`If-Modified-Since` from feed state;
      handle `304` (no body, no error, no re-parse).
- [ ] Error recording with reference semantics: a failed fetch increments
      `parsing_error_count` and stores the message; there is **no backoff and no jitter** (parity —
      see `docs/reference-notes.md`); at the error limit the scheduler excludes the feed until a
      forced refresh succeeds.
- [ ] Per-feed overrides: custom user agent, "ignore HTTP cache", proxy.
- [ ] Security: SSRF protection without relying on a connect-time hook (AsyncHTTPClient has none):
      resolve the host with NIO, reject the request if **any** resolved address is
      private/loopback/link-local, then connect through a client pinned to the validated address
      (`dnsOverride`, one short-TTL client per host). A DNS-rebinding test proves a second lookup
      cannot swap in a private address. Escape hatch: `FETCHER_ALLOW_PRIVATE_NETWORKS=true`
      (tests only).

## Implementation notes

- Reference: `miniflux/internal/reader/fetcher` (`request_builder.go`, `response_handler.go`) and
  `miniflux/internal/urllib`. Note: `internal/http` is the integrations/REST client, not the feed
  fetcher.
- The fetcher is parsing-agnostic: it returns raw bytes + headers; parsing is stage 3.

## Tests

### Unit

- Request header construction; conditional headers derived from stored state; error classification
  mapping (for status/logging only).

### Integration (stub server)

- 200 with body; 304 revalidation; redirect chains (301 → 302 → 200); redirect loops capped.
- gzip decoding works and is actually enabled; chunked responses decode correctly.
- Oversized body rejected with a clear error; a slow response hits the timeout.
- `ETag` and `Last-Modified` round-trip: the second request carries the validators.
- 4xx/5xx and connection reset recorded as fetch errors (counter + message).
- SSRF guard: private targets refused unless explicitly allowed.

## Exit criteria

- [ ] Fetch matrix green; fetch results persist validators and error state into feed state.
