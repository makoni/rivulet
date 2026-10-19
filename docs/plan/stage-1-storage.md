# Stage 1 — Storage layer

**Goal:** the single source of truth for all data: models, repositories, search, retention.
**Status:** not started. **Effort:** M. **Depends on:** Stage 0.

## Scope

- [ ] Repository API over Fluent + SQLKit for every entity of the schema (users, categories,
      feeds, entries, enclosures, icons).
- [ ] Entry lifecycle: statuses `unread/read/removed`, `starred`, hash-based dedupe,
      an upsert that preserves user state.
- [ ] Queries: entry listing with filters (unread/starred/category/feed), pagination,
      unread counts per feed and category; search via FTS5 with `bm25()` ranking
      (plain-text extraction at write time).
- [ ] Feed state bookkeeping: `etag`, `last_modified`, `next_check_at`, `error_count`,
      `error_message`, `fetched_at`.
- [ ] Retention and maintenance: per-feed/all cleanup policies, `vacuum` helper,
      `VACUUM INTO` backup helper.
- [ ] Seeding helper for benchmarks and tests (N feeds, 100k entries).

## Implementation notes

- Reference shapes: `miniflux/internal/storage` (query semantics), but queries are rewritten for
  SQLite; PG-specific constructs (arrays, upserts with `ANY`, partitioning) do not map 1:1.
- FTS5: external-content table over `entries(title, content_text)`; sync via triggers;
  `content_text` is computed with SwiftSoup `.text()` at write time so the index holds plain text.
- Write path: all mutations of a batch run inside one transaction; readers use separate
  connections (WAL allows concurrent readers with a single writer).

## Tests

### Unit

- Plain-text extraction from HTML; query-builder units (filters → SQL).

### Integration

- CRUD round-trip for every entity against a temp SQLite file.
- FTS5: insert/update/delete sync via triggers; search finds expected entries; ranking is sane
  (a relevant entry sorts above an irrelevant one).
- Entry upsert: re-importing the same GUID creates no duplicate; status/starred survive updates.
- Unread counts with mixed read/starred/removed states.
- Concurrency: one writer + several readers in parallel under WAL; `busy_timeout` retries instead
  of failing.
- Retention boundary cases; `VACUUM INTO` backup produces an openable, equal database.

## Exit criteria

- [ ] Storage suite green; stages 2–6 consumers never need raw SQL outside this layer.
- [ ] Backup/restore procedure documented and tested.
