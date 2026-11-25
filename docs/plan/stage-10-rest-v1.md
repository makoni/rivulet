# Stage 10 — Miniflux REST v1 subset

**Goal:** the endpoints the one real consumer declares, and no others. **Status:** in progress.
**Depends on:** stage 5, and the integrations item of stage 9 for the one call that runs an integration.

The consumer is Capy Reader's `minifluxclient`, read at the commit its tag names. Its half records 25
calls: 21 are in scope here, three wait for the read they call, and the per-category mark-all-as-read
stays in stage 9. The walk on the phone reached the first of them and got the answer this port gave for
a path it registered no route for at the time of the walk.

## Open work

- Issue 110 — the endpoints the consumer declares, pinned as pure logic and over a real socket.
- Issue 121 — the three calls that reach no route here until the read they call is pinned:
  `GET /v1/categories/{id}/entries`, `GET /v1/icons/{iconID}`, and the counts half of
  `GET /v1/categories?counts=true`. `POST /v1/entries/{id}/save` runs an integration, so it waits for
  issue 107.
- The calls the client matrix has no row for stay open as the phone half the stage-7 file keeps open.

## The endpoints

- `GET /v1/me`
- `GET /v1/categories`, `GET /v1/categories/{id}`, `POST /v1/categories`, `PUT /v1/categories/{id}`,
  `DELETE /v1/categories/{id}`, `GET /v1/categories/{id}/feeds`
- `GET /v1/feeds`, `GET /v1/feeds/{id}`, `POST /v1/feeds`, `PUT /v1/feeds/{id}`,
  `DELETE /v1/feeds/{id}`, `GET /v1/feeds/{id}/icon`, `PUT /v1/feeds/{id}/refresh`,
  `PUT /v1/feeds/{id}/mark-all-as-read`
- `GET /v1/entries`, `GET /v1/feeds/{id}/entries`, `GET /v1/entries/{id}`, `PUT /v1/entries`,
  `PUT /v1/entries/{id}/bookmark`
- `GET /v1/integrations/status`

The rest of the v1 surface — users CRUD, `POST /v1/discover`, export and import, `GET /v1/entries/ids`,
`PUT /v1/entries/{id}`, enclosures, flush-history, `GET /v1/version`, the api-key management endpoints,
`PUT /v1/feeds/refresh` for all feeds, the per-user and per-category mark-all-as-read, and the OPTIONS
half of the CORS middleware — stays in stage 9.

## The auth half

`X-Auth-Token` is read before a request reaches a route, as the reference's middleware reads it: an
empty header value is not read against the storage layer at all and falls through to basic auth; a value
is read against the `api_keys` table by the token, and no row answers the JSON 401. The reference puts a
key there through its web form; this port has no web UI, so the key is put there by the port's own
`create-api-key` command, recorded as a divergence. The token value is the 32-byte hex string the
reference's generator answers; the port's own generator is named there as the port's choice.

Basic auth runs after the key half: `WWW-Authenticate` is written, no header answers the JSON 401, an
empty name or an empty password answers it before the storage layer is read, the password is compared
with the stored bcrypt hash, and the row is read after the compare. The constant-time form of the
compare and the single-row limit of the read are named as unpinnable.

The error shape this path answers with is `{"error_message": ...}`, the reference's error document and
the shape the Google Reader path already pins. What a run here showed for a path with no pattern
registered is the router's own shape, `{"error":true,"reason":"Not Found"}`; the body the walk on the
phone recorded, `{"error": {"message": "resource not found"}}`, is read by no rule here as data, so the
stage names the shape the run showed and `docs/parity.md` records the two sides.

## What the runs showed

The `api_keys` table, its two reads, the `create-api-key` command, the two halves of the auth read, the
answer as pure logic, the document shape, the route registration and the answer over a socket are closed
as what their runs showed. The record lives in `docs/testing.md` under the stage-10 section.
