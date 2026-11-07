# Stage 6 — CLI & operations

**Goal:** everything is manageable without touching the database or a web UI. **Status:** in
progress — the first slice, the feed commands `add`, `remove` and `list`, is merged (PR #47). The
second slice, the maintenance commands `backup` and `vacuum`, is merged (PR #48). The third slice,
`list` for the categories and the accounts, is merged (PR #49). The fourth slice, the in-process
cadence loop through the `Cadence` seam, is merged (PR #50). The fifth slice, the process harness
with the signal seam and the wiring `serve` runs, is merged (PR #51). The sixth slice, the
free-space check the `backup` run makes at its start, is merged (PR #52), the seventh, `--force`, is
merged (PR #53), and the eighth, the check `--verify` gives the `backup` run, is the flag polish's
last piece and opens as PR #54. **Effort:** M. **Depends
on:** Stages 1–5.

## Scope

- [x] `add`, `remove` and `list` for the feeds landed with PR #47: the rule the reference's feed
validator reads, the duplicate read, the category read, the delete that applies the account, and the
listing order, with the account the command works for resolved from `--user` or from the single
account. The flag polish and the process-level checks follow.
- [x] `list` for the categories and the accounts landed with PR #49 as runs through the in-process
console: the flag names which read the run makes, no flag still means the feeds, the pair of flags
is reported as the rule the port names rather than picked, the account the run resolves reaches the
category read and not the account read, the line carries the stored position and the stored admin
flag rather than the schema default, one line carries one row, the run writes nothing, and the title
order is the port's byte order. The shape is flags rather than an argument, because `@Argument` has
no default, so a run cannot name an optional listing, and the `position` column one pin reads is the
port's own, recorded in `docs/parity.md`.
- [x] The in-process cadence loop landed with PR #50 as the calls the loop makes through its seam,
because nothing can pin a sleeping loop: the loop waits before the first read, which is the
reference's shape, every wait is given the interval the loop was built with, there is one read per
wait, each read answers the instant the clock gives at that read, a failing read is reported and the
loop runs again, an empty read reports nothing, nothing is read after the seam answers stop, and the
jobs of a tick run before the next read, which is the port's shape. The stop answer is the port's
own, because the reference's ticker goroutine has no stop rule. The real seam, which sleeps, and the
wiring that starts the loop for `serve` land with the process-level checks.
- [x] The process harness landed with PR #51 as what only a process can answer: the built binary
answering on the port the argument names, the clean signal path exiting with 0, and the WAL the
run's shutdown leaves empty. The signal seam and the wiring are the port's shapes of the reference's
select and its `signal.Notify` — the first path to reach the decision answers it, and the answer
ends the other one — with the handler put in place before the server command runs, so a signal
arriving while the server starts answers the wait instead of ending the child on the default
disposition. The wiring runs the loop to its end and the hook once after it, which is the
reference's position for the teardown. The `SIGHUP` the reference feeds to a certificate reload is
not ported, and the reference's HTTP servers are shut down before the pool, which this port has no
piece for.
- [x] The free-space check the `backup` run makes landed with PR #52 as the decision the rule
answers, read through the `FileSystemSpace` seam because the room a filesystem has is the machine's
and no pin can name it: the estimate is the bytes the source holds as the filesystem reads them —
the main file plus the `-wal` beside it as the filesystem reads it — times the factor the stage-1
note documents for `VACUUM INTO` (2); the room is read at the directory the destination is in, which
is the current directory for a destination named as a bare name; the comparison is strictly less, so
equality holds the copy; a room the filesystem cannot read answers a refusal and a size it cannot
read counts as nothing; and the check runs at the start of the run, before anything is written.
`vacuum` is not checked, because it rebuilds the file it already holds rather than writing a copy
beside it, which the run pin reads — and which is why `Vacuum` carries the filesystem it does not
read, so that pin can fail on a patch that reads the room there.

- The `--force` flag the `backup` run reads landed with PR #53 as one rule, in the code, the docs
and the suite header: without the flag a destination that already holds something is refused and
left as it was, and with the flag the file the destination names is replaced by the snapshot at the
run, read as the filesystem reads the path rather than as a database the run can open, while a path
that is a directory is reported rather than deleted; the flag does not skip the room check, a run
that cannot hold the copy removes nothing, and the flag does not build the directory the storage
layer needs. Pinned by `BackupForceTests`: 5 pins and 8 probes, with what no patch can flip named in
the header — an empty destination file, which the flag path replaces and the no-flag path reuses
with the same answer, the type guard's other branches, the shape guard that reads the row the pin
wrote after the control run, and the branch where the destination's existence cannot be read.

- `--verify` opens as PR #54 as the call the run makes through the `DatabaseVerifier` seam, read
as the run's own rule rather than as the storage rule `MaintenanceTests` pin for `quick_check`.
With the flag the run reads the copy it wrote at the path as it read it, after the write, through a
connection of its own, because the connection it wrote the copy through cannot answer for it, and
what the check observed is what the run reports as the failure. The copy is left as written: the
runbook restores another backup rather than repairing a file a check named, so a run that reports a
failing check does not remove what it read. Without the flag the run calls the check nothing, and
the flag changes neither the room check nor the directory the storage layer needs. Pinned by
`BackupVerifyTests`: 5 pins and 9 probes, and by `SystemDatabaseVerifierTests`, which reads what the
implementation answers for a real file: 4 pins and 6 probes — the clean answer, the problems the
damaged copy has, the file left as the bytes the storage rule wrote, and the failure reported for a
path the check cannot open rather than the clean answer. What no patch can flip is named in the two
headers, among them the connection the check opens, which no patch can show because the command
has no other connection to read through.

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
it reaches pinned there. The free-space check the `backup` run makes is pinned as the decision the
rule answers by `FreeSpaceCheckTests` (PR #52) through `Support/RecordingSpace.swift`, and as what
the run does with that decision by three pins in `MaintenanceCommandTests`: the refusal with nothing
written, the copy written at the boundary the rule reads as equal, and no room read at all for the
vacuum run. The system implementation of the seam answers the numbers of this machine, so its room
is never read here; the two answers a test can name without the machine — nothing for a path it
cannot read, and the bytes it holds for a file the test writes — are pinned by
`SystemFileSystemSpaceTests`, which both headers name. The `--force` flag is pinned by
`BackupForceTests` as what the run replaces, read as the filesystem reads the destination rather
than as a database the run can open, and `--verify` is pinned by `BackupVerifyTests` as the calls
the run makes through the check seam and the failure the run reports for the answer the seam
gives — that the run calls the seam nothing without the flag, that it makes the one call for the
path as it read it after the write, that it reports what the seam answers as the failure and
leaves the copy as written, that the flag does not change the room check, and that it does not
build the directory the storage layer needs — with `Support/RecordingVerifier.swift` recording
each call and whether the file was there at the call, which is how a pin reads the order the run
wrote and checked in. `SystemDatabaseVerifierTests` reads what the implementation answers for a
real file: the clean answer, the problems a damaged copy has, the file left as the bytes the
storage rule wrote, and the failure reported for a path the check cannot open. The two helpers
the command suites share moved to `Support/`
with PR #53, which is the second suite reading the run helper and the third reading the content
read: `CommandRun.swift`, which runs one command with the seam the pin names, and
`DatabaseContent.swift`, which reads a file through its own driver. The in-process cadence loop is
pinned as the calls the loop makes through its seam by `CadenceLoopTests` (PR #50): the wait before
the first read, the interval every wait is given, one read per wait, the instant each read answers,
the reported failing read with the loop going on, the empty read reported as nothing, nothing read
after the seam answers stop, and the jobs of a tick before the next read. The real seam sleeps, so
its decisions are read through test seams that name the interval as zero (`SystemCadenceTests`) and
the real signal path is read only by the process-level harness, where the wiring that starts the
loop for `serve` is read too.
- `create-admin` → the resulting credentials authenticate over the API (cross-check with stage 5).
- Process-level (`ServeProcessTests`, PR #51): the built binary answers `/healthz` on the port the
argument names, read as the port the serve event reports; SIGTERM exits with 0, which is the
reference's clean-stop exit; and the WAL is empty after the exit, which is what the run's shutdown
leaves behind, not which part of the shutdown emptied it. The harness
(`Support/SpawnedProcess.swift`) reads events rather than time — a line the child writes, a
response, an exit — and kills the child on both paths, so the rules it holds cannot be pinned by a
patch to production code; the suite names them in its header. A pin that gets no event fails at the
time limit the harness rule gives every unbounded wait, so the harness has to be able to answer a
cancelled pin, which is why the exit and the line reads answer a cancellation by killing the child.
- `backup` produces an openable copy equal to the source and `vacuum` shrinks a bloated database
after retention — pinned as storage rules by `MaintenanceTests` and as runs by
`MaintenanceCommandTests` (PR #48); `status --json` shape is stable.

## Exit criteria

- [ ] The deployment runbook (stage 8) needs nothing beyond these commands.

## Backlog

- Style findings from PR #47 that do not change behavior: the single-expression code lines in the
command pins that read over the width (the `contains` calls with the rule name and the comment
argument, and the seed calls with the fixture values), which the wrapping rule exempts, and
`FeedCommandTests` reading 407 lines, which is inside the test-file cap but above the size the file
is meant to hold as it grows — split by command when the next slice adds to it.
- Style findings from PR #48 that do not change behavior: the single-expression code lines in the
maintenance pins that read over the width (the `run` calls with the arguments and the `#expect`
calls with the comment argument), which the wrapping rule exempts, and the content read being
written twice — once in `MaintenanceTests` and once in `MaintenanceCommandTests` — which stays
duplicated because the two suites read it at different levels. It landed in
`Support/DatabaseContent.swift` with PR #53, the third suite reading it, and `MaintenanceTests`
keeps its own read because it reads only the digest rows at the storage level.
- Style findings from PR #49 that do not change behavior: `run` in `List` is 43 lines against the
~40 aim, which stays because the print switch is the whole command; `ListingCommandTests.swift`
imports `Foundation` and `ConsoleKit` that the committed code does not use — its probes patch
production code only, so unlike the maintenance suite it needs no import for a patch to compile.
- Style findings from PR #50 that do not change behavior: the single-expression code lines in the
cadence pins that read over the width (the `#expect` calls with the comment argument and the event
arrays with the pinned instants), which the wrapping rule exempts.
- The signal handler answers through a lock and a continuation, which is not async-signal-safe: a
signal delivered on a thread that already holds the source's lock can block there. The shape keeps
the guarded part short and the handler runs once per arrival, so nothing the pins read changes; if
the handler is moved to a dispatch source, as Vapor's server command uses, the answer leaves the
signal context and this finding closes.
- `serve`'s catch path runs the storage teardown without the fetcher close, which only the hook
closes, and a hook that failed after its own shutdown ran is read on that path as a second call. No
pin reaches either half: the pins read the hook path, and the exit code for a hook failure is read
through `ServeWiringTests` as the propagated error, not as the child's code. A pin for the catch
path would need the child to fail before the hook, which no input the harness can write answers.
- Two rules of the decision bite only inside the child across two decisions, so no pin can read
them: the answer belonging to the decision the path was created for, and a cancelled wait answering
only its own wait. Both are named in the suite headers or in the code comment, and both are what the
run does in the binary rather than what a test can show.
- Style findings from PR #51 that do not change behavior: the single-expression code lines over the
width in the new files, which the wrapping rule exempts because they cannot be broken without
changing what they say — the `withCheckedContinuation` calls with the continuation type in
`SystemCadence` and `ServerSignalSource`, the `Scheduler(...)` call with its four arguments in
`ServeWiring`, the `ApplicationShutdownHook(...)` call in `Serve.swift`, the `Usage:` string in the
help text, and the `reports.append(CadenceReport(...))` line in `CadenceLoop.swift`, which was
already over the width at the head before this PR. The new files are inside the size aim
(`SpawnedProcess.swift` 388 lines, `ServeWiringTests.swift` 250, `ServeProcessTests.swift` 89,
`SystemCadenceTests.swift` 82), so nothing here needs a split.
- The `import Foundation` in the two maintenance commands is not used by the code that is committed:
it is there so the probe patches that redirect the destination through `NSString` and the filesystem
through `FileManager` compile. It goes with the first probe that does not need a filesystem patch.
- The wording `list` prints for a row and the wording a failing run prints are the port's own; if
the machine-readable form is wanted for the soak, `status --json` is already the contract and `list`
should not grow a second one without a reason.
- `add` writes what it read, so the tracked-parameter case is pinned only as "the url as read"; the
cleaner the reference applies on its discovery path lands with `quickadd` in stage 5, and the two
paths are then where a parameter is dropped or kept.
- `backup` verifying the copy it wrote opens as PR #54 as the call the run makes through the
`DatabaseVerifier` seam, the shape the room pins read: the run reads the file at the path as it read
it, after the write, through a connection of its own, and reports what the check observed as the
failure. The copy is left as written, because the runbook restores another backup rather than
repairing a file a check named. What no patch can flip is named in the two headers rather than
pinned — the problems of a real file, which the seam answers in place of the machine, and the
connection the check opens, which no patch of the command can show because the command has no other
connection to read through. `Support/DatabaseCorruption.swift` gives the real file that fails
`quick_check` for the storage rules, and the implementation is read on that file by
`SystemDatabaseVerifierTests`, so the seam is not the only place the answer is pinned.
- `backup` has no overwrite flag: an existing destination is refused. `--force` landed with PR #53
as the port's own choice, not the reference's, and the rule that a run which wrote nothing reports
it is read again on the other side of the flag: a run that cannot hold the copy removes nothing, so
the destination is left as it was.
- The free-space check the stage scope names landed with PR #52 as a startup check, not as a
`backup` rule: the pins read the decision the rule answers through the seam, and the run pins read
that a run which cannot hold the copy writes nothing. The room of the machine this suite runs on is
not something a pin can name, so the room `statvfs` answers here is never read; what that
implementation answers for a path it cannot read and for a file the test writes is pinned by
`SystemFileSystemSpaceTests`.
- Style findings from PR #52 that do not change behavior: the single-expression `#expect` code lines
over the width in `FreeSpaceCheckTests.swift` — the ones at lines 67, 78, 82 and 129 — which the
wrapping rule exempts, while the calls that could be broken were broken; and the `space` property
`Vacuum` carries without reading, which is there so the pin that reads vacuum as checking nothing
can fail on a patch that reads the room there. The new files are below the size aim and well inside
the cap (`FreeSpaceCheck.swift` 55, `FileSystemSpace.swift` 19, `SystemFileSystemSpace.swift` 43,
`FreeSpaceCheckTests.swift` 133, `SystemFileSystemSpaceTests.swift` 46,
`Support/RecordingSpace.swift` 50), and `MaintenanceCommandTests.swift` was 472 then, under
the cap.
With PR #53 the files are `BackupForceTests.swift` 248, `Support/CommandRun.swift` 29,
`Support/DatabaseContent.swift` 36 and `MaintenanceCommandTests.swift` 407, after the two
helpers moved out of it and the unused imports came out of them. With PR #54 the files are
`BackupVerifyTests.swift` 238, `SystemDatabaseVerifierTests.swift` 136,
`Support/RecordingVerifier.swift` 48, `Storage/SystemDatabaseVerifier.swift` 53,
`Storage/DatabaseVerifier.swift` 14 and `Commands/Backup.swift` 124 — all under the size aim, so
nothing needs a split.
are the ones the wrapping rule exempts: the `#expect` calls with the comment argument, the
`databases.database(...)` call with the logger and the event loop, the `help` string, and the
`problems` read that names the flag, the seam and the path in one expression.
- The check reads the copy through FluentKit's `Databases` container, because these package versions
do not answer a `Database` for one path any other way: `SQLDatabase.fluent(.sqlite(.file(path)))`
does not exist, and `fluent(_:)` is Cache and Sessions. The container is closed before the answer
leaves, so the connection the check opened does not outlive the call that opened it. It is named
with `MultiThreadedEventLoopGroup.singleton` and `NIOThreadPool.singleton`, because the singletons
these packages exported as `SystemEventLoop` and `SystemEventLoopGroup` are no longer in SwiftNIO.
The three direct products `RivuletCore` now names — `FluentSQLiteDriver`, `NIOPosix`, `Logging` —
are the approved addition: all three were already in the dependency graph, and `FluentSQL` is not
imported, because nothing here uses what it exports.
- The account rule is the port's own: `--user` with the single-account fallback, and no
environment flag for the environment path, which the flag polish closes: the reference's CLI reads
the environment through its config parser (`internal/cli/cli.go`), but the only name it reads there
that resolves an account is the one `create-admin` takes from `ADMIN_USERNAME` — `METRICS_USERNAME`
is basic auth for the metrics endpoint, not an account — and no read resolves an account for a
command, so there is nothing to mirror. The `LIST_USER` and `ADD_USER` names the earlier plan
imagined are not ported, and nothing the pins read changes.
- Width: `ClientAuthTests.swift:18` and `EntryQueryTests.swift:11` read 101 characters. They
predate PR #53 and are not files this slice touches, so they stay as they are, as do the older
suites under `Tests/RivuletCoreTests/`, where the width rule was applied slice by slice rather than
repo-wide. The files this commit changes are clean, counted in characters.
