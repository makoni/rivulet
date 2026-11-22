# Stage 10 — Miniflux REST v1 subset

Scheduled from the stage-9 item "REST v1 subset and API keys (`X-Auth-Token`) — only if a real
consumer appears". The consumer appeared: Capy Reader's `minifluxclient`, read at the commit PR #85
records for that client, declares 24 endpoints, and the walk on the phone reached the first of them
(`GET /v1/me`) and got the 404 this port answers for a path it registers no route for.

**Status:** in progress. The first slice — the `api_keys` table, its two reads, the `create-api-key`
command, and the two halves of the auth read — is merged as PR #86, pinned as 23 pins and 42 probes
over six suites. The second slice is worked as its own pull request and is the answer the read
gives, pinned as pure logic, together with the document shape: the status each rule answers with,
the document the shared builder writes with the reference's wording for a guard and the rule name
for a failure the port names, the `WWW-Authenticate` name written for every request that reaches the
reference's basic half and not for one the key half answered, the three CORS names written before
the read runs, the three names the builder writes with its content type, and the three-field account
document — 6 pins and 19 probes over two suites: 5 pins and 15 probes pin the answer as pure logic
and 1 pin and 4 probes pin the document shape. Eighteen probes fire on the rule they name and one is
recorded as not biting, the patch that changed the `WWW-Authenticate` realm, which no pin here reads
as a value. Seventeen probes reach the pin they name alone and one reaches two pins. The route
registration and the pins that read an answer over a socket are the slice that also gives the client
check half the third path, so the stage-7 pin that reads this prefix as answering nothing here stays
as it is.

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
shape of its own. What a run here showed for a path this port registers no route for is Vapor's own
shape, read over the socket as `{"error":true,"reason":"Not Found"}` with `application/json;
charset=utf-8`, the router's answer rather than the reference's error document; the body the walk on
the phone recorded, `{"error": {"message": "resource not found"}}`, is read by no rule here as data,
so the stage names the shape the run showed, and `docs/parity.md` records the two sides.

## Test plan

- Pure logic: the token read (the empty value, the header name, the compare), the route parameter
  read as the reference reads it (`RouteInt64Param` answers 0 for a value it cannot read), the JSON
  body read, the validators for a category title and for a description, the entry query builder with
  the params Capy names (`status`, `offset`, `limit`, `order`, `direction`, `before`, `after`,
  `before_entry_id`, `after_entry_id`, `starred`, `search`, `category_id`, `changed_after`), and the
  document shapes with the key sets the models write.
- Integration, over a real socket, the two halves of the auth read, the route registration with the
  most specific pattern winning, the status each answer writes for the guards, and each endpoint's
  answer read against the row the storage layer answered. The socket half is not pinned by this
  slice: no route on this path is registered, so a request reaches the router's answer before any
  read runs, and the stage-7 pin that reads this prefix as answering nothing here is green on this
  head, which the run that showed these pins also showed.

## Slices

In the first slice, sixteen of its 42 probes reach more than one pin, which the headers name: the
patch that answers something for a name the request does not carry reaches six, the guard for an
empty token value and the character-class patch reach five each, the column patch for the key read
and the patch that wrote before the rules reach four each, and eleven reach the pin they name plus
one other. What the headers name as unpinnable is the same list `AGENTS.md`'s stage-10 paragraph
carries, and the two rules named as not falsifiable are the join as a join and the length guard.

The second slice, worked as this pull request, pins the answer as pure logic and the document shape:
the status each rule of the read answers with, the document the shared builder writes, the rule that
decides whether `WWW-Authenticate` is written, the three CORS names, the three names the builder
writes with its content type, and the three fields the schema has columns for. Fifteen of its 19
probes reach the answer suite and four the shape suite; eighteen fire, seventeen reach the pin they
name alone, one reaches two pins (the patch that classified the storage rules as the guard shape,
which fires on the status pin and on the document pin), and one fires nothing: the patch that
changed the realm, because the suite reads the rule that decides whether the name is written and not
the value it carries. The three CORS names are each shown by a patch that dropped that one name and
fired on its own assertion, and the content type is shown by a patch that wrote the framework's
charset. What those headers name as not pinnable is the value of that name, the reference's wording
for a storage failure the suite cannot trigger, the `Vary` name above the compression threshold, the
28 fields the schema has no column for, and the 404 the handler answers for a row its own read does
not find. The route registration, the row the read hands the handler, the pattern keeping the method
it names, and the answer the router gives for a path no pattern registers are pinned by the slice
that registers the route, which is the slice that can read this path as data: the client check half
reads calls only on the two paths it names, so until it gains the third route file the half that
reaches no route stays as the set records it.

## Exit criteria

- Every rule this stage names is pinned, and every pin is seen to fail on the rule it names.
- The parity run answers the v1 requests for the calls in scope, and every difference is a row.
- A client run against this port on the phone for a Miniflux account leaves a record the check half
  reads as data, and the matrix rows for those calls name the answer the port gives.
- The v1 half of the manual matrix criterion of `docs/plan/stage-7-acceptance.md` closes only for
  the calls this stage registers; the calls the subset does not register stay named as reaching no
  route.
- CI green, `bash -n` green for the run halves, the probe rounds green, no warning on a clean build.
