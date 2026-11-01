# Stage 4 — Ingestion & scheduling

**Goal:** unattended refresh loop; parsed entries land in the database correctly.
**Status:** in progress — nine slices merged (PR #25–#33): the pipeline, the tick's batch selection
with the worker pool, the entry-frequency mode with the weekly count, what the entry loop does not
write, the icon selector with the data-URL rules, the icon download half with the storage link and
the orphan pass, the checker half with the guard and the storage decisions, the call that path
makes for a feed from the pipeline, and the manual pass the CLI makes over the batch — the values
it reads, each job running once, a failure reported without stopping the rest, and the flag that
gates the migrations this command runs.
**Effort:** M. **Depends on:** Stage 3 and Stage 1.

The first slice is the per-feed refresh pipeline and the round-robin half of `ScheduleNextCheck`:
the user-scoped lookup, the check stamp and the site-URL fallback, the schedule fixed before the
request, the fetch, the `429` reschedule, the failure and the conditional-hit paths, the entry loop
with the cleaner and the sanitizer, and the injected `Clock` seam, pinned end to end against the
reference by `RefreshPipelineTests` and `NextCheckPolicyTests`. It also closes the stage 2 criterion
that was deferred to the refresh path: the pipeline is the caller that stores the validators and the
error state. The second slice is the tick's due-batch selection and the bounded worker pool: the
builder's rules pinned through the repository, the pool running each selected job once, one failing
job not stopping the rest, and the non-forced path the worker takes, pinned by `SchedulerBatchTests`
and `SchedulerTickTests`. The cadence loop is not here — nothing can pin a sleeping loop — and lands
with `rivulet serve`; tests drive the scheduler with explicit `tick()` calls. The entry-frequency
mode and the weekly count it divides the week by landed as PR #27, pinned by `WeeklyEntryCountTests`
and read through the pipeline by `EntryFrequencyPipelineTests`. The fourth slice is what the entry
loop does not write: an entry the parsed document no longer declares stays in place with the state
it had, and a tombstoned `(feed_id, hash)` pair is refused by the insert guard on the forced path,
pinned by `PipelineMergeAndTombstoneTests`. The fifth slice is the half of the icon finder that
reads no network: which `link` elements a document offers, and how a `data:` URL is read, pinned by
`IconDocumentLinksTests` and `IconDataURLTests`. The seventh slice is the checker, the wiring that
runs the search for one stored feed: the guard, which reads the mapping for this feed rather than
the
icon table, the store and the link as two decisions that run on either branch, the path the guard
does
not cover, and the user agent the checker hands to the builder, pinned by `IconCheckerTests`. The
eighth slice is the call that path makes for a feed from the pipeline: the branch it runs on, the
fork the forced flag selects, the icon URL the parse produced, and the site URL and the user agent
read from the row, pinned by `RefreshIconTests`. The ninth slice is the manual pass the CLI
makes over the batch: one read, each job run once through the worker's path, the failure
reported without stopping the rest, the values read from the environment, and the flag gating
the migrations this command runs, pinned by `RefreshCommandTests`. The soak artifact follows;
retention is already pinned by `RetentionTests`. The status stays in progress until the exit
criteria below cover the whole stage.

## Scope

- [x] Refresh pipeline per feed: fetch → parse → normalize → sanitize → merge → store in one
      write transaction, then update feed state. Landed as PR #25; the transaction boundary
      itself is what no test can pin, so it is stated in `docs/parity.md`.
- [x] Merge semantics: new entries inserted; changed entries only update content — user
      state (read/starred) is never touched; entries missing upstream are kept locally. The
      upsert half is pinned in stage 1, where status and starred survive an update, and the
      pipeline pins the branch that updates a known entry and that a second identical
      refresh writes nothing. The upstream-removed half is pinned by
      `PipelineMergeAndTombstoneTests`: the row the document no longer declares stays, and a
      patch that deletes the feed's rows not in the parsed document fails that pin. The
      status read there is the one the case seeded, so the pin shows the row survived, not
      that an update left user state alone.
- [ ] Icon finder: the selector half is pinned by PR #29 — the four `link` branches, which of them
      fold case, the href rules, document order, and the `data:` URL shape with its three encodings.
      The download half is pinned by PR #30: the order the search tries, the first success stopping
      it, the skipped failures against the last step's failure, the response read as bytes with the
      status rule before the empty-body rule, the join for the default icon, the dedupe by hash, the
      content type compared as the whole value, the link replacing what the feed row had, and the
      orphan pass. The checker half is pinned by PR #31: the guard, which reads the mapping for this
      feed rather than the icon table, the store and the link as two decisions that run on either
      branch, the path the guard does not cover, and the user agent the checker hands to the
      builder. The call the checker makes for a feed from the pipeline is pinned by
      `RefreshIconTests`: the branch that runs it, the fork the forced flag selects, the icon
      URL the parse produced, and the site URL and user agent read from the row. The cadence
      loop that calls the pipeline per feed is not pinnable — nothing can pin a sleeping loop —
      and the manual `rivulet refresh` path is pinned by `RefreshCommandTests`: each job of the
      batch runs once, the values are read from the environment, a failure is reported without
      stopping the rest, and the flag gates the migrations this command runs. Image resizing is not
      ported, because it needs an image-decoding dependency that has not been approved, so the
      deviation is recorded in `docs/parity.md`, as is the SVG minifier.

## Implementation notes

- Reference: `internal/cli/scheduler.go` (tick loop), `internal/model/feed.go`
  (`ScheduleNextCheck`), `internal/storage/batch.go` (due-set query),
  `internal/reader/handler/handler.go` (refresh delay from TTL/headers).
- Icon half: `internal/reader/icon/finder.go` (the selector, the data URL, the download, the order
  and the join), `internal/reader/icon/checker.go` (the per-feed wiring: the guard, the store and
  the
  link, and the user agent the reference hands to the builder, which this port takes as an argument;
  the cookie, timeout, proxy, TLS and HTTP2 half of that builder is documented as deferred, and the
  proxy decision belongs to the feed row, so no request the search builds carries one),
  `internal/storage/icon.go` (store, dedupe by hash, orphan cleanup). The scan reads through the
  port's tokenizer subset, which
  is the precedent stage 3 set for the sanitizer, rather than building a document tree.
- No external cron: the scheduler runs in-process inside `rivulet serve`.
- Target: refreshing a 100-feed database must not block API reads (WAL + short write
  transactions).

## Tests

### Unit

- Merge decisions: new / updated / unchanged / upstream-removed / tombstoned.
- Interval selection: round-robin and entry-frequency modes, clamps, `refreshDelay` from TTL and
  HTTP headers. The reference defaults of the tick values are pinned in `SchedulerOptionsTests`;
  the three rules that read a zero as a switch are pinned in the batch suite — the error limit, the
  batch size and the host limit — because a switch is only observable through the query it writes
  or the rows it scans; the mode, its clamps, the zero count and the weekly count the mode divides
  the week by are pinned in `NextCheckPolicyTests` and `WeeklyEntryCountTests`, and the count
  reaching the schedule through the pipeline is pinned by `EntryFrequencyPipelineTests`.
- Icon selection: the four `link` branches — only the three `icon` ones fold case, and a `rel` is
  compared as a whole value — the href rules, document order, and the two tokenizer facts the
  reference's tree agrees with for the cases here: content inside a raw-text element is text, and
  the self-closing token kind is read as an element. The charset layer, the escaped path and the
  tokenizer's lowercasing and value decoding are pinned as rules the icon scan reads through. The
  `data:` URL shape and its three encodings are pinned by `IconDataURLTests`, including Go's `.`
  production, which excludes a newline from the data part, and that the checksum is taken over the
  decoded bytes. The selector's test that the `href` attribute is present at all is not pinnable in
  this port, as the suite header states.

### Integration

- End-to-end (stub server + temp database): initial refresh stores N entries; a second refresh
  answering `304` stores nothing new. Pinned by the first slice.
- Feed updated upstream → new entries added, existing read state preserved.
- Entry removed upstream → it stays locally; a deleted + tombstoned entry is never re-inserted.
  Both halves are pinned by `PipelineMergeAndTombstoneTests`, which reads the rows through its own
  checkout and runs the archive inside `withTransaction`, because the delete and the tombstone
  insert are one atomic step only there.
- Fetch error → error counter increments; at the limit the feed is excluded from ticks; a forced
  refresh resets it. The increment and both resets are pinned by the first slice; the exclusion is
  the batch query, pinned by PR #26.
- A scheduler tick refreshes only due feeds (others untouched). Pinned by `SchedulerTickTests`:
  the pool is handed exactly the jobs the batch answered with, and the control rows — not due,
  disabled, at the limit — reach no run. The pool-size cap itself is not pinned, as the suite
  header states, and the completion order is not asserted because concurrency does not fix it.
- The checker for one stored feed: the guard and what it reads, the store and the link as two
  decisions that run on either branch, the path the guard does not cover, and the user agent the
  checker hands to the builder. Pinned by `IconCheckerTests`.
- The call that path makes for a feed from the pipeline: only the modified branch runs it, the
  forced flag selects which half runs, and the checker is built from the row's site URL and user
  agent with the icon URL the parse produced. Pinned by `RefreshIconTests`; the order of the writes
  inside the transaction, which is the reference's order here, is what no pin can show.
- The manual pass the CLI makes over the batch: each job of the batch run once, the control rows
  untouched, the values read from the environment, a job that fails reported without stopping the
  rest, the schedule the run left, and the flag that gates the migrations this command runs. Pinned
  by `RefreshCommandTests`; the cadence and the pool cap are named as unpinnable in the suite
  header, and the reference's check that the schema is up to date is not ported.
- Retention deletes only expired entries (boundary cases) and writes tombstones, pinned by
  `RetentionTests`.

## Exit criteria

- [ ] Soak artifact: `Scripts/soak.sh` runs ≥ 2h with ≥ 20 local stub feeds; `status --json`
      snapshots (stage 4 ships the minimal feed-state `status --json`; stage 6 extends it) show
      `fetched_at`/`next_check_at` advancing with no crashes; log excerpt attached to the stage
      status.

Findings from the review runs on PR #25 that do not change behavior:
- `recordFetch` and `recordParsingError` are keyed by the feed id, where the reference's statements
  add `WHERE user_id`; the pipeline resolves the user-scoped row before calling them, so the write
  is scoped in practice, and no pin can show the difference.
- The port reads the clock once per refresh, where the reference calls `time.Now()` twice, once in
  `CheckedNow` and once in `ScheduleNextCheck`; an injected clock answers one instant, so no pin can
  tell the two reads apart.
- The conditional-hit pin reads the half where the response carries a `Last-Modified`; the reference
  keeps the stored value when the header is empty, and no case here has an empty one.
- The pipeline's invalid-URL branch is recorded but not pinned, and the reference records another
  class there: the fetcher's own error from the request. The guard the icon path reads is pinned by
  PR #30, where the reference's builder checks nothing and fails at the client instead, and where
  `IsAbsoluteURL` compares the prefix as read rather than lower-casing the scheme.
- The single write transaction spans the HTTP fetch, which the reference's does not, and the
  transaction boundary itself is what no test here can pin.
- `docs/parity.md` says the cache lifetime is read as minutes, which is true of `<ttl>`; the policy
  compares the three delay sources as durations, so the row should separate the read from the
  comparison.


## Backlog

Findings from review run 1 on PR #26 that do not change behavior:
- `JobQueue` is a second type in `Scheduler.swift`, whose primary type is `Scheduler`; the one
  primary type per file rule asks to split it when the file grows.
- The due pins read a stored schedule of 2061 against an injected instant of 2065; both are after
  the process clock, which is what makes the injected clock distinguishable, and that argument stops
  holding after 2061.

Findings from review run 1 on PR #28 that do not change behavior: - `EntryRepository.archive`
returns the number of rows it deleted, where `ArchiveEntries` returns the number of rows it
inserted into `entry_tombstones`; the two disagree for a skipped empty hash and for a `(feed_id,
hash)` conflict. The pins cannot show it, and a live entry can never have a tombstone, so in
practice the counts agree.
Findings from review run 1 on PR #29 that do not change behavior:
- Two upstream cases are not ported: `TestFindIconURLsFromHTMLDocument_InvalidHTML`, where an
  unclosed tag lets the attribute-value state swallow the rest of the document, which no case here
  reads, and `TestFindIconURLsFromHTMLDocument_EmptyDocument`.
- The reference folds the selector's `i` flag and the attribute names with an ASCII-only lowering,
  while the port uses Swift's `lowercased()`, which maps Unicode. The two agree for every value
  these pins read, so the boundary is recorded here rather than pinned.

Findings from review run 1 on PR #30 that do not change behavior:
- The size cap is pinned only by the fetch suite: no icon case reads a body past the cap, as the
  fetcher applies it before this layer sees the bytes.
- The reference's `findIcon` can continue when a step answers with no icon and no error, which
  is its resize path for an oversized image; this port has no case that answers without an
  icon, which follows from resizing not being ported.
- The icon reads the reference has for the checker — `HasFeedIcon`, `IconByExternalID`, `Icons`
  — were not ported with PR #30, because the checker that calls them was not. `HasFeedIcon` landed
  with PR #31 as the guard's read; `IconByExternalID` was already there from stage 1 as
  `IconRepository.fetch(externalID:)`, and `Icons` is still unported, because nothing reads it until
  the stage that shows an icon.

Findings from review run 1 on PR #31 that do not change behavior:
- The guard read cannot show that a read which fails answers the same as a read that finds nothing,
  and the mechanism it reads through — the feed row rather than the join table the reference has —
  is
  recorded in `docs/parity.md`; the pins name the decision, not the mechanism.
- The user-agent pin names only that the checker hands the feed's value to the builder; which value
  wins when the feed row carries none is the fetch suite's rule, pinned in `FetchRequestTests`.
- The run proposed splitting `store` as a long function; the length rule in `AGENTS.md` is an aim
  rather than a check CI runs, and `store` is seven lines, so there is nothing to split.

Findings from review run 1 on PR #32 that do not change behavior:
- The parse-icon pin first gave the scan path nothing to answer from, so its "not the one the scan
  finds" half could not fail on the rule it named; the case now answers the scan path with different
  bytes, and the conditional-hit case gives the scan a document it could have answered from, so the
  absence of the request, the row and the mapping are all falsifiable.
- A pin that names the conditional-hit branch must reach the reference's conditional hit, so the
  case answers `304` against the validator the row holds rather than a `200` whose `ETag` matches.
- The pin that reads the site URL names a host the stub server does not answer for, which is what
  makes a request on the row's path show which value the checker was given.
- `RefreshPipelineTests` said its pins read the icon row; no assertion there reads it, so the header
  now names the icon rules as outside that suite.
- The position of the call inside the transaction is recorded as the reference's order rather than
  presented as a pinned rule, and `RefreshFeed` assigns the parsed icon URL to the model it read,
  not to a stored column; run 2 found the same wording in the pipeline's comment on this branch,
  which is folded into this commit.
