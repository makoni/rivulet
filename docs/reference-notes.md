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
- Batch selection: `internal/storage/batch.go` — `next_check_at < now() AND parsing_error_count <
  limit AND disabled IS false ORDER BY next_check_at ASC LIMIT BATCH_SIZE` (default 100); optional
  per-host limit (`POLLING_LIMIT_PER_HOST`, default 0 = off). Both zeros are switches: the error
  condition and the `LIMIT` clause are added only for a positive number, so a batch size of 0 adds
  no clause and an error limit of 0 excludes nothing. The per-host limit applies while the rows are
  iterated, after the `LIMIT`, so a row it skips still uses one of the `LIMIT` slots, and the host
  is
  `urllib.Domain` — the parsed host with its port, the input as written when the URL does not
  parse, no `www.` strip. `feedScheduler` passes neither a user nor a category, so the batch is not
  scoped. Upstream has no test for the builder; the port pins each rule in `SchedulerBatchTests`.
- Next interval: `internal/model/feed.go` `ScheduleNextCheck`:
  - round-robin (default): fixed interval, min 60m / max 1440m;
  - entry-frequency mode: `7d / (weekly_entries × factor)` clamped to [5m, 1440m]; when
    `weekly_entries ≤ 0` the interval is the maximum (1440m);
  - `interval = max(interval, refreshDelay)`, where `refreshDelay` comes from the RSS `<ttl>`,
    `Retry-After` (429), `Cache-Control: max-age` or `Expires`
    (`internal/reader/handler/handler.go`);
  - `next_check_at = now + interval`.
- Errors: **no backoff and no jitter** (verified — these concepts do not exist in the code).
  A failed refresh increments `parsing_error_count`; at `POLLING_PARSING_ERROR_LIMIT` (default 3)
  the feed is excluded from batches until a forced refresh succeeds and resets the counter.
- Worker pool: `WORKER_POOL_SIZE` (default 16).

### The refresh path (`RefreshFeed`, `internal/reader/handler/handler.go`, commit `c4d54f87`)

- The row is read through the user-scoped `FeedByID`; the not-found case returns before anything is
  stamped or fetched.
- Order: `CheckedNow` stamps the check time and puts the feed URL in place of an empty site URL,
  and `ScheduleNextCheck(weekly_count, 0)` fixes the schedule before the request is built. A `429`
  recomputes the schedule from `Retry-After` before the failure is reported. The failure is
  recorded through `UpdateFeedError`, which writes `parsing_error_msg`, `parsing_error_count`,
  `checked_at` and `next_check_at` only: no conditional-GET header is written on this path.
- Conditional headers are not sent on the forced path: the handler treats `forceRefresh` as
  `IgnoreHTTPCache`.
- A conditional hit stores `Last-Modified` only when the response carries a value, as RFC9111
  sections 3.2 and 4.3.4 read it; the stored `EtagHeader` stays as the row held it. Both branches
  end with `ResetErrorCounter`, so the hit path resets the error state.
- The modified branch stores the response's validators, recomputes the schedule from
  `max(ttl, max-age, expires)`, and writes the row through `UpdateFeed`, which carries the title
  the row already held: the parsed title is never copied on this path.
- `ProcessFeedEntries` iterates `slices.Backward`, so entries are processed oldest first and the
  row written first is the item the document declares last. The cleaner replaces an entry URL only
  when the URL parses — Go's `url.Parse` fails on an unclosed bracket host, so that URL is stored
  as the feed wrote it — and the hash is the adapter's, taken before the cleaner ran. The
  entry-update branch is gated by `forceRefresh || (!crawler && !ignore_entry_updates)`.

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
  skips `starred` (and shared entries — a feature Rivulet does not implement); keyed on
  `created_at`.
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

- Integer Unix timestamp first; then the RFC822/850/1123 group, parsed in UTC — the group name says
  "local time", but `parseLocalTimeDates` pins UTC with two named-zone exceptions: `PST`/`PDT` →
  Los Angeles, `EST`/`EDT` → New York; then the layout list after normalization — 3 layouts in the
  local-time group and 206 in the list, 209 in all — with the offset clamped to −12:00 to +14:00,
  reported as UTC.
