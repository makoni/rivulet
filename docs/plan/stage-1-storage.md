# Stage 1 — Storage layer

**Goal:** the single source of truth for all data: models, repositories, search, retention,
tombstones.
**Status:** in progress. **Effort:** M. **Depends on:** Stage 0.

## Scope

- [x] Repository API over Fluent + SQLKit for every table (users, categories, feeds, entries,
      tombstones, enclosures, icons).
- [x] Entry lifecycle: statuses `unread`/`read` and `starred`; an upsert that preserves user
      state; deletion is a real `DELETE` + tombstone. Hash generation with the per-format
      fallback rules (see `docs/reference-notes.md`) lands with the parsers in stage 3.
- [x] Tombstones: inserted when cleanup deletes entries (skip empty hashes, `ON CONFLICT DO
      NOTHING`); inserts/updates must refuse a tombstoned `(feed_id, hash)`.
- [ ] Queries: entry listing with filters (unread/starred/category/feed), pagination, unread
      counts (derived the way clients derive them), search via FTS5 with `bm25()` ranking
      (plain-text extraction at write time).
- [x] Feed state bookkeeping: `etag`, `last_modified`, `next_check_at`, `parsing_error_count`,
      `parsing_error_message`, `fetched_at`.
- [ ] Retention (port the reference defaults): daily cleanup — delete read entries older than
      60 days and unread older than 180 days, batch 10000, skip starred; per-feed policies are a
      possible extension, not MVP.
- [x] Storage wrapper: per-connection pragmas + single-writer discipline (see stage 0).
- [ ] Maintenance: `VACUUM INTO` backup helper (needs ~2× free space — documented), `vacuum`,
      `journal_size_limit`, checkpoint on shutdown, startup `PRAGMA quick_check`.
- [ ] Seeding helper for benchmarks and tests (N feeds, 100k entries).

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

## Tests

### Unit

- Plain-text extraction from HTML; query-builder units (filters → SQL).

### Integration

- CRUD round-trip for every entity against a temp SQLite file.
- FTS5: trigger sync on insert/update/delete; search finds expected entries; ranking is sane.
- Entry upsert: re-importing the same GUID creates no duplicate; status/starred survive updates;
  a tombstoned entry is refused.
- Unread counts with mixed read/starred states.
- Concurrency: one writer + several readers in parallel under WAL; `busy_timeout` absorbs
  contention instead of returning `SQLITE_BUSY` immediately (verifies the stage-0 wrapper).
- Retention boundary cases with the default numbers; a tombstone is written for every deleted
  entry; starred entries are kept.
- Disk-full behavior: force `SQLITE_FULL` (small `max_page_count`) — clean error, database intact.
- `VACUUM INTO` backup produces an openable, equal database; `vacuum` shrinks a bloated database.

## Exit criteria

- [ ] Storage suite green; stages 2–6 consumers never need raw SQL outside this layer.
- [ ] Backup/restore procedure documented and tested.
