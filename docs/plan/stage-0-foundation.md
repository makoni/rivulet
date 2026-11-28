# Stage 0 — Foundation

**Goal:** a buildable, runnable skeleton: configuration, database bootstrap, CLI shell, CI.
**Status:** done. **Effort:** M. **Depends on:** —

## Decisions this stage set

- Environment names and defaults follow the reference: `LISTEN_ADDR` (default `127.0.0.1:8080`),
  `BASE_URL`, `DATABASE_URL`, `LOG_LEVEL` (default `info`), `RUN_MIGRATIONS`. Two deliberate
  deviations: `DATABASE_URL` is required here with a clear error, and `RUN_MIGRATIONS` defaults to
  `true`; both are recorded in `docs/parity.md`. Values are trimmed, empty values fall back to
  defaults, choice options validate before the fallback, booleans read as `1/yes/true/on` and
  `0/no/false/off`, the `BASE_URL` trailing slash is trimmed, and a single `LISTEN_ADDR` is accepted.
- The storage wrapper applies the per-connection pragmas on every checkout — `foreign_keys=ON`,
  `busy_timeout=5000`, `synchronous=NORMAL` — and sets `journal_mode=WAL` once per file. The driver
  keeps one pooled connection per event loop, so a nested checkout is not allowed; `prepare()` runs
  before migrations.
- Logging claims one process-wide slot, because the logging system allows one bootstrap per process;
  the integration tests claim the same slot.
- The command set is fixed at the skeleton: `serve`, `migrate`, `create-admin`, `add`, `remove`,
  `list`, `import`, `export`, `refresh`, `status`, `integration-credentials`, `backup`, `vacuum`,
  `version`. `serve` validates the arguments it delegates before it touches the database.
- `/healthz` answers every standard method, with no database access.

## Exit criteria

- [x] `swift test` green locally and in CI (`ubuntu-latest` + `swift:latest`).
- [x] `rivulet migrate && rivulet serve` works against a fresh database; `/healthz` responds.
- [x] README lists the commands that exist so far.

Each test suite's header comment names what its tests pin.
