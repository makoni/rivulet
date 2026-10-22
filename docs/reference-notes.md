# Miniflux reference notes

Verified against the reference implementation: Miniflux **v2.3.3**, commit `c4d54f87`
(pinned reference clone). These notes are the condensed spec the stage plans rely
on. When in doubt, re-check the cited files in the reference clone.

## Configuration parsing

Source: `internal/config/parser.go`, `internal/config/options.go`.

- Keys and values are trimmed, empty list items are dropped (`parseLines`,
  `parseStringListValue`).
- Empty values fall back to the option default — except options with a validator: validators
  run before the fallback, so an empty `LOG_LEVEL`/`LOG_FORMAT` is an error.
- Booleans: case-insensitive `1/yes/true/on` (true) and `0/no/false/off` (false); anything else
  is an error.
- `LISTEN_ADDR`: comma-separated list, items trimmed and deduplicated; Unix socket paths are
  valid entries; default `127.0.0.1:8080`.
- `BASE_URL`: must parse as an absolute URL; a single trailing slash is trimmed
  (`strings.TrimSuffix`).

## Health probes

Source: `internal/http/server/routes.go`, `internal/http/server/healthcheck.go`.

- `/liveness` and `/healthz` are liveness probes: `200 OK`, body `OK`, no database access.
  Upstream registers them method-less, so any method (not only GET) answers.
- `/readiness` and `/readyz` ping the database; on failure they answer `503 Service Unavailable`
  with `Database Connection Error: ...`.
- All four are mounted on the root mux — they stay at the server root regardless of the
  configured base path.

## Scheduling and refresh

- Tick loop: `internal/cli/scheduler.go` — `time.Tick(POLLING_FREQUENCY)` (default 60 min).
- Batch selection: `internal/storage/batch.go` —
  `next_check_at < now() AND parsing_error_count < limit AND disabled IS false
  ORDER BY next_check_at ASC LIMIT BATCH_SIZE` (default 100); optional per-host limit
  (`POLLING_LIMIT_PER_HOST`, default 0 = off).
- Next interval: `internal/model/feed.go` `ScheduleNextCheck`:
  - round-robin (default): fixed interval, min 60m / max 1440m;
  - entry-frequency mode: `7d / (weekly_entries × factor)` clamped to [5m, 1440m]; when
    `weekly_entries ≤ 0` the interval is the maximum (1440m);
  - `interval = max(interval, refreshDelay)`, where `refreshDelay` comes from the RSS `<ttl>`,
    `Retry-After` (429), `Cache-Control: max-age` or `Expires` (`internal/reader/handler/handler.go`);
  - `next_check_at = now + interval`.
- Errors: **no backoff and no jitter** (verified — these concepts do not exist in the code).
  A failed refresh increments `parsing_error_count`; at `POLLING_PARSING_ERROR_LIMIT` (default 3)
  the feed is excluded from batches until a forced refresh succeeds and resets the counter.
- Worker pool: `WORKER_POOL_SIZE` (default 16).

## Retention ("archiving")

- `internal/cli/cleanup_tasks.go` runs on the reference's own scheduler every
  `CLEANUP_FREQUENCY_HOURS` (default 24; validator requires ≥1); `miniflux -run-cleanup-tasks`
  runs it once immediately and exits. It archives read entries older than
  `CLEANUP_ARCHIVE_READ_DAYS` (default 60) and unread older than
  `CLEANUP_ARCHIVE_UNREAD_DAYS` (default 180); batch size `CLEANUP_ARCHIVE_BATCH_SIZE`
  (default 10000).
- The full task set also deletes web sessions older than `CLEANUP_REMOVE_SESSIONS_DAYS`
  (default 30) and orphan icons. Web sessions belong to the web UI, which Rivulet does not have;
  orphan-icon cleanup waits for icon fetching (stage 4). Stage 1 ports only the two
  `ArchiveEntries` calls.
- "Archiving" is a hard `DELETE` plus a tombstone (`internal/storage/entry.go` `ArchiveEntries`):
  skips `starred` (and shared entries — a feature Rivulet does not implement); keyed on `created_at`.
