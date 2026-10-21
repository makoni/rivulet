# Stage 1 — Storage layer

**Goal:** the single source of truth for all data: models, repositories, search, retention,
tombstones.
**Status:** done. **Effort:** M. **Depends on:** Stage 0.

## Scope

- [x] Repository API over Fluent + SQLKit for every table (users, categories, feeds, entries,
      tombstones, enclosures, icons).
- [x] Entry lifecycle: statuses `unread`/`read` and `starred`; an upsert that preserves user
      state; deletion is a real `DELETE` + tombstone. Hash generation with the per-format
      fallback rules (see `docs/reference-notes.md`) lands with the parsers in stage 3.
- [x] Tombstones: inserted when cleanup deletes entries (skip empty hashes, `ON CONFLICT DO
      NOTHING`); inserts/updates must refuse a tombstoned `(feed_id, hash)`.
- [x] Queries: entry listing with filters (unread/starred/category/feed), pagination, unread
      counts (derived the way clients derive them), search via FTS5 with `bm25()` ranking
      (plain-text extraction at write time); bulk mark-as-read scoped to a feed or a category
      (Fever `mark=feed` / `mark=group`, Google Reader feed/label streams — reference
      `MarkFeedAsRead` / `MarkCategoryAsRead`).
- [x] Feed state bookkeeping: `etag`, `last_modified`, `next_check_at`, `parsing_error_count`,
      `parsing_error_message`, `fetched_at`.
- [x] Retention (port the reference defaults): daily cleanup — delete read entries older than
      60 days and unread older than 180 days, batch 10000, skip starred; per-feed policies are a
      possible extension, not MVP.
- [x] Storage wrapper: per-connection pragmas + single-writer discipline (see stage 0).
- [x] Maintenance: `VACUUM INTO` backup helper (needs ~2× free space — documented), `vacuum`,
      `journal_size_limit`, checkpoint on shutdown, startup `PRAGMA quick_check`.
- [x] Seeding helper for benchmarks and tests (N feeds, 100k entries).

## Implementation notes

- Reference query semantics: `miniflux/internal/storage` — rewritten for SQLite; PG constructs
  (arrays, `FOR UPDATE SKIP LOCKED`, `RETURNING` usage) do not map 1:1.
- FTS5: external-content table over `entries(title, content_text)`; sync via triggers;
  `content_text` computed with SwiftSoup `.text()` at write time.
- Write path: all mutations of a batch run inside one transaction (`SQLiteStorage.withTransaction`,
  `BEGIN IMMEDIATE` … `COMMIT`/`ROLLBACK`); readers use separate connections (WAL allows
  concurrent readers with a single writer). Entry upserts keep the entry and its enclosures in
  one commit; the retention delete and its tombstones are atomic for the same reason.
- Archive: SQLite has no data-modifying CTEs, so the reference's single `ArchiveEntries`
  statement becomes an ordered, limited `DELETE … RETURNING` plus a batched tombstone
  `INSERT … ON CONFLICT DO NOTHING` in that transaction.
- Search: the reference's PostgreSQL `websearch_to_tsquery`/`ts_rank` become FTS5 `MATCH` and
  `bm25()`, weighted 2.5:1 for title/content (PostgreSQL weights A/B). Relevance is the primary
  order and the requested sort is the tiebreaker; the reference's recency term is not ported
  because `ts_rank` and `bm25()` live on different scales (a fixed age term either dominates or
  vanishes). User input is re-quoted (bare words ANDed, double quotes group a phrase), so FTS5
  operators are searched as text and cannot break the query. There is no counter table: clients
  count filtered id lists (Fever) and `count` uses the same filters as `list` (the reference's
  per-feed web-UI counters are out of scope).
- Listings tie-break equal `published_at` by entry id so page boundaries stay stable; `limit`
  follows `WithLimit` (non-positive or oversized → 1000) while `nil` is unbounded for Fever's id
  lists. Scoped mark-as-read is one `UPDATE` (a `feeds` subquery for categories) over the
  caller's unread entries published before the cutoff, stamping `updated_at`.
