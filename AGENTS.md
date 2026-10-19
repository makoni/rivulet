# AGENTS.md — working agreement for Rivulet

This file is for AI agents (and humans) making changes to this repository.

## What this project is

Rivulet is a lightweight self-hosted feed reader: a Swift port of
[Miniflux](https://github.com/miniflux/v2), with SQLite storage, a CLI-first interface and no web UI.
Miniflux v2.3.3 is the behavioral specification (see `docs/plan/README.md`).

## Read before working

1. `docs/plan/README.md` — stages, status, definition of done.
2. The stage file for the current work (`docs/plan/stage-N-*.md`).
3. `docs/architecture.md` and `docs/testing.md`.

Current focus: **Stage 0 — Foundation** (see the status table in the plan).

## TDD is mandatory

We work test-first: **red → green → refactor**.

- Write a failing test before writing production code.
- Bug fixes start with a regression test that reproduces the bug.
- Anything crossing a module boundary (HTTP, SQLite, scheduler, API endpoints) needs an
  integration test, not just a unit test.
- Ported Miniflux behavior must bring the corresponding ported tests.
- Never delete, skip, weaken or "temporarily" disable tests to get a green run. If a test is
  genuinely wrong, fix the test in the same commit with a clear explanation.
- New public APIs without tests are not accepted.

## Commands

```sh
swift build                            # debug build
swift test                             # all tests (unit + integration); must be green before committing
swift test --filter RivuletCoreTests   # fast unit loop
swift run rivulet --help
```

## Conventions

- Swift 6, strict concurrency, `async/await`. No blocking calls on the event loop.
- Code, comments, docs and commit messages are in English.
- New dependencies require explicit approval — Linux-first, keep the surface small.
- Ported code keeps a header comment: `// Ported from Miniflux <path> (Apache-2.0); adapted for Swift/SQLite.`
  Ported tests keep a comment with the original test name.
- SQLite: batch writes in one transaction per feed refresh; use WAL; never fsync per row.
- No PostgreSQL, no Redis, no external cron, no web UI — these are explicit non-goals,
  not oversights.

## Stage workflow

- Work on one stage at a time, starting from the lowest not-started stage.
- A stage is complete when its exit criteria and the global definition of done are met.
- Update the status table in `docs/plan/README.md` in the same commit that completes a stage.

## Commits

- Small, focused commits with imperative subjects; mention the stage when relevant:
  `stage-2: support conditional GET with ETag`.
- Behavior + its tests + doc updates land in the same commit.
- Never commit generated artifacts (`.build/`, database files, secrets) — see `.gitignore`.

## Safety

- The HTML sanitizer is security-critical: never relax allowlists to make a test pass; when in
  doubt, port Miniflux behavior.
- Respect size and time limits in the fetcher; never disable SSRF protections by default.
- No secrets, tokens or personal feed lists in the repository or in fixtures.
