# Implementation plan

Rivulet is built in ten stages. Every stage file has scope, a test plan (unit and/or integration)
and exit criteria; most include implementation notes. A stage is done only when its exit criteria
and the global definition of done are met and CI is green.

## Reference implementation

Miniflux **v2.3.3** (commit `c4d54f87`, <https://github.com/miniflux/v2>) is the behavioral
specification for everything user-visible: parsing rules, sanitizer policy, scheduling, retention,
API payload shapes. Verified specifics are condensed in [reference notes](../reference-notes.md);
re-check the clone when in doubt. We re-implement in Swift; we do not transpile. Where storage
diverges (SQLite instead of PostgreSQL), behavior must match at the API level, not at the SQL level.

Earlier planning notes used milestones M0–M3 as *planning phases*, not as the MVP boundary: M0 →
stages 0–1, M1 → stages 2–4, M2 → stages 5–7, M3 → stage 9. Stage 8 (packaging) is new and is inside
the MVP.

## Principles

1. **Miniflux compatibility is the spec.** When in doubt, read the reference implementation and
mirror the observable behavior. 2. **API-first.** Google Reader API and Fever API come before
anything else, so existing clients work. 3. **SQLite-first.** One file, WAL mode, FTS5. No
PostgreSQL, no Redis, no external cron. 4. **CLI-first, no web UI.** All management happens via
commands and environment configuration. 5. **TDD.** Every behavior lands test-first; integration
tests are first-class and run in CI. See [testing strategy](../testing.md). 6. **Small dependency
surface.** Linux-first. New dependencies require explicit approval.

## Stages

| Stage | Title | Status | Effort |
| --- | --- | --- | --- |
| 0 | [Foundation](stage-0-foundation.md) | done | M |
| 1 | [Storage layer](stage-1-storage.md) | done | M |
| 2 | [Feed fetching](stage-2-fetching.md) | done — the deferred criterion is met by stage 4's pipeline | M |
| 3 | [Parsing & sanitization](stage-3-parsing.md) | merged — every format has its adapter and its corpus, and the integration items are pinned by stage 4's pipeline; the last exit criterion closed with PR #36, the two sanitizer HTML fixtures read end to end against the reference's own output | XL |
| 4 | [Ingestion & scheduling](stage-4-ingestion.md) | in progress — the pipeline, the tick's batch selection with the worker pool, both modes of `ScheduleNextCheck` with the weekly count, the merge and tombstone halves of the entry loop, the three halves of the icon path, the call that path makes for a feed from the pipeline, the manual pass the CLI makes over the batch, the minimal `status --json` contract the soak reads, and the soak artifact itself — 2h over 24 local stub feeds, its checks reading that contract round after round — are pinned, and retention is pinned by `RetentionTests`; the in-process cadence loop landed with stage 6 (PR #50); open: the icon image resizing, which needs a dependency that has not been approved | M |
| 5 | [Client APIs & OPML](stage-5-apis.md) | in progress — the first two slices are merged: `create-admin` with the user rules and the bcrypt hasher (PR #38), and `integration-credentials` with the Fever token derivation and the duplicate-name checks (PR #39); in the third slice the storage reads landed with PR #40, the Google Reader auth path with PR #41, and the contract rules the routers read — the item-id forms, the stream branches, the query read and the parameter reads — as pure logic with PR #42, the rules the handlers read — the tag read, the output read and the document shapes — merged with PR #43, and the handlers for the four endpoints merged with PR #44, pinned over a real socket: the subpath wildcard, which endpoints apply the output check, `edit-tag` reading its tags from the body and its item ids from the merged form, the branch switch with the two ways it reads the same exclude name, the continuation rule, the page-size clamp, and the status each error answer writes; three more handlers merged with PR #45 — `rename-tag`, `disable-tag` and `mark-all-as-read` — with the guard order, the two wordings that name different things, the merged list `s`, the delete guard that counts before any write, the pick it makes for the feeds of the rows it names, the switch with three cases so the types it does not handle write nothing, and the `ts` length rule; `stream/items/contents` merged with PR #46, with the order the handler runs in, the order parameter read from the URL query alone, the two titles read from two different rows, the three time columns with their two string forms, the document author against the item author, `self` from the configured base url, the item id in the full reference form and the answer carrying every row the ids name, and the storage read pinned as a read; the media proxy is recorded as a divergence because this port has none; the remaining handlers, the Fever parameter set, `quickadd` discovery, the icon route, OPML and the acceptance journey follow | XL |
| 6 | [CLI & operations](stage-6-cli.md) | in progress — the first slice is merged: the feed commands `add`, `remove` and `list` (PR #47), with the rule order, the duplicate read, the category read, the delete that applies the account it is given, and the listing order pinned, and the commands pinned as runs through the in-process console; the second slice, `backup` and `vacuum`, is merged (PR #48) with the destination read as it was given, the copy as the snapshot at the run rather than the bytes of the main file, the destination the command did not create, the rebuild that keeps the rows, and the flag gate; the third slice, `list` for the categories and the accounts, is merged (PR #49) with the flag naming which read the run makes, no flag still meaning the feeds, the pair of flags reported as the rule the port names, the account reaching the category read and not the account read, the stored position and the stored admin flag read on the line, one line per row, the run writing nothing, and the port's byte order; the fourth slice, the in-process cadence loop through the `Cadence` seam, is merged (PR #50) with the wait before the first read, the interval every wait is given, one read per wait, the instant each read answers, the reported failing read with the loop going on, the empty read, the stop answer, and the awaited tick pinned as the calls the loop makes through its seam; the fifth slice, the process harness with the signal seam and the wiring `serve` runs, is merged (PR #51), pinned by `ServeProcessTests` as what only a process can answer — the binary answering on the port the argument names, the clean signal path exiting with 0, and the empty WAL the run's shutdown leaves; the sixth slice, the free-space check the `backup` run makes at its start, is merged (PR #52), pinned as the decision the rule answers through the `FileSystemSpace` seam — the estimate as the bytes the source holds as the filesystem reads them, times the documented factor 2, the bytes the WAL holds counted, the room read at the destination's directory and as the current directory for a bare name, the boundary read as strictly less, a size the filesystem cannot read counting as nothing, and a room it cannot read answering a refusal — and as what the run does with that decision, which a patch that copied first and refused after cannot answer; the seventh slice, `--force` as the flag the `backup` run reads, is merged (PR #53); the eighth slice, the check `--verify` gives the `backup` run, is merged (PR #54) as the calls the run makes through the `DatabaseVerifier` seam — nothing called without the flag, the one call for the destination as the run read it and after the write, the failure the run reports for the answer the seam gives with the copy left as written, the flag not changing the room check, and the flag not building the directory the storage layer needs — with what the implementation answers for a real file pinned by `SystemDatabaseVerifierTests` | M |
| 7 | [Acceptance & hardening](stage-7-acceptance.md) | in progress — the first slice opens as PR #55: the hostile bodies the fetcher cannot read as written, read as which limit answers — the body cap counts the bytes the decoder produces, as the reference's `MaxBytesReader` does, and the ratio guard the port had is gone because upstream has no limit on how far a stream expands — plus the reduced 10k-entry scenario, pinned as the plan the schema answers for the hot unread listing, the page the query is given, the relevance order at the corpus size, the batch the retention pass takes with the rows it leaves, and one wall-clock bound; the parity harness and the client matrix follow | M |
| 8 | [Packaging & deployment](stage-8-deployment.md) | not started | S–M |
| 9 | [Post-MVP backlog](stage-9-stretch.md) | backlog | — |

**MVP = stages 0–8** (roughly 6–9k lines of Swift plus tests; expect a few months of part-time work
— stages 3 and 5 dominate). Stage 9 is opportunistic.

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
| Feed parser fidelity: FeedKit covers RSS 2.0/0.90-0.92, RDF, Atom 1.0, JSON Feed — but **not Atom
0.3**, and older formats are untested | Stage 3 | Spike matrix (Atom 0.3, RSS 0.91/0.92, JSON Feed
1.1) with wrap/patch/manual-fallback decisions; deviations recorded in `docs/parity.md` | | Per-
connection pragmas (`busy_timeout`, `synchronous`) are not managed by sqlite-kit — only
`foreign_keys` is | Stages 0–1 | Storage wrapper applies pragmas on every pooled connection
checkout, and the contract values are pinned as literals; `busy_timeout` absorbs short lock
contention, which the suite does not test with timed waits | | FTS5 ranking differs from PostgreSQL
`tsvector` | Stage 1 | Rank sanity tests, not exact-score tests; tune `bm25()` weights | | Client
dialects vary; upstream Fever has **no tests** — the code is the spec | Stages 5, 7 | Contract
matrix derived from the reference handler (`docs/reference-notes.md`), golden tests, replay of
captured client requests, manual checklist | | SQLite write contention under refresh load | Stages
1, 4 | WAL + `busy_timeout`; one write transaction per feed refresh; batch inserts | | Static Linux
(musl) build of the full Vapor + SQLite stack unproven end-to-end | Stage 8 | Spike the static build
early — the toolchain SDK is installed and a hello-world static build was verified during planning |
