# Stage 5 — Client APIs & OPML

**Goal:** existing native clients connect and sync.
**Status:** not started. **Effort:** L. **Depends on:** Stage 4.

## Scope

- [ ] Authentication: HTTP Basic (username/password), API key (`X-Auth-Token`), Google Reader
      `ClientLogin`, Fever `api_key` (ported derivation); consistent 401 semantics.
- [ ] Google Reader API (port `internal/googlereader`): login/token, subscription list, tag list,
      unread counts, stream contents (with continuation pagination), item ids, `edit-tag`
      (read/unread, star/unstar), `subscription/edit` (add/remove feeds — verify which clients
      need it), feed icon, `preference/stream/set`.
- [ ] Fever API (port `internal/fever`): `keys`, `groups`, `feeds`, `items`, unread/saved/hot
      items, mark item/feed/group read/unread/saved; response envelope exactly as Miniflux.
- [ ] OPML: import (nested categories) and export; shared by the CLI and used in tests.
- [ ] Deviations observed during implementation are recorded in `docs/parity.md`.

## Implementation notes

- The reference implementations are the contract: match payload shapes, status codes and
  edge-case behavior (`internal/googlereader/*_test.go` and `internal/fever/*_test.go` serve as
  specs).
- No web UI: authentication never issues browser sessions; only the client-oriented schemes above.

## Tests

### Unit

- Fever auth derivation; Google Reader response encoders (XML/JSON); OPML round-trip; pagination
  cursor math.

### Integration (the acceptance backbone)

- Full journey over real HTTP (XCTVapor app + stub feed server + temp database):
  CLI creates a user → OPML import adds feeds → refresh fetches entries → Google Reader: token →
  subscriptions → stream contents → `edit-tag` read → unread counts reflect it; Fever: feeds →
  items → mark read → counts change.
- Golden response contracts for the main endpoints (shapes stay stable as the code evolves).
- Auth matrix: every scheme succeeds with valid credentials and returns 401 with invalid ones.
- Pagination: >100 entries with continuations returns everything exactly once.

## Exit criteria

- [ ] The automated journey is green in CI.
- [ ] One real client (NetNewsWire) connects and syncs against a locally running instance
      (manual check; repeated with the full client matrix in stage 7).