- Guards in `ArchiveEntries`: `interval < 0 || limit <= 0` archives nothing; the interval is
  truncated to whole days and clamped to at least one (`max(days, 1)`); `ORDER BY created_at ASC`
  makes a limited batch archive the oldest entries first.
- Tombstones: `entry_tombstones(feed_id, hash, deleted_at)`; a tombstoned `(feed_id, hash)` must
  never be re-inserted (`ErrEntryTombstoned`).
- SQLite has no data-modifying CTEs: Rivulet deletes with an ordered, limited `DELETE … RETURNING`
  and inserts the tombstones in the same caller-provided transaction
  (`SQLiteStorage.withTransaction`), where the reference uses one statement. `Retention` runs the
  read and unread passes in two transactions, mirroring the two reference calls, and takes `now`
  as a parameter for deterministic tests.
- Entry statuses in the application are only `unread` and `read` (`internal/model/entry.go`); the
  legacy `removed` enum value survives only in old migrations and is no longer used.

## Entry identity and hashing

Per-format fallbacks before hashing (`internal/reader/*/adapter.go`):

- RSS: `GUID`, disambiguated as `GUID|URL` or `GUID|position` on duplicates → URL → `title+content`;
- Atom: `ID` → original link;
- JSON Feed: `id` → `url` → `external_url` → content;
- RDF: link → `title+description`.

Hash: SHA-256 hex (`internal/crypto`); uniqueness per feed: `UNIQUE(feed_id, hash)`.

## Entry queries (`internal/storage/entry_query_builder.go`)

- Every listing is scoped to a user and optionally filtered by a status list, the starred flag,
  a feed, a category (through a `feeds` join), a list of entry ids, a strict `published_at`
  window and strict id cursors (`AfterEntryID`/`BeforeEntryID`, used by Fever `since_id`/
  `max_id`). `GetEntries` returns rows, `GetEntryIDs` returns ids only and `CountEntries` ignores
  limit/offset. Rivulet exposes the same knobs as `EntryQuery` (`list`, `listIDs`, `count`), but
  uses `nil` for an unset filter: a set id is applied literally, so callers map zero sentinels
  to `nil` (`feedID: 0` and `categoryID: 0` select nothing, while `afterID: 0` still means
  `id > 0`).
- Search uses PostgreSQL `websearch_to_tsquery`; the rank expression
  `ts_rank(...) - extract(epoch from now() - published_at) * 0.0000001 DESC` is appended after
  the requested sort by the REST API (`internal/api/entry_handlers.go`) and is the primary order
  only where no sort is applied (web UI). SQLite searches the FTS5 index over `title` +
  `content_text` with `bm25()`, weighted 2.5:1 to approximate PostgreSQL's title `A` (1.0) and
  content `B` (0.4) weights. Rivulet makes relevance primary and the requested sort the
  tiebreaker (every query carries a sort; a date-first order would defeat search) and does not
  port the recency component: `ts_rank` and `bm25()` have different scales, so a fixed age term
  can dominate `bm25()`'s tiny scores for common terms and vanish against its larger scores for
  rare ones. User input is re-quoted: bare words are ANDed and double quotes group a phrase. FTS5
  syntax (`OR`, `-`, `*`, `NEAR`) is searched as text: no FTS5 operator is interpreted, and only
  double quotes group a phrase. `nil` and the empty string mean no filter (the reference skips
  only `""`); any other input is translated, and input without a term (whitespace, a lone quote)
  matches nothing.
- `WithLimit(0)`, negative values and values above `MaxEntryLimit` (1000) are clamped to 1000;
  no limit at all is how the reference lists every id for Fever's `unread_item_ids`/
  `saved_item_ids`. Rivulet keeps that distinction (`nil` vs a number) and emits
  `LIMIT -1 OFFSET n` when an offset has no limit, since SQLite requires a `LIMIT`.
- Equal `published_at` values have no specified order in the reference builder (the UI appends
  `id` in some views); Rivulet always appends the entry id in the sort direction, so consecutive
  pages are stable when no write intervenes.
