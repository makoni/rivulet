# Testing strategy

Rivulet is developed test-first (TDD): red → green → refactor. Integration tests are not an
afterthought — they run in CI together with unit tests.

## Levels

| Level | Location | Scope |
| --- | --- | --- |
| Unit | `Tests/RivuletCoreTests`, `Tests/RivuletAppTests` | Pure logic: date parsing, charset, sanitizer rules, merge decisions, scheduling math, config, OPML, log formatting |
| Fixture/golden | `Tests/RivuletCoreTests/Fixtures/` (target resources, added in stage 3) | Ported Miniflux corpora: encoding (11 files), parser (8), XML (3), sanitizer (2) — input bytes → golden output — plus the three corpora the port wrote from the reference's output: the hostile sanitizer corpus, the XML tolerance table and the parser error corpus |
| Integration | `Tests/RivuletIntegrationTests` | Real SQLite in a temp dir, local stub feed server, the full Vapor app over real HTTP |
| Soak | `Scripts/soak.sh` with `Tools/soak/soak_check.py` | A real-time run over local stub feeds, run by hand and not in CI: its checks read the data each round leaves behind |
| Acceptance | `Tools/parity` with `Scripts/parity.sh` (stage 7) | Semantic comparator over observable behaviour against real Miniflux in Docker, run by hand and not in CI: its rules read the pair document the run leaves behind, and the tolerance table is read as data from `docs/parity.md` |

