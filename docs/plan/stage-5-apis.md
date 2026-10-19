# Stage 5 — Client APIs & OPML

**Goal:** existing native clients connect and sync; the contract mirrors the reference exactly.
**Status:** not started. **Effort:** XL. **Depends on:** Stage 4.

## Scope

- [ ] Promote `create-admin` from stub to working — the acceptance journey and real clients need it.
- [ ] Integration credentials command: `rivulet integration-credentials` sets per-user Google
      Reader username/password (stored bcrypt) and Fever username/password (stored as the MD5
      token); prints the derived Fever `api_key`.
- [ ] Google Reader API — port the reference router exactly (see `docs/reference-notes.md`):
      `ClientLogin`; `token`; `edit-tag`; `rename-tag`; `disable-tag`; `tag/list`; `user-info`;
      `subscription/list` (embeds `iconUrl`); `subscription/edit`
      (`ac=subscribe|edit|unsubscribe`); `subscription/quickadd` (includes minimal feed discovery
      on website URLs — scan the HTML head for `<link rel="alternate">`); `stream/items/ids`;
      `stream/items/contents`; `mark-all-as-read`; catch-all `/reader/api/0/*` → `[]` + HTTP 200
      (parity: `unread-count`, `preference/stream/set` etc. stay unimplemented).
- [ ] Google Reader auth: `ClientLogin` exchange for the stateless HMAC token; token carried via
      the `T` form parameter or `Authorization: GoogleLogin auth=…`; failure semantics exactly as
      the reference (401, `text/plain`, `Unauthorized`, `X-Reader-Google-Bad-Token: true`).
- [ ] Contract details pinned by golden tests: `n` clamped to 1000 (0 → 1000); `continuation` is a
      numeric offset encoded as a JSON string, omitted when 0; `edit-tag` reads tags from the body;
      item ids accepted in 4 formats; `output=json` on the affected endpoints; unknown streams →
      500.
- [ ] Fever API — exact parameter set: `groups`, `feeds`, `favicons`, `unread_item_ids`,
      `saved_item_ids`, `items`, `mark=item|feed|group` with reference semantics (limit 50;
      `since_id` > `max_id` > `with_ids` precedence; `as=saved|unsaved`; `id<=0` → empty 200;
      `mark=feed`/`mark=group` are read-before-timestamp only). Auth: `api_key` (MD5 token);
      failure is HTTP 200 with `{"api_version": 3, "auth": 0}`. No `keys`, no `hot`.
- [ ] Public icon route: `GET /feed-icon/<external_id>` — unauthenticated, `ETag`, 72h
      `Cache-Control`; Fever `favicons` returns `mime;base64,…`.
- [ ] OPML: import (nested categories) and export; shared by the CLI and used in tests.
- [ ] Deviations are recorded in `docs/parity.md` as soon as they are observed.

## Implementation notes

- The reference code is the contract (`internal/googlereader`, `internal/fever`); upstream has
  almost no Fever tests, so our contract tests are written from the handler directly.
- No web UI: credentials are managed via the CLI; authentication never issues browser sessions.

## Tests

### Unit

- Token derivation; Google Reader response encoders (XML/JSON); OPML round-trip; pagination math.

### Integration (the acceptance backbone, real sockets via XCTVapor `.running`)

- Full journey: `create-admin` + integration credentials via CLI → OPML import adds feeds →
  refresh fetches entries (stub server) → Google Reader: `ClientLogin` → `subscription/list` →
  `stream/items/ids` with `xt=…read` (unread counts) → `stream/items/contents` → `edit-tag` read →
  counts changed; Fever: `groups` → `feeds` → `items` → `mark=item` read/saved →
  `unread_item_ids`/`saved_item_ids` changed.
- Contract matrix: every route listed above (including the `[]`/200 catch-all) and every Fever
  parameter; golden response shapes.
- Auth failures per API: Google Reader 401 + bad-token header; ClientLogin JSON error; Fever
  200/`auth: 0`.
- Pagination and ids: >1000 items with continuations; `n` edge cases; the 4 item-id formats.
- `quickadd`: website URL (discovery) and direct feed URL.
- Icon route: works without auth; `ETag` and cache headers set.

## Exit criteria

- [ ] The automated journey is green in CI.
- [ ] One real client (NetNewsWire) connects, adds a feed and syncs against a locally running
      instance (manual check; repeated with the full client matrix in stage 7).
