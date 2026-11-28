# Stage 7 — Acceptance & hardening

**Goal:** prove real-world compatibility with clients and harden the edges.
**Status:** done in code; the manual client checks left are in the release checklist (issue 130).
**Effort:** M. **Depends on:** stages 5–6.

## What this stage delivered

- The calling sets of five clients — NetNewsWire, FeedFlow, NewsFlash, Capy Reader (read from their
  source at a named commit) and Reeder Classic (from its documentation) — recorded in
  `Tests/RivuletIntegrationTests/CallingSets/` and replayed against the served app by
  `ClientSequenceReplayTests`.
- Walks with the real apps for every client; `docs/clients.md` has the setup for each and what is
  still unwalked.
- A comparison against a running Miniflux 2.3.3 over a shared corpus. It found no difference beyond
  the deliberate ones recorded in `docs/parity.md`; the comparison harness has since been removed,
  because the port is complete and Miniflux is no longer the moving target.
- The security checklist (`docs/security.md`), including the one production fix it found: a repeated
  response header keeps its first value, as Go's `Header.Get` does.
- Performance measurements (`docs/performance.md`) and the hostile-input and large-feed suites
  (`FetcherHostileInputTests`, `LargeFeedTests`).

## Left for the release checklist

The four Reeder Classic Fever items no walk reached (`favicons`, `links`, mark a feed read before a
time, mark a group read) and deleting a category from Capy Reader over REST v1 — issue 130.
