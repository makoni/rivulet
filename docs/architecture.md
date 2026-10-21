# Architecture

## Overview

Rivulet is a single binary with two faces over one core:

```
┌─────────────────────────────┐   ┌────────────────────────────────┐
│ CLI (ConsoleKit)            │   │ HTTP server (Vapor)            │
│ serve · migrate · add ·     │   │ Google Reader API · Fever API  │
│ import · refresh · status … │   │ /feed-icon · /healthz          │
└──────────────┬──────────────┘   └───────────────┬────────────────┘
               │                                  │
               └───────────────┬──────────────────┘
                               │
        ┌──────────────────────▼─────────────────────────┐
        │                    RivuletApp                  │
        │  application factory · commands · routes ·     │
        │  logging bootstrap                             │
        └──────────────────────┬─────────────────────────┘
                               │
        ┌──────────────────────▼─────────────────────────┐
        │                   RivuletCore                  │
        │  config · storage · fetcher · parser ·         │
        │  sanitizer · scheduler · OPML                  │
        └──────────────────────┬─────────────────────────┘
                               │
                     SQLite (WAL + FTS5)
```

## Modules

```
Sources/
├── RivuletCore/            # framework-independent core (+ DocC catalog: RivuletCore.docc)
│   ├── Config/             # environment → Config, validation
│   ├── Storage/            # Fluent models, repositories and raw SQLKit queries
│   ├── Reader/             # fetcher, parser, dates, charset, sanitizer, OPML
│   └── Scheduler/          # refresh loop, retention jobs
├── RivuletApp/             # application layer — the only target that knows Vapor
│   ├── Commands/           # serve, migrate, version + registered stubs for the final CLI
│   ├── Logging/            # text/JSON swift-log bootstrap
│   └── Routes/             # /healthz now; client APIs arrive in stage 5
└── rivulet/                # executable: entry point only
```

## Data model

| Table | Key columns |
| --- | --- |
| `users` | id, username, password_hash (bcrypt), is_admin, google_reader_username, google_reader_password_hash, fever_username, fever_token, created_at, updated_at |
| `categories` | id, user_id, title, position, created_at, updated_at |
| `feeds` | id, user_id, category_id, url, site_url, title, description, icon_id, etag, last_modified, next_check_at, check_interval, parsing_error_count, parsing_error_message, user_agent, disabled, fetched_at, created_at, updated_at |
| `entries` | id, user_id, feed_id, hash, title, url, author, content (sanitized HTML), content_text (plain text), status (`unread` / `read`), starred, published_at, created_at, updated_at |
| `entry_tombstones` | feed_id, hash, deleted_at — a tombstoned entry must never be re-inserted |
| `enclosures` | id, entry_id, url, mime_type, size |
| `icons` | id, hash (unique), mime_type, content (BLOB), external_id (random, for the public URL), created_at |
| `entries_fts` | FTS5 virtual table over `title`, `content_text`; synced by triggers |

Categories own their feeds: deleting a category cascades to its feeds, and deleting a feed
cascades to its entries, enclosures and tombstones (upstream parity).

Indexes target hot paths: entries by `(feed_id, status)`, `(user_id, status, published_at)`,
`(user_id, status, created_at)` and `(user_id, status, starred)` — the last three serve the
user-scoped listings and counts; the retention archive is not user-scoped, so it runs as a
scan bounded by its batch, as in the reference. Feeds by `next_check_at` and
`(user_id, category_id)`; enclosures by `entry_id`; tombstones by `(feed_id, hash)` and
`deleted_at`; FTS5 handles search.

Entry listings use `EntryQuery` (status/starred/feed/category/id filters, date and id cursors,
pagination and optional FTS5 search) through `EntryRepository`, which also owns feed- and
category-scoped mark-as-read. Unread counts are derived from `status` through the same filters;
there is no counter table.

Until the first release the schema is edited in place (`SchemaV1`); versioned migrations start
with the first release.

## CLI

ConsoleKit; the executable is a thin entry point that runs `RivuletCLI.run` and maps errors to a
non-zero exit status — everything else lives in `RivuletApp`.

- `serve` — builds the app via `ApplicationFactory`, applies WAL, runs the startup integrity
  check (`PRAGMA quick_check`) before migrations, migrates when `RUN_MIGRATIONS=true`, boots,
  then delegates to Vapor's built-in `ServeCommand` (so `--hostname`/`--port`/`--bind` keep
  working) and waits for the shutdown signal, like `Application.execute()` does. Unsupported
  arguments are rejected before the database is touched, and a damaged database is refused
  instead of served. The default server address comes from `LISTEN_ADDR`.
- `migrate` — creates or updates the SQLite schema; it always migrates (`RUN_MIGRATIONS` only
  gates what `serve` does on start).
- `version` — prints the version.
- Every other command of the final surface (`create-admin`, `add`, `remove`, `list`, `import`,
  `export`, `refresh`, `status`, `integration-credentials`, `backup`, `vacuum`) is a registered
  stub that reports the stage implementing it.

`--help` lists every command and, like `version`, works without configuration.

## HTTP surface

- `/healthz` — liveness probe: every standard method answers `200 OK`, body `OK`, no database
  access (upstream registers it on a method-less pattern; Rivulet registers the standard NIO
  set, and upstream's `/readiness` probe pings the database and arrives together with the
  client APIs).

## Decisions and deviations from Miniflux

