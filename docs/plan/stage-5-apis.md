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
The rest of the handlers are not started, and the OPML slice is merged as PR #64.
**Effort:** XL.
**Depends on:** Stage 4.

## Scope

[x] Promote `create-admin` from stub to working — the acceptance journey and real clients need
      it. nded with PR #38: the rule order, the character class read per scalar, the byte-counted
      nimum, the skip that runs before the rules, the secure read, the trim and the migration gate e
      pinned by `CreateAdminTests` and `UserValidationTests`, and the reference cost and the
      oss-marker compatibility by `BcryptHasherTests`. The locale wording, the terminal check and e
      environment path are named as not pinned in the suite header; the environment path arrives th
      `serve`. [x] Integration credentials command: `rivulet integration-credentials` sets per-user
      Google Reader ername/password (stored bcrypt) and Fever username/password (stored as the MD5
      token); ints the derived Fever `api_key`. Landed with PR #39: the join, the lowercase hex
      form, the rts read as given, the order the two duplicate checks are read in, the guard inside
      the rule nction that an empty name is not read against the answer, the per-user exclusion, the
      values mpared as read, each check reading its own column, and the rule that a blank password
      read eps the stored value are pinned by `FeverTokenTests`, `IntegrationValidationTests`,
      serRepositoryTests` and `IntegrationCredentialsTests`. The goldens are the reference's own
      tput at the toolchain `go.mod` pins. What the header names as not pinned: the prompt rding,
      which is the port's own, though the order the reads happen in is pinned by the flags those
      reads; the command's guard that an empty name never reaches the storage layer; the ank-name
      rule (this port keeps the stored value where the form writes what was submitted), e absent
      flag that would turn an integration off, the Fever password the reference does not ore, and
      the unique index on `fever_token`. These are recorded in `docs/parity.md`. [ ] Google Reader
      API — port the reference router exactly (see `docs/reference-notes.md`): lientLogin`; `token`;
      `edit-tag`; `rename-tag`; `disable-tag`; `tag/list`; `user-info`; ubscription/list` (embeds
      `iconUrl`); `subscription/edit` (`ac=subscribe|edit|unsubscribe`); ubscription/quickadd`
      (includes minimal feed discovery on website URLs — scan the HTML head r `<link
      rel="alternate">`; known deviation: the reference finder also probes well-known ths and
      site-specific handlers — record it in `docs/parity.md`); `stream/items/ids`;
      tream/items/contents`; `mark-all-as-read`; catch-all `/reader/api/0/*` → `[]` + HTTP 200
      arity: `unread-count`, `preference/stream/set` etc. stay unimplemented). Landed with PR #44 r
      the four handlers this piece implements — `edit-tag`, `tag/list`, `user-info` and
      tream/items/ids` — pinned by `GoogleReaderHandlerTests` over a real socket: the subpath
      ldcard, the row id the auth read hands the handler, `edit-tag` reading `a` and `r` from the dy
      and `i` from the merged form, the storage values the tag branches write, the branch itch with
      the two ways it reads the same exclude name and the feed filter that only a sitive parsed
      value applies, the two times every branch applies, the order the parameter ad answers, the
      continuation rule, the page-size clamp, and which endpoints the output check plies to.
      `rename-tag`, `disable-tag` and `mark-all-as-read` merged with PR #45, pinned by
      oogleReaderWriteHandlerTests` over the same socket: the merged list `s` that handler reads, e
      parameter name the read error names rather than the error itself, the guard order that ns the
      type check before the empty-destination guard, the two type-check wordings that name fferent
      things, the 404 the category read answers, the rule order that reads the row before e
      duplicate answer and writes after it, the delete guard that counts before any write and e pick
      it makes for the feeds of the rows it names, the switch with three cases so the types does not
      handle write nothing, the status the integer read maps to here, and the `ts` ngth rule with
      its two units, the sign guard and the comparison that is strictly before.
      tream/items/contents` merged with PR #46, pinned by `GoogleReaderContentHandlerTests` over e
      same socket: the order the handler runs in, with the order parameter read from the URL ery
      alone, the two titles read from two different rows and the site url read from the feed w, the
      three time columns with the two string forms built by multiplying, the document thor as the
      account name against the entry author the item writes, `self` as the configured se url, the
      item id in the full reference form, and the answer carrying every row the ids me, with the
      storage read pinned by `EntryContentsReadTests` and the categories rule for one em by
      `GoogleReaderItemCategoriesTests`. The media proxy is recorded in `docs/parity.md`, cause this
      port has none. The three subscription endpoints merged with PR #59, pinned er the same socket:
      the listing order, the six fields of the subscription document with e label being the category
      title, the icon link's two branches and the base it is built om, the whole merged list read
      for `s` against the single value read for `a`, the esence test that opens the write branch,
      the order the guards run in, and the status the teger read failure maps to here. The minimal
      discovery `quickadd` calls is pinned as re logic, with its two steps read over a stub server.
      The rest stays on the catch-all swer until its handler lands. [x] The storage reads the client
      auth path is built on: the Fever token lookup, with both sides wercase, and the stored-hash
      read for one Google Reader row, with the name compared as read. nded with PR #40, pinned by
      `ClientAuthTests`; the reference's `*_enabled` gate has nothing pin here; for "no row" the
      Fever read answers `nil` as upstream does, while the Google read ports an error upstream; and
      a row that stores nothing is `NULL` here where upstream's lumns default to an empty string, so
      the pin reads the port's side only. [x] Google Reader auth: `ClientLogin` exchange for the
      stateless HMAC token. Token transport is thod-specific exactly like the reference: **POST
      routes read the `T` form field; GET routes ad `Authorization: GoogleLogin auth=…`**. Response
      shapes are client-visible: `ClientLogin` turns plain text `SID=…/LSID=…/Auth=…` by default
      (JSON only with `output=json`), the token dpoint returns bare text, write operations return
      plain text `OK`. Failure semantics: 401, ext/plain`, `Unauthorized`,
      `X-Reader-Google-Bad-Token: true`. Landed with PR #41 for the dpoints this piece answers:
      `ClientLogin`, the token endpoint and the catch-all's `[]` + 0. The field names the login
      reads, the text shape by default and the JSON shape only when utput` says `json`, the compare
      against the stored value with a stored value the compare nnot read answering the same as a
      mismatch, the guard that an empty name ends the login fore the read — only its name half can
      fail, and the suite header names the password half — e transport chosen by method, the merged
      form with Go's order and its two pair-level errors, e header read as `strings.Fields` splits
      it, the three headers the response builder writes every response of this path, and the two 401
      shapes that differ between the login path and e protected path are pinned by
      `GoogleReaderAuthTests` over a real socket; the derivation d the JSON write are pinned against
      the reference's own output by `GoogleReaderTokenTests` d `JSONValueTests`. Plain text `OK` for
      the write operations follows with the routers, and do the mux rules above, except the no-slash
      path, where this port has no rule that reads e trailing slash and the pin records that
      divergence. [ ] Contract details pinned by golden tests. The pure rules landed with PR #42,
      with no HTTP: the ur item-id forms with the `fmt.Sscanf` `%016x` rules and the error wordings
      — the space the an skips before the field, the newline it does not skip, and the read per
      Unicode scalar — e stream branches with the two forms of each prefix as an OR and the seven
      suffixes, the ery read — which pairs are read, the order they answer in, the escape rules and
      the bounds eck that runs before the escape's two characters are read — and the parameter reads
      with the der read, the list read's trim as Go's `unicode.IsSpace` and its skip of an empty
      value, and e continuation rule, pinned by `GoogleReaderItemIDTests`,
      `GoogleReaderStreamTests`, oogleReaderQueryTests` and `GoogleReaderRequestModifiersTests`. The
      rules the handlers read nded with PR #43, also with no HTTP: the tag read with the add loop
      before the remove loop d the value each branch writes, the output read with the side chosen by
      method, and the cument shapes with the `omitempty` rule, the continuation as a string omitted
      when 0, and e empty list written as `[]`, pinned by `GoogleReaderTagsTests`,
      `GoogleReaderOutputTests` d `GoogleReaderShapeTests`. What landed with the handlers (PR #44):
      `n` clamped to 1000 ere the query builder applies it, the value the handler gives the
      continuation rule, dit-tag` reading its tags from the body and its item ids from the merged
      form, which dpoints the output read applies to and the status each error answer writes, the
      known-stream 500 wording, and the subpath wildcard, pinned by `GoogleReaderHandlerTests` er a
      socket with the status mapping pinned directly by `GoogleReaderResponseStatusTests`; e
      plain-text `OK` for a write operation and the token-transport split landed with PR #41. at the
      remaining handlers still have to answer is their own storage read and the document ch one
      builds. [ ] Fever API — exact parameter set: `groups`, `feeds`, `favicons`, `unread_item_ids`,
      aved_item_ids`, `items`, `mark=item|feed|group` with reference semantics (limit 50; ince_id` >
      `max_id` > `with_ids` precedence; `as=saved|unsaved`; invalid id → 0; `mark=feed` th `id<=0` →
      empty 200; `mark=group` with `id<0` → empty 200, ** `id=0` → mark all items ad (user-wide,
      ignores `before`)**, `id>0` → category read before `before`). Every response rries
      `last_refreshed_on_time` (0 on auth failure) and `items` carries `total_items`. Auth: pi_key`
      (MD5 token); failure is HTTP 200 with "api_version": 3, "auth": 0, "last_refreshed_on_time":
      0}`. No `keys`, no `hot`. [ ] Public icon route: `GET /feed-icon/<external_id>` —
      unauthenticated, `ETag`, 72h ache-Control`; Fever `favicons` returns `mime;base64,…`. [x]
      OPML: import (nested categories) and export; shared by the CLI and used in tests, merged as
      #64: the shape rules the model tags and the value rules the switch carries are read as the
      ference reads them over the tree the tolerant reader builds, and the bytes the encoder swers
      are reproduced rule by rule; the handler applies the duplicate answer, the category solution,
      the rules and the row per record. 57 pins and 76 probes across `OPMLReadTests`,
      PMLSerializeTests`, `OPMLImportTests` and `OPMLCommandTests`. `import` is the port's own mmand
      and `--file` is the port's own half of `export`; the settings the port schema has no eld for
      are read as data and not persisted, and the validation rules past the four ported es are not
      ported. Both are recorded in `docs/parity.md`. The icon route above is still en, and so is the
      exit criterion for the journey. [ ] Deviations are recorded in `docs/parity.md` as soon as
      they are observed.

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
