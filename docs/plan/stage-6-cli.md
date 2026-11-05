# Stage 6 — CLI & operations

**Goal:** everything is manageable without touching the database or a web UI.
**Status:** in progress — the first slice, the feed commands `add`, `remove` and `list`, is merged
(PR #47). The second slice, the maintenance commands `backup` and `vacuum`, is merged (PR #48). The
third slice, `list` for the categories and the accounts, is open as PR #49.
**Effort:** M. **Depends on:** Stages 1–5.

## Scope

- [x] `add`, `remove` and `list` for the feeds landed with PR #47: the rule the reference's feed
      validator reads, the duplicate read, the category read, the delete that applies the account,
      and the listing order, with the account the command works for resolved from `--user` or from
      the single account. The flag polish and the process-level checks follow.
- [x] `list` for the categories and the accounts landed with PR #49 as runs through the in-process
      console: the flag names which read the run makes, no flag still means the feeds, the pair of
      flags is reported as the rule the port names rather than picked, the account the run resolves
      reaches the category read and not the account read, the line carries the stored position and
      the stored admin flag rather than the schema default, one line carries one row, the run writes
      nothing, and the title order is the port's byte order. The shape is flags rather than an
      argument, because `@Argument` has no default, so a run cannot name an optional listing.
- [ ] Finalize the remaining commands (stubs created in stage 0): `serve`, `migrate`, `create-admin`
      (core lands in stage 5; this stage polishes prompts and flags), `import`/`export` (OPML),
      `refresh` (all/one) and `status` (`--json`) — the cores of both landed in stage 4 as the
      manual pass over the batch and the minimal contract the soak reads; this stage polishes their
      flags and output. `integration-credentials` (polish) and `version`.
- [x] `backup` and `vacuum` landed as runs through the in-process console (PR #48): the destination
      read as it was given, the copy as the snapshot at the run rather than the bytes of the main
      file, the copy being a file of its own, a destination the command did not create reported
      rather than built or overwritten, the file rebuilt without losing a row, and the flag that
      gates the migrations. What SQLite enforces on the destination and the rebuild landed with
      stage 1 and are pinned as storage rules by `MaintenanceTests`; what these pins add is the
      command's own choice of what it does, read on the filesystem after the run.
- [ ] No `api-key` command: REST v1 and API keys are non-goals (stage 9 backlog if ever needed).
- [ ] Graceful shutdown and structured logs; `/healthz`; signals handled by Vapor's built-in serve
      command.
- [ ] Startup checks: `PRAGMA quick_check` + free-space check (integrates with stage 1); checkpoint
      on shutdown; `status --json` as a stable machine-readable contract for monitoring and the
      stage-4 soak.

## Implementation notes

- In-process console tests use `TestConsole`; process-level behavior (signals, exit codes of the
  real binary) is tested by spawning the built executable.

## Tests

### Integration

- Every command against a temp database through the in-process console: exit codes, error messages,
  observable effects. For the feed commands this is `FeedCommandTests`; the rule is pinned as pure
  logic by `FeedValidationTests` and the reads by `FeedManagementReadsTests`. For the maintenance
  commands this is `MaintenanceCommandTests`, with the storage rules it calls pinned by
  `MaintenanceTests`. For the listings this is `ListingCommandTests`, with the two orders it reads
  pinned as reads by `CategoryRepositoryTests` and `UserRepositoryTests`, and the account resolution
  it reaches pinned there.
- `create-admin` → the resulting credentials authenticate over the API (cross-check with stage 5).
- Process-level: spawn the built binary with `serve`; `/healthz` answers; SIGTERM shuts down cleanly
  (no lost refresh batch).
- `backup` produces an openable copy equal to the source and `vacuum` shrinks a bloated database
  after retention — pinned as storage rules by `MaintenanceTests` and as runs by
  `MaintenanceCommandTests` (PR #48); `status --json` shape is stable.

## Exit criteria

- [ ] The deployment runbook (stage 8) needs nothing beyond these commands.

## Backlog

- Style findings from PR #47 that do not change behavior: the single-expression code lines in the
  command pins that read over the width (the `contains` calls with the rule name and the comment
  argument, and the seed calls with the fixture values), which the wrapping rule exempts, and
  `FeedCommandTests` reading 407 lines, which is inside the test-file cap but above the size the
  file is meant to hold as it grows — split by command when the next slice adds to it.
- Style findings from PR #48 that do not change behavior: the single-expression code lines in the
  maintenance pins that read over the width (the `run` calls with the arguments and the `#expect`
  calls with the comment argument), which the wrapping rule exempts, and the content read being
  written twice — once in `MaintenanceTests` and once in `MaintenanceCommandTests` — which stays
  duplicated because the two suites read it at different levels; it moves to `Support/` when a third
  suite reads it.
- The `import Foundation` in the two maintenance commands is not used by the code that is committed:
  it is there so the probe patches that redirect the destination through `NSString` and the
  filesystem through `FileManager` compile. It goes with the first probe that does not need a
  filesystem patch.
- The wording `list` prints for a row and the wording a failing run prints are the port's own; if
  the machine-readable form is wanted for the soak, `status --json` is already the contract and
  `list` should not grow a second one without a reason.
- `add` writes what it read, so the tracked-parameter case is pinned only as "the url as read"; the
  cleaner the reference applies on its discovery path lands with `quickadd` in stage 5, and the two
  paths are then where a parameter is dropped or kept.
- `backup` does not verify the copy it wrote: the runbook says to verify it by opening the file and
  running `PRAGMA quick_check`. If the command is to do that itself, that belongs to this stage's
  flag polish, and a pin for it needs a copy the run can be shown to fail on, which means a damaged
  destination written after the copy — the storage rules refuse a damaged destination before the
  write, so the check would have to run on the file the run wrote.
- `backup` has no overwrite flag: an existing destination is refused. A `--force` flag would be the
  port's own choice, not the reference's, and the rule that a run which wrote nothing reports it
  would then have to be read again on the other side of that flag.
- The free-space check the stage scope names is a startup check, not a `backup` rule: these pins
  read the copy the run wrote, not the space the run had.
- The account rule is the port's own: `--user` with the single-account fallback. If a flag is wanted
  for the environment path (`LIST_USER`, `ADD_USER`), that belongs to this stage's flag polish, not
  to the read.