| Topic | Miniflux | Rivulet | Why |
| --- | --- | --- | --- |
| Database | PostgreSQL (required) | SQLite, single file, WAL | Maximal lightness for a personal VPS; zero services to run |
| Full-text search | `tsvector` + `ts_rank` | FTS5 + `bm25()` | SQLite-native; ranking tuned, not matched exactly |
| Feed ↔ icon | `feed_icons` join table (many-to-many) | direct `feeds.icon_id` | One icon per feed is sufficient; dedup by hash retained |
| Integration credentials | configured on the web UI integrations page | set via a CLI command | No web UI (explicit non-goal) |
| Accept-Encoding | `br,gzip` | `gzip` advertised (brotli deferred) | AsyncHTTPClient decompression is gzip/deflate only; documented in parity notes |
| Timestamps | `timestamptz` | unix seconds (INTEGER) | SQLite convention; avoids timezone ambiguity |
| Arrays | PostgreSQL arrays | child tables | SQLite has no array types |
| Web sessions | cookie sessions for the web UI | none | No web UI (explicit non-goal) |
| Bare invocation | `miniflux` starts the server | `rivulet` prints help and fails | The CLI is explicit about what it runs; `serve` is a command like any other |
| Config names | `LISTEN_ADDR`, `BASE_URL`, `LOG_LEVEL`, … | same where meaningful; `DATABASE_URL` = SQLite file path | Familiar to Miniflux users |
| Web UI and REST v1 | full UI + REST v1 | none in MVP; REST subset later on demand | Focus on the client APIs that matter |

## Configuration

Environment parsing follows Miniflux (`internal/config/parser.go`): keys and values are trimmed;
empty values fall back to the defaults — except `LOG_LEVEL`/`LOG_FORMAT`, whose choices are
validated before the fallback (an empty value is an error, like upstream); booleans accept
`1/yes/true/on` and `0/no/false/off` (case-insensitive). Deliberate differences:

- `DATABASE_URL` is required, must be a SQLite file path and must not carry a URL scheme
  (upstream ships a default PostgreSQL DSN).
- `RUN_MIGRATIONS` defaults to `true` (upstream: `false`).
- `LISTEN_ADDR` accepts a single TCP `host:port`; the upstream comma-separated list (including
  Unix socket paths) is rejected with a clear error.
- `LOG_LEVEL`/`LOG_FORMAT` matching is case-insensitive.

## Storage and concurrency

- Swift 6 strict concurrency throughout; `async/await` end to end.
- Vapor + SwiftNIO for the server; the same HTTP client stack for fetching feeds.
- SQLite access goes through a thin storage wrapper because the driver manages only
  `PRAGMA foreign_keys` per connection: the wrapper applies the required pragmas on every pooled
  connection checkout (`busy_timeout`, `synchronous=NORMAL`; `journal_mode=WAL` once per file)
  and exposes `Database.withConnection` plus raw SQL via SQLKit. There is no `DatabasePool`
  type in FluentKit — pool configuration lives in `FluentSQLiteConfiguration`.
- `SQLiteStorage.prepare()` enables `journal_mode=WAL`, verifies that SQLite accepted it, and
  runs before migrations.
- Schema-lookup pragmas (`index_info`, `table_info`, …) resolve against the connection's cached
  schema and do not refresh it: a pooled connection that loaded its schema before the migration
  (for example, the one that ran `journal_mode=WAL`) keeps seeing the old schema. Run an
  ordinary statement first (or use a fresh connection) when such a pragma must observe the
  current schema.
- The driver keeps one pooled connection per event loop: `withConnection` bodies must not open
  a nested checkout (repositories take the checked-out connection) — a nested checkout waits
  for the pool and fails on the connection-pool timeout.
- `withTransaction` wraps a checkout in `BEGIN IMMEDIATE` … `COMMIT`, or `ROLLBACK` when the body
  throws. The immediate lock makes a write batch fail cleanly instead of upgrading a read
  snapshot halfway; the tombstone guard is part of the insert statement, so a refresh cannot
  race a cleanup that commits between an existence check and the insert.
- A feed refresh batches all its writes in one transaction; readers use separate connections.
- The scheduler is an actor; long jobs (retention, vacuum) run off the request path.
- WAL allows concurrent readers with a single writer; `busy_timeout` absorbs short lock
  contention; a truncating checkpoint runs on shutdown (a blocked checkpoint is logged and the
  teardown continues); `journal_size_limit` (64 MiB) is the size the WAL is truncated to when it
  is reset after a checkpoint.
- Maintenance lives on the wrapper: `backup(to:)` (`VACUUM INTO`), `vacuum()` (a rebuild followed
  by a truncating checkpoint, so freed pages actually leave the file), `quickCheck()` at `serve`
  startup — a corrupt database is reported as `StorageError.databaseCorrupt` and never served —
  and `checkpoint()` on shutdown. `checkpoint()`/`vacuum()` report a reader that prevents the WAL
  truncation as `StorageError.checkpointBusy` instead of claiming success. The operator procedure
  is `docs/backup-restore.md`.
- Retention is a driver (`Retention.run` over `RetentionPolicy`), not a timer: it mirrors the
  reference's two `ArchiveEntries` passes, one transaction each, with the reference guards and
  defaults. Stage 4 schedules it daily; per-feed policies are not MVP.
- `Seeding` builds deterministic feed/entry corpora in one transaction (recursive CTE) for
  benchmarks and the opt-in heavy suite.

## Porting rules

- Ported Miniflux code carries a header comment with the original path (see `AGENTS.md`).
- Behavior visible to users or clients must match the reference (see `docs/reference-notes.md`);
  internal structure may differ — SQLite forces a redesigned storage layer anyway.
- Attribution lives in `NOTICE`; keep it accurate as new code and test fixtures are ported.
