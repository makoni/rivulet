# Backup and restore

All Rivulet state is one SQLite database file (WAL mode, `DATABASE_URL`). A backup is a single
self-contained file: there is nothing else to copy — no external cache and no separate index
(the FTS5 index lives inside the same database).

## Taking a backup

`SQLiteStorage.backup(to:)` wraps SQLite's `VACUUM INTO`: it writes a consistent, compacted
snapshot of a live database (readers and the writer keep working) to a new file. The stage-6 CLI
will expose the same helper as `rivulet backup <path>`.

Rules SQLite enforces for the destination:

- the parent directory must exist;
- the destination must not be an existing non-empty file: a previous backup is refused
  (`output file already exists`), and any other non-empty non-database file fails with
  `file is not a database`;
- an existing empty file is reused.

Free space: budget about twice the database size. The snapshot is a complete copy written next to
the source, and keeping the previous backup while the new one is written doubles that space.
`VACUUM INTO` compacts the copy, so it is usually smaller than the live file with its free pages
and WAL.

```sh
# stage 6 CLI; put the target outside the data directory
rivulet backup "/var/backups/rivulet-$(date +%F).db"
```

A backup is a plain SQLite file. Verify it by opening it and running `PRAGMA quick_check`
(`SQLiteStorage.quickCheck()` does that and maps problems to
`StorageError.databaseCorrupt(details:)`), or by restoring it on a scratch copy.

## Restoring

1. Stop the service (`systemctl stop rivulet`) so no process holds the database or its WAL.
2. Keep the current file: rename `rivulet.db` to `rivulet.db.broken`; do not delete it until the
   restore is verified.
3. Copy the backup over `DATABASE_URL` and **remove the stale `rivulet.db-wal` and
   `rivulet.db-shm` files** next to it. A `-wal` file belonging to another database would be
   replayed into the restored one and corrupt it.
4. Check ownership and permissions: the service user must be able to write the file and its
   directory.
5. Start the service. Startup runs `PRAGMA quick_check` and refuses to serve a database that
   fails the check, cannot be read at all, or cannot be checked at all — a lock held by another
   connection or a full disk reports through the same error. The reported details show what
   SQLite saw, so page damage and an unreadable file are told apart. Restore another backup
   instead of trying to repair the file.

## Why not copy the file directly?

In WAL mode recent commits live in `rivulet.db-wal`; the main file alone can be missing data or
hold a stale snapshot, and copying a live database without its `-wal`/`-shm` is not atomic. A
stop-the-world copy of all three files works (stop the service, copy `rivulet.db*`), but
`VACUUM INTO` is simpler and needs no downtime. Never copy only the main file of a running server.

## Disk-space housekeeping

- `DELETE` (retention, feed removal) marks pages free but never shrinks the file.
  `SQLiteStorage.vacuum()` rebuilds the database and finishes with a truncating WAL checkpoint, so
  the reclaimed space is released to the filesystem when the call returns.
- `SQLiteStorage.checkpoint()` runs `PRAGMA wal_checkpoint(TRUNCATE)`; the server calls it on
  shutdown. A checkpoint blocked by a reader reports `StorageError.checkpointBusy` instead of
  pretending to succeed — retry once the reader is gone.
- `journal_size_limit` (64 MiB) is the size to which the WAL is truncated when SQLite resets it
  after a checkpoint; between checkpoints the file can grow past the limit.

## Durability

WAL mode with `PRAGMA synchronous=NORMAL`: a committed transaction survives an application crash,
while an OS crash or power loss may lose the most recent commits — without corrupting the
database. Choose a backup schedule that matches the refresh volume you can afford to lose; a
daily backup is plenty for a feed reader.
