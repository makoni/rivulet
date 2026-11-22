# Stage 10 — Miniflux REST v1 subset

Scheduled from the stage-9 item "REST v1 subset and API keys (`X-Auth-Token`) — only if a real
consumer appears". The consumer appeared: Capy Reader's `minifluxclient`, read at the commit PR #85
records for that client, declares 24 endpoints, and the walk on the phone reached the first of them
(`GET /v1/me`) and got the 404 this port answers for a path it registers no route for.

**Status:** in progress. The first slice — the `api_keys` table, its two reads, the `create-api-key`
command, and the two halves of the auth read — is merged as PR #86, pinned as 23 pins and 42 probes
over six suites. The route half, the response shapes, the entry read, and the check half gaining the
third path are the slices that follow.

## Scope

The endpoints that client declares, and no others:

- `GET /v1/me`
- `GET /v1/categories`, `GET /v1/categories/{id}`, `POST /v1/categories`,
  `PUT /v1/categories/{id}`, `DELETE /v1/categories/{id}`, `GET /v1/categories/{id}/feeds`
- `GET /v1/feeds`, `GET /v1/feeds/{id}`, `POST /v1/feeds`, `PUT /v1/feeds/{id}`,
  `DELETE /v1/feeds/{id}`, `GET /v1/feeds/{id}/icon`, `PUT /v1/feeds/{id}/refresh`,
  `PUT /v1/feeds/{id}/mark-all-as-read`
- `GET /v1/entries`, `GET /v1/feeds/{id}/entries`, `GET /v1/entries/{id}`, `PUT /v1/entries`,
  `PUT /v1/entries/{id}/bookmark`
- `GET /v1/integrations/status`

Two of its calls stay out because this port has no piece for what they read:
`POST /v1/entries/{id}/save` runs an integration, and integrations are their own stage-9 item.
`GET /v1/categories/{id}/entries`, `GET /v1/icons/{iconID}` and the counts half of
`GET /v1/categories?counts=true` are inside the read half, so they are in scope only once the read
they call is pinned; until then the matrix names them as calls that reach no route here. The rest of
the v1 surface — users CRUD, `POST /v1/discover`, export and import, `GET /v1/entries/ids`,
`PUT /v1/entries/{id}`, enclosures, flush-history, `GET /v1/version`, the api-key management
endpoints, `PUT /v1/feeds/refresh` for all feeds, the per-user and per-category mark-all-as-read,
and the OPTIONS half of the CORS middleware — stays in stage 9.

## The auth half

`X-Auth-Token` is read before a request reaches a route, as the reference's middleware reads it: an
empty header value is not read against the storage layer at all and falls through to basic auth; a
value is read against the `api_keys` table by the token, and no row answers the JSON 401. The table
is new here, and the schema is edited in place until the first release. The reference puts a key
there through its web form; this port has no web UI, so the key is put there by the port's own
`create-api-key` command, recorded as a divergence the way `import` is. The token value is the
32-byte hex string `crypto.GenerateRandomStringHex` answers upstream; the port's own generator is
named there as the port's choice.

Basic auth runs after the key half: `WWW-Authenticate` is written, no header answers the JSON 401,
an empty name or an empty password answers it before the storage layer is read, the password is
compared with the stored bcrypt hash, and the row is read after the compare, as upstream reads them.
The constant-time form of the compare and the single-row limit of the read are named as unpinnable,
as the stage-5 auth header names them.

The error shape this path answers with is `{"error_message": ...}`, which is the reference's
`generateJSONError` and the shape the Google Reader path already pins: `JSONUnauthorized` and
`JSONNotFound` build it through the same builder, so this path reads that builder rather than a
shape of its own. The body the Capy walk saw, `{"error": {"message": "resource not found"}}`, is
Vapor's own shape for a path this port registers no route for, not the shape the reference answers
for an error a handler names, so it belongs to the route-mismatch row of `docs/parity.md` and is not
a shape this stage pins.

## Test plan

- Pure logic: the token read (the empty value, the header name, the compare), the route parameter
  read as the reference reads it (`RouteInt64Param` answers 0 for a value it cannot read), the JSON
  body read, the validators for a category title and for a description, the entry query builder with
  the params Capy names (`status`, `offset`, `limit`, `order`, `direction`, `before`, `after`,
  `before_entry_id`, `after_entry_id`, `starred`, `search`, `category_id`, `changed_after`), and the
  document shapes with the key sets the models write.
- Integration, over a real socket: the two halves of the auth read, the route registration with the
  most specific pattern winning, the status each answer writes for the guards, and each endpoint's
  answer read against the row the storage layer answered.
- The parity harness gains the v1 requests for the calls in scope, and the tolerance table gains a
  row for every document field the port's schema has no column for — the user fields upstream
  carries (theme, language, timezone, entry_direction, entries_per_page, keyboard_shortcuts,
  show_reading_time, last_login_at), the api-key fields, and the entry fields built from the clock.
  Each is a row before it is a finding, so the comparator reports nothing for it.
- The client matrix gains the calls the set records on the third path: Capy Reader's set keeps the
  Google Reader half as the half its calls are read on, and the Miniflux half gains the calls a run
  on the phone writes with the account configured as a Miniflux source, which is a run half on the
  machine, not a rule.

## Slices

Sixteen probes reach more than one pin, which the headers name: the patch that answers something for
a name the request does not carry reaches six, the guard for an empty token value and the
character-class patch reach five each, the column patch for the key read and the patch that wrote
before the rules reach four each, and eleven reach the pin they name plus one other. What the
headers name as unpinnable is the same list `AGENTS.md`'s stage-10 paragraph carries, and the two
rules named as not falsifiable are the join as a join and the length guard.

## Exit criteria

- Every rule this stage names is pinned, and every pin is seen to fail on the rule it names.
- The parity run answers the v1 requests for the calls in scope, and every difference is a row.
- A client run against this port on the phone for a Miniflux account leaves a record the check half
  reads as data, and the matrix rows for those calls name the answer the port gives.
- The v1 half of the manual matrix criterion of `docs/plan/stage-7-acceptance.md` closes only for
  the calls this stage registers; the calls the subset does not register stay named as reaching no
  route.
- CI green, `bash -n` green for the run halves, the probe rounds green, no warning on a clean build.
