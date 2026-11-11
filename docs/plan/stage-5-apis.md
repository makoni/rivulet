# Stage 5 — Client APIs & OPML

**Goal:** existing native clients connect and sync; the contract mirrors the reference exactly.
**Status:** in progress — the first two slices are merged: `create-admin` with the user rules and
the bcrypt hasher (PR #38), and `integration-credentials` with the Fever token derivation and the
duplicate-name rules (PR #39). In the third slice the storage reads landed with PR #40, the Google
Reader auth path with PR #41, and the contract rules the routers read with PR #42; the rules the
handlers read — the tag read, the output read and the document shapes — merged with PR #43 as pure
logic too, and the handlers for the four endpoints this piece implements merged with PR #44 over a
real socket, with the three POST write handlers — `rename-tag`, `disable-tag` and `mark-all-as-read`
— merged with PR #45 over the same socket, and `stream/items/contents` merged with PR #46, pinned
over the same socket with the storage read it builds on pinned as a read, and the three subscription
endpoints merged with PR #59 over the same socket with the minimal discovery pinned as pure logic.
The rest of the handlers are not started, the OPML slice is merged as PR #64, and the public icon
route is merged as PR #65.
**Effort:** XL.
**Depends on:** Stage 4.

## Scope

- [x] Promote `create-admin` from stub to working — the acceptance journey and real clients need it.
      Landed with PR #38: the rule order, the character class read per scalar, the byte-counted
      minimum, the skip that runs before the rules, the secure read, the trim and the migration gate
      are pinned by `CreateAdminTests` and `UserValidationTests`, and the reference cost and the
      cross-marker compatibility by `BcryptHasherTests`. The locale wording, the terminal check and
      the environment path are named as not pinned in the suite header; the environment path arrives
      with `serve`.
- [x] Integration credentials command: `rivulet integration-credentials` sets per-user Google Reader
      username/password (stored bcrypt) and Fever username/password (stored as the MD5 token);
      prints the derived Fever `api_key`. Landed with PR #39: the join, the lowercase hex form, the
      parts read as given, the order the two duplicate checks are read in, the guard inside the rule
      function that an empty name is not read against the answer, the per-user exclusion, the values
      compared as read, each check reading its own column, and the rule that a blank password read
      keeps the stored value are pinned by `FeverTokenTests`, `IntegrationValidationTests`,
      `UserRepositoryTests` and `IntegrationCredentialsTests`. The goldens are the reference's own
      output at the toolchain `go.mod` pins. What the header names as not pinned: the prompt
      wording, which is the port's own, though the order the reads happen in is pinned by the flags
      of those reads; the command's guard that an empty name never reaches the storage layer; the
      blank-name rule (this port keeps the stored value where the form writes what was submitted),
      the absent flag that would turn an integration off, the Fever password the reference does not
      store, and the unique index on `fever_token`. These are recorded in `docs/parity.md`.
- [ ] Google Reader API — port the reference router exactly (see `docs/reference-notes.md`):
      `ClientLogin`; `token`; `edit-tag`; `rename-tag`; `disable-tag`; `tag/list`; `user-info`;
      `subscription/list` (embeds `iconUrl`); `subscription/edit` (`ac=subscribe|edit|unsubscribe`);
      `subscription/quickadd` (includes minimal feed discovery on website URLs — scan the HTML head
      for `<link rel="alternate">`; known deviation: the reference finder also probes well-known
      paths and site-specific handlers — record it in `docs/parity.md`); `stream/items/ids`;
      `stream/items/contents`; `mark-all-as-read`; catch-all `/reader/api/0/*` → `[]` + HTTP 200
      (parity: `unread-count`, `preference/stream/set` etc. stay unimplemented). Landed with PR #44
      for the four handlers this piece implements — `edit-tag`, `tag/list`, `user-info` and
      `stream/items/ids` — pinned by `GoogleReaderHandlerTests` over a real socket: the subpath
      wildcard, the row id the auth read hands the handler, `edit-tag` reading `a` and `r` from the
      body and `i` from the merged form, the storage values the tag branches write, the branch
      switch with the two ways it reads the same exclude name and the feed filter that only a
      positive parsed value applies, the two times every branch applies, the order the parameter
      read answers, the continuation rule, the page-size clamp, and which endpoints the output check
      applies to. `rename-tag`, `disable-tag` and `mark-all-as-read` merged with PR #45, pinned by
      `GoogleReaderWriteHandlerTests` over the same socket: the merged list `s` that handler reads,
      the parameter name the read error names rather than the error itself, the guard order that
      runs the type check before the empty-destination guard, the two type-check wordings that name
      different things, the 404 the category read answers, the rule order that reads the row before
      the duplicate answer and writes after it, the delete guard that counts before any write and
      the pick it makes for the feeds of the rows it names, the switch with three cases so the types
      it does not handle write nothing, the status the integer read maps to here, and the `ts`
      length rule with its two units, the sign guard and the comparison that is strictly before.
      `stream/items/contents` merged with PR #46, pinned by `GoogleReaderContentHandlerTests` over
      the same socket: the order the handler runs in, with the order parameter read from the URL
      query alone, the two titles read from two different rows and the site url read from the feed
      row, the three time columns with the two string forms built by multiplying, the document
      author as the account name against the entry author the item writes, `self` as the configured
      base url, the item id in the full reference form, and the answer carrying every row the ids
      name, with the storage read pinned by `EntryContentsReadTests` and the categories rule for one
      item by `GoogleReaderItemCategoriesTests`. The media proxy is recorded in `docs/parity.md`,
      because this port has none. The three subscription endpoints merged with PR #59, pinned
      over the same socket: the listing order, the six fields of the subscription document with
      the label being the category title, the icon link's two branches and the base it is built
      from, the whole merged list read for `s` against the single value read for `a`, the
      presence test that opens the write branch, the order the guards run in, and the status the
      integer read failure maps to here. The minimal discovery `quickadd` calls is pinned as
      pure logic, with its two steps read over a stub server. The rest stays on the catch-all
      answer until its handler lands.
- [x] The storage reads the client auth path is built on: the Fever token lookup, with both sides
      lowercase, and the stored-hash read for one Google Reader row, with the name compared as read.
      Landed with PR #40, pinned by `ClientAuthTests`; the reference's `*_enabled` gate has nothing
      to pin here; for "no row" the Fever read answers `nil` as upstream does, while the Google read
      reports an error upstream; and a row that stores nothing is `NULL` here where upstream's
      columns default to an empty string, so the pin reads the port's side only.
- [x] Google Reader auth: `ClientLogin` exchange for the stateless HMAC token. Token transport is
      method-specific exactly like the reference: **POST routes read the `T` form field; GET routes
      read `Authorization: GoogleLogin auth=…`**. Response shapes are client-visible: `ClientLogin`
      returns plain text `SID=…/LSID=…/Auth=…` by default (JSON only with `output=json`), the token
      endpoint returns bare text, write operations return plain text `OK`. Failure semantics: 401,
      `text/plain`, `Unauthorized`, `X-Reader-Google-Bad-Token: true`. Landed with PR #41 for the
      endpoints this piece answers: `ClientLogin`, the token endpoint and the catch-all's `[]` +
      200. The field names the login reads, the text shape by default and the JSON shape only when
      `output` says `json`, the compare against the stored value with a stored value the compare
      cannot read answering the same as a mismatch, the guard that an empty name ends the login
      before the read — only its name half can fail, and the suite header names the password half —
      the transport chosen by method, the merged form with Go's order and its two pair-level errors,
      the header read as `strings.Fields` splits it, the three headers the response builder writes
      on every response of this path, and the two 401 shapes that differ between the login path and
      the protected path are pinned by `GoogleReaderAuthTests` over a real socket; the derivation
      and the JSON write are pinned against the reference's own output by `GoogleReaderTokenTests`
      and `JSONValueTests`. Plain text `OK` for the write operations follows with the routers, and
      so do the mux rules above, except the no-slash path, where this port has no rule that reads
      the trailing slash and the pin records that divergence.
- [ ] Contract details pinned by golden tests. The pure rules landed with PR #42, with no HTTP: the
      four item-id forms with the `fmt.Sscanf` `%016x` rules and the error wordings — the space the
      scan skips before the field, the newline it does not skip, and the read per Unicode scalar —
      the stream branches with the two forms of each prefix as an OR and the seven suffixes, the
      query read — which pairs are read, the order they answer in, the escape rules and the bounds
      check that runs before the escape's two characters are read — and the parameter reads with the
      order read, the list read's trim as Go's `unicode.IsSpace` and its skip of an empty value, and
      the continuation rule, pinned by `GoogleReaderItemIDTests`, `GoogleReaderStreamTests`,
      `GoogleReaderQueryTests` and `GoogleReaderRequestModifiersTests`. The rules the handlers read
      landed with PR #43, also with no HTTP: the tag read with the add loop before the remove loop
      and the value each branch writes, the output read with the side chosen by method, and the
      document shapes with the `omitempty` rule, the continuation as a string omitted when 0, and
      the empty list written as `[]`, pinned by `GoogleReaderTagsTests`, `GoogleReaderOutputTests`
      and `GoogleReaderShapeTests`. What landed with the handlers (PR #44): `n` clamped to 1000
      where the query builder applies it, the value the handler gives the continuation rule,
      `edit-tag` reading its tags from the body and its item ids from the merged form, which
      endpoints the output read applies to and the status each error answer writes, the
      unknown-stream 500 wording, and the subpath wildcard, pinned by `GoogleReaderHandlerTests`
      over a socket with the status mapping pinned directly by `GoogleReaderResponseStatusTests`;
      the plain-text `OK` for a write operation and the token-transport split landed with PR #41.
      What the remaining handlers still have to answer is their own storage read and the document
      each one builds.
- [ ] Fever API — exact parameter set: `groups`, `feeds`, `favicons`, `unread_item_ids`,
      `saved_item_ids`, `items`, `mark=item|feed|group` with reference semantics (limit 50;
      `since_id` > `max_id` > `with_ids` precedence; `as=saved|unsaved`; invalid id → 0; `mark=feed`
      with `id<=0` → empty 200; `mark=group` with `id<0` → empty 200, ** `id=0` → mark all items
      read (user-wide, ignores `before`)**, `id>0` → category read before `before`). Every response
      carries `last_refreshed_on_time` (0 on auth failure) and `items` carries `total_items`. Auth:
      `api_key` (MD5 token); failure is HTTP 200 with
      `{"api_version": 3, "auth": 0, "last_refreshed_on_time": 0}`. No `keys`, no `hot`.
- [x] Public icon route: `GET /feed-icon/<external_id>` — unauthenticated, `ETag`, 72h
      `Cache-Control`; Fever `favicons` returns `mime;base64,…`. Landed as PR #65: the four rules
      the response builder applies for a cached asset — the `ETag` shape, the `If-None-Match` read,
      the `Cache-Control` value and the `Expires` value — are pinned as pure logic, and the answer
      the route gives a row is pinned over a real socket: the read it runs, which values it takes
      from the row, which headers it writes on which branch, and the status the two branches answer.
      The builder's three headers are read as one rule shared by both paths. 10 pins and 15 probes
      by `CachingRulesTests`, 7 pins and 10 probes by `IconRouteTests`; the three reaches the round
      records, the one probe that cannot bite, and what no pin here can show are named in the suite
      headers.
- [x] OPML: import (nested categories) and export; shared by the CLI and used in tests, merged as
      PR #64: the shape rules the model tags and the value rules the switch carries are read as the
      reference reads them over the tree the tolerant reader builds, and the bytes the encoder
      answers are reproduced rule by rule; the handler applies the duplicate answer, the category
      resolution, the rules and the row per record. 57 pins and 76 probes across `OPMLReadTests`,
      `OPMLSerializeTests`, `OPMLImportTests` and `OPMLCommandTests`. `import` is the port's own
      command and `--file` is the port's own half of `export`; the settings the port schema has no
      field for are read as data and not persisted, and the validation rules past the four ported
      ones are not ported. Both are recorded in `docs/parity.md`. The acceptance journey is what is
      left open for this stage.
- [ ] Deviations are recorded in `docs/parity.md` as soon as they are observed.

## Implementation notes

- The reference code is the contract (`internal/googlereader`, `internal/fever`); upstream has
  almost no Fever tests, so our contract tests are written from the handler directly.
- Response shapes must match the reference where clients depend on them: plain text where the
  reference sends plain text (ClientLogin lines, `OK`, token), JSON otherwise.
- No web UI: credentials are managed via the CLI; authentication never issues browser sessions.

## Tests

### Unit

- Token derivation; Google Reader response encoders (JSON + plain text); OPML round-trip; pagination
  math.

### Integration (the acceptance backbone, real sockets through Vapor's client)

- Full journey: `create-admin` + integration credentials via CLI → OPML import adds feeds → refresh
  fetches entries (stub server) → Google Reader: `ClientLogin` (plain-text `SID/LSID/Auth` lines —
  the JSON path only with `output=json`) → `subscription/list` → `stream/items/ids` with `xt=…read`
  (unread counts) → `stream/items/contents` → `edit-tag` read → counts changed; Fever: `groups` →
  `feeds` → `items` → `mark=item` read/saved → `unread_item_ids`/ `saved_item_ids` changed.
- Contract matrix: every route listed above (including the `[]`/200 catch-all) and every Fever
  parameter; golden response shapes, including the text responses and the token-transport split
  (POST `T` vs GET `Authorization: GoogleLogin`).
- Auth failures per API: Google Reader 401 + bad-token header; ClientLogin JSON error; Fever 200/
  `auth: 0` with `last_refreshed_on_time: 0`.
- Pagination and ids: >1000 items with continuations; `n` edge cases; the 4 item-id formats.
- Fever edge semantics: `mark=group` with `id=0` marks everything read; `id<0` and `mark=feed` with
  `id<=0` return empty 200.
- `quickadd`: website URL (discovery) and direct feed URL.
- Icon route: works without auth; `ETag` and cache headers set.

## Exit criteria

- [ ] The automated journey is green in CI.
- [ ] One real client (NetNewsWire) connects, adds a feed and syncs against a locally running
      instance (manual check; repeated with the full client matrix in stage 7).

## Backlog
Findings from review runs 1 and 2 on PR #64 that do not change behavior:

- `OPMLImportTests.swift` is 469 lines, close to the ≤500 aim for a test file. The import and export
halves are one handler, so the file splits only when the next slice adds tests to it.

- The reference's own OPML tests are not ported as tests. `parser_test.go` reads a malformed
character entity, which here is the tokenizer's rule and is named as unpinnable in the read header;
`serializer_test.go` asserts the round trip, which the port pins as one pin rather than as one per
field.

- The byte comparison for the group order is written element by element rather than as a comparison
of two `[UInt8]` values, because the standard library has no `<` for an array: the shorter form
type-checked only inside the module, where another file's import brought an operator in.



Findings from the work on PR #46 that do not change behavior:

- `EntryContents.swift`'s initializer takes 15 parameters, which is the row the reference scans for
  this read. The type is one row, so grouping the three time columns or the three join values would
  be a style change rather than a behavior change.
- The page-size rule is not falsifiable in this port, so it is named in the suite header and in
  `docs/testing.md` rather than pinned; the pin that names it records the answer carrying both rows.

Findings from the work on PR #45 that do not change behavior:

- `GoogleReaderWriteHandlerTests.swift` is 554 lines, past the ≤500 aim for a test file. The three
  handlers are one concern — the POST write path — and the pins that name the storage reads the
  handlers use are already separate suites, so the file splits by handler only when the next slice
  adds tests to it.
- In `GoogleReaderHandlers+Write.swift`, `renameTag` is 47 lines and `markAllAsRead` 44, past the
  ~40 aim. Each is the handler's own sequence of guards and branches with no nesting to flatten, so
  the split would be a style matter.

Findings from review run 1 on PR #44 that do not change behavior:

- `GoogleReaderHandlers.swift` is 317 lines, a little over the ~300 aim for a production file: the
  handlers are one function per endpoint, so the file can only be split by grouping endpoints, which
  is a style matter. Closed by PR #45, which put the three POST write handlers in their own file and
  left this one at 295 lines.

Findings from the runs on PR #41 that do not change behavior:

- `GoogleReaderAuthTests`' assertion that no `Location` is written for the path without the trailing
  slash states the divergence rather than pinning it: a wrong read that writes the reference's
  redirect cannot be observed here, because Vapor's client follows a redirect and reports the answer
  after the follow. The pin's comment says this, and the pin fails on a read that distinguishes the
  trailing slash.
- `docs/testing.md` is over the file-size aim for a document (699 lines at the head PR #45 merges):
  it is one file for the levels, the support helpers and the CI rules, and splitting it by level is
  a style matter.

Findings from review run 1 on PR #38 that do not change behavior:

- `UserRepository.userExists` repeats the body of `fetch(username:)`. The reference has these as two
  statements, and the pin for the case-insensitive read fails on either one, so the duplication is a
  style matter rather than a rule; keeping the bodies separate keeps the comment that names the
  reference's `LIMIT 1` read on the function the pin reads.
- `CreateAdmin` trims with Swift's `whitespaces`, which is not Go's `TrimSpace`: the two differ on
  `U+0085`. A console read has already removed the line ending, so the difference cannot be reached
  here, and it is recorded in the comment rather than pinned.
- `BcryptHasher` runs the digest on the caller's task, which is what the plan asks for on the CLI
  path: one hash per command run. It is also where the stage-5 routers will compare hashes, and one
  comparison per request is not a loop; the hop is what to revisit if that path grows into a loop,
  and the type stays in `RivuletApp` either way, because `RivuletCore` must not depend on Vapor. The
  type is not `async` while the command that calls it is.
- Two table rows are split across lines from earlier commits, at `docs/parity.md:395` and
  `docs/testing.md:17`, which puts them past the 100-column width; they are not part of this slice.
- `docs/testing.md` is at 585 lines, past the ~500 cap.

Findings from review run 1 on this slice (PR #39) that do not change behavior:

- `IntegrationCredentialsTests.withRun` is 47 lines, past the ~40 aim: the seed write and the read
  back are two halves that could be split, and the pins would read the same outcome.
- The empty-name guard is written in two places, `hasName` on the command and the check inside
  `IntegrationValidation.validate`. The reference has it once, in the handler before its read, so
  the second is the rule function's own guard, and the pins can fail only on that one, which is what
  the header now says.

Findings from the runs on PR #64 that do not change behavior:

- The probe round for this slice runs `swift test` filtered to the four OPML suites, one run per
  probe, so a pin outside them is not read. On the first round the probe for the root-name rule
  reported `ServeProcessTests`' `theBuiltBinaryAnswersOnTheProbedPort` next to the pin it names;
  that pin reads the built binary over a socket, and no patch to the OPML read can reach it, so that
  report was a flake of that suite rather than a double-firing.
- The upstream `parser_test.go` cases are read as rules rather than ported as cases, because each of
  them asserts on the value layer this port does not have. The two upstream names the serialize
  suite cites are the cases that survive as round-trip pins, and the read suite's pins name the rule
  each case can fail on instead of the case.
