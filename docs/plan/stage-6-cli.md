# Stage 6 — CLI & operations

**Goal:** everything is manageable without touching the database or a web UI.
**Status:** in progress — the first slice, the feed commands `add`, `remove` and `list`, lands
(PR #47). **Effort:** M. **Depends on:** Stages 1–5.

## Scope

- [x] `add`, `remove` and `list` for the feeds land with PR #47: the rule the reference's feed
      validator reads, the duplicate read, the category read, the delete that applies the account,
      and the listing order, with the account the command works for resolved from `--user` or from
      the single account. `list` for categories and users is open, as is the flag polish below.
- [ ] Finalize the remaining commands (stubs created in stage 0): `serve`, `migrate`, `create-admin`
      (core lands in stage 5; this stage polishes prompts and flags), `import`/`export` (OPML),
      `refresh` (all/one) and `status` (`--json`) — the cores of both landed in stage 4 as the
      manual pass over the batch and the minimal contract the soak reads; this stage polishes their
      flags and output. `integration-credentials` (polish), `backup` (`VACUUM INTO`), `vacuum`,
      `version`.
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
  logic by `FeedValidationTests` and the reads by `FeedManagementReadsTests`.
- `create-admin` → the resulting credentials authenticate over the API (cross-check with stage 5).
- Process-level: spawn the built binary with `serve`; `/healthz` answers; SIGTERM shuts down cleanly
  (no lost refresh batch).
- `backup` produces an openable copy equal to the source; `vacuum` shrinks a bloated database after
  retention; `status --json` shape is stable.

## Exit criteria

- [ ] The deployment runbook (stage 8) needs nothing beyond these commands.

## Backlog

- Style findings from PR #47 that do not change behavior: the single-expression code lines in the
  command pins that read over the width (the `contains` calls with the rule name and the comment
  argument, and the seed calls with the fixture values), which the wrapping rule exempts, and
  `FeedCommandTests` reading 407 lines, which is
  inside the test-file cap but above the size the file is meant to hold as it grows — split by
  command when the next slice adds to it.
- The wording `list` prints for a row and the wording a failing run prints are the port's own; if
  the machine-readable form is wanted for the soak, `status --json` is already the contract and
  `list` should not grow a second one without a reason.
- `add` writes what it read, so the tracked-parameter case is pinned only as "the url as read"; the
  cleaner the reference applies on its discovery path lands with `quickadd` in stage 5, and the two
  paths are then where a parameter is dropped or kept.
- The account rule is the port's own: `--user` with the single-account fallback. If a flag is wanted
  for the environment path (`LIST_USER`, `ADD_USER`), that belongs to this stage's flag polish, not
  to the read.
