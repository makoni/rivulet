# AGENTS.md — working agreement for Rivulet

This file is for AI agents (and humans) making changes to this repository.

## What this project is

Rivulet is a lightweight self-hosted feed reader: a Swift port of
[Miniflux](https://github.com/miniflux/v2) (behavioral reference: v2.3.3), with SQLite storage,
a CLI-first interface and no web UI.

## Read before working

1. `docs/plan/README.md` — stages, status, definition of done.
2. The stage file for the current work (`docs/plan/stage-N-*.md`).
3. `docs/reference-notes.md` — verified Miniflux behavior (scheduling, auth, endpoints, retention).
   Re-check the clone when in doubt.
4. `docs/architecture.md` and `docs/testing.md`.

Current focus: **Stage 3 — Parsing & sanitization** (charset, XML reader, date parser, the URL layer
the sanitizer resolves through, the sanitizer core and its text layer (`StripTags`, `TruncateHTML`)
merged, and the format adapters next). Stage 2 is merged, with one exit criterion
deferred to the refresh path; see its stage file. Keep this line and the plan's status table in
sync.

## Toolchain

- Use the latest Swift release installed on the system (currently 6.4.1). Do not target old
  toolchains or work around modern Swift; prefer current stdlib and Concurrency features.
- CI is GitHub Actions on `ubuntu-latest` with the `swift:latest` container
  (see `.github/workflows/ci.yml`).

## TDD is mandatory

We work test-first: **red → green → refactor**.

- Write a failing test before writing production code.
- Bug fixes start with a regression test that reproduces the bug.
- Anything crossing a module boundary (HTTP, SQLite, scheduler, API endpoints) needs an
  integration test, not just a unit test.
- Ported Miniflux behavior must bring the corresponding ported tests.
- Tests are written with Swift Testing (`@Suite`/`@Test`, `#expect`/`#require`, `Test.cancel`);
  XCTest and `XCTVapor` are not used anywhere.
- Never delete, skip, weaken or "temporarily" disable tests to get a green run. If a test is
  genuinely wrong, fix the test in the same commit with a clear explanation.
- New public APIs without tests are not accepted.

## Documentation and DocC

- Documentation and tutorials are a project deliverable, not an afterthought. We will collect them
  with DocC and publish them later (planned: GitHub Pages, wired up in stage 8).
- Every public API gets a DocC documentation comment.
- DocC catalogs live next to the code (`Sources/RivuletCore/RivuletCore.docc/`, later also for
  the executable): articles for concepts, tutorials for key workflows (setup, feeds, clients,
  deployment).
- Write docs so they can be published as-is: no local-only references, no TODOs in prose.
- Keep `docs/` (plan, architecture, testing, reference notes) current. When code and docs
  disagree, fix both in the same commit.

## Code quality

- Architecture first: keep the module boundaries from `docs/architecture.md`, dependencies point
  inward, no cycles.
- Follow SOLID, YAGNI and KISS: the simplest thing that works; no speculative abstractions; keep
  only the seams the plan requires.
- File size: aim for 150–300 lines per production file, hard cap ~500 — split before you reach it.
  One primary type per file. Test files: aim ≤ 500 lines, split by concern; large tables/fixtures
  go to resource files, not inline megablocks.
- Functions: aim for ≤ ~40 lines; extract named helpers instead of deep nesting.
- Wrapping: prose and comments wrap at ≤100 columns, breaking at word boundaries. Two things are
  exempt because neither can be broken without changing what it says: a Markdown table row, and an
  inline code span longer than the width, which stays whole on its own line. Code lines are single
  expressions and are not split to meet the width. A commit that only rewraps does not change
  behavior, so it does not reopen a review that already approved the words.
- Prefer the standard library and existing dependencies. `swift-collections`
  (`Deque`, `OrderedDictionary`, …), `swift-algorithms` and `swift-crypto` (SHA-256, MD5) are
  pre-approved when they make data structures, algorithms or hashing clearer or more efficient —
  add them as direct dependencies of the module that uses them when first used (they are already
  in the dependency graph via Vapor; `RivuletCore` must not depend on Vapor itself). Any other new
  dependency needs explicit approval — Linux-first, keep the surface small.
- Measure before optimizing; batch SQLite writes; no accidental O(n²).

## Review

- Every PR is reviewed by three read-only reviewers, and all three must APPROVE on the final head.
- The budget is three runs, hard cap four. Run 1 is a full review of the pushed head; run 2 verifies
  the delta — that each blocker is resolved — and does not look for anything new; run 3 happens only
  if run 2 found a blocker, and only for that blocker. Once the budget is spent, merge. This
  replaces the older "two clean rounds" wording, which counted rounds but did not cap them: a run
  per blocker kept the count open.
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
```

## Conventions

- Swift 6, strict concurrency, `async/await`. No blocking calls on the event loop.
- Code, comments, docs and commit messages are in English.
- Ported code keeps a header comment:
  `// Ported from Miniflux <path> (Apache-2.0); adapted for Swift/SQLite.`
  Ported tests keep a comment with the original test name.
- SQLite: one write transaction per feed refresh; WAL; per-connection pragmas via the storage
  wrapper; never fsync per row. Until the first release the schema is edited in place
  (`SchemaV1`) — versioned migrations start at the first release.
- No PostgreSQL, no Redis, no external cron, no web UI — these are explicit non-goals,
  not oversights.

## Stage workflow

- Work on one stage at a time, starting from the lowest not-started stage.
- A stage is complete when its exit criteria and the global definition of done are met.
- Update the status table in `docs/plan/README.md` and the "Current focus" line above in the same
  commit that completes a stage.

## Commits

- Small, focused commits with imperative subjects; mention the stage when relevant:
  `stage-2: support conditional GET with ETag`.
- Behavior + its tests + doc updates land in the same commit.
- Never commit generated artifacts (`.build/`, `.docc-build/`, database files, secrets) —
  see `.gitignore`.

## Safety

- The HTML sanitizer is security-critical: never relax allowlists to make a test pass; when in
  doubt, port Miniflux behavior.
- Respect size and time limits in the fetcher; never disable SSRF protections by default.
- No secrets, tokens or personal feed lists in the repository or in fixtures.
