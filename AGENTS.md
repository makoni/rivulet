# AGENTS.md — working agreement for Rivulet

How we work in this repository, for AI agents and humans. It holds rules, not history: what a change
did lives in git history and in the test suites; open work lives in issues.

## What this project is

Rivulet is a lightweight self-hosted feed reader: a Swift port of
[Miniflux](https://github.com/miniflux/v2) (behavioral reference: v2.3.3), with SQLite storage, a
CLI-first interface and no web UI. Clients connect through the Google Reader, Fever and Miniflux
REST APIs.

## Read before working

1. `docs/plan/README.md` — stages, status, definition of done; then the stage file for the work.
2. The issue you are working on.
3. `docs/architecture.md` and `docs/testing.md`.
4. `docs/reference-notes.md` (verified Miniflux behavior) and `docs/parity.md` (where Rivulet
   deliberately differs) when the change touches behavior Miniflux defines. Re-check the Miniflux
   source when in doubt.

Current focus: the stage 9 backlog — the 0.1.0 scope (`docs/plan/stage-9-stretch.md`).

## Explore with codegraph

The repo is indexed by the **codegraph** MCP server (`.codegraph/`, git-ignored, local to each
machine; it trails writes by about a second). `codegraph_explore` returns the current source of the
relevant symbols, the call path among them and which tests cover them. Use it when the answer spans
more than one place, or before changing a rule, to see which tests depend on it. Do not follow it
with a Read or grep sweep over the same files — what it printed is the current file content. Use
Read and Grep when the file and symbol are already known, or for files outside the index (`docs/`,
`Scripts/`, `Tools/`, `Package.swift`). Edit with the normal file tools.

## Toolchain

- Use the latest Swift release installed on the system; prefer current stdlib and Concurrency
  features over workarounds for old toolchains.
- CI is GitHub Actions on `ubuntu-latest` with the `swift:latest` container
  (`.github/workflows/ci.yml`): `swift build` and `swift test`.

## TDD is mandatory

Red → green → refactor.

- Write a failing test before production code; a bug fix starts with a test that reproduces it.
- Make sure a new test can fail on the behavior it names: break that rule in the code, see it go
  red, revert (see "Checking that a test can fail" in `docs/testing.md`). Don't record or count these
  checks anywhere.
- Anything crossing a module boundary (HTTP, SQLite, scheduler, API endpoints) needs an integration
  test, not just a unit test.
- Ported Miniflux behavior brings the corresponding ported tests.
- Swift Testing only (`@Suite`/`@Test`, `#expect`/`#require`, `Test.cancel`); no XCTest, no
  `XCTVapor`.
- Never delete, skip, weaken or "temporarily" disable a test to get a green run. If a test is wrong,
  fix it in the same commit and say why.
- New public API needs tests.

## Documentation

- Every public declaration has a DocC documentation comment; `DocumentationConsistencyTests` enforces
  it, and checks that the README, the deploy docs and the DocC catalog show only real commands, flags
  and configuration variables.
- User documentation is the DocC catalog (`Sources/RivuletCore/RivuletCore.docc/`); write it for
  readers — publishable as is, no local-only references, no TODOs. `Scripts/build-docs.sh` builds the
  archive; it is published by hand outside this repository.
- Keep `docs/` current, in plain language. When code and docs disagree, fix both in the same commit.

## Code quality

- Keep the module boundaries in `docs/architecture.md`: dependencies point inward, no cycles.
- SOLID, YAGNI, KISS: the simplest thing that works, no speculative abstractions.
- Files: aim for 150–300 lines, hard cap ~500, one primary type per file. Functions: aim for ≤ ~40
  lines. Test files: aim for ≤ 500 lines, split by concern; large fixtures go to resource files.
- Zero warnings: `swift build` and `swift build --build-tests` finish with no warning. Fix each warning
  where it is raised; don't silence it with a flag.
- Prefer the standard library and existing dependencies. Pre-approved when first used, as direct
  dependencies of the module that uses them: `swift-collections`, `swift-algorithms`, `swift-crypto`
  (`RivuletCore` must not depend on Vapor). Approved for icon resizing in `RivuletCore`:
  `tayloraswift/swift-png` (from 4.5.2) and `tayloraswift/swift-jpeg` (from 2.1.0). Refused:
  `fwcd/swift-gif` (eight transitive dependencies) and libwebp bindings (C dependency), so GIF and
  WebP are read for their dimensions only. Any other dependency needs explicit approval.
- Measure before optimizing; batch SQLite writes; no accidental O(n²).

## Review

- Before opening a pull request, have it reviewed by an independent read-only reviewer: correctness
  against the Miniflux reference, tests that can actually fail, docs that match the code. Changes to
  the sanitizer, the fetcher's limits or SSRF guard, or authentication get a second reviewer.
- Fix blockers in new commits and have the fix confirmed once. Non-blocking notes land in the same
  pull request or become issues; style findings never block.
- Open the pull request after the review, so CI runs on the final head.

## Commands

```sh
swift build                            # debug build
swift test                             # all tests (unit + integration); must be green
swift test --filter RivuletCoreTests   # fast unit loop
swift build --build-tests              # must be warning-free
swift run rivulet --help
```

## Conventions

- Swift 6, strict concurrency, `async/await`; no blocking calls on the event loop.
- Code, comments, docs and commit messages are in English.
- Ported code keeps a header: `// Ported from Miniflux <path> (Apache-2.0); adapted for Swift/SQLite.`
  Ported tests keep a comment with the original test name.
- SQLite: one write transaction per feed refresh; WAL; per-connection pragmas via the storage
  wrapper; never fsync per row. Until the first release the schema is edited in place (`SchemaV1`);
  versioned migrations start with the release.
- No PostgreSQL, no Redis, no external cron, no web UI — explicit non-goals.

## Stages and issues

- Work one stage at a time, from the lowest unfinished one, unless redirected.
- Open work is an issue; the pull request that finishes it closes it.
- When a stage is complete, update the status table in `docs/plan/README.md`, the stage list in
  `README.md` and the "Current focus" line above in the same commit.

## Commits

- Small, focused commits with imperative subjects; mention the stage when relevant:
  `stage-2: support conditional GET with ETag`.
- Behavior, its tests and its doc updates land in the same commit.
- Never commit generated artifacts (`.build/`, `.docc-build/`, database files, secrets).

## Safety

- The HTML sanitizer is security-critical: never relax an allowlist to make a test pass; when in
  doubt, port Miniflux's behavior.
- Respect the fetcher's size and time limits; never disable the SSRF protections by default.
- No secrets, tokens or personal feed lists in the repository or in fixtures.
