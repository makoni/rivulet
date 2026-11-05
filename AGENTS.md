# AGENTS.md — working agreement for Rivulet

This file is for AI agents (and humans) making changes to this repository.

## What this project is

Rivulet is a lightweight self-hosted feed reader: a Swift port of
[Miniflux](https://github.com/miniflux/v2) (behavioral reference: v2.3.3), with SQLite storage, a
CLI-first interface and no web UI.

## Read before working

1. `docs/plan/README.md` — stages, status, definition of done. 2. The stage file for the current
work (`docs/plan/stage-N-*.md`). 3. `docs/reference-notes.md` — verified Miniflux behavior
(scheduling, auth, endpoints, retention). Re-check the clone when in doubt. 4.
`docs/architecture.md` and `docs/testing.md`.

Current focus: **Stage 6 — CLI & operations**, with its first slice merged: the feed commands `add`,
`remove` and `list` (PR #47). The order the rule reads — the guard, then the absolute-URL rule, then
the duplicate read, then the category read — the url written as the command read it, the category
resolved from the named title or from the default, the account resolved from `--user` or from the
single account, the delete that applies the account it is given, and the listing order with the
lowercased title as the tiebreaker, are pinned by `FeedValidationTests`, `FeedManagementReadsTests`
and `FeedCommandTests`. What those headers name as unpinnable: the single-row limit of the duplicate
read, the order between the duplicate read and the category read at the command level — a category
name the command cannot resolve answers `0`, so the guard runs first — the rows below the feed at
the command level, which the read suite pins, the wording of the lines and of the reported failures,
and the rules the port names rather than the reference. The command surface is recorded in
`docs/parity.md`. The second slice lands as PR #48: `backup` and `vacuum` as runs, with the
destination read as it was given, the copy as the snapshot at the run rather than the bytes of the
main file, the copy being a file of its own that does not change with the source afterwards, a
destination the command did not create reported rather than built or overwritten, the file rebuilt
without losing a row, and the flag that gates the migrations, pinned by `MaintenanceCommandTests`,
with the storage rules these commands call pinned by `MaintenanceTests`. What that header names as
unpinnable: the truncating checkpoint the vacuum run ends with, because `RivuletApplication` runs a
best-effort one after every command; which file the environment names, which `ConfigTests` pin;
reusing an existing empty destination file; the size of the main file before the run, because the
checkpoint at the end of a run moves the rows from the WAL into it; and the wording of the lines.
`list` for categories and users, the flag polish and the process-level checks follow.

Stage 5 is in progress, with its first two slices merged: `create-admin` with the user rules and the
bcrypt hasher (PR #38), and `integration-credentials` with the Fever token derivation and the
duplicate-name rules (PR #39). For the second slice the join, the lowercase hex form, the parts read
as given, the order the two duplicate checks are read in, the guard inside the rule function that an
empty name is not read against the answer, the per-user exclusion, the values compared as read, each
check reading its own column, and the rule that a blank password read keeps the stored value are
pinned by `FeverTokenTests`, `IntegrationValidationTests`, `UserRepositoryTests` and
`IntegrationCredentialsTests`; for the first slice the rule order, the character class read per
Unicode scalar, the byte-counted minimum, the existence read that runs before any rule, the secure
read and the trim, and the flag that gates the migrations are pinned by `UserValidationTests` and
`CreateAdminTests`, and the reference cost, the 72-byte rule and the marker direction by
`BcryptHasherTests`. What those pins cannot show is named in the suite headers — the locale wording,
the terminal check, the environment path, which marker the port writes, the single-row limit of the
existence read, the prompt wording of the credentials command (its read order is pinned by the flags
of the reads), the command's guard that an empty name never reaches the storage layer, the
blank-name rule this port reads differently from the reference's form, the absent enabled flag, the
Fever password the reference does not store, and the unique index on `fever_token`. The storage
reads the routers are built on landed with PR #40 and are pinned by `ClientAuthTests`: the Fever
lookup lowercases both sides, the Google Reader read compares the name as read, both answer nothing
when no row matches, and the control pin shows that the account lookup lowercases what it is given
while this read does not. What that suite cannot show is named in its header — the `*_enabled` gate,
the single-row limit, the bcrypt compare, the Google read's error wording upstream, the empty-string
default upstream's columns carry, and `LOWER` on SQLite being ASCII-only. The Google Reader auth
path merged with PR #41: the login's own field names, the text shape by default and the JSON shape
only when `output` says `json`, the compare against the stored value, the guard that an empty name
ends the login before the read, the transport chosen by method, the merged form with Go's order, the
header read as `strings.Fields` splits it, the three headers the response builder writes on every
response of this path, the structure rule and the two 401 shapes are pinned by
`GoogleReaderAuthTests` over a real socket, with the derivation and the JSON write pinned against
the reference's own output by `GoogleReaderTokenTests` and `JSONValueTests`, and the port's answer
for the path without the trailing slash pinned as a divergence; the timing form of the compare, the
guard's password half and the one-part structure are named as unpinnable in that header, as are the
mux rules the router piece brings. The contract rules those routers read merged with PR #42, as pure
logic with no HTTP: the four item-id forms with the `fmt.Sscanf` `%016x` rules and the error
wordings — including the space the scan skips before the field, the newline it does not skip, and
the read per Unicode scalar — the stream branches with the two forms of each prefix as an OR and the
seven suffixes, the query read with the pair it skips for a `;` or a bad escape, the bounds check
that runs before the two characters of an escape are read, and the order the pairs answer in, and
the parameter reads with the order read, the list read's trim as Go's `unicode.IsSpace` and its skip
of an empty value, and the continuation rule, are pinned by `GoogleReaderItemIDTests`,
`GoogleReaderStreamTests`, `GoogleReaderQueryTests` and `GoogleReaderRequestModifiersTests`. What
those headers name as unpinnable: the count `fmt.Sscanf` reports, the order the two stream prefixes
are removed in, the error `r.URL.Query()` discards, the `WithOffset` branch the parameter read never
reaches, the platform reading `bitSize 0` as 64 bits, and which count the continuation rule is
given, because that is the handler's choice. The form read reports a pair error for the whole form
while the query read skips that pair, which is `r.URL.Query()`; both are recorded in the code
comment.

PR #43 merged the rules the handlers read, still as pure logic with no HTTP: the tag read with the
add loop before the remove loop, the value each branch writes for `read`, `kept-unread` and
`starred` — the other way round for the remove loop — the two wordings that name different things,
and the branches that write nothing and are not the unsupported error; the output read, where the
method decides which side is read and only the value `json` passes, compared as the read gives it;
and the document shapes with the `omitempty` rule, the continuation written as a string and omitted
when it is 0, and the empty list written as `[]` because the reference builds the slice with `make`
— are pinned by `GoogleReaderTagsTests`, `GoogleReaderOutputTests` and `GoogleReaderShapeTests`.
What those headers name as unpinnable: the guard inside the add loop, which asks for the map key
that loop never writes so it can never fire, the guard that an empty add and an empty remove answer
the reference's own wording, which the handler suite now pins over a socket, and which document a
handler builds, which stays the handler's choice. PR #44 merged the handlers for the four endpoints
this piece implements — `edit-tag`, `tag/list`, `user-info` and `stream/items/ids` — over a real
socket: the subpath wildcard with the exact registered path winning for its method, the row id the
auth read hands the handler, which endpoints apply the output check, `edit-tag` reading `a` and `r`
from the body and `i` from the merged form, the storage values the tag branches write, the handler
order that reports the tag error before the item read, the status each error answer writes, the
branch switch with the two ways it reads the same exclude name and the feed filter that only a
positive parsed value applies, the two times every branch applies, the order the parameter read
answers, the continuation rule with the count the handler gives it, and the page-size clamp, are
pinned by `GoogleReaderHandlerTests`, with the status mapping pinned directly by
`GoogleReaderResponseStatusTests` and the storage reads the handlers use pinned by
`EntryQueryTests`, `CategoryRepositoryTests` and `ClientAuthTests`. What that header names as
unpinnable: the user-info guard that a row found by auth is read back, the handler's own answer for
a form the read cannot parse, which the transport reports as 401 first, the order of the two storage
write sets, which are disjoint for every input that reaches them, the integration settings the
reference reads after the write, a storage-layer failure this suite cannot trigger, and the method
mismatch, where the reference answers 405 and this port answers Vapor's 404, recorded in
`docs/parity.md`. PR #45 merged the three POST write handlers of this path over the same socket: the
list `s` the merged form gives `disable-tag`, the parameter name the read error names, which is the
handler's own wrap rather than the stream read's wording, the guard order that runs the type check
before the empty-destination guard, the two type-check wordings that name different things, the 404
the category read answers for a title it does not find, the rule order that reads the row before the
duplicate answer and writes after it with the duplicate read's exclusion of the row it is checking,
the delete guard that counts before any write and the pick it makes for the feeds of the rows it
names, the switch with three cases so the stream types it does not handle answer `OK` writing
nothing, the status the integer read maps to here — 400 where the same read answers 500 for
`stream/items/ids` — and the `ts` length rule with its two units, the sign guard's presence, the
default that is the time the handler runs at, and the comparison that is strictly before, are pinned
by `GoogleReaderWriteHandlerTests`, with the storage reads it uses pinned by
`CategoryRepositoryTests` and the `ts` rule as pure logic by `GoogleReaderTimestampTests`; the
integer read's wordings are written once in `GoParseInt`, which the three call sites of this path
read from. What that header names as unpinnable: the transaction boundary the delete path runs
inside, the row order the delete's read answers its rows in, which the statement does not order, the
rule that a feed id of 0 selects nothing, the message the handler writes for the rule the socket
cannot reach, the reference's localized strings for the two category rules — the port names the
rule, so the answer is the rule name, and the keys are recorded in `docs/reference-notes.md` — the
order of the two statements of the delete path, and the order of the sign guard and the `ts` length
test, which no input can tell apart because both apply to every value the guard accepts. PR #46
merged `stream/items/contents` over the same socket: the order the handler runs in — the output
check, the form read, the stream read, then the item ids — with the order parameter read from the
URL query alone, so the same name in a POST body is not read here; the storage read with the two
titles read from two different rows and the site url read from the feed row; the three time columns,
with the two string forms built by multiplying those whole seconds; the document author as the
account name against the entry author the item writes; the document `id` as the generic prefix while
the categories carry the row number; `self` as the configured base URL rather than the host the
request came in on; the item id in the full reference form; and the answer carrying every row the
ids name, are pinned by `GoogleReaderContentHandlerTests`, with the read pinned by
`EntryContentsReadTests` and the categories rule for one item by `GoogleReaderItemCategoriesTests`.
What that header names as unpinnable: the page size, because this port's read for this endpoint has
no `LIMIT` clause at all, as the reference's `fetchEntries` has none; the media proxy, which this
port does not have and which `docs/parity.md` records; the inner join on categories, which this
port's schema cannot leave unfulfilled; and the order of the two statements that build the
attachments. What follows: the Fever parameter set, `quickadd` discovery, the icon route, OPML and
the acceptance journey.

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
read the data each round leaves behind rather than the process that produced them, and each check is
shown to fail on the rule it names; the in-process cadence loop itself waits for stage 6, and
retention is pinned by `RetentionTests`). Stage 4 keeps two open things: the icon image resizing,
which needs a dependency that has not been approved, and the cadence loop named above. Stage 3 is
merged, with its remaining findings in its stage-file backlog and every exit criterion met: the two
sanitizer HTML fixtures are read end to end against the reference's own output, which took two
insertion-mode rules the port had not modelled — `inCaptionIM`, and the mode the open stack gives
back to the element around a nested table when it closes — and both are pinned case by case by
`SanitizerTableModeTests`. Stage 2 is merged, and the exit criterion it deferred to the refresh path
is met by the pipeline. Keep this line and the plan's status table in sync.

## Toolchain

- Use the latest Swift release installed on the system (currently 6.4.1). Do not target old
  toolchains or work around modern Swift; prefer current stdlib and Concurrency features.
- CI is GitHub Actions on `ubuntu-latest` with the `swift:latest` container (see
  `.github/workflows/ci.yml`).

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

- Documentation and tutorials are a project deliverable, not an afterthought. We will collect them
  with DocC and publish them later (planned: GitHub Pages, wired up in stage 8).
- Every public API gets a DocC documentation comment.
- DocC catalogs live next to the code (`Sources/RivuletCore/RivuletCore.docc/`, later also for the
  executable): articles for concepts, tutorials for key workflows (setup, feeds, clients,
  deployment).
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
- Wrapping: prose and comments wrap at ≤100 columns, breaking at word boundaries. Two things are
  exempt because neither can be broken without changing what it says: a Markdown table row, and an
  inline code span longer than the width, which stays whole on its own line. Code lines are single
  expressions and are not split to meet the width. A commit that only rewraps does not change
  behavior, so it does not reopen a review that already approved the words.
- Prefer the standard library and existing dependencies. `swift-collections` (`Deque`,
  `OrderedDictionary`, …), `swift-algorithms` and `swift-crypto` (SHA-256, MD5) are pre-approved
  when they make data structures, algorithms or hashing clearer or more efficient — add them as
  direct dependencies of the module that uses them when first used (they are already in the
  dependency graph via Vapor; `RivuletCore` must not depend on Vapor itself). Any other new
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
  `// Ported from Miniflux <path> (Apache-2.0); adapted for Swift/SQLite.` Ported tests keep a
  comment with the original test name.
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

- Small, focused commits with imperative subjects; mention the stage when relevant:
  `stage-2: support conditional GET with ETag`.
- Behavior + its tests + doc updates land in the same commit.
- Never commit generated artifacts (`.build/`, `.docc-build/`, database files, secrets) — see
  `.gitignore`.

## Safety

- The HTML sanitizer is security-critical: never relax allowlists to make a test pass; when in
  doubt, port Miniflux behavior.
- Respect size and time limits in the fetcher; never disable SSRF protections by default.
- No secrets, tokens or personal feed lists in the repository or in fixtures.
