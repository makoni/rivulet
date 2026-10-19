# Stage 6 — CLI & operations

**Goal:** everything is manageable without touching the database or a web UI.
**Status:** not started. **Effort:** M. **Depends on:** Stages 1–5.

## Scope

- [ ] Final command set: `serve`, `migrate`, `create-admin`, `add`, `remove`,
      `list` (feeds/categories/users), `import`/`export` (OPML), `refresh` (all/one),
      `status` (per-feed last fetch, errors, next check + totals), `api-key` (create/revoke),
      `backup` (`VACUUM INTO`), `vacuum`, `version`.
- [ ] Interactive prompts (e.g. admin password) with non-interactive flags for scripting.
- [ ] Graceful shutdown (SIGINT/SIGTERM); structured logs; `/healthz`.
- [ ] `status --json` for scripts and monitoring.

## Tests

### Integration

- Every command against a temp database through the in-process console: exit codes, error
  messages, observable effects.
- `create-admin` → the resulting credentials authenticate over the API.
- `serve` + `/healthz`; SIGTERM shuts down cleanly (no lost refresh batch).
- `backup` produces an openable copy equal to the source; `vacuum` shrinks a bloated database
  after retention.

## Exit criteria

- [ ] The deployment runbook (stage 8) needs nothing beyond these commands.