- Normalization is a 79-pair table scanned over the bytes: zone locations written as names,
  localized day and month names, and the two weekday spellings that are not Go's own. At a position
  Go takes the pair with the highest priority, which is the first one in the order the pairs are
  listed in. The only pattern that is a prefix of another is `Mai`, and the longer `Mai ` is listed
  first; its pattern and replacement carry the same trailing space, so the output is the same as a
  longest-match reading would give.
- A zone abbreviation is resolved through the machine's local zone (`lookupName`), with the
  documented fallback offset of 0; `GMT` keeps a signed hour as part of its name. A value that reads
  no zone at all is read as UTC, because `time.Parse`'s default location is UTC.
- On complete failure the adapters fall back to `time.Now()`.

## URL rules (`internal/urllib`, `internal/reader/urlcleaner`)

- `IsRelativePath` rejects a value containing a backslash before parsing, because a browser reads
  `/\evil.com` as an open redirect while Go reads the backslash as an ordinary path character.
  Otherwise a value is relative when it parses and carries neither a scheme nor a host.
- `IsAbsoluteURL` checks the `http`/`https` prefix on the value as it was read, before parsing, so a
  value that starts with whitespace is not absolute even though `url.Parse` would trim it.
- `RootURL` turns a leading `//` into `https://`, and a value that does not parse, or parses with no
  scheme or no host, is answered with as it was read. Otherwise the answer is scheme + `://` + host
  + `/`. `Domain` is the host as the parse reports it, which is the decoded form, and
  `DomainWithoutWWW` removes only a leading `www.`.
- The host is read through Go's host mode: a byte at or above DEL is part of the host, a percent
  escape may carry only such a byte except `%25`, and a bracket that opens inside the host is
  refused. The port is read at the first colon for `http` and `https` — Go's strict-colon rule with
  its default on — and at the last colon for another scheme. The user part of an authority is
  checked against the class RFC 3986 §3.2.1 allows, after the host is read.
- `resolveToAbsoluteURL` answers three cases before the base is used: a value beginning with the
  authority marker takes `https:` whatever the base scheme is; an `http`/`https` prefix is returned
  as it was read; a value that carries a scheme is returned as it was read. The base is parsed only
  when it has not been parsed already, and the join is `ResolveReference().String()`.
- Tracking parameters (`internal/reader/urlcleaner`): the parameter name is compared lower-cased
  against the table, and the `utm_`/`mtm_` prefixes are checked before the table. `ref` is an
  outbound parameter, so it is removed only when one of its values equals the feed host or the site
  host. The query is written back only when something was removed, and then in sorted key order, so
  a URL with no tracker comes back with its pairs in the order the feed declared them.
- Two rules of `internal/urllib` are not ported yet because no reader path uses them:
  `IsValidProxyURL` (the fetcher's proxy check, which needs a host as well as an HTTP or SOCKS5
  prefix) and `JoinBaseURLAndPath` (the integrations, stage 6). Both read through the same parse
  when they land.

## HTML sanitizer (`internal/reader/sanitizer`)

- The rules below are read through `golang.org/x/net/html`, the package `miniflux/go.mod` pins at
  v0.57.0. There is no Go toolchain on this machine, so they are traced from the source; the copy
  the entity table was generated from is the module cache at v0.61.0.
- The input is wrapped in `<body>` before it is parsed, and the output is built from the children of
  the body node. A document that does not parse — the open-element stack passing its limit of 512,
  with `html` and `body` counted in it — is answered with the empty string.
- The output string is written by the sanitizer itself: the element name, then the attributes it
  kept in the order they were read, then the attributes it adds. Text is written through
  `EscapeString`, which uses `&#34;` and `&#39;` rather than the named forms `&quot;` and `&apos;`
  and writes a carriage return as `&#13;`.
- A tag outside the allowlist is not written, but its content is. An element is skipped with its
  content when it is a one-pixel image — both `height` and `width` present and each one the digit
  `1` or `0`, read from the value as the tokenizer read it — when it is one of the three tags that
  can carry script (`noscript`, `script`, `style`), or when it carries the `hidden` attribute.
