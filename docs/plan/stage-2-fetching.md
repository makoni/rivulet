# Stage 2 — Feed fetching (HTTP)

**Goal:** robust conditional HTTP fetching of feed documents.
**Status:** done. **Effort:** M. **Depends on:** stage 1.

## Decisions this stage set

- The fetcher is parsing-agnostic: it returns raw bytes and headers. What this stage left open was the
  caller that writes the validators and the error state into feed state; that caller is stage 4's
  refresh pipeline, which is what `RefreshPipelineTests` pins, and the error-limit exclusion is the
  batch query.
- Decompression is explicitly enabled, because the client does not decompress by default; brotli is
  deferred and recorded as a deviation in `docs/parity.md`.
- Conditional requests send `If-None-Match` and `If-Modified-Since` from feed state; a `304` writes
  nothing. Only the statuses the reference follows are followed (301, 302, 303, 307, 308); a 300 with
  a `Location` is an ordinary response, and an unparseable `Location` is a fetch error. The timeout is
  one deadline shared by the hops and covers body reading.
- The address policy runs through an injectable resolver seam, with no connect-time hook: any resolved
  address that is private, loopback, link-local, multicast, unspecified or in the RFC 6598 range
  refuses the request, and the client connects to the validated address, so a later lookup cannot
  change the target. A proxied hop is not pinned, because the proxy resolves the target, so the policy
  is skipped there, as upstream does. The escape hatch `FETCHER_ALLOW_PRIVATE_NETWORKS=true` is for
  tests.

## Exit criteria

- [x] Fetch matrix green.
- [x] Fetch results persist validators and error state into feed state, through stage 4's pipeline.

Each test suite's header comment names what its tests pin.
