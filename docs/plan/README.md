# Implementation plan

Rivulet is built in ten stages. Every stage file has scope, a test plan (unit and/or integration)
and exit criteria; most include implementation notes. A stage is done only when its exit criteria
and the global definition of done are met and CI is green.

## Reference implementation

Miniflux **v2.3.3** (commit `c4d54f87`, <https://github.com/miniflux/v2>) is the behavioral
specification for everything user-visible: parsing rules, sanitizer policy, scheduling, retention,
API payload shapes. Verified specifics are condensed in [reference notes](../reference-notes.md);
re-check the clone when in doubt. We re-implement in Swift; we do not transpile.
Where storage diverges (SQLite instead of PostgreSQL), behavior must match at the API level,
not at the SQL level.

Earlier planning notes used milestones M0–M3 as *planning phases*, not as the MVP boundary:
M0 → stages 0–1, M1 → stages 2–4, M2 → stages 5–7, M3 → stage 9. Stage 8 (packaging) is new and
is inside the MVP.

## Principles

1. **Miniflux compatibility is the spec.** When in doubt, read the reference implementation and
   mirror the observable behavior.
2. **API-first.** Google Reader API and Fever API come before anything else, so existing clients
   work.
3. **SQLite-first.** One file, WAL mode, FTS5. No PostgreSQL, no Redis, no external cron.
4. **CLI-first, no web UI.** All management happens via commands and environment configuration.
5. **TDD.** Every behavior lands test-first; integration tests are first-class and run in CI. See
   [testing strategy](../testing.md).
6. **Small dependency surface.** Linux-first. New dependencies require explicit approval.

## Stages

| Stage | Title | Status | Effort |
| --- | --- | --- | --- |
| 0 | [Foundation](stage-0-foundation.md) | done | M |
| 1 | [Storage layer](stage-1-storage.md) | done | M |
| 2 | [Feed fetching](stage-2-fetching.md) | fetcher merged, exit criterion deferred | M |
| 3 | [Parsing & sanitization](stage-3-parsing.md) | charset, XML reader, date parser, URL layer, the sanitizer core and its text layer merged, plus the normalized model with the shared primitives and the RSS, RDF and Atom adapters merged; the adapters land one format at a time, with the JSON reader layer and the JSON Feed adapter merged | XL |
| 4 | [Ingestion & scheduling](stage-4-ingestion.md) | not started | M |
| 5 | [Client APIs & OPML](stage-5-apis.md) | not started | XL |
| 6 | [CLI & operations](stage-6-cli.md) | not started | M |
| 7 | [Acceptance & hardening](stage-7-acceptance.md) | not started | M |
| 8 | [Packaging & deployment](stage-8-deployment.md) | not started | S–M |
| 9 | [Post-MVP backlog](stage-9-stretch.md) | backlog | — |

**MVP = stages 0–8** (roughly 6–9k lines of Swift plus tests; expect a few months of part-time
work — stages 3 and 5 dominate). Stage 9 is opportunistic.

## Working agreement

- Stages are sequential: start the lowest not-started stage unless explicitly redirected.
- Update the status table in the same commit that completes a stage.

## Definition of done (every stage)

- [ ] New behavior is covered by tests written first (TDD).
- [ ] Integration tests cover anything that crosses a module boundary (HTTP, SQLite, scheduler,
  API).
- [ ] `swift test` is green locally and in CI.
- [ ] Docs updated (`README.md`, stage status, `docs/` as needed); public APIs carry DocC comments.
- [ ] Ported code/fixtures carry provenance comments and `NOTICE` stays accurate.
- [ ] No new compiler warnings; no skipped or disabled tests (except the documented heavy/on-demand
  suites).

## Non-goals (MVP)

- Web UI of any kind.
- PostgreSQL, Redis, external cron, message queues.
- Multi-user (single user; the schema leaves room for more).
- Miniflux REST v1 parity and API keys (a subset may appear later on demand).
- Native apps of our own — we reuse the existing client ecosystem.

## Known risks

| Risk | Where | Mitigation |
| --- | --- | --- |
| Feed parser fidelity: FeedKit covers RSS 2.0/0.90-0.92, RDF, Atom 1.0, JSON Feed — but **not Atom 0.3**, and older formats are untested | Stage 3 | Spike matrix (Atom 0.3, RSS 0.91/0.92, JSON Feed 1.1) with wrap/patch/manual-fallback decisions; deviations recorded in `docs/parity.md` |
| Per-connection pragmas (`busy_timeout`, `synchronous`) are not managed by sqlite-kit — only `foreign_keys` is | Stages 0–1 | Storage wrapper applies pragmas on every pooled connection checkout, and the contract values are pinned as literals; `busy_timeout` absorbs short lock contention, which the suite does not test with timed waits |
| FTS5 ranking differs from PostgreSQL `tsvector` | Stage 1 | Rank sanity tests, not exact-score tests; tune `bm25()` weights |
| Client dialects vary; upstream Fever has **no tests** — the code is the spec | Stages 5, 7 | Contract matrix derived from the reference handler (`docs/reference-notes.md`), golden tests, replay of captured client requests, manual checklist |
| SQLite write contention under refresh load | Stages 1, 4 | WAL + `busy_timeout`; one write transaction per feed refresh; batch inserts |
| Static Linux (musl) build of the full Vapor + SQLite stack unproven end-to-end | Stage 8 | Spike the static build early — the toolchain SDK is installed and a hello-world static build was verified during planning |
