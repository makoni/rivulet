# Stage 2 — Feed fetching (HTTP)

**Goal:** robust conditional HTTP fetching of feed documents.
**Status:** not started. **Effort:** M. **Depends on:** Stage 1.

## Scope

- [ ] `Fetcher` over Vapor's HTTP client (AsyncHTTPClient): GET with configurable `User-Agent`,
      `Accept`, timeouts, response size cap, redirect limit, gzip/deflate decoding.
- [ ] Conditional requests: send `If-None-Match`/`If-Modified-Since` from feed state;
      handle `304` (no body, no error, no re-parse).
- [ ] Error classification: DNS / TLS / timeout / HTTP 4xx / HTTP 5xx / too-large /
      unsupported content; retryable vs permanent (feeds the scheduler's backoff).
- [ ] Per-feed overrides: custom user agent, HTTP basic auth for the fetch, "ignore HTTP cache"
      flag, proxy via environment.
- [ ] Security: block private/link-local network targets unless
      `FETCHER_ALLOW_PRIVATE_NETWORKS=true` (needed for tests only).

## Implementation notes

- Reference: `miniflux/internal/http` and the fetching half of `internal/reader`; mirror error
  semantics.
- The fetcher is parsing-agnostic: it returns raw bytes + headers; parsing is stage 3.

## Tests

### Unit

- Request header construction; conditional headers derived from stored state; backoff computation
  from `error_count`; error classification mapping.

### Integration (stub server)

- 200 with body; 304 revalidation; redirect chains (301 → 302 → 200); redirect loops capped.
- gzip and chunked responses decode correctly.
- Oversized body rejected with a clear error; a slow response hits the timeout.
- `ETag` and `Last-Modified` round-trip: the second request carries the validators.
- 4xx/5xx classification; connection reset treated as retryable.
- SSRF guard: private targets refused unless explicitly allowed.

## Exit criteria

- [ ] Fetch matrix green; fetch results persist validators into feed state.
