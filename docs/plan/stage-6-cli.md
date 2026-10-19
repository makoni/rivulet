# Stage 6 — CLI & operations

**Goal:** everything is manageable without touching the database or a web UI.
**Status:** not started. **Effort:** M. **Depends on:** Stages 1–5.

## Scope

- [ ] Finalize the remaining commands (stubs created in stage 0): `serve`, `migrate`,
      `create-admin` (core lands in stage 5; this stage polishes prompts and flags), `add`,
      `remove`, `list` (feeds/categories/users), `import`/`export` (OPML), `refresh` (all/one),
      `status` (per-feed last fetch, errors, next check + totals; `--json`), `integration-credentials`
      (polish), `backup` (`VACUUM INTO`), `vacuum`, `version`.
- [ ] No `api-key` command: REST v1 and API keys are non-goals (stage 9 backlog if ever needed).
- [ ] Graceful shutdown and structured logs; `/healthz`; signals handled by Vapor's built-in
      serve command.
- [ ] Startup checks: `PRAGMA quick_check` + free-space check (integrates with stage 1);
      checkpoint on shutdown; `status --json` as a stable machine-readable contract for
      monitoring and the stage-4 soak.

## Implementation notes

- In-process console tests use `TestConsole`; process-level behavior (signals, exit codes of the
  real binary) is tested by spawning the built executable.

## Tests

### Integration

- Every command against a temp database through the in-process console: exit codes, error
  messages, observable effects.
- `create-admin` → the resulting credentials authenticate over the API (cross-check with stage 5).
- Process-level: spawn the built binary with `serve`; `/healthz` answers; SIGTERM shuts down
  cleanly (no lost refresh batch).
- `backup` produces an openable copy equal to the source; `vacuum` shrinks a bloated database
  after retention; `status --json` shape is stable.

## Exit criteria

- [ ] The deployment runbook (stage 8) needs nothing beyond these commands.