- An attribute outside the tag's own list is read and dropped. A value that holds a URL (`src`,
  `href`, `poster`, `cite`) is resolved against the base URL and checked against the scheme
  allowlist; the tracking parameters are removed from it only when it carries a query. A data URL
  on an `img` and an in-document anchor (`href` starting with `#`) are kept as they were read,
  before any resolution.
- Three attributes are mandatory, and they decide what happens to the content: `a` needs `href`,
  `iframe` needs `src`, `img` and `source` need `src` or `srcset`. An element missing one writes
  nothing for itself but still writes its content, except an `iframe`, which writes nothing at all.
- What the sanitizer adds, after the attributes it kept: `a` gets `rel` and `referrerpolicy`, plus
  `target` when the option is on; `video` and `audio` get `controls`; `iframe` gets `sandbox` and
  `loading`, plus `referrerpolicy` for a YouTube embed, which is the only place that attribute is
  written; `img` gets `loading`. None of it is written for an in-document anchor, because the anchor
  branch sets the flag the added attributes check.
- The `iframe` rules read the source before it is resolved, so a protocol-relative source is
  judged on the host as it was written. The domain compared with the allowlist is the host without
  a leading `www.`, and the YouTube override domain and the Invidious instance are compared the
  same way. The embed prefix replaces `youtube.com` only for the `/embed/` path, and the Vimeo
  player gets `dnt=1` only for `/video/`.
- `srcset` is read as candidates — a URL up to the first ASCII whitespace, then its descriptors —
  and the value written is the serializer's join of the candidates that survive, so the spacing the
  feed wrote is replaced. A candidate whose URL does not resolve, or whose scheme is invalid or
  blocked, is dropped, and a value with no surviving candidate is not written. A descriptor is kept
  only when it parses as one height, one width or one density that is finite and not below zero —
  negative zero passes, while a leading `+` or a trailing `.` is not a number. The two integer
  descriptors read through `ParseUint(value, 10, 0)`, whose range is the whole unsigned 64-bit
  value. The string written back is the serializer's own: the density with
  `strconv.FormatFloat(value, 'g', -1, 64)`, which takes the exponent form when the decimal exponent
  is below -4 or at least 6, and the width as `FormatUint` writes it. A URL ending with a comma has
  its comma removed instead of taking a descriptor.
- Text is written after the insertion mode has removed NUL from the token, and the newline rules are
  the tokenizer's: CRLF and a lone CR become LF, and a newline at the start of a `pre` or `listing`
  block is dropped when it is the first thing in it.

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
- SSRF protection: private-network check in the dialer's `Control` callback (TOCTOU-safe), which
  runs on **every** dial, including the hop reached through a redirect; active unless
  `FETCHER_ALLOW_PRIVATE_NETWORKS=true` (`internal/reader/fetcher/request_builder.go`). An
  explicitly configured proxy is a trusted hop: the check runs on direct connections only, and the
  connection to the proxy itself is allowed even when the proxy address is private.
- Proxy precedence in `ExecuteRequest`: the per-feed proxy URL, then the application proxy when the
  feed has `fetch_via_proxy` (`UseCustomApplicationProxyURL(feed.FetchViaProxy)`), then the proxy
  list. Proxy URLs use the ports `80`, `443` and `1080` when the URL gives none.
- Per-feed settings include: custom user agent, proxy, "ignore HTTP cache".
- Request defaults: 20 second timeout (`HTTP_CLIENT_TIMEOUT`), 15 MiB body cap
  (`HTTP_CLIENT_MAX_BODY_SIZE`), a redirect cap of 10 requests (`CheckRedirect` refuses the 10th, so
  at most 9 are followed — see the deviation below), `Connection: close`, and the `Accept` value
  `application/xml,application/atom+xml,application/rss+xml,application/rdf+xml,application/feed+json,text/html,*/*;q=0.9`.
