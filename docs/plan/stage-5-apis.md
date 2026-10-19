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
      on website URLs — scan the HTML head for `<link rel="alternate">`; known deviation: the
      reference finder also probes well-known paths and site-specific handlers — record it in
      `docs/parity.md`); `stream/items/ids`; `stream/items/contents`; `mark-all-as-read`;
      catch-all `/reader/api/0/*` → `[]` + HTTP 200 (parity: `unread-count`,
      `preference/stream/set` etc. stay unimplemented).
- [ ] Google Reader auth: `ClientLogin` exchange for the stateless HMAC token. Token transport is
      method-specific exactly like the reference: **POST routes read the `T` form field; GET routes
      read `Authorization: GoogleLogin auth=…`**. Response shapes are client-visible: `ClientLogin`
      returns plain text `SID=…/LSID=…/Auth=…` by default (JSON only with `output=json`), the token
      endpoint returns bare text, write operations return plain text `OK`. Failure semantics: 401,
      `text/plain`, `Unauthorized`, `X-Reader-Google-Bad-Token: true`.
- [ ] Contract details pinned by golden tests: `n` clamped to 1000 (0 → 1000); `continuation` is a
      numeric offset encoded as a JSON string, omitted when 0; `edit-tag` reads tags from the body;
      item ids accepted in 4 formats; `output=json` on the affected endpoints; unknown streams →
      500; text-vs-JSON response shapes and the token-transport split above.
- [ ] Fever API — exact parameter set: `groups`, `feeds`, `favicons`, `unread_item_ids`,
      `saved_item_ids`, `items`, `mark=item|feed|group` with reference semantics (limit 50;
      `since_id` > `max_id` > `with_ids` precedence; `as=saved|unsaved`; invalid id → 0; `mark=feed`
      with `id<=0` → empty 200; `mark=group` with `id<0` → empty 200, **`id=0` → mark all items
      read (user-wide, ignores `before`)**, `id>0` → category read before `before`). Every response
      carries `last_refreshed_on_time` (0 on auth failure) and `items` carries `total_items`.
      Auth: `api_key` (MD5 token); failure is HTTP 200 with
      `{"api_version": 3, "auth": 0, "last_refreshed_on_time": 0}`. No `keys`, no `hot`.
- [ ] Public icon route: `GET /feed-icon/<external_id>` — unauthenticated, `ETag`, 72h
      `Cache-Control`; Fever `favicons` returns `mime;base64,…`.
- [ ] OPML: import (nested categories) and export; shared by the CLI and used in tests.
- [ ] Deviations are recorded in `docs/parity.md` as soon as they are observed.

## Implementation notes

- The reference code is the contract (`internal/googlereader`, `internal/fever`); upstream has
  almost no Fever tests, so our contract tests are written from the handler directly.
- Response shapes must match the reference where clients depend on them: plain text where the
  reference sends plain text (ClientLogin lines, `OK`, token), JSON otherwise.
- No web UI: credentials are managed via the CLI; authentication never issues browser sessions.

## Tests

### Unit

- Token derivation; Google Reader response encoders (JSON + plain text); OPML round-trip;
  pagination math.

### Integration (the acceptance backbone, real sockets through Vapor's client)

- Full journey: `create-admin` + integration credentials via CLI → OPML import adds feeds →
  refresh fetches entries (stub server) → Google Reader: `ClientLogin` (plain-text `SID/LSID/Auth`
  lines — the JSON path only with `output=json`) → `subscription/list` → `stream/items/ids` with
  `xt=…read` (unread counts) → `stream/items/contents` → `edit-tag` read → counts changed;
  Fever: `groups` → `feeds` → `items` → `mark=item` read/saved → `unread_item_ids`/
  `saved_item_ids` changed.
- Contract matrix: every route listed above (including the `[]`/200 catch-all) and every Fever
  parameter; golden response shapes, including the text responses and the token-transport split
  (POST `T` vs GET `Authorization: GoogleLogin`).
- Auth failures per API: Google Reader 401 + bad-token header; ClientLogin JSON error; Fever
  200/`auth: 0` with `last_refreshed_on_time: 0`.
- Pagination and ids: >1000 items with continuations; `n` edge cases; the 4 item-id formats.
- Fever edge semantics: `mark=group` with `id=0` marks everything read; `id<0` and `mark=feed`
  with `id<=0` return empty 200.
- `quickadd`: website URL (discovery) and direct feed URL.
- Icon route: works without auth; `ETag` and cache headers set.

## Exit criteria

- [ ] The automated journey is green in CI.
- [ ] One real client (NetNewsWire) connects, adds a feed and syncs against a locally running
      instance (manual check; repeated with the full client matrix in stage 7).
