# Testing strategy

Rivulet is developed test-first (TDD): red → green → refactor. Integration tests are not an
afterthought — they run in CI together with unit tests.

## Levels

| Level | Location | Scope |
| --- | --- | --- |
| Unit | `Tests/RivuletCoreTests` | Pure logic: date parsing, charset, sanitizer rules, merge decisions, scheduling math, config, OPML |
| Fixture/golden | `Tests/RivuletCoreTests/Fixtures/` (target resources) | Ported Miniflux corpora: encoding (11 files), parser (8), XML (3), sanitizer — input bytes → golden output |
| Integration | `Tests/RivuletIntegrationTests` | Real SQLite in a temp dir, local stub feed server, the full Vapor app over real HTTP |
| Acceptance | `Tools/parity` (stage 7) | Real clients checklist + semantic diff against real Miniflux in Docker |

The integration test target and its XCTVapor dependency are added to `Package.swift` in stage 0.
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

- `TestDatabase.swift` — temp-file SQLite database (temp dir per test run), migrations applied,
  wiped on teardown.
- `StubFeedServer.swift` — in-process HTTP server serving feed fixtures with configurable
  behavior: status codes, `ETag`/`Last-Modified`, gzip, redirects, delays, cut connections,
  charset headers. **Binds port 0** and exposes the assigned address; no fixed ports.
- `TestConsole.swift` — runs console commands in-process against a temp database.
- Clock injection: long-running logic (scheduler, retention) takes a `Clock` abstraction; tests
  use a manual clock and explicit `tick()` calls — no sleeping in tests.

App-level tests build the real Vapor app with a temp database and speak real HTTP over a socket
(XCTVapor `.running` mode) — this is the mode used for the client-API journey tests.

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
- Heavy suites (100k-entry benchmarks, big-feed scenarios) are tagged and skipped by default;
  run them explicitly with `RIVULET_HEAVY=1 swift test --filter HeavyTests` (XCTSkipUnless-based).

CI runs on Linux: `ubuntu-latest` with the `swift:latest` container and a 15-minute job timeout.
Keep the default suite well under that. Stage 7 adds a cheap CI slice (reduced hostile corpus +
reduced large-feed smoke); the full parity harness runs on demand via `Scripts/parity.sh`.

## Framework

XCTest everywhere (Vapor's `XCTVapor` for app tests) — one framework, no mixing.
Revisit only if Vapor's Swift Testing support becomes the default.
