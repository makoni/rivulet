# Testing strategy

Rivulet is developed test-first (TDD): red → green → refactor. Integration tests are not an
afterthought — they run in CI together with unit tests.

## Levels

| Level | Location | Scope |
| --- | --- | --- |
| Unit | `Tests/RivuletCoreTests`, `Tests/RivuletAppTests` | Pure logic: date parsing, charset, sanitizer rules, merge decisions, scheduling math, config, OPML, log formatting |
| Fixture/golden | `Tests/RivuletCoreTests/Fixtures/` (target resources, added in stage 3) | Ported Miniflux corpora: encoding (11 files), parser (8), XML (3), sanitizer (2) — input bytes → golden output |
| Integration | `Tests/RivuletIntegrationTests` | Real SQLite in a temp dir, local stub feed server, the full Vapor app over real HTTP |
| Acceptance | `Tools/parity` (stage 7) | Real clients checklist + semantic diff against real Miniflux in Docker |

The integration test target is added to `Package.swift` in stage 0 (no `XCTVapor`: app tests
speak to a real socket through Vapor's client).
Fixture files will be target resources (`resources: [.copy("Fixtures")]`, read via `Bundle.module`)
when stage 3 ports them.

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

- `TestDatabase.swift` — temp-file SQLite database in a temp dir per test; the schema migration is
  registered but applied explicitly by each test (`autoMigrate()`); wiped on teardown.
- `MigratedStorage.swift` — the `withMigratedStorage` helper: runs a body with a `TestDatabase` and
  a prepared, schema-migrated `SQLiteStorage`, shutting the app down (and removing the temp dir) on
  both success and failure; used by every suite that needs the migrated schema.
- `EntryFixtures.swift` — seeds users, categories and feeds, inserts entries through the repository
  with a chosen status/starred state, bulk-seeds entries for pagination limits, builds entry inputs,
  counts entries, tombstones and FTS matches, and backdates timestamps for the retention suites.
- `DatabaseCorruption.swift` — damages a real SQLite page (the two-byte cell count of page 2, the
  `_fluent_migrations` root, using the page size from the file header) so integrity tests observe
  `PRAGMA quick_check` failures without shipping a corrupt database fixture.
- `FileSize.swift` — file size in bytes, throwing when the file is missing or its metadata cannot be
  read, so an assertion that a WAL is empty cannot be satisfied by a deleted file.
- `StubFeedServer.swift` — in-process HTTP server serving feed fixtures with configurable behavior:
  status codes, `ETag`/`Last-Modified`, gzip, redirects, delays (before the answer, or after the
  head so a body can arrive later than a deadline), cut connections, chunked responses, charset
  headers. **Binds port 0** and exposes the assigned address; no fixed ports. It records every
  request it receives (target and headers) so a test can check what the client actually sent, and
  `waitForRequest(for:)` waits for one to arrive — check and wait in one step under the lock — so a
  test can act while a request is in flight without polling or sleeping, which holds only while the
  answer is still pending: a quick response releases the client before the test can act. The cache
  test therefore holds the body back. The proxy tests use `StubProxy`, not this server.
- `StubProxy.swift` — minimal proxy bound to port 0: it answers the `CONNECT` handshake and then
  serves one canned response on the tunnel, which is how AsyncHTTPClient proxies a request. Records
  the targets it was asked to connect to.
- `FetchTestSupport.swift` — setup shared by the fetch suites: the options with the values a test
  cares about named at the call site, a server, proxy or fetcher started for one test and closed on
  both the success and the failure path, and the two resolvers a fetch test injects (one seeded from
  a table, one counting the lookups).
- `GzipStream.swift` — writes a gzip stream with stored DEFLATE blocks so the stub server can serve
  a compressed body without a compression dependency. The fetch test uses this same encoder, so it
  shows that the client decompresses the fixture; the encoder itself is checked against `gunzip` by
  hand when it changes, which is why no test can prove it. Stored blocks cannot reach a compression
  ratio above 1, so the decompression guard `docs/reference-notes.md` records is not exercised by
  any test either.
- `TestConsole.swift` — in-process console that captures output and replays input; CLI smoke tests
  run commands against a temp database through it.
- `TemporaryDirectory.swift` — unique temp directory per test, removed on teardown (used by the CLI
  and probe tests).
- `TestLogging.swift` — installs a silent handler once per process through `LoggingSetup`'s
  bootstrap slot, so commands can run in-process without a second `LoggingSystem.bootstrap`
  (swift-log traps on a second one).
- Time injection: long-running logic takes the current time explicitly — `Retention.run(now:)` takes
  Unix seconds, scheduling will take a clock — so tests pass fixed values and never sleep.

`SystemAddressResolver` is the only public API that cannot have a hermetic test against a
network: it calls the real `getaddrinfo`, which the determinism rules below forbid. Its test is
the narrow case that works without one — a numeric host, which the resolver answers from the
string itself — and that is also the only place the byte order of the raw `addrinfo` layout
is pinned. Everything else that matters — one lookup for a direct hop, the answer handed to
the policy, and the client pinned to the answer it was built from — is tested through the
resolver seam, with a seeded resolver for the pinning and a counting one for the single lookup.

The cache has two behaviour tests. The first pins the one effect that can be observed from
outside an eviction: while a request is in flight the client serving it must not be closed,
or that request is cancelled — that is the failure the test reproduces. The request head
reaches the stub only after the client was taken from the cache, so waiting for the head
with `waitForRequest(for:)` puts the test at a known point without a sleep, and the body
is held long enough for the fillers to run, which the test states. The second asserts what
`shutdown()` can be observed to do: a second call finds nothing to close, and the next fetch
builds a client again. The recovery assertion carries the weight, but the second call is not
worthless either — an implementation that left closed entries in the cache would fail it with
AsyncHTTPClient's `alreadyShutdown`. That a call overlapping the first cannot close the same
client twice follows from taking the entries out before the first await; it cannot be reproduced
without a client-creation seam the plan does not have, so it is documented rather than tested.
Everything else about the cache is not observable from outside when two hosts are answered by the
same address: what is asserted is the key, because the guarantee that a pin is never reused for
another host or a proxied request rests on it; the TTL clock is monotonic so an NTP step cannot
stretch or shrink it, and eviction is by expiry among idle entries, not by use, which the code
states plainly. A client in use is never pruned; `shutdown()` closes every client regardless
of use, so calling it when no `fetch` is in flight is a caller's contract and the suite does
not assert the failure a shutdown during a fetch causes — that is a misuse, not a supported path.

App-level tests build the real Vapor app with a temp database and speak real HTTP over a
socket: the `/healthz` tests start the server on an ephemeral port (never the configured one)
and use Vapor's client. The same socket-level approach backs the client-API journey tests.

Determinism rules: no fixed ports, no sleeps or real-time waits (`TZ=UTC` for date tests, per-test
temp directories, no network access except to the local stub server or the stub proxy). The ported
date parser needs neither the clock nor the machine's zone: it reads no clock and no tzdata, and a
value that reads no zone is read as UTC, which is what the reference does as well. A bounded
timeout that proves a failure is fast rather than hanging is allowed — the pool-timeout test
asserts one — and a test whose pass condition is a timeout says so in its comment. A stub-side
hold is the only margin that can turn a test into a false pass: the first cache test keeps a
request in flight under a one-second body delay while eight local round trips fill the cache,
and a slow machine can only make that a false pass, never a false failure; the fetch timing
tests hold their margin the same way, with the first hop's delay small against the deadline so
CI overhead can only make the deadline fire earlier, never let a hop that should be cut finish. A
test that waits without a bound carries a `timeLimit` so a regression fails instead of hanging.

## Fixtures

Ported from Miniflux (Apache-2.0) into `Tests/RivuletCoreTests/Fixtures/<area>/`. The directory
gets its own `README.md` recording provenance: upstream repository, commit `c4d54f87`, license,
and which files were copied verbatim vs regenerated. `NOTICE` is updated when fixtures land.
Each ported case carries a comment pointing to the original Go test (`internal/reader/...`).

The URL layer has no fixture corpus, because the reference has none for it: its cases are the ported
tables from `internal/urllib/url_test.go` and `internal/reader/urlcleaner/urlcleaner_test.go`, plus
pins traced against Go's `net/url` source — there is no Go toolchain on this machine, so each suite
says which pins come from the upstream corpus and which are traced from the source, and
`docs/parity.md` records where the traced subset stops. Nothing in it reads a clock, a locale or the
network.

The sanitizer's upstream corpus is ported in full except `TestStripTags` and `TestTruncateHTML`,
 which belong to the format adapters and land with the next slice, and `TestFuzzSanitizer`, which
 compares token counts a subset tokenizer does not expose. The tokenizer and the insertion modes
 have no upstream corpus, so the five sanitizer suites name what is traced against
 `golang.org/x/net/html`, and `docs/parity.md` records where that subset stops.

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