The integration test target is added to `Package.swift` in stage 0 (no `XCTVapor`: app tests speak
to a real socket through Vapor's client). Fixture files are target resources (`resources:
[.copy("Fixtures")]`, read via `Bundle.module`), as stage 3 landed them. Part of this level spawns
the built executable rather than running the app in-process; that is the process harness
(`Support/SpawnedProcess.swift`, used by `ServeProcessTests`), whose header comments state its
rules, and it is what reads the facts only a process can answer.

## Workflow (TDD)

1. Write a failing test that describes the behavior.
2. Implement the minimal change to make it pass.
3. Refactor with tests green.
4. Bug fixes start with a regression test that reproduces the bug.

Rules:

- No production code without a corresponding test change.
- Never delete, skip or weaken a test to make the suite pass (see `AGENTS.md`).
- When behavior crosses a module boundary, cover it with an integration test, not only a unit test.

### Probes

Suite headers and the security checklist say a pin "can fail on" a rule, or count "probes". A probe
is a deliberate patch to production code that breaks one rule: the suite is rebuilt and run, the pin
that names the rule must fail, and the patch is reverted byte-identically. A pin no probe can make
fail does not pin its rule, so the header says what it cannot show instead. The Python check halves
use the same idea with crafted input documents instead of patches (their probe rounds).

## Integration test infrastructure

Support helpers live in `Tests/RivuletIntegrationTests/Support/`:

- `TestDatabase.swift` — temp-file SQLite database in a temp dir per test; the schema migration is
registered but applied explicitly by each test (`autoMigrate()`); wiped on teardown.
- `MigratedStorage.swift` — the `withMigratedStorage` helper: runs a body with a `TestDatabase` and
a prepared, schema-migrated `SQLiteStorage`, shutting the app down (and removing the temp dir) on
both success and failure; used by every suite that needs the migrated schema.
- `ServedApp.swift` — the `withServedApp` helper for the routes suites: boots the real application
on an ephemeral port with the schema migrated and runs the body with the storage, the application
and the base URL of the socket it answers on. The server is stopped before the application on both
paths, because only `ServeCommand` stops it for the happy path and a started server that is not
stopped trips `HTTPServer`'s deinit assertion instead of reporting the failure; the temp directory
is removed here, so the teardown rule stays in one place.
- `GoogleReaderRequests.swift` — the requests and answer reads the Google Reader suite shares: the
form body is sent as the bytes are given, so a rule about what the form read sees is shown by the
bytes rather than by an encoding the client added. `body(token:pairs:)` builds the POST body with
the token as the `T` field of the merged form, which is what a POST request has to carry, and
`seedIntegrationUser` creates the user the way `UserRepository.create` does — with the default "All"
category — and sets the integration credentials the token read needs, so a pin that depends on which
categories a user has reads the graph the command creates rather than a set the test made.
- `FeverRequests.swift` — the requests and answer reads the five Fever suites over a real socket
share: `get`, `post` and `head` build the path the client calls, `postParts` and `multipart` send
the body as the bytes are given so a rule about what the form read sees is shown by the bytes rather
than by an encoding the client added, and `body`, `contentType` and `header` read the answer as the
transport left it, so the pin for a method that writes no bytes reads the framing name. `seed`
creates the account through `UserRepository.create`, so the default "All" category the create path
writes is one of the rows the pins read, and answers the token the guard reads; `categoryID` reads
the id the groups golden names. The rows are written through SQL on one connection and the request
runs after that connection goes back to the pool, because the driver keeps a single pooled
connection, so a pin cannot hold one while the handler checks out another.
- `EntryFixtures.swift` — seeds users, categories and feeds, inserts entries through the repository
with a chosen status/starred state, bulk-seeds entries for pagination limits, seeds the four-entry
set the stream branch pins read, builds entry inputs, counts entries, tombstones and FTS matches,
and backdates timestamps for the retention suites.
- `DatabaseCorruption.swift` — damages a real SQLite page (the two-byte cell count of page 2, the
`_fluent_migrations` root, using the page size from the file header) so integrity tests observe
`PRAGMA quick_check` failures without shipping a corrupt database fixture.
- `FileSize.swift` — file size in bytes, throwing when the file is missing or its metadata cannot be
read, so an assertion that a WAL is empty cannot be satisfied by a deleted file.
- `CommandRun.swift` — the `runCommand` helper the command suites share: runs one command through
the in-process console against the file the pin names and answers the outcome the pins read. The
filesystem the run reads is the seam the pin names, because the room of the machine this process
runs on is not something a pin can name; the default answers enough room for anything, so the pins
that do not read the free-space check answer as they did before it. The database the copy check
reads is the seam the pin names for the same reason, because the problems a real file has cannot be
named by a pin, so the default answers a clean check and the pins that do not read the verify step
answer as they did before it.
- `RecordingVerifier.swift` — the `DatabaseVerifier` seam the verify pins drive: answers the
problems the pin names and records the calls the run made through it, with whether the file was
already there at the call, which is how a pin reads the check as running after the write rather than
before it. The recording is a read the helper makes on the filesystem itself, not a rule the check
applies, so a pin that reads the check as not running answers a control that does run it.
- `DatabaseContent.swift` — the content read the command suites share: the tables a file holds and
one digest line per entry, ordered by id, read through SQL, so a pin is not satisfied by the read it
is testing. `content(at:on:as:)` reads a file through its own driver, which is what the copy pins
need, because the copy is not the connection the test seeded with.
- `RecordingSpace.swift` — the filesystem the free-space pins drive instead of the real one,
because the room a real filesystem reports is not something a pin can name.
- `SubscriptionSocket.swift` — the socket the three Google Reader subscription suites read through:
the authenticated account, the rows the pins write, and the values read back through SQL.
- `TestClock.swift` — a clock that answers one injected instant, so every stamp a pipeline pin reads
is that value rather than the process clock.
- `AcceptanceJourney.swift` — the chain the acceptance journey pin runs: account and credentials,
OPML import, one refresh pass, then client requests over the socket.
- `SpawnedProcess.swift` — the process harness: spawns the built `rivulet` executable, reads the
line it writes once it serves, sends signals, and reports how the child exited (`ServeProcessTests`).
- `CallingSets.swift` — reads the acceptance clients' calling sets from
`CallingSets/` as data for the replay pins.
- `StubFeedServer.swift` — in-process HTTP server serving feed fixtures with configurable behavior:
status codes, `ETag`/ `Last-Modified`, gzip, redirects, delays (before the answer, or after the head
so a body can arrive later than a deadline), cut connections, chunked responses, charset headers.
**Binds port 0** and exposes the assigned address; no fixed ports. It records every request it
receives (target and headers) so a test can check what the client actually sent, and
`waitForRequest(for:)` waits for one to arrive — check and wait in one step under the lock — so a
test can act while a request is in flight without polling or sleeping, which holds only while the
answer is still pending: a quick response releases the client before the test can act. The cache
test therefore holds the body back. `waitForArrival(for:)` is the same arrival read with the pin's
own cancellation answered as the cancellation it was given, and answers whether an arrival came, so
a pin whose rule may be answered no arrival fails at its limit instead of hanging — the process pin
that reads the loop's read as a request the child makes is the one that needs it. The proxy tests
use `StubProxy`, not this server.
- `StubProxy.swift` — minimal proxy bound to port 0: it answers the `CONNECT` handshake and then
serves one canned response on the tunnel, which is how AsyncHTTPClient proxies a request. Records
the targets it was asked to connect to.
- `FetchTestSupport.swift` — setup shared by the fetch suites: the options with the values a test
cares about named at the call site, a server, proxy or fetcher started for one test and closed on
both the success and the failure path, and the two resolvers a fetch test injects (one seeded from a
table, one counting the lookups).
- `GzipStream.swift` — writes a gzip stream with stored DEFLATE blocks so the stub server can serve
a compressed body without a compression dependency. The fetch test uses this same encoder, so it
shows that the client decompresses the fixture; the encoder itself is checked against `gunzip` by
hand when it changes, which is why no test can prove it. Stored blocks cannot reach a compression
ratio above 1, so the decompression guard `docs/reference-notes.md` records is not exercised by any
test either.
- `TestConsole.swift` — in-process console that captures output and replays input; CLI smoke tests
run commands against a temp database through it. It records the `isSecure` flag of every read, in
the order the reads happened, so a pin can name which path a read took rather than only the value
that came back.
- `SchemaTables.swift` — the tables a database file holds, read through an application built for
that file. CLI pins use it on both sides of the migration flag, so what a pin reports is the gate
rather than a schema the test built itself.
- Nullable columns in the CLI pins are read through `decodeNil(column:)`, so a pin can tell a stored
value apart from the column being empty: decoding a `NULL` as `String` throws, which a run would
report as a failure rather than as the rule the pin reads.
- `TemporaryDirectory.swift` — unique temp directory per test, removed on teardown (used by the CLI
and probe tests).
- `TestLogging.swift` — installs a silent handler once per process through `LoggingSetup`'s
bootstrap slot, so commands can run in-process without a second `LoggingSystem.bootstrap` (swift-log
traps on a second one).
- Time injection: long-running logic takes the current time explicitly — `Retention.run(now:)` takes
Unix seconds, scheduling will take a clock — so tests pass fixed values and never sleep.

`SystemAddressResolver` is the only public API that cannot have a hermetic test against a network:
it calls the real `getaddrinfo`, which the determinism rules below forbid. Its test is the narrow
case that works without one — a numeric host, which the resolver answers from the string itself —
and that is also the only place the byte order of the raw `addrinfo` layout is pinned. Everything
else that matters — one lookup for a direct hop, the answer handed to the policy, and the client
pinned to the answer it was built from — is tested through the resolver seam, with a seeded resolver
for the pinning and a counting one for the single lookup.

The fetcher's client cache has four behaviour tests (`FetcherClientCacheTests`). The first pins the one effect that can be observed from outside
an eviction: while a request is in flight the client serving it must not be closed, or that request
is cancelled — that is the failure the test reproduces. The request head reaches the stub only after
the client was taken from the cache, so waiting for the head with `waitForRequest(for:)` puts the
test at a known point without a sleep, and the body is held long enough for the fillers to run,
which the test states. The second asserts what `shutdown()` can be observed to do: a second call
finds nothing to close, and the next fetch builds a client again. The recovery assertion carries the
weight, but the second call is not worthless either — an implementation that left closed entries in
the cache would fail it with AsyncHTTPClient's `alreadyShutdown`. The third and the fourth read the
trim through an internal accessor, which is the only place the trim is visible, because closing a
client changes nothing a fetch can answer: the next request for that host builds a client again and
gets the same response. They pin the cache staying at the cap after a checkout that goes over it,
and the entry the trim closes being the one whose expiry comes first — 2 pins, listed
in `docs/security.md`. That a call overlapping the
first cannot close the same client twice follows from taking the entries out before the first await;
it cannot be reproduced without a client-creation seam the plan does not have, so it is documented
rather than tested. Everything else about the cache is not observable from outside when two hosts
are answered by the same address: what is asserted is the key, because the guarantee that a pin is
never reused for another host or a proxied request rests on it; the TTL clock is monotonic so an NTP
step cannot stretch or shrink it, and eviction is by expiry among idle entries, not by use, which
the code states plainly and the trim pin reads through the accessor, on the input where every entry
is idle so the earliest expiry is also the first created — an LRU could not be told apart there,
which the header names. A client in use is never pruned; `shutdown()` closes every client regardless
of use, so calling it when no `fetch` is in flight is a caller's contract and the suite does not
assert the failure a shutdown during a fetch causes — that is a misuse, not a supported path.

App-level tests build the real Vapor app with a temp database and speak real HTTP over a socket: the
`/healthz` tests start the server on an ephemeral port (never the configured one) and use Vapor's
client. The same socket-level approach backs the client-API journey tests.

Determinism rules: no fixed ports, no sleeps or real-time waits (`TZ=UTC` for date tests, per-test
temp directories, no network access except to the local stub server or the stub proxy). The ported
date parser needs neither the clock nor the machine's zone: it reads no clock and no tzdata, and a
value that reads no zone is read as UTC, which is what the reference does as well. A bounded timeout
that proves a failure is fast rather than hanging is allowed — the pool-timeout test asserts one —
and a test whose pass condition is a timeout says so in its comment. A stub-side hold is the only
margin that can turn a test into a false pass: the first cache test keeps a request in flight under
a one-second body delay while eight local round trips fill the cache, and a slow machine can only
make that a false pass, never a false failure; the fetch timing tests hold their margin the same
way, with the first hop's delay small against the deadline so CI overhead can only make the deadline
fire earlier, never let a hop that should be cut finish. A test that waits without a bound carries a
`timeLimit` so a regression fails instead of hanging.

## Fixtures

Ported from Miniflux (Apache-2.0) into `Tests/RivuletCoreTests/Fixtures/<area>/`. The directory gets
its own `README.md` recording provenance: upstream repository, commit `c4d54f87`, license, and which
files were copied verbatim vs regenerated. `NOTICE` is updated when fixtures land. Each ported case
carries a comment pointing to the original Go test (`internal/reader/...`).

The parser corpus (`ParserCorpusTests`) reads the 8 fixtures end to end. Upstream uses these files
only as benchmark and fuzz inputs, so there is no upstream assertion to port, and the expected
values could not come from a test. They were obtained by running the reference itself — Miniflux
v2.3.3, Go 1.26.0, the version `go.mod` declares — over these bytes with `TZ=UTC`. The run is a
scratch package inside a verbatim copy of the clone, because the `internal/` packages cannot be
imported from another module, so nothing in the repository depends on a Go toolchain. Each golden
file pins one value per line as `path = value`, says that its values are the reference's output for
that fixture, names the rule its fixture pins, and says what it cannot show; a value that would
break a line is written escaped, and content longer than the files keep readable is pinned as its
first 120 code points plus its SHA-256, which pins the whole of it.

The sanitizer fixture corpus (`SanitizerFixtureCorpusTests`) reads the two `sanitizer/` HTML
fixtures the same way, end to end, and its golden files hold the output as bytes with no header
line, because the assertion compares the whole document. The run used the version `go.mod` declares,
Go 1.26.0, the reference's test helper options — `OpenLinksInNewTab: true` with what
`config.NewConfigOptions()` gives — and the base URL the reference's own benchmark pairs with each
file, because the URLs the sanitizer writes out are resolved against it, and it ran in a copy of the
pinned clone so the clone itself stayed clean.

All five things in the corpus that are not copies of an upstream file — the 8 parser goldens, the
two sanitizer goldens and the three corpora — were run again on that toolchain, and every value
reproduces the file committed here except the two kinds of line the files name: the two date lines
of `rdf_UTF8.xml`, which record the clock the suite injects, because the adapter answers with the
clock for an item that has no date, so a run answers with its own clock for them; and the outcome
lines of the parser error corpus, which name the branch the switch takes, and which for a routed
case whose scan fails are not what the reference answers — for those two it answers with the failure
the adapter reports.

Only the values named below were traced independently of the run, from the fixture bytes; every
other pinned value rests on the run, which is why the golden files and the test say plainly that a
golden value is the reference's output and not Rivulet's. The independent checks are: the SHA-256 of
a GUID, of an entry URL and of an entry ID (`encoding_WINDOWS-1251.xml`, the entry-1 item of
`no_encoding_ISO-8859-1.xml`, which has no GUID, and `small_atom.xml`), the windows-1251 title, the
entry-1 content of `no_encoding_ISO-8859-1.xml` — the no-label path drops the bytes that are not XML
characters — a numeric character reference kept as written inside CDATA, the epoch a date resolves
to, and an entity decoded in a media thumbnail URL. The zone name a date resolves to is not pinned,
because the reference reads it through the machine's tzdata — see `docs/parity.md` — while the epoch
and the offset are. Nothing in this corpus reads a clock, a locale or the network; the date the RDF
items start with is the clock the suite injects.

The URL layer has no fixture corpus, because the reference has none for it: its cases are the ported
tables from `internal/urllib/url_test.go` and `internal/reader/urlcleaner/urlcleaner_test.go`, plus
pins traced against Go's `net/url` source, so each suite says which pins come from the upstream
corpus and which are traced from the source, and `docs/parity.md` records where the traced subset
stops. Nothing in it reads a clock, a locale or the network. The URL rules the sanitizer reads
attribute values through — that a value already read as absolute is written as it was read, that the
control-byte check is the parse's and not the writer's, that the query is not decoded, and that the
entity decoding happens in the tokenizer before the URL part sees the value — are pinned by the
hostile corpus below.

The sanitizer's upstream corpus is ported in full except the fuzz target `FuzzSanitizer`, whose
expectation is that the sanitized output has no more tokens than the input, which needs a fuzz
harness and a seed corpus that Swift Testing has neither. The two text-layer suites port
`TestStripTags` and `TestTruncateHTML`, and name the three rules the corpus does not cover: the
count per code point rather than per Swift grapheme, the set `unicode.IsSpace` answers with as its
generated table rather than as its comment reads it, and the raw state that ends at its end tag
because the script escaping states are not ported. The tokenizer and the insertion modes have no
upstream corpus, so the eight sanitizer suites — the hostile corpus among them — name what is traced
against `golang.org/x/net/html` at the version `miniflux/go.mod` pins, v0.57.0, which is the copy
the rules were read from, and `docs/parity.md` records where that subset stops. Four of those pins
cannot be seen through the sanitizer output and are asserted through the tokenizer itself: a NUL in
a tag name, a NUL in an attribute key — neither is ever in the allowlist — the shape of the entity
table, and where comment data ends, because the renderer writes nothing for a comment.

The hostile corpus the plan names is `SanitizerHostileCorpusTests` over
`Fixtures/sanitizer/hostile_corpus.txt`: 146 inputs that try to make the sanitizer write active
content, each with the output the reference produced for it and the rule that output pins. The inputs are ours, not
upstream's; the outputs were written by running Miniflux v2.3.3 at commit `c4d54f87` with the
reference's test helper options — `OpenLinksInNewTab: true`, base URL `http://example.org/`,
`TZ=UTC` — the same method the parser corpus uses, so a failure here is a difference in the port.
Every case can fail on the rule its line names: a case is not in the corpus when a wrong
implementation of that rule writes the same output, which is what the fixture says.

What it pins is the rules its cases name: the scheme allowlist, the data-URI prefixes, the mandatory
attributes, the pixel tracker, the blocked resources, the hidden check, what a dropped tag leaves of
its content, the control bytes the URL parse refuses while the as-read path does not, the entity
lookup inside an attribute value — which is where the URL part's entity decoding happens, because
the value reaches the URL layer already decoded — the srcset whitespace class, that the URL part
normalizes no whitespace of its own, and the order a formatting element writes its attributes in.
What it cannot pin is content inside `math` or `svg`, which the reference inserts through the
foreign-content rules this port does not have, and the rules an output cannot tell apart, such as a
raw path that is already the canonical encoding, a plus in a query that round-trips to the same
string, an attribute allowlist with a single name, a read order that is already the sorted order, or
the sort tie-break by value, which needs two attributes with the same name. The limit of 512 open
elements in `parse.go` is pinned by the two cases that mirror `TestDeeplyNestedpage`: the reference
reaches it by panicking and its own parse recovers that as an error, so a chain one past the limit
answers with nothing, and the port refuses at the same count.

The XML tolerance table (`XMLToleranceTests`) is the run the plan's test-plan item asks for: 52
inputs over the four quirk classes, read through `NewXMLDecoder` and `Token()` — the reader path,
not `Decode` — with the same reference and the same method the parser corpus uses, comparing the
token stream and how the stream ends. The run found no divergence, so the table in
`docs/reference-notes.md` records what the reference reports rather than a difference; `docs/parity.md` records only the
modeling choice for the end of the stream. The
30 cases that can fail on the rule they name are committed as the fixture
`Tests/RivuletCoreTests/Fixtures/xml/tolerance_corpus.txt`; a case is left out when a wrong
implementation of its rule writes the same stream, so the suite reads the fixture rather than
carrying the inputs inline. What the corpus cannot pin: the production a run of text came from,
which `Token()` reports as character data either way, and a stream that ends at the end of the
document inside a CDATA section, because the port reports that as the one failure case it has. A pin
cannot fail on the wording of a failure message either, which is why the test compares the case the
message names, and it cannot tell a clean end of the stream from an end reached inside an element,
which is the equivalence recorded in `docs/parity.md`.

The typed error on the parser path (`ParserErrorTests`, over
`Fixtures/parser/parser_error_corpus.txt`) is read from the same reference with the same method: 10
inputs, comparing what `DetectFeedFormat` answers, which branch `ParseFeed` takes for that answer,
and how the scan ends.

Per-suite notes — what each pin can fail on and what it cannot show — live in the header comment of
the suite itself, not here.

Performance budgets are documented rather than asserted, because a number one machine measured
cannot be a pin: `LargeFeedTests` reads a single 250 ms bound on the corpus read path (which
measures 1–4 ms), and the memory budget is the corpus rows plus the body the fetcher can hold, the
15 MiB cap the configuration reads by default. Measured numbers are in `docs/performance.md`.

## Manual harnesses (outside CI)

Some checks need a real clock, Docker, systemd, a live Miniflux or the DocC tool, so they are not
part of `swift test`. Each is split into a *run half* (a shell script that drives the real system
and writes what it saw to a file) and a *check half* (a Python script whose rules read that file as
data). The check halves carry their own probe rounds — crafted inputs that each rule must report —
and those rounds, which need no container or service, run in CI as the `probe-rounds` job. What a
harness cannot show is listed in its check half (`CANNOT_SHOW`) or in its script header.

| Harness | Run half | Check half | Reads / records |
| --- | --- | --- | --- |
| Soak (stage 4) | `Scripts/soak.sh` | `Tools/soak/soak_check.py` | ≥ 2 h over ≥ 20 local stub feeds; `status --json` snapshots per round |
| Parity (stage 7) | `Scripts/parity.sh` | `Tools/parity/parity_check.py` | Real Miniflux vs Rivulet over one corpus; tolerance table in `docs/parity.md`, last run in `docs/parity-report.md` |
| Client matrix (stage 7) | `Scripts/client-run.sh`, `Scripts/perf.sh` | `Tools/clients/replay.py` | Calling sets in `Tests/RivuletIntegrationTests/CallingSets/`, `docs/clients.md`, `docs/performance.md` |
| Static release build (stage 8) | `Scripts/build-release.sh` | checks inside the script | The static musl artifact built with the Swift Static Linux SDK |
| Clean-container smoke (stage 8) | `Scripts/smoke.sh` | `Tools/smoke/smoke_check.py` | The CLI chain in an empty container; `Tools/smoke/run.json` |
| Deploy artifacts (stage 8) | `Scripts/deploy.sh` | `Tools/deploy/deploy_check.py` | `deploy/compose.yml`, `deploy/rivulet.service`, `.env.example` as Docker and systemd read them; `Tools/deploy/deploy.json` |
| DocC (stage 8) | `Scripts/docs.sh` | `Tools/docs/docs_check.py` | The DocC catalog as `docc convert` reads it; `Tools/docs/docs.json`, `docs/docc.md` |

## Running

- `swift test` — everything (unit + integration); this is what CI runs.
- `swift test --filter RivuletCoreTests` — unit only (fast loop).
- `swift test --filter RivuletIntegrationTests` — integration only.
- `swift build --build-tests` — must finish with no warnings.
- Heavy suites (100k-entry benchmarks, big-feed scenarios) are disabled by default behind an
  `.enabled(if:)` trait gated on `RIVULET_HEAVY`; run them with `RIVULET_HEAVY=1 swift test --filter
  HeavyTests`. The reduced large-feed scenario (`LargeFeedTests`) is not gated and runs in the default
  job.
- A few storage tests need at least two event loops (one pooled connection per loop); they
  `Test.cancel` on single-loop runners. CI runners always expose ≥ 2 event loops.
- The probe rounds of the manual harnesses: `python3 Tools/<name>/probes.py` for `clients`, `parity`,
  `smoke`, `deploy` and `docs`, plus `python3 Tools/soak/soak_check.py --probe`. The harness run
  halves are the scripts in the table above; `PARITY_DRY_RUN=1 Scripts/parity.sh` runs the parity
  guards alone, and `RIVULET_SKIP_BUILD=1 Scripts/build-release.sh` checks an artifact already on disk.

CI (`.github/workflows/ci.yml`) has two jobs: `swift build` + `swift test` in the `swift:latest`
container on `ubuntu-latest` with a 15-minute timeout — keep the default suite well under that — and
the five probe rounds on the runner host, because the Swift container has no `python3`.

## Framework

Swift Testing everywhere (`import Testing`, `@Suite`/ `@Test`, `#expect`/ `#require`) — one
framework, no mixing; XCTest and `XCTVapor` are not in the tree. Tests run in parallel by default
and every test owns its resources (temp directories, kernel-assigned ports), so no suite depends on
execution order. Use the `.serialized` trait only where a suite must share process-wide state.
