# Stage 10 — Miniflux REST v1 subset

Scheduled from the stage-9 item the plan's non-goals named as a subset appearing later on demand, the
REST v1 subset and API keys (`X-Auth-Token`), which stage 9 names as worked here. The consumer
appeared: Capy Reader's `minifluxclient`, read at the commit PR #85 records for that client, declares
24 endpoints, and the walk on the phone reached the first of them
(`GET /v1/me`) and got the 404 this port answered for a path it registered no route for at the time
of the walk; the route is registered by the third slice, merged as PR #88.

**Status:** in progress. The first slice — the `api_keys` table, its two reads, the `create-api-key`
command, and the two halves of the auth read — is merged as PR #86, pinned as 23 pins and 42 probes
over six suites. The second slice, the answer the read gives as pure logic together with the
document shape, is merged as PR #87, pinned as 6 pins and 19 probes over two suites: 5 pins and 15
probes pin the answer as pure logic and 1 pin and 4 probes pin the document shape. Eighteen probes
fire on the rule they name and one is recorded as not biting, the patch that changed the
`WWW-Authenticate` realm, which no pin here reads as a value. Seventeen probes reach the pin they
name alone and one reaches two pins. The third slice is merged as PR #88: the route registration and
the pins that read an answer over a socket, 8 pins and 13 probes in `RestV1RouteTests`, and the
stage-7 pin for this prefix rewritten to read the route the port registers, which is 9 pins and 12
probes in `ClientSequenceReplayTests`, the twelfth being the patch that moves a call on the half read
through the tolerance table to the other side. Every probe fires on the rule it names. The patch for the
path the pattern registers reaches every pin in the route suite except the one for the method,
because that pin reads an answer the router gives either way, and it reaches the pin for this
prefix; the patch that changed the realm value, which PR #87 recorded as not biting, fires on the
route suite alone.

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
shape of its own. What a run here showed for a path with no pattern registered is Vapor's own
shape, read over the socket as `{"error":true,"reason":"Not Found"}` with `application/json;
charset=utf-8`, the router's answer rather than the reference's error document; the body the walk
on the phone recorded, `{"error": {"message": "resource not found"}}`, is read by no rule here as
data, so the stage names the shape the run showed, and `docs/parity.md` records the two sides.

## Test plan

- Pure logic: the token read (the empty value, the header name, the compare), the route parameter
  read as the reference reads it (`RouteInt64Param` answers 0 for a value it cannot read), the JSON
  body read, the validators for a category title and for a description, the entry query builder
  with the params Capy names (`status`, `offset`, `limit`, `order`, `direction`, `before`, `after`,
  `before_entry_id`, `after_entry_id`, `starred`, `search`, `category_id`, `changed_after`), and
  the document shapes with the key sets the models write.
- Integration, over a real socket, the two halves of the auth read, the route registration with the
  most specific pattern winning, the status each answer writes for the guards, and each endpoint's
  answer read against the row the storage layer answered. The socket half is pinned by the third
  slice, which is the slice that registers the route: the answer the read gives for the path the
  pattern registers, the row the read hands the handler, the status the guard answers over the
  socket, the names the answer carries, the document as bytes, and the method the pattern
  registers.

## Slices

In the first slice, sixteen of its 42 probes reach more than one pin, which the headers name: the
patch that answers something for a name the request does not carry reaches six, the guard for an
empty token value and the character-class patch reach five each, the column patch for the key read
and the patch that wrote before the rules reach four each, and eleven reach the pin they name plus
one other. What the headers name as unpinnable is the same list `AGENTS.md`'s stage-10 paragraph
carries, and the two rules named as not falsifiable are the join as a join and the length guard.

The second slice, merged as PR #87, pins the answer as pure logic and the document shape: the
status each rule of the read answers with, the document the shared builder writes, the rule that
decides whether `WWW-Authenticate` is written, the three CORS names, the three names the builder
writes with its content type, and the three fields the schema has columns for. Fifteen of its 19
probes reach the answer suite and four the shape suite; eighteen fire, seventeen reach the pin they
name alone, one reaches two pins (the patch that classified the storage rules as the guard shape,
which fires on the status pin and on the document pin), and one fires nothing: the patch that
changed the realm, because the suite reads the rule that decides whether the name is written and
not the value it carries. The three CORS names are each shown by a patch that dropped that one name
and fired on its own assertion, and the content type is shown by a patch that wrote the framework's
charset. What those headers name as not pinnable is the value of that name, which the socket pin of
the third suite reads as the whole value, so the patch that changed the realm fires there, the
reference's wording for a storage failure the suite cannot trigger, the `Vary` name above the
compression threshold, the 28 fields the schema has no column for, and the 404 the handler answers
for a row its own read does not find. The route registration, the row the read hands the handler,
the pattern keeping the method it names, and the answer the router gives for a path no pattern
registers are pinned by the third slice, which is the slice that registers the route and the one
that can read this path as data: the client check half now reads the third route file as data, as
the prefix the half names is the one the port registers one route on, and the pin for this half
reads the two answers the port gives: the read's answer for the path the pattern registers and the
router's answer for a path on the same prefix with no pattern.

The third slice pins the route over a real socket: the path the pattern registers, the row the read
hands the handler, the status the guard answers, the names the answer carries, the document as
bytes, and the method the pattern registers. Every one of its 13 probes fires on the pin it names.
The patch for the path the pattern registers fires on 10 assertions across the 8 pins, because
every pin here reads an answer that reaches the router once the registration is renamed, except
the pin for the method, which reads an answer the router gives either way; it fires on the pin for
this prefix in `ClientSequenceReplayTests` as well, 11 assertions in all. The round ran the four
suites together, so the patches for the guard status, the two halves of the name rule, the three
CORS names, the name the OPTIONS branch writes, the content type and the key order fire on the
pure pins that read the same rules as well. The patch that changed the realm value, which PR #87
recorded as not biting, fires on the route suite alone, and the patch for the method fires on the
pin for the method alone.

## Exit criteria

- Every rule this stage names is pinned, and every pin is seen to fail on the rule it names.
- The parity run answers the v1 requests for the calls in scope, and every difference is a row.
- A client run against this port on the phone for a Miniflux account leaves a record the check half
  reads as data, and the matrix rows for those calls name the answer the port gives.
- The v1 half of the manual matrix criterion of `docs/plan/stage-7-acceptance.md` closes only for
  the calls this stage registers; the calls the subset does not register stay named as reaching no
  route.
- CI green, `bash -n` green for the run halves, the probe rounds green, no warning on a clean build.
