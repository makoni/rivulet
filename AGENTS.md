# AGENTS.md — working agreement for Rivulet

This file is for AI agents (and humans) making changes to this repository. It holds the agreement:
how we work. It does not hold the record of what a run showed — no pin or probe counts, no pull
request numbers, no per-slice history. Those live in `docs/plan/README.md`, the stage files, and the
documents the check halves read as data. What no check half can read as data is not stated here as a
fact about a run: it is stated as an aim, or it is not stated.

## What this project is

Rivulet is a lightweight self-hosted feed reader: a Swift port of
[Miniflux](https://github.com/miniflux/v2) (behavioral reference: v2.3.3), with SQLite storage, a
CLI-first interface and no web UI.

## Read before working

1. `docs/plan/README.md` — stages, status, definition of done.
2. The stage file for the current work (`docs/plan/stage-N-*.md`).
3. `docs/reference-notes.md` — verified Miniflux behavior (scheduling, auth, endpoints, retention).
   Re-check the clone when in doubt.
4. `docs/architecture.md` and `docs/testing.md`.

Current focus: **Stage 10 — Miniflux REST v1 subset**, the stage-9 item scheduled on the calls Capy
Reader's `minifluxclient` declares, worked here while the stage 7 file keeps its `/v1` half open; the
plan's working agreement allows the redirect. The stage-9 backlog is the 0.1.0 scope.

## Explore with codegraph before reading files

This repo is indexed by the **codegraph** MCP server: the index lives in `.codegraph/` (git-ignored,
local to each machine) and trails writes by about a second, so it reflects an edit just made.
`codegraph_explore` is Read-equivalent — a question or a bag of symbol names answers the verbatim,
line-numbered source of the relevant symbols, the call path among them, and the blast radius: which
tests cover a symbol, and which have none within a few hops. Pass the project as `projectPath` when
the session has no index of its own.

Reach for it when the answer spans more than one place: a subsystem not read yet, or before editing a
rule, where the blast radius names the pins that can fail on it — the same list a review run checks.
Read and Grep stay right for the opposite case: the file and the symbol are already known, one value
or one line is needed, or the file is outside the index (`docs/`, `Scripts/`, `Tools/`,
`Package.swift`).

Two rules once it has been called:

- Do **not** follow it with a grep or Read sweep over the same files: the source it printed is
  current on-disk content, so treat it as already read.
- Use the normal file tools for editing. Codegraph is for finding and understanding, and it cannot
  show what a probe round shows — that a rule is falsifiable is something the round proves by hand.

## Toolchain

- Use the latest Swift release installed on the system. Do not target old toolchains or work around
  modern Swift; prefer current stdlib and Concurrency features.
- CI is GitHub Actions on `ubuntu-latest` with the `swift:latest` container
  (see `.github/workflows/ci.yml`).

## TDD is mandatory

We work test-first: **red → green → refactor**.

- Write a failing test before writing production code.
- Bug fixes start with a regression test that reproduces the bug.
- Anything crossing a module boundary (HTTP, SQLite, scheduler, API endpoints) needs an integration
  test, not just a unit test.
- Ported Miniflux behavior must bring the corresponding ported tests.
- Tests are written with Swift Testing (`@Suite`/ `@Test`, `#expect`/ `#require`, `Test.cancel`);
  XCTest and `XCTVapor` are not used anywhere.
- Never delete, skip, weaken or "temporarily" disable tests to get a green run. If a test is
  genuinely wrong, fix the test in the same commit with a clear explanation.
- New public APIs without tests are not accepted.

## Documentation and DocC

- Documentation and tutorials are a project deliverable, not an afterthought. We collect them with
  DocC; `Scripts/build-docs.sh` writes the archive the site is built from, and the site itself is
  outside this repository, so no CI job here publishes it. The script is run by the person, who
  publishes the archive themselves, and the site is not something this project returns to.
- Every public API gets a DocC documentation comment.
- DocC catalogs live next to the code (`Sources/RivuletCore/RivuletCore.docc/`, later also for the
  executable): articles for concepts, tutorials for key workflows (setup, feeds, clients, deployment).
- Write docs so they can be published as-is: no local-only references, no TODOs in prose.
- Keep `docs/` (plan, architecture, testing, reference notes) current. When code and docs disagree,
  fix both in the same commit.

## Code quality

- Architecture first: keep the module boundaries from `docs/architecture.md`, dependencies point
  inward, no cycles.
- Follow SOLID, YAGNI and KISS: the simplest thing that works; no speculative abstractions; keep
  only the seams the plan requires.
- File size: aim for 150–300 lines per production file, hard cap ~500 — split before you reach it.
  One primary type per file. Test files: aim ≤ 500 lines, split by concern; large tables/fixtures go
  to resource files, not inline megablocks.
- Functions: aim for ≤ ~40 lines; extract named helpers instead of deep nesting.
- Zero warnings: the project and the test targets build clean — `swift build` and `swift build
  --build-tests` answer with no warning on a clean build. Each warning is fixed at the site it names,
  not silenced with a flag: the `await` on a call that is not async is dropped, a binding or a result
  nothing reads is removed or assigned to `_`, and `@discardableResult` is put on a function only when
  no caller reads its result.
- Prefer the standard library and existing dependencies. `swift-collections` (`Deque`,
  `OrderedDictionary`, …), `swift-algorithms` and `swift-crypto` (SHA-256, MD5) are pre-approved when
  they make data structures, algorithms or hashing clearer or more efficient — add them as direct
  dependencies of the module that uses them when first used (they are already in the dependency graph
  via Vapor; `RivuletCore` must not depend on Vapor itself). Any other new dependency needs explicit
  approval — Linux-first, keep the surface small. `tayloraswift/swift-png` (from 4.5.2) and
  `tayloraswift/swift-jpeg` (from 2.1.0), both Apache-2.0, are approved for the icon image resizing
  as direct dependencies of `RivuletCore`; `fwcd/swift-gif` was refused because it brings eight
  transitive dependencies, and a libwebp binding because it is a C dependency, so GIF and WebP are
  read for their dimensions only.
- Measure before optimizing; batch SQLite writes; no accidental O(n²).

## Review

- Every PR is reviewed by three read-only reviewers, and all three must APPROVE on the final head.
- The budget is three runs, hard cap four. Run 1 is a full review of the pushed head; run 2 verifies
  the delta — that each blocker is resolved — and does not look for anything new; run 3 happens only
  if run 2 found a blocker, and only for that blocker. Once the budget is spent, merge. This replaces
  the older "two clean rounds" wording, which counted rounds but did not cap them: a run per blocker
  kept the count open.
- Runs are sequential, one agent at a time: a run starts only after the previous one has reported.
  Three reviewers read the same head, so the three agents run one after another, never together — a
  parallel set is one pass over the head, not three runs, and it cannot verify a delta that does not
  exist yet.
- Run 1 checks three things, so nothing from it expands into later runs: the semantics against the
  reference, that every assertion can actually fail on the behavior it names, and that the docs say
  what the tests pin.
- The cap counts runs, not fixes. A blocker is fixed in the commit that answers it; when the budget
  is spent, findings that do not change behavior go to the backlog and the PR merges.
- Non-blocking observations do not reopen a review: they land in the same commit or go to the
  backlog. A wording change that restates what a reviewer proposed is confirmed with one line, not
  with a run. Style findings (file and function size, unused imports, unported upstream tests) are
  backlog items, not blockers.
- Open the PR after the review runs are done, so CI runs once on the final head and the approvals
  are counted on that head.

## Commands

```sh
swift build                            # debug build
swift test                             # all tests (unit + integration); must be green
swift test --filter RivuletCoreTests   # fast unit loop
swift run rivulet --help
swift build --build-tests              # must be warning-free, for the project and the tests
```

## Conventions

- Swift 6, strict concurrency, `async/await`. No blocking calls on the event loop.
- Code, comments, docs and commit messages are in English.
- Ported code keeps a header comment: `// Ported from Miniflux <path> (Apache-2.0); adapted for
  Swift/SQLite.` Ported tests keep a comment with the original test name.
- SQLite: one write transaction per feed refresh; WAL; per-connection pragmas via the storage
  wrapper; never fsync per row. Until the first release the schema is edited in place (`SchemaV1`) —
  versioned migrations start at the first release.
- No PostgreSQL, no Redis, no external cron, no web UI — these are explicit non-goals, not
  oversights.

## Stage workflow

- Work on one stage at a time, starting from the lowest not-started stage.
- A stage is complete when its exit criteria and the global definition of done are met.
- Update the status table in `docs/plan/README.md` and the "Current focus" line above in the same
  commit that completes a stage.

## Commits

- Small, focused commits with imperative subjects; mention the stage when relevant: `stage-2:
  support conditional GET with ETag`.
- Behavior + its tests + doc updates land in the same commit.
- Never commit generated artifacts (`.build/`, `.docc-build/`, database files, secrets) — see
  `.gitignore`.

## Safety

- The HTML sanitizer is security-critical: never relax allowlists to make a test pass; when in
  doubt, port Miniflux behavior.
- Respect size and time limits in the fetcher; never disable SSRF protections by default.
- No secrets, tokens or personal feed lists in the repository or in fixtures.
