# Miniflux reference notes

Verified against the reference implementation: Miniflux **v2.3.3**, commit `c4d54f87`
(the local clone used during planning). These notes are the condensed spec the stage plans rely
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

- `internal/cli/cleanup_tasks.go` runs daily: archive read entries older than
  `CLEANUP_ARCHIVE_READ_DAYS` (default 60) and unread older than `CLEANUP_ARCHIVE_UNREAD_DAYS`
  (default 180); batch size `CLEANUP_ARCHIVE_BATCH_SIZE` (default 10000).
- "Archiving" is a hard `DELETE` plus a tombstone (`internal/storage/entry.go` `ArchiveEntries`):
  skips `starred` (and shared entries — a feature Rivulet does not implement); keyed on `created_at`.
- Tombstones: `entry_tombstones(feed_id, hash, deleted_at)`; a tombstoned `(feed_id, hash)` must
  never be re-inserted (`ErrEntryTombstoned`).
- Entry statuses in the application are only `unread` and `read` (`internal/model/entry.go`); the
  legacy `removed` enum value survives only in old migrations and is no longer used.

## Entry identity and hashing

Per-format fallbacks before hashing (`internal/reader/*/adapter.go`):

- RSS: `GUID`, disambiguated as `GUID|URL` or `GUID|position` on duplicates → URL → `title+content`;
- Atom: `ID` → original link;
- JSON Feed: `id` → `url` → `external_url` → content;
- RDF: link → `title+description`.

Hash: SHA-256 hex (`internal/crypto`); uniqueness per feed: `UNIQUE(feed_id, hash)`.

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
  unless `FETCHER_ALLOW_PRIVATE_NETWORKS=true` (`internal/reader/fetcher/request_builder.go`).
- Per-feed settings include: custom user agent, proxy, "ignore HTTP cache".
- Relevant packages: `internal/reader/fetcher` (request building, response handling),
  `internal/urllib` (IP helpers) — not `internal/http`, which is the integrations/REST client.

## Test fixtures in the reference

- `internal/reader/encoding/testdata` — 11 files; `internal/reader/parser/testdata` — 8 files;
  `internal/reader/xml/testdata` — 3 files; sanitizer testdata — 2 files
  (plus most cases live inline in Go tests).
