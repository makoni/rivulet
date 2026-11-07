# Backup and restore

All Rivulet state is one SQLite database file (WAL mode, `DATABASE_URL`). A backup is a single
self-contained file: there is nothing else to copy — no external cache and no separate index
(the FTS5 index lives inside the same database).

## Taking a backup

`SQLiteStorage.backup(to:)` wraps SQLite's `VACUUM INTO`: it writes a consistent, compacted
snapshot of a live database (readers and the writer keep working) to a new file. The stage-6 CLI
exposes the same helper as `rivulet backup <destination>`, which is the path as the command reads
it: a relative value is the process's working directory, the port does not create a missing parent
directory, and a destination that already holds something is refused rather than overwritten.

`--force` is the flag that lets the run replace what the destination holds. Without it the
destination is left as it was; with it the run removes what is there and writes the snapshot at the
run in its place. The flag does not change the room check, and a run that cannot hold the copy
removes nothing, so the destination of a refused run is still there to read. The flag is the port's
own: the reference has no backup command to have a flag for. What the run replaces is the file the
path names, read as the filesystem reads it; a path that is a directory is reported rather than
deleted.

Rules SQLite enforces for the destination:

- the parent directory must exist;
- the destination must not be an existing non-empty file: a previous backup is refused
  (`output file already exists`), and any other non-empty non-database file fails with
  `file is not a database`; with `--force` the run removes what is there first, so SQLite writes
  to a path it does not find rather than one it found;
- an existing empty file is reused, which is what `--force` does to it too: the run removes it and
writes a new one, so both answers leave the same path with the same content — a different file, the
same rows — and no pin can tell the two apart.

Free space: budget about twice the database size. The snapshot is a complete copy written next to
the source, and keeping the previous backup while the new one is written doubles that space.
`VACUUM INTO` compacts the copy, so it is usually smaller than the live file with its free pages
and WAL.

The `backup` run checks that room at its start, before it writes anything: the estimate is the bytes
the source holds as the filesystem reads them — the main file plus the `-wal` beside it as the
filesystem reads it — times the factor budgeted above, and the room is read at the directory the
destination is in, which is the current directory for a destination named as a bare name. A run
whose destination has less room than that reports it and writes nothing; a destination with exactly
that room is written. A room the filesystem cannot read is reported as a refusal, because the run
cannot know whether the copy fits, and a size it cannot read counts as nothing. `rivulet vacuum` is
not checked, because it rebuilds the file it already holds rather than writing a copy beside it.

```sh
# Put the target outside the data directory; the path is used as it is read.
rivulet backup "/var/backups/rivulet-$(date +%F).db"

# Replacing the copy the same name holds is the flag, not the default.
rivulet backup --force "/var/backups/rivulet-$(date +%F).db"
```

A backup is a plain SQLite file. Verify it by opening it and running `PRAGMA quick_check`
(`SQLiteStorage.quickCheck()` does that and maps problems to
`StorageError.databaseCorrupt(details:)`), or by restoring it on a scratch copy. The `--verify`
flag does the same check inside the run: it opens the file the run wrote at the path it was given,
reports what the check observed as the failure, and leaves the copy as it was written — the run
below restores another backup rather than repairing a file, so a run that reports a failing check
removes nothing.

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
  the reclaimed space is released to the filesystem when the call returns; `rivulet vacuum` is the
  command that runs it.
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
