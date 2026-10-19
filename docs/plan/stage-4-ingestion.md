# Stage 4 — Ingestion & scheduling

**Goal:** unattended refresh loop; parsed entries land in the database correctly.
**Status:** not started. **Effort:** M. **Depends on:** Stage 3 and Stage 1.

## Scope

- [ ] Refresh pipeline per feed: fetch → parse → normalize → sanitize → merge → store, in one
      write transaction, then update feed state (`next_check_at`, errors).
- [ ] Merge semantics: new entries inserted; changed entries updated (content) **without**
      touching user state (read/starred/removed); entries missing upstream are kept locally.
- [ ] Icons: capture the feed/website icon; store a BLOB deduplicated by hash; expose the hash
      for the client APIs.
- [ ] Scheduler actor: pick due feeds (`next_check_at <= now`), fixed worker pool, jitter,
      per-feed interval (Miniflux-compatible default and minimum), transient-error backoff
      (port `internal/scheduler` semantics).
- [ ] Retention job: periodic cleanup per policy + weekly `VACUUM`.
- [ ] Manual refresh: `rivulet refresh [feed-id|all]` (also used by integration tests).

## Implementation notes

- Reference: `miniflux/internal/scheduler` (tick loop, jitter, backoff), `internal/worker`
  (pool).
- No external cron: the scheduler runs in-process inside `rivulet serve`.
- Target: refreshing a 100-feed database must not block API reads (WAL + short write
  transactions).

## Tests

### Unit

- Merge decisions: new / updated / unchanged / upstream-removed.
- Backoff and `next_check_at` math, jitter bounds, due-set selection.

### Integration

- End-to-end: stub server + temp database — initial refresh stores N entries; a second refresh
  answering `304` stores nothing new.
- Feed updated upstream → new entries added, existing read state preserved.
- Entry removed upstream → it stays locally.
- Fetch error → `error_count` increases and `next_check_at` moves out with backoff; success
  resets counters.
- Scheduler tick refreshes only due feeds (others untouched).
- Retention deletes only expired entries (boundary cases).

## Exit criteria

- [ ] `rivulet serve` keeps a local corpus of feeds updated unattended for hours (observed runs).