- There is no unread-counter table: `CountAllEntries` groups by status, and the web UI's
  per-feed/per-category counters are `COUNT(*) … GROUP BY` queries. Rivulet derives counts the
  same way (`count` with the listing filters); client APIs either use those or count the id
  lists themselves.
- `MarkFeedAsRead` / `MarkCategoryAsRead` update only unread rows with `published_at < before`
  and stamp `changed_at`; the category variant joins `feeds` and scopes by `feeds.user_id`.
  Starred entries are marked too (only the flag survives). Rivulet has no `changed_at` column and
  stamps `updated_at`, using one `UPDATE` with a `feeds` subquery for the category scope.

## Dates (`internal/reader/date/parser.go`)

- Integer Unix timestamp first; then RFC822/850/1123 interpreted as local time; then ~70 layouts
  after string normalization; PST/PDT/EST/EDT workaround and UTC-offset clamping.
- On complete failure the adapters fall back to `time.Now()`.

## Icons

- Stored in the database: `icons(id, hash unique, mime_type, content bytea)`
  (`internal/database/migrations.go`); deduplicated by hash; the public URL uses a random
  `external_id`; feeds relate to icons via the `feed_icons` join table (many-to-many).
- Served **unauthenticated** at `BASE_URL/feed-icon/<external_id>` with `ETag` and a 72h
  `Cache-Control`.
- Google Reader `subscription/list` embeds `iconUrl` (there is no dedicated feed-icon endpoint);
  Fever `favicons` returns `mime;base64,…` without the `data:` prefix.

## Google Reader API (`internal/googlereader`)

Implemented routes (`handler.go`, Go 1.22 mux):

