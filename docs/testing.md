# Testing strategy

Rivulet is developed test-first (TDD): red → green → refactor. Integration tests are not an
afterthought — they run in CI together with unit tests.

## Levels

| Level | Location | Scope |
| --- | --- | --- |
| Unit | `Tests/RivuletCoreTests` | Pure logic: date parsing, charset, sanitizer rules, merge decisions, backoff math, config, OPML |
| Fixture/golden | `Tests/RivuletCoreTests` + `Tests/Fixtures` | Ported Miniflux corpora: encoding (11 files), parser (8), XML (3), sanitizer — input bytes → golden output |
| Integration | `Tests/RivuletIntegrationTests` | Real SQLite in a temp dir, local stub feed server, the full Vapor app over real HTTP |
| Acceptance | `Tools/parity` (stage 7) | Real clients checklist + semantic diff against real Miniflux in Docker |

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

- `Support/TestDatabase.swift` — temp-file SQLite database, migrations applied, wiped on teardown.
- `Support/StubFeedServer.swift` — in-process HTTP server serving feed fixtures with configurable
  behavior: status codes, `ETag`/`Last-Modified`, gzip, redirects, delays, cut connections,
  charset headers.
- App-level tests boot the real Vapor app with a temp database and the stub server, and speak
  real HTTP (XCTVapor).

## Fixtures

Ported from Miniflux (Apache-2.0) into `Tests/Fixtures/<area>/`. Each ported case carries a
comment pointing to the original Go test (`internal/reader/...`). Golden outputs are checked in.

## Running

- `swift test` — everything (unit + integration); this is what CI runs.
- `swift test --filter RivuletCoreTests` — unit only (fast loop).
- `swift test --filter RivuletIntegrationTests` — integration only.

CI runs on Linux (`swift:6.4.1-jammy` container). Keep the default suite under ~10 minutes;
heavy benchmarks (100k entries) and the parity harness run on demand, not in the default job.

## Framework

XCTest everywhere (Vapor's `XCTVapor` for app tests) — one framework, no mixing.
Revisit only if Vapor's Swift Testing support becomes the default.
