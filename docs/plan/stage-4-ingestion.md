# Stage 4 — Ingestion & scheduling

**Goal:** unattended refresh loop; parsed entries land in the database correctly.
**Status:** in progress — the first slice merged (PR #25). **Effort:** M. **Depends on:** Stage 3
and Stage 1.

The first slice is the per-feed refresh pipeline and the round-robin half of `ScheduleNextCheck`:
the user-scoped lookup, the check stamp and the site-URL fallback, the schedule fixed before the
request, the fetch, the `429` reschedule, the failure and the conditional-hit paths, the entry loop
with the cleaner and the sanitizer, and the injected `Clock` seam, pinned end to end against the
reference by `RefreshPipelineTests` and `NextCheckPolicyTests`. It also closes the stage 2 criterion
that was deferred to the refresh path: the pipeline is the caller that stores the validators and the
error state. The tick loop, the entry-frequency mode, the manual `rivulet refresh` path, retention
and the soak artifact follow. The status stays in progress until the exit criteria below cover the
whole stage.

## Scope

- [ ] Refresh pipeline per feed: fetch → parse → normalize → sanitize → merge → store in one
      write transaction, then update feed state.
- [ ] Merge semantics: new entries inserted; changed entries only update content — user state
      (read/starred) is never touched; entries missing upstream are kept locally.
- [ ] Tombstones are honored end-to-end: a cleaned-up, tombstoned entry never resurfaces through
      refresh. The repository refuses a tombstoned `(feed_id, hash)` pair, which stage 1 pins, and the
      pipeline reads that outcome as no write; no case drives a tombstoned entry through a refresh.
- [ ] Icons: take the feed/website icon, download within size caps, store bytes + hash
      (dedupe) + mime + random `external_id`, link to the feed.
- [ ] Scheduler actor with **reference semantics** (no jitter, no backoff — parity, see
      `docs/reference-notes.md`):
      tick every `POLLING_FREQUENCY` (default 60m); due batch `next_check_at < now()` ordered by
      `next_check_at`, size `BATCH_SIZE` (default 100); worker pool `WORKER_POOL_SIZE` (default 16);
      next interval via `ScheduleNextCheck` — round-robin mode 60–1440m (default), entry-frequency
      mode 5–1440m, `max(interval, refreshDelay)` where `refreshDelay` comes from RSS `<ttl>`,
      `Retry-After` (429), `Cache-Control: max-age` or `Expires`; error limit
      `POLLING_PARSING_ERROR_LIMIT` (default 3) excludes a feed from batches until a forced
      refresh resets it; optional `POLLING_LIMIT_PER_HOST`.
- [ ] Manual refresh: `rivulet refresh [feed-id|all]` — the "forced" path that also resets error
      counters.
- [ ] Retention job (daily): the stage-1 cleanup with tombstones + periodic `VACUUM`.
- [ ] Deterministic testing: an injectable `Clock` abstraction; tests drive the scheduler with
      explicit `tick()` calls — no sleeping. The seam landed with the first slice and is pinned from
      both sides (`SystemClockTests` for the production clock, the injected one for the pipeline); the
      explicit `tick()` calls come with the loop.

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
  HTTP headers; due-set selection; error-limit behavior.

### Integration

- End-to-end (stub server + temp database): initial refresh stores N entries; a second refresh
  answering `304` stores nothing new. Pinned by the first slice.
- Feed updated upstream → new entries added, existing read state preserved.
- Entry removed upstream → it stays locally; a deleted + tombstoned entry is never re-inserted.
- Fetch error → error counter increments; at the limit the feed is excluded from ticks; a forced
  refresh resets it. The increment and both resets are pinned by the first slice; the exclusion is
  the batch query, which comes with the loop.
- A scheduler tick refreshes only due feeds (others untouched).
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
