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
  `next_check_at < now() AND parsing_error_count < limit AND disabled IS false ORDER BY next_check_at ASC LIMIT BATCH_SIZE`
  (default 100); optional per-host limit (`POLLING_LIMIT_PER_HOST`, default 0 = off).
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
  Los Angeles, `EST`/`EDT` → New York; then ~70 layouts after normalization, with offset clamping.
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

Verified against `encoding/xml` (Go 1.22), which is the decoder Miniflux uses, with the
configuration `decoder.go` builds: `Strict = false` and `Entity = xml.HTMLEntity`.

- An attribute name with no `=` after it becomes its own value. An unquoted value is read over the
  characters `attrval` lists — letters, digits, `_`, `:`, `-` — which is not the class `readName`
  reads a name over, because `isNameByte` also has `.`, and the character that stops the value is
  put back, so `href=a.b` gives `a` and the dot is left for the next attribute position.
- A mismatched end tag closes the element that is open, and the name as written is kept for after it.
- Unknown, malformed and oversized character references stay as written; the five references XML
  requires are resolved before the HTML table, which has 252 entries.
- `space()` skips only space, tab, line feed and carriage return, so a vertical tab is not tag
  whitespace. It is not an XML `Char` either, so it is removed with the other illegal characters
  before the document is read.
- `readName` does not clear the buffer, which is what lets a character reference keep the `&` it
  started with; `name()` and `attrval()` clear it before reading. A name that reads but is not one
  (`1tag`, `.b`) fails `isName`, because a name cannot start with a digit or a dot.
- `text` puts back the `<` that ends it, reports an unescaped `<` inside a quoted value and an
  unescaped `]]>` outside a CDATA section, rewrites unescaped `CR` and `CRLF` as `LF`, and checks the
  characters it returns against XML's `Char` production, which a numeric character reference can
  still reach because the document is filtered before decoding.
- A comment inside a directive is written as a single space, so that the markup parts it separated do
  not become new markup when the directive is written back out; a partial match of `!--` keeps the
  characters it matched, and the `<` counts as nesting.
- `Decode` stops at the end of the root element, so markup after the root is not read, and the
  `AutoClose` list is never set by the reference, so it does not invent end tags.
- Format detection (`parser/format.go`): JSON is decided by the first character that is not
  whitespace before any XML token is read, with Go's `unicode.IsSpace` class, which counts U+0085 and
  U+00A0 as whitespace; at most 50 tokens are considered; roots are matched on the local name alone,
  which is why `rdf:RDF` is `RDF`; a failure ends the scan without an answer, so the answer is
  `unknown`; an Atom root with no `version` attribute reports `1.0`.

## Test fixtures in the reference

- `internal/reader/encoding/testdata` — 11 files; `internal/reader/parser/testdata` — 8 files;
  `internal/reader/xml/testdata` — 3 files; sanitizer testdata — 2 files
  (plus most cases live inline in Go tests).
