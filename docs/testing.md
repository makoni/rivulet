# Testing strategy

Rivulet is developed test-first (TDD): red → green → refactor. Integration tests are not an
afterthought — they run in CI together with unit tests.

## Levels

| Level | Location | Scope |
| --- | --- | --- |
| Unit | `Tests/RivuletCoreTests`, `Tests/RivuletAppTests` | Pure logic: date parsing, charset, sanitizer rules, merge decisions, scheduling math, config, OPML, log formatting |
| Fixture/golden | `Tests/RivuletCoreTests/Fixtures/` (target resources) | Ported Miniflux corpora: encoding (11 files), parser (8), XML (3), sanitizer — input bytes → golden output |
| Integration | `Tests/RivuletIntegrationTests` | Real SQLite in a temp dir, local stub feed server, the full Vapor app over real HTTP |
| Acceptance | `Tools/parity` (stage 7) | Real clients checklist + semantic diff against real Miniflux in Docker |

The integration test target is added to `Package.swift` in stage 0 (no `XCTVapor`: app tests
speak to a real socket through Vapor's client).
Fixture files are target resources (`resources: [.copy("Fixtures")]`, read via `Bundle.module`).

## Workflow (TDD)

1. Write a failing test that describes the behavior.
2. Implement the minimal change to make it pass.
3. Refactor with tests green.
4. Bug fixes start with a regression test that reproduces the bug.

Rules:

- No production code without a corresponding test change.
- Never delete, skip or weaken a test to make the suite pass (see `AGENTS.md`).
- When behavior crosses a module boundary, cover it with an integration test, not only a unit test.

## Integration test infrastructure

Support helpers live in `Tests/RivuletIntegrationTests/Support/`:

- `TestDatabase.swift` — temp-file SQLite database in a temp dir per test; the schema migration
  is registered but applied explicitly by each test (`autoMigrate()`); wiped on teardown.
- `MigratedStorage.swift` — the `withMigratedStorage` helper: runs a body with a `TestDatabase`
  and a prepared, schema-migrated `SQLiteStorage`, shutting the app down (and removing the temp
  dir) on both success and failure; used by every suite that needs the migrated schema.
- `EntryFixtures.swift` — seeds users, categories and feeds, inserts entries through the
  repository with a chosen status/starred state, bulk-seeds entries for pagination limits, builds
  entry inputs, counts entries, tombstones and FTS matches, and backdates timestamps for the
  retention suites.
- `DatabaseCorruption.swift` — damages a real SQLite page (page 2, the `users` root) so integrity
  tests observe `PRAGMA quick_check` failures without shipping a corrupt database fixture.
- `StubFeedServer.swift` — in-process HTTP server serving feed fixtures with configurable
  behavior: status codes, `ETag`/`Last-Modified`, gzip, redirects, delays, cut connections,
  charset headers. **Binds port 0** and exposes the assigned address; no fixed ports.
- `TestConsole.swift` — in-process console that captures output and replays input; CLI smoke
  tests run commands against a temp database through it.
- `TemporaryDirectory.swift` — unique temp directory per test, removed on teardown (used by the
  CLI and probe tests).
- `TestLogging.swift` — installs a silent handler once per process through `LoggingSetup`'s
  bootstrap slot, so commands can run in-process without a second `LoggingSystem.bootstrap`
  (swift-log traps on a second one).
- Time injection: long-running logic takes the current time explicitly — `Retention.run(now:)`
  takes Unix seconds, scheduling will take a clock — so tests pass fixed values and never sleep.

App-level tests build the real Vapor app with a temp database and speak real HTTP over a
socket: the `/healthz` tests start the server on an ephemeral port (never the configured one)
and use Vapor's client. The same socket-level approach backs the client-API journey tests.

Determinism rules: no fixed ports, no real-time waits, `TZ=UTC` for date tests, per-test temp
directories, no network access except to the local stub server.

## Fixtures

Ported from Miniflux (Apache-2.0) into `Tests/RivuletCoreTests/Fixtures/<area>/`. The directory
gets its own `README.md` recording provenance: upstream repository, commit `c4d54f87`, license,
and which files were copied verbatim vs regenerated. `NOTICE` is updated when fixtures land.
Each ported case carries a comment pointing to the original Go test (`internal/reader/...`).

## Running

- `swift test` — everything (unit + integration); this is what CI runs.
- `swift test --filter RivuletCoreTests` — unit only (fast loop).
- `swift test --filter RivuletIntegrationTests` — integration only.
- Heavy suites (100k-entry benchmarks, big-feed scenarios) are disabled by default and enabled
  by an `.enabled(if:)` trait gated on `RIVULET_HEAVY`; run them explicitly with
  `RIVULET_HEAVY=1 swift test --filter HeavyTests`.
- A few storage tests need at least two event loops (one pooled connection per loop); they
  `Test.cancel` on single-loop runners. CI runners always expose ≥2 event loops.

CI runs on Linux: `ubuntu-latest` with the `swift:latest` container and a 15-minute job timeout.
Keep the default suite well under that. Stage 7 adds a cheap CI slice (reduced hostile corpus +
reduced large-feed smoke); the full parity harness runs on demand via `Scripts/parity.sh`.

## Framework

Swift Testing everywhere (`import Testing`, `@Suite`/`@Test`, `#expect`/`#require`) — one
framework, no mixing; XCTest and `XCTVapor` are not in the tree. Tests run in parallel by
default and every test owns its resources (temp directories, kernel-assigned ports), so no
suite depends on execution order. Use the `.serialized` trait only where a suite must share
process-wide state.
