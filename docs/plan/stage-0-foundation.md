# Stage 0 — Foundation

**Goal:** a buildable, runnable skeleton: configuration, database bootstrap, CLI shell, CI.
**Status:** in progress (package skeleton, CI and docs scaffolding done).
**Effort:** M. **Depends on:** —

## Scope

- [x] SwiftPM package (Swift 6, Vapor 4, Fluent + SQLite); targets `RivuletCore`, `rivulet`, tests.
- [x] Apache-2.0 LICENSE + NOTICE attribution; CI workflow building and testing on Linux.
- [ ] Config: environment-based loader with Miniflux-compatible names where meaningful —
      `LISTEN_ADDR`, `BASE_URL`, `DATABASE_URL` (path to the SQLite file), `LOG_LEVEL`,
      `RUN_MIGRATIONS`; strict validation with clear error messages.
- [ ] Logging: swift-log via Vapor; text (default) and JSON format options.
- [ ] Database bootstrap: SQLite pragmas (`journal_mode=WAL`, `synchronous=NORMAL`,
      `foreign_keys=ON`, `busy_timeout`), Fluent migration runner.
- [ ] Schema v1: `users`, `categories`, `feeds`, `entries`, `enclosures`, `icons`,
      FTS5 table + sync triggers (see `docs/architecture.md`).
- [ ] CLI shell (ConsoleKit through Vapor) with stubbed commands: `serve`, `migrate`,
      `create-admin`, `add`, `remove`, `list`, `import`, `export`, `refresh`, `status`,
      `api-key`, `version`; `--help` for each.
- [ ] Minimal HTTP server with `GET /healthz`.

## Implementation notes

- Reference: `miniflux/internal/config` (environment names, defaults),
  `miniflux/internal/database/migrations` (schema shape).
- Deviations from Miniflux are listed in `docs/architecture.md`; keep that list updated as the
  schema grows.

## Tests

### Unit

- Config: defaults, overrides, invalid values, `DATABASE_URL` handling.

### Integration

- Migrations apply to an empty temp database and re-run idempotently (assert tables and FTS5
  objects exist afterwards).
- `rivulet migrate` end-to-end through the in-process console against a temp database.
- CLI smoke: `--help` lists all commands; `version` prints the version.
- App boot: the server starts with a temp database; `GET /healthz` returns 200.

## Exit criteria

- [ ] `swift test` green locally and in CI.
- [ ] `rivulet migrate && rivulet serve` works against a fresh database; `/healthz` responds.
- [ ] README lists the commands that exist so far.

## Risks

- None significant; this stage is mostly mechanical.
