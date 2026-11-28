# Stage 5 — Client APIs & OPML

**Goal:** existing native clients connect and sync; the contract mirrors the reference exactly.
**Status:** complete. **Effort:** XL. **Depends on:** stage 4.

## Decisions this stage set

- The reference code is the contract, and upstream has almost no Fever tests, so the contract tests
  are written from the handler directly.
- Response shapes match the reference where clients depend on them: plain text where the reference
  sends plain text (`ClientLogin` lines, `OK`, the token), JSON otherwise.
- No web UI: credentials are managed through the commands, and authentication never issues browser
  sessions.
- The acceptance backbone is the chain the pins run as one run each: `create-admin` and the integration
  credentials through the commands, OPML import adding feeds, a refresh fetching entries through the
  stub server, then `ClientLogin`, `subscription/list`, `stream/items/ids` with the read marker,
  `stream/items/contents`, `edit-tag`, and the counts; on the Fever side, `groups`, `feeds`, `items`,
  `mark=item`, and the unread and saved id lists. Each pin reads one link of the chain and asserts
  literals built from the fixture's own inputs, with the stored values read through SQL digest lines,
  so a pin is not satisfied by the read it tests.
- `import` is the port's own command, and `--file` is the port's own half of `export`; both are
  recorded in `docs/parity.md`, as is the media proxy, which this port does not have.

## Exit criteria

- [x] Every handler this stage names has landed, and the deviations are recorded in `docs/parity.md` as
  soon as they are observed.
- [x] The single-client criterion names one real client rather than a client by name; it is closed by
  the client runs stage 7 reads as data, and the add half stays open for the Fever client whose set has
  no call that can write a feed row.

Each test suite's header comment names what its tests pin.
