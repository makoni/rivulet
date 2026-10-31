# Stage 4 — Ingestion & scheduling

**Goal:** unattended refresh loop; parsed entries land in the database correctly.
**Status:** in progress — two slices merged: the pipeline (PR #25) and the tick's batch selection
with the worker pool (PR #26). **Effort:** M. **Depends on:** Stage 3 and Stage 1.

The first slice is the per-feed refresh pipeline and the round-robin half of `ScheduleNextCheck`:
the user-scoped lookup, the check stamp and the site-URL fallback, the schedule fixed before the
request, the fetch, the `429` reschedule, the failure and the conditional-hit paths, the entry loop
with the cleaner and the sanitizer, and the injected `Clock` seam, pinned end to end against the
reference by `RefreshPipelineTests` and `NextCheckPolicyTests`. It also closes the stage 2 criterion
that was deferred to the refresh path: the pipeline is the caller that stores the validators and the
error state. The second slice is the tick's due-batch selection and the bounded worker pool: the
builder's rules pinned through the repository, the pool running each selected job once, one failing
job not stopping the rest, and the non-forced path the worker takes, pinned by `SchedulerBatchTests`
and `SchedulerTickTests`. The cadence loop is not here — nothing can pin a sleeping loop — and lands
with `rivulet serve`; tests drive the scheduler with explicit `tick()` calls. The entry-frequency
mode and the weekly count it divides the week by landed as PR #27, pinned by `WeeklyEntryCountTests`
and read through the pipeline by `EntryFrequencyPipelineTests`; the manual `rivulet refresh` path,
retention and the soak artifact follow. The status stays in progress until the exit criteria below
cover the whole stage.

## Scope

- [x] Refresh pipeline per feed: fetch → parse → normalize → sanitize → merge → store in one
      write transaction, then update feed state. Landed as PR #25; the transaction boundary
      itself is what no test can pin, so it is stated in `docs/parity.md`.
- [ ] Merge semantics: new entries inserted; changed entries only update content — user state
      (read/starred) is never touched; entries missing upstream are kept locally. The upsert half
      is pinned in stage 1, where status and starred survive an update, and the pipeline pins the
      branch that updates a known entry and that a second identical refresh writes nothing; no
      case shows an entry the upstream document no longer declares.
- [ ] Tombstones are honored end-to-end: a cleaned-up, tombstoned entry never resurfaces through
      refresh. The repository refuses a tombstoned `(feed_id, hash)` pair, which stage 1 pins,
      and the
      pipeline reads that outcome as no write; no case drives a tombstoned entry through a refresh.
- [ ] Icons: take the feed/website icon, download within size caps, store bytes + hash
      (dedupe) + mime + random `external_id`, link to the feed.
- [ ] Scheduler actor with **reference semantics** (no jitter, no backoff — parity, see
      `docs/reference-notes.md`). The batch selection landed as PR #26 with every rule of the
      builder pinned: strict `next_check_at < now()`, the direction of the `next_check_at` ordering,
      size `BATCH_SIZE`
      (default 100), error limit `POLLING_PARSING_ERROR_LIMIT` (default 3) excluding a feed from
      batches until a forced refresh resets it, the disabled gate, and optional
      `POLLING_LIMIT_PER_HOST`, which runs only on the rows the `LIMIT` read. The pool runs each
      selected job once; `WORKER_POOL_SIZE` (default 16) is pinned as a value in
      `SchedulerOptionsTests`, while the cap itself is not. Still open: the `POLLING_FREQUENCY`
      cadence (60m), which lands with `rivulet serve`. Both modes of `ScheduleNextCheck` landed: the
      round-robin pair, the entry-frequency `7d / (weekly_entries × factor)` with the cap then the
      floor, the zero count answering the maximum, and the weekly count itself, read through the
      pipeline.
- [ ] Manual refresh: `rivulet refresh [feed-id|all]` — the "forced" path that also resets error
      counters.
- [ ] Retention job (daily): the stage-1 cleanup with tombstones + periodic `VACUUM`.
- [x] Deterministic testing: an injectable `Clock` abstraction; tests drive the scheduler with
      explicit `tick()` calls — no sleeping. The seam is pinned from both sides (`SystemClockTests`
      for the production clock, the injected one for the pipeline and the tick), and the tick suite
      drives the scheduler through `tick()` without sleeping.

## Implementation notes

- Reference: `internal/cli/scheduler.go` (tick loop), `internal/model/feed.go`
  (`ScheduleNextCheck`), `internal/storage/batch.go` (due-set query),
  `internal/reader/handler/handler.go` (refresh delay from TTL/headers).
- No external cron: the scheduler runs in-process inside `rivulet serve`.
- Target: refreshing a 100-feed database must not block API reads (WAL + short write
  transactions).

## Tests

### Unit

- Merge decisions: new / updated / unchanged / upstream-removed / tombstoned.
- Interval selection: round-robin and entry-frequency modes, clamps, `refreshDelay` from TTL and
  HTTP headers. The reference defaults of the tick values are pinned in `SchedulerOptionsTests`;
  the two rules that read a zero as a switch are pinned where they change the query, in the batch
  suite, because a switch is only observable through the query it writes.

### Integration

- End-to-end (stub server + temp database): initial refresh stores N entries; a second refresh
  answering `304` stores nothing new. Pinned by the first slice.
- Feed updated upstream → new entries added, existing read state preserved.
- Entry removed upstream → it stays locally; a deleted + tombstoned entry is never re-inserted.
- Fetch error → error counter increments; at the limit the feed is excluded from ticks; a forced
  refresh resets it. The increment and both resets are pinned by the first slice; the exclusion is
  the batch query, pinned by PR #26.
- A scheduler tick refreshes only due feeds (others untouched). Pinned by `SchedulerTickTests`:
  the pool is handed exactly the jobs the batch answered with, and the control rows — not due,
  disabled, at the limit — reach no run. The pool-size cap itself is not pinned, as the suite
  header states, and the completion order is not asserted because concurrency does not fix it.
- Retention deletes only expired entries (boundary cases) and writes tombstones.

## Exit criteria

- [ ] Soak artifact: `Scripts/soak.sh` runs ≥ 2h with ≥ 20 local stub feeds; `status --json`
      snapshots (stage 4 ships the minimal feed-state `status --json`; stage 6 extends it) show
      `fetched_at`/`next_check_at` advancing with no crashes; log excerpt attached to the stage
      status.

Findings from the review runs on PR #25 that do not change behavior:
- `recordFetch` and `recordParsingError` are keyed by the feed id, where the reference's statements
  add `WHERE user_id`; the pipeline resolves the user-scoped row before calling them, so the write
  is scoped in practice, and no pin can show the difference.
- The port reads the clock once per refresh, where the reference calls `time.Now()` twice, once in
  `CheckedNow` and once in `ScheduleNextCheck`; an injected clock answers one instant, so no pin can
  tell the two reads apart.
- The conditional-hit pin reads the half where the response carries a `Last-Modified`; the reference
  keeps the stored value when the header is empty, and no case here has an empty one.
- The invalid-URL branch is recorded but not pinned, and the reference records a different class
  there: the fetcher's own error from the request.
- The single write transaction spans the HTTP fetch, which the reference's does not, and the
  transaction boundary itself is what no test here can pin.
- `docs/parity.md` says the cache lifetime is read as minutes, which is true of `<ttl>`; the policy
  compares the three delay sources as durations, so the row should separate the read from the
  comparison.


## Backlog

Findings from review run 1 on PR #26 that do not change behavior:
- `JobQueue` is a second type in `Scheduler.swift`, whose primary type is `Scheduler`; the one
  primary type per file rule asks to split it when the file grows.
- The due pins read a stored schedule of 2061 against an injected instant of 2065; both are after
  the process clock, which is what makes the injected clock distinguishable, and that argument stops
  holding after 2061.