- `POST /accounts/ClientLogin`
- `GET  /reader/api/0/token`
- `POST /reader/api/0/edit-tag`
- `POST /reader/api/0/rename-tag`
- `POST /reader/api/0/disable-tag`
- `GET  /reader/api/0/tag/list`
- `GET  /reader/api/0/user-info`
- `GET  /reader/api/0/subscription/list` (embeds `iconUrl`)
- `POST /reader/api/0/subscription/edit` (`ac=subscribe|edit|unsubscribe`)
- `POST /reader/api/0/subscription/quickadd` (performs feed discovery on website URLs; the
  reference finder additionally probes well-known paths and a few site-specific handlers —
  Rivulet's minimal `<link rel="alternate">` scan is a recorded deviation)
- `GET  /reader/api/0/stream/items/ids`
- `POST /reader/api/0/stream/items/contents`
- `POST /reader/api/0/mark-all-as-read`
- catch-all `GET|POST /reader/api/0/*` → `[]` + HTTP 200 for unimplemented endpoints
  (`unread-count` and `preference/stream/set` are **not** implemented — they hit the catch-all).

Authentication:

- Separate per-user integration credentials (Google Reader username/password, independent from the
  account password; password stored bcrypt).
- `ClientLogin` exchanges them for a stateless token:
  `username + "/" + hex(HMAC-SHA256(key: username+password, message: empty))`; `GET /token`
  returns the same value.
- Token transport is method-specific: **POST routes read the `T` form field only; GET routes read
  the `Authorization: GoogleLogin auth=<token>` header only.**
- `ClientLogin` returns plain text `SID=…\nLSID=…\nAuth=…` by default (`output=json` switches to
  JSON) — clients like NetNewsWire parse the text lines. `GET /token` returns the bare token as
  plain text; write operations (`edit-tag`, `rename-tag`, `disable-tag`, `subscription/edit`,
  `mark-all-as-read`) return plain text `OK`.
- Failure: HTTP 401, `text/plain`, body `Unauthorized`, header `X-Reader-Google-Bad-Token: true`;
  `ClientLogin` failure returns JSON `{"error_message": "access unauthorized"}`.

Contract details worth pinning in golden tests:

- page size `n` clamped to `MaxEntryLimit` = 1000 (0 → 1000);
  `continuation` is a numeric offset encoded as a JSON string, omitted when 0;
- `edit-tag` reads its tags from the body (`a`/`r`); item ids (`i`) are accepted in 4 formats;
- response id formats differ per endpoint; `output=json` is required on some endpoints
  (`tag/list`, `subscription/list`, `stream/items/ids`, `stream/items/contents`);
- unknown/ambiguous stream selections → HTTP 500; label streams are unsupported on
  `stream/items/ids`.

## Fever API (`internal/fever`)

Implemented parameters (`handler.go` dispatch): `groups`, `feeds`, `favicons`,
`unread_item_ids`, `saved_item_ids`, `items`, `mark=item|feed|group`; unknown requests get an
empty base response.

Semantics:

- `mark=item`: read/unread/saved/unsaved.
- `mark=feed`: `id ≤ 0` → empty 200; `id > 0` → that feed read before `before`.
- `mark=group`: `id < 0` → empty 200; **`id = 0` → mark *all* items as read (user-wide, `before`
  is ignored)** — real clients use this; `id > 0` → that category read before `before`.
- Items: fixed limit 50; precedence `since_id` > `max_id` > `with_ids`; `as=saved|unsaved`
  toggles; invalid id → id 0; `id<=0` → empty 200.
- Every response carries `last_refreshed_on_time` (server time at response time; `0` on auth
  failure); `items` additionally carries `total_items`.
- Reported API version: 3. No `keys` or `hot` endpoints.
- Auth: `api_key` = stored MD5 token of `fever_username:fever_password` (lookup case-insensitive).
  Failure → HTTP 200 with `{"api_version": 3, "auth": 0, "last_refreshed_on_time": 0}`.
- `internal/fever` has no tests upstream — the code is the spec, so our contract tests are
  written from the handler.

## Fetching

- `Accept-Encoding: br,gzip` (or `identity` when compression is disabled); conditional GET with
  `If-None-Match` / `If-Modified-Since`.
- SSRF protection: private-network check in the dialer's `Control` callback (TOCTOU-safe), active
  unless `FETCHER_ALLOW_PRIVATE_NETWORKS=true` (`internal/reader/fetcher/request_builder.go`). An
  explicitly configured proxy is a trusted hop: the check runs on direct connections only, and the
  connection to the proxy itself is allowed even when the proxy address is private.
- Proxy precedence in `ExecuteRequest`: the per-feed proxy URL, then the application proxy when the
  feed has `fetch_via_proxy` (`UseCustomApplicationProxyURL(feed.FetchViaProxy)`), then the proxy
  list. Proxy URLs use the ports `80`, `443` and `1080` when the URL gives none.
- Per-feed settings include: custom user agent, proxy, "ignore HTTP cache".
- Request defaults: 20 second timeout (`HTTP_CLIENT_TIMEOUT`), 15 MiB body cap
  (`HTTP_CLIENT_MAX_BODY_SIZE`), 10 followed redirects, `Connection: close`, and the `Accept`
  value `application/xml,application/atom+xml,application/rss+xml,application/rdf+xml,application/feed+json,text/html,*/*;q=0.9`.
- Rivulet's deviations, recorded here so they are not mistaken for upstream behavior: it
  advertises `gzip` only (AsyncHTTPClient decompresses gzip and deflate, not brotli); it does not
  send `Connection: close` because it keeps a connection pool; the advertised user agent is
  Rivulet's own; brotli, per-feed proxy lists, TLS-error tolerance and HTTP/2 toggles are
  deferred. The private-network check runs on the address Rivulet resolved and pinned, which
  removes the time-of-check window the reference closes with its dialer. A per-feed proxy URL is
  not stored yet, so only the application proxy can apply. AsyncHTTPClient tunnels through a proxy
  with `CONNECT` even for plain `http` targets, and connects to the proxy in plain HTTP for `https`
  proxy URLs, so a proxied target is resolved by the proxy and cannot be pinned — the policy is
  skipped for proxied requests, as it is upstream.
- Relevant packages: `internal/reader/fetcher` (request building, response handling),
  `internal/urllib` (IP helpers) — not `internal/http`, which is the integrations/REST client.

## Test fixtures in the reference

- `internal/reader/encoding/testdata` — 11 files; `internal/reader/parser/testdata` — 8 files;
  `internal/reader/xml/testdata` — 3 files; sanitizer testdata — 2 files
  (plus most cases live inline in Go tests).
