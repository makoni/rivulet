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
        ┌──────▼──────────────────────────────────▼──────┐
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
│   ├── Model/              # domain types: User, Category, Feed, Entry, Icon …
│   ├── Storage/            # Fluent models + repositories + raw SQLKit queries
│   ├── Reader/             # fetcher, parser, dates, charset, sanitizer, OPML
│   └── Scheduler/          # refresh loop, retention jobs
└── rivulet/                # executable
    ├── Commands/           # serve, migrate, create-admin, add, import, refresh, status, …
    └── API/                # Google Reader API, Fever API, /feed-icon, /healthz
```

## Data model

| Table | Key columns |
| --- | --- |
| `users` | id, username, password_hash (bcrypt), is_admin, google_reader_username, google_reader_password_hash, fever_username, fever_token, created_at |
| `categories` | id, user_id, title, position |
| `feeds` | id, user_id, category_id, url, site_url, title, description, icon_id, etag, last_modified, next_check_at, check_interval, parsing_error_count, parsing_error_message, user_agent, fetched_at, created_at, updated_at |
| `entries` | id, user_id, feed_id, hash, title, url, author, content (sanitized HTML), content_text (plain text), status (`unread` / `read`), starred, published_at, created_at, updated_at |
| `entry_tombstones` | feed_id, hash, deleted_at — a tombstoned entry must never be re-inserted |
| `enclosures` | id, entry_id, url, mime_type, size |
| `icons` | id, hash (unique), mime_type, content (BLOB), external_id (random, for the public URL) |
| `entries_fts` | FTS5 virtual table over `title`, `content_text`; synced by triggers |

Indexes target hot paths: entries by `(feed_id, status)` and `(user_id, status, published_at)`;
feeds by `next_check_at`; tombstones by `(feed_id, hash)`; FTS5 handles search.

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
| Config names | `LISTEN_ADDR`, `BASE_URL`, `LOG_LEVEL`, … | same where meaningful; `DATABASE_URL` = SQLite file path | Familiar to Miniflux users |
| Web UI and REST v1 | full UI + REST v1 | none in MVP; REST subset later on demand | Focus on the client APIs that matter |

## Storage and concurrency

- Swift 6 strict concurrency throughout; `async/await` end to end.
- Vapor + SwiftNIO for the server; the same HTTP client stack for fetching feeds.
- SQLite access goes through a thin storage wrapper because the driver manages only
  `PRAGMA foreign_keys` per connection: the wrapper applies the required pragmas on every pooled
  connection checkout (`busy_timeout`, `synchronous=NORMAL`; `journal_mode=WAL` once per file)
  and exposes `Database.withConnection` plus raw SQL via SQLKit. There is no `DatabasePool`
  type in FluentKit — pool configuration lives in `FluentSQLiteConfiguration`.
- A feed refresh batches all its writes in one transaction; readers use separate connections.
- The scheduler is an actor; long jobs (retention, vacuum) run off the request path.
- WAL allows concurrent readers with a single writer; `busy_timeout` absorbs short lock
  contention; checkpoint on shutdown; `journal_size_limit` bounds WAL growth.

## Porting rules

- Ported Miniflux code carries a header comment with the original path (see `AGENTS.md`).
- Behavior visible to users or clients must match the reference (see `docs/reference-notes.md`);
  internal structure may differ — SQLite forces a redesigned storage layer anyway.
- Attribution lives in `NOTICE`; keep it accurate as new code and test fixtures are ported.
