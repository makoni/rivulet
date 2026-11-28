# Stage 10 — Miniflux REST v1 subset

**Goal:** the endpoints the one real consumer declares, and no others. **Status:** in progress — the 20
endpoints in scope are done; four further calls are open (issue 121).
**Depends on:** stage 5, and the integrations item of stage 9 for the one call that runs an integration.

The consumer is Capy Reader's `minifluxclient`, read at the commit its tag names. It declares 25
calls: 20 are in scope here and implemented; four are open (issue 121) — two wait for the read they
call, one runs an integration, one stays in stage 9; and one, `GET /v1/categories/{id}`, is a route
Miniflux 2.3.3 does not register either, so both answer 404 for it.

## Open work

- Issue 121 — the four open calls: `GET /v1/categories/{id}/entries` and
  `GET /v1/icons/{iconID}`, which reach no route until the read they call is pinned;
  `POST /v1/entries/{id}/save`, which runs an integration and so waits for issue 107; and
  `PUT /v1/categories/{id}/mark-all-as-read`, which stays in stage 9. The counts half of
  `GET /v1/categories?counts=true` is a half of an endpoint already in the 20, so it is not a call of
  its own.
- Deleting a category from the app over REST v1 has not been walked yet — issue 130.

## The endpoints

- `GET /v1/me`
- `GET /v1/categories`, `POST /v1/categories`, `PUT /v1/categories/{id}`,
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
registered is the router's own shape, `{"error":true,"reason":"Not Found"}`; the walk on the phone
recorded `{"error": {"message": "resource not found"}}`; `docs/parity.md` records the two sides.

## What the runs showed

The `api_keys` table, its two reads, the `create-api-key` command, the two halves of the auth read, the
answer as pure logic, the document shape, the route registration and the answer over a socket are closed
as what their runs showed. The categories, feeds, entries and integrations halves of issue 110 are
closed the same way; the pins are the `RestV1*Tests` suites. What the
entries round could not show is stated in its suite headers rather than asserted: the order between the
either-field rule and the status rule, which no input can fail both, and the order between the status
write and the starred write, which both write different columns of the same rows.
