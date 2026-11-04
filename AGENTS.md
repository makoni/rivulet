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

Current focus: **Stage 5 — Client APIs & OPML**, with its first two slices merged: `create-admin`
with the user rules and the bcrypt hasher (PR #38), and `integration-credentials` with the Fever
token derivation and the duplicate-name rules (PR #39). For the second slice the join, the
lowercase hex form, the parts read as given, the order the two duplicate checks are read in, the
guard inside the rule function that an empty name is not read against the answer, the per-user
exclusion, the values compared as read, each check reading its own column, and the rule that a blank
password read keeps the stored value are pinned by `FeverTokenTests`, `IntegrationValidationTests`,
`UserRepositoryTests` and `IntegrationCredentialsTests`; for the first slice the rule order, the
character class read per Unicode scalar, the byte-counted minimum, the existence read that runs
before any rule, the secure read and the trim, and the flag that gates the migrations are pinned by
`UserValidationTests` and
`CreateAdminTests`, and the reference cost, the 72-byte rule and the marker direction by
`BcryptHasherTests`. What those pins cannot show is named in the suite headers — the locale wording,
the terminal check, the environment path, which marker the port writes, the single-row limit of the
existence read, the prompt wording of the credentials command (its read order is pinned by the flags
of the reads), the command's guard that an empty name never reaches the storage layer, the
blank-name rule this port reads differently from the reference's form, the absent enabled flag, the
Fever password the reference does not store, and the unique index on `fever_token`. The next slice
is the Google Reader and Fever routers.

Stage 4 — Ingestion & scheduling is pinned end to end (the per-feed refresh pipeline, the tick's
due-batch selection with the bounded worker pool, both modes of `ScheduleNextCheck` with the weekly
count the entry-frequency mode divides the week by, the two halves of the entry loop that write
nothing — an entry the document no longer declares and a tombstoned `(feed_id, hash)` pair — and the
icon finder. The selector half is the four `link` branches with the `data:` URL rules, and the
download half is the order the search tries, the response read as the icon bytes, the join for the
default icon, and the storage dedupe, link and orphan pass, and the checker half is the guard with
what it reads, the store and the link as two decisions that run on either branch, the path the guard
does not cover, and the user agent the checker hands to the builder. All three halves are pinned end
to end against the reference except the pool cap, which no test can assert without a timed wait, and
the rules the icon suite headers name as unpinnable — the checksum function, the size cap, the basis
the empty-body rule measures, the join escaping, the `external_id` randomness, the transaction
boundary, the join table this port does not have, and the reference logging that a swallowed checker
failure leaves no record for. The call the refresh path makes for that checker — the branch it runs
on, the fork the forced flag selects, the icon URL the parse produced, and the site URL and user
agent read from the row — is pinned by `RefreshIconTests`, and the manual pass the CLI makes over
the batch is pinned by `RefreshCommandTests`: each job of the batch runs once, the values reach it
from the environment, a failure is reported without stopping the rest, and the flag gates the
migrations the command runs, and the minimal `status --json` contract the soak reads is pinned by
`StatusSnapshotTests` and `StatusCommandTests`: each field is the value the row holds, an absent
stamp stays `null`, the rows are listed in id order, the counts read every row whatever its state,
`due` is the batch's pick, the environment values reach the totals through the command, and the flag
gates the migrations. The soak artifact landed with PR #35: the shell is its cadence, its checks
read the data each round leaves behind rather than the process that produced them, and each
check is shown to fail on the rule it names; the in-process cadence loop itself waits for
stage 6, and retention is pinned by `RetentionTests`).
Stage 4 keeps two open things: the icon image resizing, which needs a dependency that has not
been approved, and the cadence loop named above.
Stage 3 is merged, with its remaining findings in its stage-file backlog and every exit criterion
met: the two sanitizer HTML fixtures are read end to end against the reference's own output, which
took two insertion-mode rules the port had not modelled — `inCaptionIM`, and the mode the open stack
gives back to the element around a nested table when it closes — and both are pinned case by case by
`SanitizerTableModeTests`. Stage 2 is merged, and the exit criterion it deferred to the refresh path
is met by the pipeline. Keep this line and the plan's
status table in sync.

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
