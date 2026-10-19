# Stage 4 — Ingestion & scheduling

**Goal:** unattended refresh loop; parsed entries land in the database correctly.
**Status:** not started. **Effort:** M. **Depends on:** Stage 3 and Stage 1.

## Scope

- [ ] Refresh pipeline per feed: fetch → parse → normalize → sanitize → merge → store in one
      write transaction, then update feed state.
- [ ] Merge semantics: new entries inserted; changed entries only update content — user state
      (read/starred) is never touched; entries missing upstream are kept locally.
- [ ] Tombstones are honored end-to-end: a cleaned-up, tombstoned entry never resurfaces through
      refresh.
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
      explicit `tick()` calls — no sleeping.

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
  answering `304` stores nothing new.
- Feed updated upstream → new entries added, existing read state preserved.
- Entry removed upstream → it stays locally; a deleted + tombstoned entry is never re-inserted.
- Fetch error → error counter increments; at the limit the feed is excluded from ticks; a forced
  refresh resets it.
- A scheduler tick refreshes only due feeds (others untouched).
- Retention deletes only expired entries (boundary cases) and writes tombstones.

## Exit criteria

- [ ] Soak artifact: `Scripts/soak.sh` runs ≥ 2h with ≥ 20 local stub feeds; `status --json`
      snapshots show `fetched_at`/`next_check_at` advancing with no crashes; log excerpt attached
      to the stage status.
