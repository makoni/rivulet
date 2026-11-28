# Stage 1 — Storage layer

**Goal:** the single source of truth for all data: models, repositories, search, retention,
tombstones.
**Status:** done. **Effort:** M. **Depends on:** stage 0.

## Decisions this stage set

- The factor the free-space estimate is built with is 2, for `VACUUM INTO`, which is what
  `Sources/RivuletCore/Storage/FreeSpaceCheck.swift` reads and what `docs/parity.md` records as the
  port's own rule.
- `VACUUM INTO` is a consistent snapshot of a live database; the destination must not be an existing
  non-empty file. `vacuum` is `VACUUM` followed by `PRAGMA wal_checkpoint(TRUNCATE)`, because in WAL
  mode the rebuilt pages commit through the WAL. A checkpoint blocked by a reader answers as busy.
  `journal_size_limit` is 64 MiB, applied on every pooled connection.
- Retention: read entries older than 60 days and unread older than 180 days, batch 10000, starred
  skipped, the age keyed on `created_at`, the cutoff strict, a zero batch a no-op, a negative age
  skipping that status, a zero age clamping to one day, the two passes committing independently. It is
  not scoped to one user. Per-feed policies are the stage-9 extension.
- Search is FTS5 with `bm25()` weighted 2.5:1 for title and content; relevance is the primary order
  and the requested sort the tiebreaker; user input is re-quoted so FTS5 operators cannot break the
  query. There is no counter table: clients count filtered id lists.
- One write transaction per feed refresh; the entry upsert keeps the entry and its enclosures in one
  commit; the retention delete and its tombstones are atomic. Tombstoned `(feed_id, hash)` pairs are
  refused.
- `quick_check` maps a problem row, an empty result set, an unreadable file or a failure that prevents
  the check to the integrity case, while a cancellation is rethrown unchanged; startup serves nothing
  until it passes.

## Exit criteria

- [x] Storage suite green; raw SQL stays inside this layer — the wrapper and its repositories are the
  only access path.
- [x] Backup helper tested; the restore procedure is documented in `docs/backup-restore.md` — it is a
  manual file copy with no code path to test.

Each test suite's header comment names what its tests pin.