- Rivulet's deviations, recorded here so they are not mistaken for upstream behavior:
  - Rivulet has no connect-time hook, so the private-network check runs on the answers the resolver
    seam returns for a named host, or on the address itself when the URL already carries one and no
    lookup happens. The client is pinned with `dnsOverride` to one address it validated at build
    time, and that pin cannot be changed by a later lookup; a cached client keeps it, so on a cached
    hop the policy checks the current answers while the connection uses the address pinned at build
    time. This is the same TOCTOU guarantee the reference gets from its dialer's `Control` callback
    — the difference is the mechanism, not the property.
  - The body cap is enforced by AsyncHTTPClient's response accumulator, which counts the
    decompressed body — the same thing the reference's `MaxBytesReader` counts when it wraps the
    decompression reader, so only the mechanism differs.
  - `Accept-Encoding: gzip` only (AsyncHTTPClient decompresses gzip and deflate, not brotli); no
    `Connection: close` because Rivulet keeps a connection pool; the advertised user agent is
    Rivulet's own. Brotli, TLS-error tolerance and HTTP/2 toggles are deferred. The pool runs on
    AsyncHTTPClient's defaults (60 s idle, 8 connections per host), not the reference's
    `MaxIdleConns: 50` / `IdleConnTimeout: 10s` (90 s is Go's default, not what Miniflux sets); the
    decompression-bomb guard (`limit: .ratio(25)`) is a Rivulet addition, since upstream relies on
    the body cap alone.
  - Every direct redirect hop is validated: the fetcher follows redirects itself, one request per
    hop, so the address policy runs on each direct hop the way the reference's dialer `Control`
    does, and the exception is the same — the dial to an explicitly configured proxy is not checked.
    The statuses followed are 301, 302, 303, 307 and 308, and cycles are allowed up to the limit —
    upstream's `CheckRedirect` counts requests and does not refuse a repeated URL. The boundary
    differs by one hop: upstream refuses the redirect that would make the count reach the limit,
    Rivulet refuses the one after the limit is reached.
  - The timeout is one deadline shared by all hops, as the reference's `Client.Timeout` is computed
    once and covers connection, redirects and body reading together; Rivulet sets no per-hop read
    timeout. A redirect status with an empty `Location` is returned as the response, as Go's `do`
    does.
  - A failure the client reports is mapped to the fetcher's categories. An error with no category is
    reported as a network failure with the client's wording, which is the same category the
    reference uses for it: `isNetworkError` is true for `*url.Error` — which `net/http`'s
    `Client.do` wraps every failure in — so only the wording differs on that path: Go prints its
    `Get "url":` wrapper, Rivulet prints its own phrase with the client's wording after it; the
    strings Miniflux shows for these come from locale keys
    (`internal/locale/translations/en_US.json`), which Rivulet does not reproduce. For an
    unparseable `Location` Rivulet prints Go's phrase (`failed to parse Location header`, which
    `net/http`'s `Client.do` writes) without the `Get "url":` wrapper and without the parse error Go
    adds after the colon, since it has no parse error to print. Two more wording details: the
    reference quotes the host in the private-network message with `%q` and Rivulet prints it bare,
    and `ErrHostnameResolution` is only compared (`internal/ui/proxy.go:106`) — the fetch path
    reports a DNS failure as Go's resolver error inside `Get "url":`, so Rivulet's category for it
    is its own, reached through the resolver seam upstream does not have. Three of the reference's
    categories are one-sided: `error.network_timeout` sits behind `isNetworkError`, so a timeout
    Go's client wraps is a network error there while Rivulet reports it as a timeout;
    `error.http_empty_response` sits behind it too, for the same reason; and
    `error.http_client_error` needs an error that is not a `*url.Error`, which Miniflux's fetch path
    does not produce — it builds the request with a literal `GET` and a background context, and a
    `url.Parse` failure is a `*url.Error` — so it is effectively unreachable upstream.
    `error.tls_error` is reachable upstream and Rivulet has no TLS category: a TLS failure arrives
    as a network error.
  - Headers are forwarded to every hop verbatim. Go strips sensitive headers (`Authorization`,
    `Cookie`, `Proxy-Authorization`) when a redirect leaves the initial domain and adds a `Referer`;
    Rivulet does neither — no effect today, because the request builder sets none of those headers.
  - A 4-in-6 address is classified through its IPv4 form, as Go's `netip.Addr.Unmap()` does, and the
    canonical text prints that form. Rivulet's text parser does not accept the mixed
    `::ffff:a.b.c.d` spelling — the unmapped form comes from resolver bytes.
  - Rivulet refuses the whole request when **any** resolved answer is non-public. Upstream checks
    the address it dials one attempt at a time, so a private answer later in the list is never
    reached when a public answer connects first; Rivulet is stricter here on purpose.
  - `HTTPDate` is read the way Go's parser reads `time.RFC1123`: three letters of a day name for the
    weekday with its comma, a two-digit day validated against the month, a four-digit year, and the
    minute and second fixed at two digits while the hour is not. The divergences: Go looks a zone
    name up in the local zone table, so `EST` shifts the time when that table defines it (otherwise
    the name is kept with no offset); Go reads the zone as a name or a signed hour (`+03`, `GMT+3`),
    but a bare `+03` is taken as a zone name with no shift — only `GMT+3` moves the time — while
    Rivulet reads only the four-digit `+hhmm` form, which is what servers actually send and what
    `RFC1123Z` accepts upstream, and shifts for it; Rivulet does not read a fractional second, which
    Go accepts after the seconds field; and Rivulet splits the value on spaces, so it reads a padded
    value — Go rejects a leading space before the weekday and any leftover after the zone, though a
    run of spaces in the middle counts as one separator, so a doubled space parses upstream as well.
    Leftover text that is not spaces is rejected by Rivulet too. Rivulet is stricter at the offset
    boundary: Go's numeric path (`RFC1123Z`) reads fixed-width two-digit fields and allows an hour
    of 24 and a minute of 60 (`hr > 24`, `mm > 60`), so `+2400` and `+0360` parse there, while
    Rivulet reads only an hour of 0...23 and a minute of 0...59. Go's `> 23` check is in
    `parseSignedOffset`, which reads the signed hour of a zone name (`+03`, `GMT+3`), not the
    numeric field.
  - `Expires` becomes a delay in whole minutes: `Until(now).Truncate(minute) + minute`, so a value
    inside the current minute yields a minute even when it is already past, a past value that
    truncates to exactly the previous minute yields nothing, and one further past yields a negative
    delay. Rivulet divides whole seconds the same way — truncating toward zero, which is what Go's
    `Truncate` does — so it returns the same negative value. Upstream the handler takes
    `refreshDelay = max(feed TTL, cacheControlMaxAge, expires)`
    (`internal/reader/handler/handler.go`), which can itself be negative, and
    `Feed.ScheduleNextCheck` clamps it with `interval = max(interval, refreshDelay)` against the
    configured minimum (`internal/model/feed.go`); the refresh path has to do both here.
  - Address text is read the way Go's parser reads it (`netip.ParseAddr`, which `net.ParseIP` uses):
    every field must have a digit, so an empty octet is not an address; a group is at most four hex
    digits and a sign is not a group; `::` must stand for at least one zero group; an octet with a
    leading zero is rejected; and a zone is not accepted — `netip.ParseAddr` would accept a zone,
    but `net.ParseIP`, which the reference uses, rejects it. Two further differences: Rivulet trims
    the text first, which Go does not, and it does not read the mixed form `::ffff:1.2.3.4` — the
    unmapped form comes from resolver bytes. Its canonical text prints the eight groups in full,
    while Go's `String()` applies RFC 5952 compression, so the two print the same address
    differently.
  - The empty-body decision uses the bytes actually read; upstream uses `ContentLength`.
  - Environment names mirror the reference (`HTTP_CLIENT_TIMEOUT`, `HTTP_CLIENT_USER_AGENT`,
    `HTTP_CLIENT_MAX_BODY_SIZE`, `HTTP_CLIENT_PROXY`, `FETCHER_ALLOW_PRIVATE_NETWORKS`).
    `FETCHER_IGNORE_HTTP_CACHE` is a Rivulet addition: upstream has only the per-feed flag. Upstream
    also proxies from the environment (`ProxyFromEnvironment`), and proxy URLs may carry
    credentials; both are deferred. A per-feed proxy URL is not stored yet, so only the application
    proxy can apply.
  - AsyncHTTPClient tunnels through a proxy with `CONNECT` even for plain `http` targets, and
    reaches an `https` proxy in plain HTTP, so a proxied target is resolved by the proxy and cannot
    be pinned — the policy is skipped for that hop, as it is upstream.
- Relevant packages: `internal/reader/fetcher` (request building, response handling),
  `internal/urllib` (IP helpers) — not `internal/http`, which is the integrations/REST client.

## Encoding and XML tolerance

- `internal/reader/encoding/encoding.go`: `CharsetReader` does not convert when the document is
  already valid UTF-8, so a prolog label that contradicts the bytes is ignored and a mislabeled
  UTF-8 document is not re-decoded. With a label, conversion follows the WHATWG label map; the
  content-type path is BOM → content-type `charset` → meta prescan in the first 1024 bytes →
  "looks like UTF-8" heuristic → default `windows-1252`, and an unknown label in the content type
  is not an error there: it falls through to the next step.
- `internal/reader/xml/decoder.go`: when the prolog declares UTF-8, invalid XML characters are
  filtered in place rather than converted; unknown entities come from the HTML entity table,
  `Strict = false` accepts junk before the prolog, and illegal characters are dropped.
- `hasUTF8XMLDeclaration` scans the whole document (not just the prolog) for the first `encoding=`
  and compares the quoted value with `utf-8` case-insensitively, so the valid alias `utf8` does
  not count as a UTF-8 declaration — the document then takes the `CharsetReader` path, where its
  valid UTF-8 bytes still win and nothing is converted.

### Tolerant tokenizer (`encoding/xml`, as the reference configures it)

Verified against `encoding/xml`, which is the decoder Miniflux uses, traced from the module-cache
copy `golang.org/x/net@v0.52.0/webdav/internal/xml` — an internal copy of the package — with the
configuration `decoder.go` builds: `Strict = false` and `Entity = xml.HTMLEntity`. The rules below
were then confirmed by running the reference, which is what the decision table after this section
rests on.

- An attribute name with no `=` after it becomes its own value. An unquoted value is read over the
  characters `attrval` lists — letters, digits, `_`, `:`, `-` — which is not the class `readName`
  reads a name over, because `isNameByte` also has `.`, and the character that stops the value is
  put back, so `href=a.b` gives `a` and the dot is left for the next attribute position.
- A mismatched end tag closes the element that is open, and the name as written is kept for
  after it.
- Unknown, malformed and oversized character references stay as written; the five references XML
  requires are resolved before the HTML table, which has 252 entries. A numeric reference to a
  surrogate resolves to U+FFFD, because the reference writes `string(rune(n))` for every value up to
  the largest rune, and U+FFFD is inside the `Char` production, so the text keeps it.
- `space()` skips only space, tab, line feed and carriage return, so a vertical tab is not tag
  whitespace. It is not an XML `Char` either, so it is removed with the other illegal characters
  before the document is read.
- `readName` does not clear the buffer, which is what lets a character reference keep the `&` it
  started with; `name()` and `attrval()` clear it before reading. A name that reads but is not one
  (`1tag`, `.b`) fails `isName`, because a name cannot start with a digit or a dot.
- `text` puts back the `<` that ends it, reports an unescaped `<` inside a quoted value and an
  unescaped `]]>` outside a CDATA section, rewrites unescaped `CR` and `CRLF` as `LF`, and
  checks the characters it returns against XML's `Char` production, which a numeric character
  reference can still reach because the document is filtered before decoding.
- `text` reports nothing in the reference only when it never wrote a byte at all: `Bytes()` on a
  buffer that was emptied is an empty but non-nil slice, so the three `data == nil` checks in
  `rawToken` are reached only when an error is already recorded. Every path that calls `text` has
  written a byte by the time it can return — the first byte of text, the name read before an
  attribute value, and the two `]` of a CDATA terminator, which are written before the `]]>` check —
  so no input reaches the two states separately, and the ported empty string matches the reference
  for every input, including `<![CDATA[]]>`, which is empty text.
- A comment inside a directive is written as a single space, so that the markup parts it
  separated do not become new markup when the directive is written back out; a partial match of
  `!--` keeps the characters it matched, and the character that stopped it is handled again, so a
  `>` in it still counts against the nesting. The content of a comment is the buffer without the
  `-->` that ends it.
- The end of the document is recorded as the failure as soon as `getc` reaches it, and nothing
  is read after a failure; putting a byte back after one changes nothing, which is what `ungetc`
  gets from `getc` rather than from checking the failure itself. A primitive that can still return
  what it has read at the end — `text` outside a CDATA section — does so, and the failure is
  reported on the next read, which is what `mustgetc` does not. In a CDATA section the end is
  reported at once.
- `Decode` stops at the end of the root element, so markup after the root is not read, and the
  `AutoClose` list is never set by the reference, so it does not invent end tags.
- Format detection (`parser/format.go`): JSON is decided by the first character that is not
  whitespace before any XML token is read, with Go's `unicode.IsSpace` class, which counts
  U+0085 and U+00A0 as whitespace; at most 50 tokens are considered; roots are matched on the
  local name alone,
  which is why `rdf:RDF` is `RDF`; a failure ends the scan without an answer, so the answer is
  `unknown`; an Atom root with no `version` attribute reports `1.0`.

### Tolerance decision table (the quirks the plan names)

The rows are the rules the plan's test-plan item names — the byte-order mark, garbage before the
prolog, character references, `<![CDATA[` — with the two configuration choices that decide them.
They were confirmed by running the reference: Miniflux v2.3.3 at commit `c4d54f87`, Go 1.26.0, read
through `NewXMLDecoder` and `Token()` — the reader path, not `Decode` — with `Strict = false` and
`Entity = xml.HTMLEntity`, over 52 inputs, comparing the token stream and how the stream ends. The
run found no divergence from the port, so the table records what the reference reports rather than a
difference. 30 of those inputs are committed as the fixture
`Tests/RivuletCoreTests/Fixtures/xml/tolerance_corpus.txt`, which the suite
`Tests/RivuletCoreTests/XMLToleranceTests.swift` reads; a case is left out when a wrong
implementation of the rule it names writes the same stream, so the pinned set is smaller than the
read set. The method is in `docs/testing.md`. The pin compares the stream as `Token()` reports it,
which carries no label for the production a run came from: the CDATA flag is this port's model, and
it is pinned in `XMLTreeTests`.

| Case | What the reference reports on this path | Pinned by the corpus case that says |
| --- | --- | --- |
| A byte-order mark at the start of the document | a run of text before the first element: the `Token()` path has no mark rule, so nothing strips it | the mark is character data before the first element, because this path has no mark rule |
| A mark after the prolog | its own run; the instruction is a token of its own, so the mark is not part of the prolog | the mark is not part of the prolog |
| A mark inside text | kept, as part of the run | a mark inside text is kept as part of the run |
| A mark together with garbage before the prolog | one run: nothing before the prolog is markup, so the mark is not a boundary | the mark and the garbage are one run |
| A mark with a declared label while the bytes are valid UTF-8 | not decoded through the label, because `CharsetReader` returns valid UTF-8 bytes unchanged, so the mark stays the mark, not the three characters windows-1252 gives for them | valid UTF-8 bytes are not decoded through the label |
| A document that is only the mark | one run of text | a document that is only the mark is one run of text |
| Garbage before the prolog | text at the document level: `Strict = false` does not make it a failure | junk before the prolog is text at the document level, not a failure |
| Markup before the prolog | tokens, so a text run stops at it; the text between markup is a run of its own | text stops at markup |
| Leading whitespace before the prolog | a run of text, not tag whitespace, because it is not between parts of a tag | leading whitespace is a run of text |
| The entity table | the 252-entry map `encoding/xml` carries, resolved after the five references XML requires: `copy` is in it, `NewLine` and `colon` are not, so those two stay as written | `NewLine` is not in the table encoding/xml carries, so it stays as written |
| A numeric reference at the boundary | `&#x10FFFF;` — the largest character the reference can write — resolves, while `&#1114112;` past it stays as written | the largest character the reference can write resolves, so U+10FFFF is text |
| A resolved character outside the `Char` production | the failure for an illegal character code, which the pins compare as the case the message names, not the wording | a resolved character outside Char is the failure for an illegal character code |
| `<![CDATA[` | the characters are read as written, so references inside are not decoded | references inside a CDATA section are not decoded |
| Where a CDATA run ends | `]]>` ends it and what follows is another run, because the marker that started the first is not part of the second | the terminator ends the run and what follows is a run of its own |
| A CDATA section at the document level | content, so it appears in the stream, which a pin through the tree cannot see because the reader keeps only what is inside an element | a CDATA section at the document level is content |
| Text before a CDATA marker | the marker ends the run, so the two are runs of their own | text before a CDATA marker and the section it opens are two runs |
| `AutoClose` | never set by the reference, so an open element is closed by the next end tag, not by the next token | AutoClose is never set, so an open element is closed by the next end tag |
| A stream that ends in a failure | a message naming the failure, which the port models as one case, so the pins compare the case and cannot pin the wording, nor tell a clean end of the stream from an end reached inside an element | the mark is text, and the end tag after it has no element open |

The typed error on the parser path (`parser/parser.go`)

The reference has one error on this path: the sentinel `ErrFeedFormatNotDetected`
(`internal/reader/parser/parser.go:17`), reported for any document `DetectFeedFormat` answers
`unknown` for. `ParseFeed` routes the four formats it can decide on to their adapters and
reports the sentinel for the rest, and the port models the failure as one case,
`ParserError.feedFormatNotDetected`. The version `DetectFeedFormat` answers is read only by
the Atom branch: `atom.Parse` calls the parser for Atom 0.3 when the version says `0.3` and
the one for Atom 1.0 for anything else.

| Case | What the reference reports on this path | Pinned by the corpus case that says |
| --- | --- | --- |
| A JSON document whose content is followed by a real element | `json`, decided before any XML token is read | the JSON rule answers before any token is read, so a real element after the JSON content is not switched on |
| A JSON document whose content is a field named `feed` | `json`, because the switch on the name reads roots and never a field | a JSON document whose content is a field named feed is answered JSON |
| Whitespace before the JSON root, longer than the 32-byte buffer | `json`: the first character that is not whitespace decides, and the rule reads past the buffer | the character that decides the JSON rule is the first one that is not whitespace |
| A document that is only whitespace | `unknown`, so the sentinel | a document that is only whitespace is answered unknown and reported as the typed error |
| The token read as the 50th, and the token read as the 51st | the 50th is switched on, so `rss`; the 51st is not, because the cap is checked before the switch on the name | the pair whose roots sit on the two sides of the boundary |
| An Atom root with the `version` attribute written with a prefix | `0.3`, because the attribute read is the one whose name is `version` whatever prefix it is written with | the attribute the reference reads is the one whose name is version |
| A scan that fails before a root is read | `unknown`, with the failure for an angle bracket inside an attribute value | a scan that fails before a root is read ends it without an answer |
| A document with no root the switch reads, or text only | `unknown`, so the sentinel | the scan ends with the answer unknown for a document with no root the switch reads |

The corpus the rows rest on is
`Tests/RivuletCoreTests/Fixtures/parser/parser_error_corpus.txt`, read by
`Tests/RivuletCoreTests/ParserErrorTests.swift`; the method is in `docs/testing.md`. What it
cannot pin, and says so on its own lines: the size of the buffer the JSON rule reads, because
a larger buffer writes the same decision for every case; the characters above ASCII that Go's
whitespace class counts, U+0085 and U+00A0, because no case here has one; the wording of the
sentinel, because the port keeps one case for each failure; and which adapter is called, since
the outcome names the branch the switch takes. The number the cap counts is pinned only by the
pair whose roots sit on the two sides of the boundary — a cap read as 49 fails the case read
as the 50th token and a cap read as 60 the case read as the 51st — and a case for a root read
far past the cap is left out because a wrong number writes the same answer for it. Nine of the
ten end states map to one case, so those pins fail only on the case the mapping can tell
apart.

## Test fixtures in the reference


- `internal/reader/encoding/testdata` — 11 files; `internal/reader/parser/testdata` — 8 files;
  `internal/reader/xml/testdata` — 3 files; sanitizer testdata — 2 files
  (plus most cases live inline in Go tests).
