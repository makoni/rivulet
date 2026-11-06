# Stage 6 — CLI & operations

**Goal:** everything is manageable without touching the database or a web UI.
**Status:** in progress — the first slice, the feed commands `add`, `remove` and `list`, is merged
(PR #47). The second slice, the maintenance commands `backup` and `vacuum`, is merged (PR #48). The
third slice, `list` for the categories and the accounts, is merged (PR #49). The fourth slice, the
in-process cadence loop through the `Cadence` seam, is merged (PR #50). The fifth slice, the process
harness with the signal seam and the wiring `serve` runs, is open as PR #51.
**Effort:** M. **Depends on:** Stages 1–5.

## Scope

- [x] `add`, `remove` and `list` for the feeds landed with PR #47: the rule the reference's feed
      validator reads, the duplicate read, the category read, the delete that applies the account,
      and the listing order, with the account the command works for resolved from `--user` or from
      the single account. The flag polish and the process-level checks follow.
- [x] `list` for the categories and the accounts landed with PR #49 as runs through the in-process
      console: the flag names which read the run makes, no flag still means the feeds,
      the pair of flags is reported as the rule the port names rather than picked, the account the
      run resolves reaches the category read and not the account read, the line carries the stored
      position and the stored admin flag rather than the schema default, one line carries one row,
      the run writes nothing, and the title order is the port's byte order. The shape is flags
      rather than an argument, because `@Argument` has no default, so a run cannot name an optional
      listing, and the `position` column one pin reads is the port's own, recorded in
      `docs/parity.md`.
- [x] The in-process cadence loop landed with PR #50 as the calls the loop makes through its seam,
      because nothing can pin a sleeping loop: the loop waits before the first read, which is the
      reference's shape, every wait is given the interval the loop was built with, there is one read
      per wait, each read answers the instant the clock gives at that read, a failing read is
      reported and the loop runs again, an empty read reports nothing, nothing is read after the
      seam answers stop, and the jobs of a tick run before the next read, which is the port's shape.
      The stop answer is the port's own, because the reference's ticker goroutine has no stop rule.
      The real seam, which sleeps, and the wiring that starts the loop for `serve` land with the
      process-level checks.
- [ ] The process harness lands with PR #51 as what only a process can answer: the built binary
      answering on the port the argument names, the clean signal path exiting with 0, and the WAL
      being empty after that exit because the checkpoint ran before the teardown. The signal seam
      and the wiring are the port's shapes of the reference's select and its `signal.Notify` — the
      first path to reach the decision answers it, and the answer ends the other one — with the
      handler put in place before the server command runs, so a signal arriving while the server
      starts answers the wait instead of ending the child on the default disposition. The wiring
      runs the loop to its end and the hook once after it, which is the reference's position for
      the teardown. The `SIGHUP` the reference feeds to a certificate reload is not ported, and the
      reference's HTTP servers are shut down before the pool, which this port has no piece for.

## Implementation notes

- In-process console tests use `TestConsole`; process-level behavior (signals, exit codes of the
  real binary) is tested by spawning the built executable.

## Tests

### Integration

- Every command against a temp database through the in-process console: exit codes, error messages,
  observable effects. For the feed commands this is `FeedCommandTests`; the rule is pinned as pure
  logic by `FeedValidationTests` and the reads by `FeedManagementReadsTests`. For the maintenance
  commands this is `MaintenanceCommandTests`, with the storage rules it calls pinned by
  `MaintenanceTests`. For the listings this is `ListingCommandTests`, with the two orders it reads
  pinned as reads by `CategoryRepositoryTests` and `UserRepositoryTests`, and the account resolution
  it reaches pinned there. The in-process cadence loop is pinned as the calls the loop makes through
  its seam by `CadenceLoopTests` (PR #50): the wait before the first read, the interval every wait
  is given, one read per wait, the instant each read answers, the reported failing read with the
  loop going on, the empty read reported as nothing, nothing read after the seam answers stop, and
  the jobs of a tick before the next read. The real seam sleeps, so its decisions are read through
  test seams that name the interval as zero (`SystemCadenceTests`) and the real signal path is read
  only by the process-level harness, where the wiring that starts the loop for `serve` is read too.
- `create-admin` → the resulting credentials authenticate over the API (cross-check with stage 5).
- Process-level (`ServeProcessTests`, PR #51): the built binary answers `/healthz` on the port the
  argument names, read as the port the serve event reports; SIGTERM exits with 0, which is the
  reference's clean-stop exit; and the WAL is empty after the exit, which is the shutdown checkpoint
  running before the teardown. The harness (`Support/SpawnedProcess.swift`) reads events rather than
  time — a line the child writes, a response, an exit — and kills the child on both paths, so the
  rules it holds cannot be pinned by a patch to production code; the suite names them in its header.
- `backup` produces an openable copy equal to the source and `vacuum` shrinks a bloated database
  after retention — pinned as storage rules by `MaintenanceTests` and as runs by
  `MaintenanceCommandTests` (PR #48); `status --json` shape is stable.

## Exit criteria

- [ ] The deployment runbook (stage 8) needs nothing beyond these commands.

## Backlog

- Style findings from PR #47 that do not change behavior: the single-expression code lines in the
  command pins that read over the width (the `contains` calls with the rule name and the comment
  argument, and the seed calls with the fixture values), which the wrapping rule exempts, and
  `FeedCommandTests` reading 407 lines, which is inside the test-file cap but above the size the
  file is meant to hold as it grows — split by command when the next slice adds to it.
- Style findings from PR #48 that do not change behavior: the single-expression code lines in the
  maintenance pins that read over the width (the `run` calls with the arguments and the `#expect`
  calls with the comment argument), which the wrapping rule exempts, and the content read being
  written twice — once in `MaintenanceTests` and once in `MaintenanceCommandTests` — which stays
  duplicated because the two suites read it at different levels; it moves to `Support/` when a third
  suite reads it.
- Style findings from PR #49 that do not change behavior: `run` in `List` is 43 lines against the
  ~40 aim, which stays because the print switch is the whole command; `ListingCommandTests.swift`
  imports `Foundation` and `ConsoleKit` that the committed code does not use — its probes patch
  production code only, so unlike the maintenance suite it needs no import for a patch to compile.
- Style findings from PR #50 that do not change behavior: the single-expression code lines in the
  cadence pins that read over the width (the `#expect` calls with the comment argument and the event
  arrays with the pinned instants), which the wrapping rule exempts.
- Style findings from PR #51 that do not change behavior: the single-expression code lines over the
  width in the new files, which the wrapping rule exempts because they cannot be broken without
  changing what they say — the `withCheckedContinuation` calls with the continuation type in
  `SystemCadence` and `ServerSignalSource`, the `Scheduler(...)` call with its four arguments in
  `ServeWiring`, the `ApplicationShutdownHook(...)` call in `Serve.swift`, the `Usage:` string in
  the help text, and the `reports.append(CadenceReport(...))` line in `CadenceLoop.swift`, which
  was already over the width at the head before this PR. The new files are inside the size aim
  (`SpawnedProcess.swift` 295 lines, `ServeWiringTests.swift` 249, the other test files under 80),
  so nothing here needs a split.
- The `import Foundation` in the two maintenance commands is not used by the code that is committed:
  it is there so the probe patches that redirect the destination through `NSString` and the
  filesystem through `FileManager` compile. It goes with the first probe that does not need a
  filesystem patch.
- The wording `list` prints for a row and the wording a failing run prints are the port's own; if
  the machine-readable form is wanted for the soak, `status --json` is already the contract and
  `list` should not grow a second one without a reason.
- `add` writes what it read, so the tracked-parameter case is pinned only as "the url as read"; the
  cleaner the reference applies on its discovery path lands with `quickadd` in stage 5, and the two
  paths are then where a parameter is dropped or kept.
- `backup` does not verify the copy it wrote: the runbook says to verify it by opening the file and
  running `PRAGMA quick_check`. If the command is to do that itself, that belongs to this stage's
  flag polish, and a pin for it needs a copy the run can be shown to fail on, which means a damaged
  destination written after the copy — the storage rules refuse a damaged destination before the
  write, so the check would have to run on the file the run wrote.
- `backup` has no overwrite flag: an existing destination is refused. A `--force` flag would be the
  port's own choice, not the reference's, and the rule that a run which wrote nothing reports it
  would then have to be read again on the other side of that flag.
- The free-space check the stage scope names is a startup check, not a `backup` rule: these pins
  read the copy the run wrote, not the space the run had.
- The account rule is the port's own: `--user` with the single-account fallback. If a flag is wanted
  for the environment path (`LIST_USER`, `ADD_USER`), that belongs to this stage's flag polish, not
  to the read.