- Retention (`Retention`, ported from `internal/cli/cleanup_tasks.go`): two archive passes — read
  entries, then unread — each in its own write transaction, exactly like the reference's two
  `ArchiveEntries` calls. Defaults 60/180 days and a batch of 10000; the age is keyed on
  `created_at`, starred entries are skipped. Reference guards are kept: `batchSize <= 0` is a
  no-op, a negative age skips that status, and a zero age clamps to one day. `now` is injectable
  for deterministic tests. The reference's web-session and orphan-icon cleanup tasks are out of
  scope (no web UI).
- Maintenance (`SQLiteStorage`): `backup(to:)` is `VACUUM INTO` (a consistent snapshot of a live
  database; the destination must not be an existing non-empty file — see
  `docs/backup-restore.md`). `vacuum()` is `VACUUM` followed by `PRAGMA wal_checkpoint(TRUNCATE)`:
  in WAL mode the rebuilt pages commit through the WAL, so without the checkpoint the main file
  keeps its old size. `quickCheck()` runs `PRAGMA quick_check` and maps any problem row or
  statement failure to `StorageError.databaseCorrupt(details:)`; startup serves nothing until it
  passes. `journal_size_limit` (64 MiB) is part of the per-connection pragmas.
- Seeding (`Seeding`) builds a benchmark corpus — one user, one category, N feeds and M entries in
  round-robin order — in one transaction. Entries are inserted by one recursive CTE joined to
  `row_number()` over the feeds, so the seeder does not rely on consecutive feed ids; titles,
  URLs, content and timestamps derive only from the entry index, which makes two fresh databases
  byte-for-byte comparable. 100k entries seed in under two seconds.

## Tests

### Unit

- Plain-text extraction from HTML; search-text → FTS5 `MATCH` translation (terms, quoted
  phrases, FTS5 operators kept as text, input without terms).

### Integration

- CRUD round-trip for every entity against a temp SQLite file.
- FTS5: trigger sync on insert/update/delete; search finds expected entries; ranking is sane.
- Entry queries: owner scoping, status/starred/feed/category filters, strict date and id
  cursors, deterministic pagination with limit clamping, batch enclosures, search matching and
  `bm25()` ranking across those filters.
- Scoped mark-as-read: only the caller's unread entries published before the cutoff change;
  `updated_at` is stamped; other feeds, categories and users are untouched.
- Entry upsert: re-importing the same GUID creates no duplicate; status/starred survive updates;
  a tombstoned entry is refused.
- Unread counts with mixed read/starred states.
- Concurrency: one writer + several readers in parallel under WAL; `busy_timeout` absorbs
  contention instead of returning `SQLITE_BUSY` immediately (verifies the stage-0 wrapper).
- Retention boundary cases with the default numbers; a tombstone is written for every deleted
  entry; starred entries are kept.
- Retention driver guards: the cutoff is strict and keyed on `created_at` (not `published_at`),
  batches archive the oldest entries first, a zero batch archives nothing, a negative age skips
  that status and a zero age clamps to one day.
- Disk-full behavior: force `SQLITE_FULL` (small `max_page_count`) — clean error, database intact.
- `VACUUM INTO` backup produces an openable, equal database; a second backup over an existing copy
  is refused; `vacuum` shrinks a bloated database; `checkpoint` truncates the WAL;
  `journal_size_limit` is applied on every connection; `quick_check` reports a corrupted page.
- Seeding: the requested corpus shape and round-robin distribution; two fresh databases seeded
  with the same parameters produce identical entry data.
- Heavy (opt-in, `RIVULET_HEAVY=1`): a 100 × 1000 corpus answers the hot unread-listing query.

## Exit criteria

- [x] Storage suite green; stages 2–6 consumers never need raw SQL outside this layer.
- [x] Backup/restore procedure documented and tested.
