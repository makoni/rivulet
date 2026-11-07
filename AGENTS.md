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

Current focus: **Stage 7 — Acceptance & hardening**, whose first slice is merged (PR #55): the
hostile bodies the fetcher cannot read as written — a stream that inflates far past the size it is
stored in, and a stream the decoder cannot finish — read as which limit answers. The body cap,
counted on the bytes the decoder produces as the reference's `MaxBytesReader` counts them, is the
only limit, because the ratio guard the port had of its own refused a body upstream would have read;
and the reduced 10k-entry scenario, pinned as the plan the schema answers for the hot unread
listing, the page the query is given, the relevance order the FTS index answers at the corpus size,
the batch the retention pass takes with the rows it leaves for the next run, and one wall-clock
bound the read path stays inside — 4 pins and 5 probes by `FetcherHostileInputTests`, 5 pins and 6
probes by `LargeFeedTests`, which is the reduced scenario the default CI job runs rather than the
gated 100k corpus. What those headers name as unpinnable: which parts the accumulator is given,
because no patch can change what the pipeline hands it, so the cap rule is read through the guard
being absent; the fixture encoder, checked against `gunzip` by hand; the memory budget, documented
because no pin reads memory; the numbers of another machine, which the timed pin reads as a bound
rather than as a measurement; the plan the planner chooses for a corpus of a different size; and the
category the reference gives a body it cannot inflate, which is the port's divergence recorded in
`docs/reference-notes.md`. The second slice is the security checklist, which opens as PR #56:
`docs/security.md` names for each of its sub-items — SSRF, the size and time caps, the auth
behavior, the sanitizer bypass surface, and the dependency audit — what the rule is, where the port
reads it, which test can fail on it, and what no test can show. 8 pins and 7 probes: the response
name that appears twice keeps the first value, as the reference's `Header.Get` reads it, which is
the finding closed in production code, with the same name written two ways counting as one name and
the first `Location` being the hop taken; the address policy running on the hop that took its client
from the cache, read as the seam's call count, because no answer on that hop can be refused through
the stub; the client cache staying at its cap after a checkout that goes over it, and the entry the
trim closes being the one whose expiry comes first, both read through an internal accessor, because
closing a client changes nothing a fetch can answer; the sign `strconv.Atoi` reads as part of the
number, so `width="+10"` is kept; and the entity table membership the sanitizer's scheme check reads
through, because the check runs on the decoded value. What the pass could not pin is documented
rather than asserted: the connect timeout as a limit of its own, which needs a client-creation seam
the plan does not have; the header-block size, which this port reads no limit of its own for
and which the reference caps only on the server side; the timing form of the constant-time
token compare; the NUL byte in a password, which the dependency measures with `strlen` and which
`docs/parity.md` records; and the header value of a hop that is not the last one, which `fetch` does
not return. The dependency audit found no advisory that affects a pin. The parity harness and the
client matrix follow, and the parity harness cannot run on this machine because the Docker daemon is
not reachable.

**Stage 6 — CLI & operations** is in progress with its eight slices merged; the deployment runbook
is the one exit criterion still open and it belongs to stage 8. Its first slice was the feed
commands `add`, `remove` and `list` (PR #47). The order the rule reads — the guard, then the
absolute-URL rule, then the duplicate read, then the category read — the url written as the command
read it, the category resolved from the named title or from the default, the account resolved from
`--user` or from the single account, the delete that applies the account it is given, and the
listing order with the lowercased title as the tiebreaker, are pinned by `FeedValidationTests`,
`FeedManagementReadsTests` and `FeedCommandTests`. What those headers name as unpinnable: the
single-row limit of the duplicate read, the order between the duplicate read and the category read
at the command level — a category name the command cannot resolve answers `0`, so the guard runs
first — the rows below the feed at the command level, which the read suite pins, the wording of the
lines and of the reported failures, and the rules the port names rather than the reference. The
command surface is recorded in `docs/parity.md`. The second slice is merged (PR #48): `backup` and
`vacuum` as runs, with the destination read as it was given, the copy as the snapshot at the run
rather than the bytes of the main file, the copy being a file of its own that does not change with
the source afterwards, a destination the command did not create reported rather than built or
overwritten and read against a row the pin writes after the control run, the file rebuilt without
losing a row, and the flag that gates the migrations, pinned by `MaintenanceCommandTests`, with the
storage rules these commands call pinned by `MaintenanceTests`. What that header names as
unpinnable: the truncating checkpoint the vacuum run ends with, because `RivuletApplication` runs a
best-effort one after every command; which file the environment names, which `ConfigTests` pin;
reusing an existing empty destination file; the size of the main file before the run, because the
checkpoint at the end of a run moves the rows from the WAL into it; the shape guards that read what
the pin built before the run, which bite only on the storage rules; the copy being a plain file with
no `-wal` beside it; that these commands fetch nothing and sleep nothing; the wording of the lines
and of the reported failures; and the rules the port names rather than the reference. The third
slice is merged (PR #49): `list` answers one listing per run, with the flag naming which read the
run makes, no flag still meaning the feeds, the pair of flags reported as the rule the port names
rather than picked, the account the run resolves reaching the category read and not the account
read, the line carrying the stored position and the stored admin flag rather than the schema
default, one line carrying one row, the run writing nothing, and the title order being the port's
byte order, pinned by `ListingCommandTests` over the in-process console, with the two orders it
reads pinned as reads by `CategoryRepositoryTests` and `UserRepositoryTests`. What that header names
as unpinnable: the wording of the lines and of the reported failures apart from the values the pins
read off a line and the rule name the run writes; a flag the command does not know, which the
command-signature parser rejects before the command runs; which fields a line carries and their
order on the line; the header line, read only as the one line that is not a row; the `position`
column, which is the port's own and recorded in `docs/parity.md`; the guards that read what the pin
built before the run, which bite only on the storage rules; the single-row limit of the reads; the
account resolution, which `FeedCommandTests` pin; the flag that gates the migrations; that these
commands fetch nothing and sleep nothing; and the collation the reference's Postgres answers `ORDER
BY title` with, which this port cannot have. The shape is flags because `@Argument` has no default,
so a run cannot name an optional listing. The fourth slice is merged (PR #50): the in-process
cadence loop, pinned as the calls the loop makes through its seam — the wait before the first read,
which is the reference's shape, the interval the loop was built with on every wait, one read per
wait, the instant the clock gives at each read, the reported failing read with the loop going on,
the empty read reported as nothing, nothing read after the seam answers stop, and the jobs of a tick
before the next read, which is the port's shape — by `CadenceLoopTests` through test seams that
record each call. What that header names as unpinnable: that any time passes, since the seam stands
in for a sleep; the number of iterations, which is the answer the seam gives; the order the jobs of
one tick are recorded in, which concurrency does not fix, so the pins read the calls across the tick
boundary; the shape and the field names of a report, which are the port's choice; that the
reference's ticker goroutine has no stop rule at all, so the stop answer is the port's own, recorded
in `docs/parity.md`; the reference's second ticker for the cleanup tasks, which this port has no
loop for and which `RetentionTests` pin as storage rules; the pool cap; the real seam
implementation, which sleeps, so its decisions are read through test seams that name the interval as
zero (`SystemCadenceTests`) and its real signal source lands with the process harness. The fifth
slice is merged (PR #51): the process harness (`Support/SpawnedProcess.swift`) reads the built
binary as the events it answers — the port the serve event reports, the response a request on that
port gets, the exit code the clean signal path leaves (0, which is the reference's clean-stop exit),
and the WAL the run's shutdown leaves empty — pinned by `ServeProcessTests`, with the wiring that
runs the loop to its end and the hook once after it pinned as the calls it makes through its seams
by `ServeWiringTests`. What those headers name as unpinnable: the harness rules themselves — waits
that answer on an event, the probed port, the child killed on both paths, and the line the harness
reads as the serve event, from which a pin reads only the port value; that the child exits at all,
because a patch that made the child never exit hangs a pin rather than flipping what it reads, while
a child that writes no line fails the pin through the harness; which part of the shutdown emptied
the WAL, because a clean close checkpoints on its own; which line is the serve event and its
wording; the order the two paths of the decision answer on, which no in-process test can read
either; the answer belonging to the decision the path was created for, and a cancelled wait
answering only its own wait, which bite only inside the child across two decisions; the reference's
HTTP servers being shut down before the pool, which this port has no piece for; `SIGHUP`, which the
reference feeds to a certificate reload and which is not ported; and the reference's log lines,
which have no layer here. The sixth slice is merged (PR #52): the free-space check the `backup` run
makes at its start, read as the decision the rule answers through the `FileSystemSpace` seam — the
estimate as the bytes the source holds as the filesystem reads them, times the factor the stage-1
note documents for `VACUUM INTO` (2), the bytes the WAL holds counted, the room read at the
directory the destination is in and as the current directory for a destination named as a bare name,
the comparison read as strictly less, a size the filesystem cannot read counting as nothing, and a
room it cannot read answering a refusal — pinned by `FreeSpaceCheckTests`, and as what the run does
with that decision by three pins in `MaintenanceCommandTests`: the refusal with nothing written, the
copy written at the boundary the rule reads as equal, and no room read at all for the vacuum run.
What those headers name as unpinnable: the numbers a real filesystem reports, which the seam answers
in place of the machine, so the room it answers is never read here; the two answers of that
implementation a test can name without the machine — nothing for a path it cannot read, and the
bytes it holds for a file the test writes — are pinned by `SystemFileSystemSpaceTests`; the factor
the copy would truly need, which is the documented choice of the port rather than a fact about
SQLite; that the check runs before the migrations, which nothing in the run answers, so the pins
read only that it ran before the write, and not the order between the check and the destination
rules, which no pin reads; and the wording of the reported failure. `vacuum` is not checked, because
it rebuilds the file it already holds rather than writing a copy beside it, and `Vacuum` carries the
filesystem it does not read so that pin can fail on a patch that reads the room there. The seventh
slice is merged (PR #53): `--force` as the flag the `backup` run reads, pinned what the run replaces
— the file the destination names, read as the filesystem reads the path rather than as a database
the run can open, a directory reported rather than deleted, the flag not skipping the room check, a
run that cannot hold the copy removing nothing, and the flag not building the directory the storage
layer needs — 5 pins and 8 probes by `BackupForceTests`. What that header names as unpinnable: an
empty destination file, which the flag path replaces and the no-flag path reuses with the same
answer, the type guard's other branches, and the shape guard that reads the row the pin wrote after
the control run, which bites only on the storage rules. No environment flag is ported for the
account path: the reference's CLI reads the environment through its config parser, but the only name
it reads there that resolves an account is `ADMIN_USERNAME` for `create-admin` — `METRICS_USERNAME`
is basic auth for the metrics endpoint, not an account — and nothing there resolves an account for a
command, so there is no read to mirror; the port's `--user` with the single-account fallback stays
the rule. The eighth slice is merged (PR #54): `--verify` as the call the run makes through the
`DatabaseVerifier` seam — that the run calls the seam nothing without the flag, that it makes the
one call for the destination as the run read it and after the write, that it reports the failure the
seam answers with and leaves the copy as written, that the flag does not change the room check, and
that it does not build the directory the storage layer needs — 5 pins and 9 probes by
`BackupVerifyTests`, plus 4 pins and 6 probes by `SystemDatabaseVerifierTests`, which reads what the
implementation answers for a real file: the clean answer, the problems the damaged copy has, the
file left as the bytes the storage rule wrote, and the failure reported for a path the check cannot
open rather than the clean answer. What those headers name as unpinnable: the problems of a real
file, which the seam answers in place of the machine, and the connection the check opens, which no
patch can show because the command has no other connection to read through.

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
shown to fail on the rule it names; the in-process cadence loop landed with stage 6 as PR #50, read
as the calls the loop makes through its seam, and retention is pinned by `RetentionTests`). Stage 4
keeps one open thing: the icon image resizing, which needs a dependency that has not been approved.
Stage 3 is merged, with its remaining findings in its stage-file backlog and every exit criterion
met: the two sanitizer HTML fixtures are read end to end against the reference's own output, which
took two insertion-mode rules the port had not modelled — `inCaptionIM`, and the mode the open stack
gives back to the element around a nested table when it closes — and both are pinned case by case by
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
- Wrapping: prose and comments wrap at ≤100 columns, breaking at word boundaries. Two things are
exempt because neither can be broken without changing what it says: a Markdown table row, and an
inline code span longer than the width, which stays whole on its own line. Code lines are single
expressions and are not split to meet the width. A commit that only rewraps does not change
behavior, so it does not reopen a review that already approved the words.
- Prefer the standard library and existing dependencies. `swift-collections` (`Deque`,
`OrderedDictionary`, …), `swift-algorithms` and `swift-crypto` (SHA-256, MD5) are pre-approved when
they make data structures, algorithms or hashing clearer or more efficient — add them as direct
dependencies of the module that uses them when first used (they are already in the dependency graph
via Vapor; `RivuletCore` must not depend on Vapor itself). Any other new dependency needs explicit
approval — Linux-first, keep the surface small.
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

