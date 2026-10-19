# Stage 0 — Foundation

**Goal:** a buildable, runnable skeleton: configuration, database bootstrap, CLI shell, CI.
**Status:** done (CLI, logging and `/healthz` landed in part 2).
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
- [x] Logging: swift-log via Vapor; text (default, standard error) and JSON (one object per line)
      formats; the bootstrap runs once per process, so the first command run decides the level
      and format.
- [x] Storage bootstrap: SQLite via Fluent through a thin **storage wrapper** that applies
      per-connection pragmas on every connection checkout (`foreign_keys=ON`, `busy_timeout=5000`,
      `synchronous=NORMAL`) and sets `journal_mode=WAL` once per file (`prepare()` verifies that
      SQLite accepted it); Fluent migration runner.
- [x] Schema v1: `users`, `categories`, `feeds`, `entries`, `entry_tombstones`, `enclosures`,
      `icons`, `entries_fts` + sync triggers and indexes (see `docs/architecture.md`).
- [x] CLI skeleton with stubs for the full final command set: `serve`, `migrate`, `create-admin`,
      `add`, `remove`, `list`, `import`, `export`, `refresh`, `status`, `integration-credentials`,
      `backup`, `vacuum`, `version`. Our `serve` is a thin wrapper that delegates to Vapor's
      built-in `ServeCommand` — so its flags keep working — and validates the delegated
      arguments before it touches the database. Stubs report the stage that implements them
      (with or without arguments); `--help` and `version` work without configuration.
- [x] Minimal HTTP server with a method-agnostic `/healthz` (liveness probe, upstream parity:
      every standard method answers `200 OK` body `OK`, no database access).
- [x] Integration test target `Tests/RivuletIntegrationTests` wired into `Package.swift`
      (with the `XCTVapor` product) and the `Support/` skeleton (`TestDatabase`, `TestConsole`,
      `TemporaryDirectory`, `TestLogging`; `StubFeedServer` arrives with stage 2, when it is
      first needed).

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
- CLI topology: the executable target is a thin entry point; `RivuletApp` builds the command
  group (ConsoleKit), the application factory and the routes. `serve` validates the delegated
  arguments before any database work (Vapor's `ServeCommand` would only reject them after
  prepare/migrate/boot, and Fluent's boot-time scan reacts to `--auto-migrate`/`--auto-revert`
  first), then delegates to `ServeCommand` and, like `Application.execute()`, waits for the
  shutdown signal before shutting down; `migrate` always migrates — `RUN_MIGRATIONS` only gates
  what `serve` does.
- Logging bootstrap (`LoggingSetup`) claims a process-wide single slot because swift-log allows
  one `LoggingSystem.bootstrap` per process; the integration tests claim the same slot through
  `TestLogging`, so running a command in-process cannot bootstrap twice.

## Tests

### Unit

- Config: defaults, overrides, invalid values, missing `DATABASE_URL` error, `LISTEN_ADDR` parsing.
- Logging: the JSON handler's record fields, metadata merge order (handler → provider → call),
  level filtering, one-line escaping, non-finite doubles; the format switch and the level
  mapping of `LoggingSetup`.

### Integration

- Migrations apply to an empty temp database and re-run idempotently; assert tables, FTS5 objects
  **and triggers** exist afterwards.
- Pragmas are applied on every pooled connection (open several connections, read the pragma
  values back).
- CLI smoke through the in-process console: `--help` lists all commands, `version` prints,
  `migrate` creates the schema (also with `RUN_MIGRATIONS=false`), planned commands report
  their stage even with arguments, `serve` rejects unsupported arguments before creating the
  database.
- App boot: the server starts with a temp database; `/healthz` returns 200 for every standard
  method.

## Exit criteria

- [x] `swift test` green locally and in CI (`ubuntu-latest` + `swift:latest`).
- [x] `rivulet migrate && rivulet serve` works against a fresh database; `/healthz` responds.
- [x] README lists the commands that exist so far.

## Risks

- None significant; this stage is mostly mechanical.
