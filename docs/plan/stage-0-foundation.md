# Stage 0 — Foundation

**Goal:** a buildable, runnable skeleton: configuration, database bootstrap, CLI shell, CI.
**Status:** in progress (package skeleton, CI and docs scaffolding done).
**Effort:** M. **Depends on:** —

## Scope

- [x] SwiftPM package (Swift 6, Vapor 4, Fluent + SQLite); targets `RivuletCore`, `rivulet`; tests.
- [x] Apache-2.0 LICENSE + NOTICE; CI building and testing on `ubuntu-latest` with the
      `swift:latest` container.
- [x] Config: environment-based loader with Miniflux-compatible names — `LISTEN_ADDR`
      (default `127.0.0.1:8080`), `BASE_URL`, `DATABASE_URL` (**required**, SQLite file path;
      clear error if missing), `LOG_LEVEL` (default `info`), `RUN_MIGRATIONS` (default `true`);
      strict validation with clear error messages. Parsing follows upstream semantics: values
      trimmed, empty values fall back to defaults (choice options validate first, so an empty
      `LOG_LEVEL`/`LOG_FORMAT` is an error), booleans `1/yes/true/on` / `0/no/false/off`,
      `BASE_URL` trailing slash trimmed; a single `LISTEN_ADDR` (lists rejected).
- [ ] Logging: swift-log via Vapor; text (default) and JSON format options.
- [x] Storage bootstrap: SQLite via Fluent through a thin **storage wrapper** that applies
      per-connection pragmas on every connection checkout (`foreign_keys=ON`, `busy_timeout=5000`,
      `synchronous=NORMAL`) and sets `journal_mode=WAL` once per file (`prepare()` verifies that
      SQLite accepted it); Fluent migration runner.
- [x] Schema v1: `users`, `categories`, `feeds`, `entries`, `entry_tombstones`, `enclosures`,
      `icons`, `entries_fts` + sync triggers and indexes (see `docs/architecture.md`).
- [ ] CLI skeleton with stubs for the full final command set: `serve`, `migrate`, `create-admin`,
      `add`, `remove`, `list`, `import`, `export`, `refresh`, `status`, `integration-credentials`,
      `backup`, `vacuum`, `version`. `serve` reuses Vapor's built-in `ServeCommand` (configured
      from our config) — do not register a custom command with the same name.
- [ ] Minimal HTTP server with `GET /healthz`.
- [ ] Integration test target `Tests/RivuletIntegrationTests` wired into `Package.swift`
      (with the `XCTVapor` product) and the `Support/` skeleton (`TestDatabase`, `TestConsole`;
      `StubFeedServer` arrives with stage 2, when it is first needed).

## Implementation notes

- Reference: `miniflux/internal/config` (environment names, defaults). Schema shape:
  `miniflux/internal/database/migrations.go` — this is a single file upstream, not a directory.
- Migrations: sqlite-nio prepares exactly one statement per call — execute multi-statement DDL
  one statement at a time; create the FTS5 table and triggers via raw SQL (`sql.raw(...).run()`
  on the SQLKit view of the database).
- Intentional deviations from upstream defaults: `DATABASE_URL` is required here with a clear
  error (Miniflux ships a default DSN), and `RUN_MIGRATIONS` defaults to `true` (upstream defaults
  to `false`). The config test covers the error path.
- `app.db` stays private to the storage layer: repositories are the only accessors, so the pragma
  wrapper cannot be bypassed by other modules.
- The driver keeps one pooled connection per event loop, so `SQLiteStorage.withConnection` bodies
  must not open a nested checkout (repositories take the checked-out connection); a nested
  checkout fails fast on the connection-pool timeout. `prepare()` runs before migrations.

## Tests

### Unit

- Config: defaults, overrides, invalid values, missing `DATABASE_URL` error, `LISTEN_ADDR` parsing.

### Integration

- Migrations apply to an empty temp database and re-run idempotently; assert tables, FTS5 objects
  **and triggers** exist afterwards.
- Pragmas are applied on every pooled connection (open several connections, read the pragma
  values back).
- CLI smoke through the in-process console: `--help` lists all commands, `version` prints,
  `migrate` creates the schema.
- App boot: the server starts with a temp database; `GET /healthz` returns 200.

## Exit criteria

- [ ] `swift test` green locally and in CI (`ubuntu-latest` + `swift:latest`).
- [ ] `rivulet migrate && rivulet serve` works against a fresh database; `/healthz` responds.
- [ ] README lists the commands that exist so far.

## Risks

- None significant; this stage is mostly mechanical.
