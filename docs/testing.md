# Testing strategy

Rivulet is developed test-first (TDD): red → green → refactor. Integration tests are not an
afterthought — they run in CI together with unit tests.

## Levels

| Level | Location | Scope |
| --- | --- | --- |
| Unit | `Tests/RivuletCoreTests`, `Tests/RivuletAppTests` | Pure logic: date parsing, charset,
sanitizer rules, merge decisions, scheduling math, config, OPML, log formatting | | Fixture/golden |
`Tests/RivuletCoreTests/Fixtures/` (target resources, added in stage 3) | Ported Miniflux corpora:
encoding (11 files), parser (8), XML (3), sanitizer (2) — input bytes → golden output — plus the
three corpora the port wrote from the reference's output: the hostile sanitizer corpus, the XML
tolerance table and the parser error corpus | | Integration |
`Tests/RivuletIntegrationTests` | Real SQLite in a temp dir, local stub feed server, the full Vapor
app over real HTTP | | Soak | `Scripts/soak.sh` with `Scripts/soak_check.py` | A real-time run over local stub feeds, run by hand and not in CI: its checks read the data each round leaves behind |
| Acceptance | `Tools/parity` (stage 7) | Real clients checklist + semantic
diff against real Miniflux in Docker |

The integration test target is added to `Package.swift` in stage 0 (no `XCTVapor`: app tests
speak to a real socket through Vapor's client).
Fixture files are target resources (`resources: [.copy("Fixtures")]`, read via `Bundle.module`), as
stage 3 landed them.

## Workflow (TDD)

1. Write a failing test that describes the behavior.
2. Implement the minimal change to make it pass.
3. Refactor with tests green.
4. Bug fixes start with a regression test that reproduces the bug.

Rules:

- No production code without a corresponding test change.
- Never delete, skip or weaken a test to make the suite pass (see `AGENTS.md`).
- When behavior crosses a module boundary, cover it with an integration test, not only a unit test.

## Integration test infrastructure

Support helpers live in `Tests/RivuletIntegrationTests/Support/`:

- `TestDatabase.swift` — temp-file SQLite database in a temp dir per test; the schema migration is
  registered but applied explicitly by each test (`autoMigrate()`); wiped on teardown.
- `MigratedStorage.swift` — the `withMigratedStorage` helper: runs a body with a `TestDatabase` and
  a prepared, schema-migrated `SQLiteStorage`, shutting the app down (and removing the temp dir) on
  both success and failure; used by every suite that needs the migrated schema.
- `EntryFixtures.swift` — seeds users, categories and feeds, inserts entries through the repository
  with a chosen status/starred state, bulk-seeds entries for pagination limits, builds entry inputs,
  counts entries, tombstones and FTS matches, and backdates timestamps for the retention suites.
- `DatabaseCorruption.swift` — damages a real SQLite page (the two-byte cell count of page 2, the
  `_fluent_migrations` root, using the page size from the file header) so integrity tests observe
  `PRAGMA quick_check` failures without shipping a corrupt database fixture.
- `FileSize.swift` — file size in bytes, throwing when the file is missing or its metadata cannot be
  read, so an assertion that a WAL is empty cannot be satisfied by a deleted file.
- `StubFeedServer.swift` — in-process HTTP server serving feed fixtures with configurable behavior:
  status codes, `ETag`/`Last-Modified`, gzip, redirects, delays (before the answer, or after the
  head so a body can arrive later than a deadline), cut connections, chunked responses, charset
  headers. **Binds port 0** and exposes the assigned address; no fixed ports. It records every
  request it receives (target and headers) so a test can check what the client actually sent, and
  `waitForRequest(for:)` waits for one to arrive — check and wait in one step under the lock — so a
  test can act while a request is in flight without polling or sleeping, which holds only while the
  answer is still pending: a quick response releases the client before the test can act. The cache
  test therefore holds the body back. The proxy tests use `StubProxy`, not this server.
- `StubProxy.swift` — minimal proxy bound to port 0: it answers the `CONNECT` handshake and then
  serves one canned response on the tunnel, which is how AsyncHTTPClient proxies a request. Records
  the targets it was asked to connect to.
- `FetchTestSupport.swift` — setup shared by the fetch suites: the options with the values a test
  cares about named at the call site, a server, proxy or fetcher started for one test and closed on
  both the success and the failure path, and the two resolvers a fetch test injects (one seeded from
  a table, one counting the lookups).
- `GzipStream.swift` — writes a gzip stream with stored DEFLATE blocks so the stub server can serve
  a compressed body without a compression dependency. The fetch test uses this same encoder, so it
  shows that the client decompresses the fixture; the encoder itself is checked against `gunzip` by
  hand when it changes, which is why no test can prove it. Stored blocks cannot reach a compression
  ratio above 1, so the decompression guard `docs/reference-notes.md` records is not exercised by
  any test either.
- `TestConsole.swift` — in-process console that captures output and replays input; CLI smoke tests
  run commands against a temp database through it.
- `TemporaryDirectory.swift` — unique temp directory per test, removed on teardown (used by the CLI
  and probe tests).
- `TestLogging.swift` — installs a silent handler once per process through `LoggingSetup`'s
  bootstrap slot, so commands can run in-process without a second `LoggingSystem.bootstrap`
  (swift-log traps on a second one).
- Time injection: long-running logic takes the current time explicitly — `Retention.run(now:)` takes
  Unix seconds, scheduling will take a clock — so tests pass fixed values and never sleep.

`SystemAddressResolver` is the only public API that cannot have a hermetic test against a
network: it calls the real `getaddrinfo`, which the determinism rules below forbid. Its test is
the narrow case that works without one — a numeric host, which the resolver answers from the
string itself — and that is also the only place the byte order of the raw `addrinfo` layout
is pinned. Everything else that matters — one lookup for a direct hop, the answer handed to
the policy, and the client pinned to the answer it was built from — is tested through the
resolver seam, with a seeded resolver for the pinning and a counting one for the single lookup.

The cache has two behaviour tests. The first pins the one effect that can be observed from
outside an eviction: while a request is in flight the client serving it must not be closed,
or that request is cancelled — that is the failure the test reproduces. The request head
reaches the stub only after the client was taken from the cache, so waiting for the head
with `waitForRequest(for:)` puts the test at a known point without a sleep, and the body
is held long enough for the fillers to run, which the test states. The second asserts what
`shutdown()` can be observed to do: a second call finds nothing to close, and the next fetch
builds a client again. The recovery assertion carries the weight, but the second call is not
worthless either — an implementation that left closed entries in the cache would fail it with
AsyncHTTPClient's `alreadyShutdown`. That a call overlapping the first cannot close the same
client twice follows from taking the entries out before the first await; it cannot be reproduced
without a client-creation seam the plan does not have, so it is documented rather than tested.
Everything else about the cache is not observable from outside when two hosts are answered by the
same address: what is asserted is the key, because the guarantee that a pin is never reused for
another host or a proxied request rests on it; the TTL clock is monotonic so an NTP step cannot
stretch or shrink it, and eviction is by expiry among idle entries, not by use, which the code
states plainly. A client in use is never pruned; `shutdown()` closes every client regardless
of use, so calling it when no `fetch` is in flight is a caller's contract and the suite does
not assert the failure a shutdown during a fetch causes — that is a misuse, not a supported path.

App-level tests build the real Vapor app with a temp database and speak real HTTP over a
socket: the `/healthz` tests start the server on an ephemeral port (never the configured one)
and use Vapor's client. The same socket-level approach backs the client-API journey tests.

Determinism rules: no fixed ports, no sleeps or real-time waits (`TZ=UTC` for date tests, per-test
temp directories, no network access except to the local stub server or the stub proxy). The ported
date parser needs neither the clock nor the machine's zone: it reads no clock and no tzdata, and a
value that reads no zone is read as UTC, which is what the reference does as well. A bounded
timeout that proves a failure is fast rather than hanging is allowed — the pool-timeout test
asserts one — and a test whose pass condition is a timeout says so in its comment. A stub-side
hold is the only margin that can turn a test into a false pass: the first cache test keeps a
request in flight under a one-second body delay while eight local round trips fill the cache,
and a slow machine can only make that a false pass, never a false failure; the fetch timing
tests hold their margin the same way, with the first hop's delay small against the deadline so
CI overhead can only make the deadline fire earlier, never let a hop that should be cut finish. A
test that waits without a bound carries a `timeLimit` so a regression fails instead of hanging.

## Fixtures

Ported from Miniflux (Apache-2.0) into `Tests/RivuletCoreTests/Fixtures/<area>/`. The directory
gets its own `README.md` recording provenance: upstream repository, commit `c4d54f87`, license,
and which files were copied verbatim vs regenerated. `NOTICE` is updated when fixtures land.
Each ported case carries a comment pointing to the original Go test (`internal/reader/...`).

The parser corpus (`ParserCorpusTests`) reads the 8 fixtures end to end. Upstream uses these files
only as benchmark and fuzz inputs, so there is no upstream assertion to port, and the expected
values could not come from a test. They were obtained by running the reference itself — Miniflux
v2.3.3, Go 1.26, the version `miniflux/go.mod` pins — over these bytes with `TZ=UTC`. The run is a
scratch package inside a verbatim copy of the clone, because the `internal/` packages cannot be
imported from another module, so nothing in the repository depends on a Go toolchain. Each golden
file pins one value per line as `path = value`, says that its values are the reference's output for
that fixture, names the rule its fixture pins, and says what it cannot show; a value that would
break a line is written escaped, and content longer than the files keep readable is pinned as its
first 120 code points plus its SHA-256, which pins the whole of it.

Only the values named below were traced independently of the run, from the fixture bytes; every
other pinned value rests on the run, which is why the golden files and the test say plainly that a
golden value is the reference's output and not Rivulet's. The independent checks are: the SHA-256
of a GUID, of an entry URL and of an entry ID (`encoding_WINDOWS-1251.xml`, the entry-1 item of
`no_encoding_ISO-8859-1.xml`, which has no GUID, and `small_atom.xml`), the windows-1251 title,
the entry-1 content of `no_encoding_ISO-8859-1.xml` — the no-label path drops the bytes that are
not XML characters — a numeric character reference kept as written inside CDATA, the epoch a date
resolves to, and an entity decoded in a media thumbnail URL. The zone name a date resolves to is
not pinned, because the reference reads it through the machine's tzdata — see `docs/parity.md` —
while the epoch and the offset are. Nothing in this corpus reads a clock, a locale or the network;
the date the RDF items start with is the clock the suite injects.

The URL layer has no fixture corpus, because the reference has none for it: its cases are the ported
tables from `internal/urllib/url_test.go` and `internal/reader/urlcleaner/urlcleaner_test.go`, plus
pins traced against Go's `net/url` source, so each suite says which pins come from the upstream
corpus and which are traced from the source, and `docs/parity.md` records where the traced subset
stops. Nothing in it reads a clock, a locale or the network. The URL rules the sanitizer reads
attribute values through — that a value already read as absolute is written as it was read, that the
control-byte check is the parse's and not the writer's, that the query is not decoded, and that the
entity decoding happens in the tokenizer before the URL part sees the value — are pinned by the
hostile corpus below, which is where the plan's open entity-decoding and whitespace items closed.

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
`Fixtures/sanitizer/hostile_corpus.txt`: 145 inputs that try to make the sanitizer write active
content, each with the output the reference produced for it and the rule that output pins. The
inputs are ours, not upstream's; the outputs were written by running Miniflux v2.3.3 at commit
`c4d54f87` with the reference's test helper options — `OpenLinksInNewTab: true`, base URL
`http://example.org/`, `TZ=UTC` — the same method the parser corpus uses, so a failure here is a
difference in the port. Every case can fail on the rule its line names: a case is not in the corpus
when a wrong implementation of that rule writes the same output, which is what the fixture says.

What it pins is the rules its cases name: the scheme allowlist, the data-URI prefixes, the mandatory
attributes, the pixel tracker, the blocked resources, the hidden check, what a dropped tag leaves of
its content, the control bytes the URL parse refuses while the as-read path does not, the entity
lookup inside an attribute value — which is where the URL part's entity decoding happens, because
the value reaches the URL layer already decoded — the srcset whitespace class, that the URL part
normalizes no whitespace of its own, and the order a formatting element writes its attributes in.
What it cannot pin is content inside `math` or `svg`, which the reference inserts through the
foreign-content rules this port does not have, and the rules an output cannot tell apart, such
as a raw path that is already the canonical encoding, a plus in a query that round-trips to the
same string, an attribute allowlist with a single name, a read order that is already the sorted
order, or the sort tie-break by value, which needs two attributes with the same name. The limit
of 512 open elements in `parse.go` is pinned by the two cases that mirror
`TestDeeplyNestedpage`: the reference reaches it by panicking and its own parse recovers that as
an error, so a chain one past the limit answers with nothing, and the port refuses at the same
count.

The XML tolerance table (`XMLToleranceTests`) is the run the plan's test-plan item asks for: 52
inputs over the four quirk classes, read through `NewXMLDecoder` and `Token()` — the reader path,
not `Decode` — with the same reference and the same method the parser corpus uses, comparing the
token stream and how the stream ends. The run found no divergence, so the table in
`docs/reference-notes.md` records what the reference reports rather than a difference, and
`docs/parity.md` gained no new row there beyond the modeling choice for the end of the stream.
The 30 cases that can fail on the rule they name are committed as the fixture
`Tests/RivuletCoreTests/Fixtures/xml/tolerance_corpus.txt`; a case is left out when a wrong
implementation of its rule writes the same stream, so the suite reads the fixture rather than
carrying the inputs inline. What the corpus cannot pin: the production a run of text came from,
which `Token()` reports as character data either way, and a stream that ends at the end of the
document inside a CDATA section, because the port reports that as the one failure case it has. A
pin cannot fail on the wording of a failure message either, which is why the test compares the case
the message names, and it cannot tell a clean end of the stream from an end reached inside an
element, which is the equivalence recorded in `docs/parity.md`.

The typed error on the parser path (`ParserErrorTests`) is read from the same reference, with
the same method: 10 inputs, each with the rule its line names, comparing what
`DetectFeedFormat` answers, which branch `ParseFeed` takes for that answer, and how the scan
ends. The run found no divergence, so `docs/reference-notes.md` records what the reference
reports rather than a difference. Every case can fail on the rule it names, checked by
patching each rule and reverting: a different case for the typed error fails the five pins
that name it; the JSON rule read after the tokens fails the case whose JSON content is
followed by a real element; the first character read as written, or one buffer read instead of
reading until the first character, fails the case whose whitespace is longer than the buffer;
the count checked after the switch on the name, or read as 60, fails the case whose root is
read as the 51st token; a `version` attribute matched only without a prefix fails the prefixed
case; and an angle bracket inside a quoted attribute value tolerated fails the case that names
the failure. The number the cap counts is pinned only by the pair whose roots sit on the two
sides of the boundary — a cap read as 49 fails the case read as the 50th token and a cap read
as 60 the case read as the 51st — so no case pins it alone, and a case for a root read far
past the cap is left out because a wrong number writes the same answer for it. What no case
can pin: the buffer size, because a larger one writes the same decision for every case; the
characters above ASCII that Go's whitespace class counts, U+0085 and U+00A0, because no case
here has one; the wording of the sentinel; and which adapter the switch calls, since the
outcome compares the branch, not a call.

The format adapters have no fixture corpus of their own. The RSS and RDF suites are the ported
cases from `internal/reader/rss/parser_test.go` and `internal/reader/rdf/parser_test.go`, split
by what the adapter writes — the feed level, the entry level, the attachments, the identity —
plus the pins traced against the reference where the corpus does not reach. The RDF suite has no
attachment or identity cases because the structs this format reads have no such fields, so the
two negative pins there are what the model starts with. Every traced case states the value the
reference produces, and the tree rules the adapters read through — `",chardata"` at the
element's own level, the CDATA marker inside `Inner`, the markup a child contributes to it, and
the last match at the element's own level, which is what the reference assigns a field — are
pinned in `XMLTreeTests` and `RDFEntryTests`, while the default space standing in for a name
with no prefix is pinned in `RSSFeedTests`. The clock the date fallback reads is injected as a
parameter, so no case depends on the machine's time; nothing else in this layer reads a clock, a
locale or the network.

Atom is the seven suites `AtomFeedTests`, `AtomEntryTests`, `AtomTextConstructTests`,
`AtomMediaTests`, `AtomHashTests`, `Atom03Tests` and `AtomLanguageTests`, ported from
`internal/reader/atom/atom_10_test.go` (64 test functions) and
`internal/reader/atom/atom_03_test.go` (10), with the media description rule carried by
`TestDescription` and `TestFirstDescription` from `internal/reader/media/media_test.go`. The tree
keeps character data as the reader resolved it, which is what the reference's `",chardata"` field
holds, so a case whose stated value is text with entities is pinnable, and `",chardata"` keeping
only the level the field is read at is pinned in `XMLTreeTests` and `RDFEntryTests`. The boundary
that cannot be pinned is the xhtml branch: the reference answers `innerxml` — the markup as the
bytes it read — while the tree keeps a reconstruction of the text it read, so
`TestParseEntryWithXHTMLSummary` and `TestParseEntryWithXHTMLContent`, whose stated value keeps an
entity inside the div, are left unported; `TestParseEntryWithXHTMLTitle` is ported because its div
has no entity, where the two answers agree. Each suite names what it ports. `Atom03Tests` also pins
what this format does not read: its structs have no icon, tags, comments or attachments, so those
fields are what the model starts with. `AtomMediaTests` pins the Atom group order and the key its
media thumbnails test the deduplication map against — the value as the element carries it, before
the reference resolves it, which is where the shared media rule has to be the format's own and is
read as a flag on the candidate.

The JSON reader has no corpus of its own, because the reference has no JSON reader code to port: it
reads a feed through `encoding/json`. Its two suites — `JSONScannerTests` for the token machine and
`JSONReaderTests` for the tree — are traced against `scanner.go`, `decode.go` and `stream.go` (Go
1.26, the version `miniflux/go.mod` pins), and every case states the value the reference produces on
the `Decode` path, which is the path the JSON adapter takes. What cannot be pinned is the byte
offset `SyntaxError` carries, which the model does not keep, and the contexts the states name at the
end of input, because `readValue` reports `io.ErrUnexpectedEOF` there and only `checkValid` reports
the space it invents; the pins name the end of input, and `docs/parity.md` records where the traced
subset stops.

The JSON Feed adapter ports `internal/reader/json/parser_test.go` (40 test functions) into
six suites: `JSONFeedTests` for the feed-level chains, `JSONEntryTests`, `JSONAuthorTests`,
`JSONEnclosureTests` and `JSONHashTests` for the entry rules, and `JSONFieldReadTests` for
the field read the adapter reads through, which the reference has no code for and so no corpus
of its own. Each case names the upstream test it comes from, and a traced case states the
value the reference produces. What cannot be pinned is the byte offset `UnmarshalTypeError`
carries and the message the reference builds from it, because nothing in the port reads the
message; the pins name the value word and the type. The rules that can only be pinned by
this layer are the three branches of `JSONAuthors.UnmarshalJSON` and the order the first
failure is recorded in, because the reference has no code of its own for them. One case
asserts a deviation recorded in `docs/parity.md` — the name match is exact, where `foldName`
would also fold — so it states what this layer does rather than what the reference does.

The refresh pipeline suite (`RefreshPipelineTests`) is the integration suite where the fetcher, the
parser, the sanitizer and the storage layer meet: each case runs the pipeline against the stub
server and reads what landed in the database through its own checkout. The pipeline opens the
single write transaction it owns, so a test must not hold a connection across `refresh`: the SQLite
driver keeps one pooled connection per event loop and a nested checkout would wait for it forever.
The clock is the injected seam (`Support/TestClock.swift`), so every stamp a pin reads is the
instant the test supplied, which the process clock could not produce; `SystemClockTests` pins the
other side of the seam, that the production clock answers Unix seconds.
`NextCheckPolicyTests` pins that the delay is added to the clock with the reference's second
precision, which no integration case can show because its delay sources answer whole minutes.
Entry order is pinned
through insertion order read by `ORDER BY id`, not through `created_at`, because the storage clock
is not a seam there. Pins compare the typed error case, not the message wording, because Rivulet
has no locale layer. What the suite cannot pin is stated in the file: the single transaction
itself, because nothing can make one statement inside it fail while the others succeed; the two
columns the reference gates the entry-update branch on, which the schema does not have; the rules
the plan leaves for the later stages; and the icon rules, which this suite does not read at all and
which `IconCheckerTests` and `RefreshIconTests` pin.

The scheduler suites (`SchedulerBatchTests`, `SchedulerTickTests`, `SchedulerOptionsTests`) pin the
tick's batch selection against the builder, because upstream has no test for it: each rule can fail
on its own — strict due-ness, the direction of the ordering, the three rules that read a zero as a
switch (the error limit, the batch size and the host limit), the disabled gate, the host filter
running only on the rows the `LIMIT` read, the host as `Domain` reads it, the missing user scope,
and the feed URL in the job. The tick pins read what the pool was handed and what it reported for
each run, with a recorder runner standing in for the pipeline in the selection pins and the real
pipeline pinned on the worker's non-forced path in the last one, including that the schedule the
pipeline wrote is the one the next tick reads. The pool size is not pinned — a cap cannot be
asserted without a timed wait, which the determinism rules forbid — and the suite header states it;
the order of the outcomes is not asserted either, because concurrency does not fix it. The due pins
read only instants after the process clock — 2065 against a stored schedule of 2061 — so the
injected instant and the process one cannot answer the same batch. The values the batch is built
with are pinned as the reference's defaults in `SchedulerOptionsTests`, and as the readings of
the five variables in `ConfigTests`: each default, and the validators that read three of them as at
least one while the two switches accept zero, because for them zero is the value that means off.

The manual pass (`RefreshCommandTests`) pins the command the plan lists for stage 4: every job of
the batch it reads runs once, so the control rows — a feed not yet due, a disabled feed, a feed at
the error limit — reach no request; a patch that runs a job twice in the pool fails, because the
arrivals are counted per path; the values reach the batch from the environment, so a pin that sets
one of them can fail on a patch that keeps the reference defaults; the run is the worker's
non-forced path, read as the stored validator reaching the request; a job that fails is reported
without stopping the rest, which a patch that propagates the first failure fails; the pass leaves
the schedule it advanced, so a second pass runs nothing; and `RUN_MIGRATIONS` gates the migrations
this command runs. The report is read as the counts, not as the words, because the reference logs
through `slog` and `RivuletCore` has no logging layer. Each feed's site URL is a path of its own,
because the icon checker the run calls asks the server for the site URL: a feed whose site path
were its feed path could not tell the job's request from the checker's. What the pins cannot fail
on is stated in the header: that the pass is one pass (a patch that looped would hang the suite
rather than fail it), the pool cap, the closing of the fetcher the command created, and the
reference's check that the schema is up to date, which this port does not port.

The status contract (`StatusSnapshotTests`, `StatusCommandTests`) pins the minimal feed-state
document the soak reads, which is the port's own shape because the reference has no status command.
The storage half pins that each field is the value the row holds - the pin seeds values that are not
the schema defaults, because a pin reading an empty column can only show that an empty column reads
as `""` rather than as `nil` - and that an absent stamp is read as `nil`; the rows are listed in id
order, which the pins show against the orders the storage would give by reading another column,
because the scan order for these rows is already the id order; the counts read every row whatever
its state; and `due` is the batch's pick, pinned on the values that make each of its rules
falsifiable: a row scheduled at exactly the instant for the strict comparison, a disabled row for
the gate, a batch size of zero for the switch that adds no `LIMIT`, and a window smaller than the
matching rows for the host filter running only on the rows the window read. The command half pins
that `--json` selects the document, that the whole output is the document, that the keys are the
documented ones, that an absent stamp stays `null` rather than becoming `0`, that the human form
carries the row's values as the numbers on its line - read as a set, so the pins cannot tell which
number belongs to which field - that the environment values reach the totals through the command,
that the due count is read against the process clock, and that `RUN_MIGRATIONS` gates the migrations
this command runs. What no pin can show is stated in the headers: that the command fetches nothing
and does not sleep, which clock it is built with, the order of the JSON keys, the order of the
numbers on a human line, the order of rows sharing one `next_check_at`, the closing of the storage
the command opened, and the wording of the human lines, which is the port's own.

The entry-frequency half (`NextCheckPolicyTests`, `WeeklyEntryCountTests`,
`EntryFrequencyPipelineTests`) pins the mode the reference's `PollingScheduler()` selects and the
count the storage layer answers for it: the rounding up, the gap keeping its fraction as the
reference's division does, the week window at its boundary, the user scope, the empty result, the
zero count answering the maximum, and through the pipeline that the count is read before the
entries land. What cannot be pinned there: the order of the two entry-frequency clamps, because for
a pair the reference's validator accepts they commute and for the pair it would reject the mode's
cap is applied again after the delay; the `NULLIF` guard, because SQLite answers a division by zero
as null, which `COALESCE` turns into the same 0; the mode gate in the pipeline, because the round-
robin mode reads the count for nothing; the shape of the ceiling, because exact integer arithmetic
answers the same value as `CEIL` of the reference's real division for every case these pins read;
and the transaction the count read runs inside.

The merge and tombstone half (`PipelineMergeAndTombstoneTests`) pins what the entry loop does not
write: an entry the document no longer declares is left in place, and a tombstoned `(feed_id,
hash)` pair is refused by the insert guard once the entry loop runs on a forced refresh, which is
what makes sure the answer is not a conditional hit. Both pins read the rows through their own
checkout, and the archive runs inside `withTransaction`, because the delete and the tombstone
insert are one atomic step only there. What these pins cannot fail on is stated in the suite
header: the age boundary, the batch limit and the starred rule of the archive, which
`RetentionTests` pins, because the pin that runs the archive runs it on an instant past every
stored row and on a single row; the atomicity itself; the user state an update must not touch,
which the storage suite pins; and the reference's return value, which counts the tombstone rows it
inserted rather than the rows it deleted.

The icon finder half (`IconDocumentLinksTests`, `IconDataURLTests`) pins the two rules of
`internal/reader/icon/finder.go` that read no network: which `link` elements a document offers as
the feed icon, and how a `data:` URL is read. The selector's four branches are pinned one by one,
with the two rules that make them differ from each other — only the three `icon` branches fold case,
and a `rel` is compared as a whole value — plus the href rules (not whitespace-only, and a value the
parse cannot read is skipped rather than passed through) and document order. The scan reads through
the port's tokenizer subset and the charset layer rather than through a `goquery` tree, so the two
cases that come from the tree are pinned as tokenizer facts: a `link` inside a raw-text element is
text, not an element, and `/>` is the self-closing token kind. The data-URL suite pins the shape —
the mediatype is mandatory and has to name an image, the encoding is one of three, data is required
and cannot contain a newline, which is Go's `.` production — and that the three encodings do three
different things, with Go's `QueryUnescape` turning a `+` into a space and refusing a truncated
escape.

The download half of the same file (`IconDownloadTests`, `URLJoinPathTests`, `IconFinderTests`) is
the part that reads the network. `IconDownloadTests` pins how a response becomes an icon: the
checksum covers the body bytes rather than the response as a whole, the content type is the header
as it was read with its parameters, and the status failure is read before the empty-body failure,
which is the order the reference's handler has. It also pins the rule the icon path has and the feed
path does not: the reference reports an empty body through `LocalizedError`, which both paths read,
and `ReadBody` reports an empty buffer for any response, so an icon is a failure on a conditional
hit while the feed path accepts one, because there an empty body means nothing to re-parse.
`URLJoinPathTests` pins the two guards the reference runs before it joins, that the join reads the
escaped path, the `path.Join` cleaning — multiple slashes reduced, `.` dropped, an inner `..`
removing the element before it, and a `..` that begins a rooted path having nothing to remove — that
the trailing slash survives only from the last element, and that the base's query stays after the
path. `IconFinderTests` pins the order end to end against a stub server: the feed's icon URL, then
the website document, then the root document only when it differs from the website URL, then the
default icon joined to the root; the first step that produces an icon stops the search, an earlier
failure is skipped while the last step's failure is the answer, a `data:` href answers without a
request, and the feed's icon URL is read as the icon bytes rather than scanned as a document. What
these three cannot fail on is stated in their headers: the join does not escape what it joins, which
is Go's documented expectation and is pinned only as that it does not escape, while a character the
path mode escapes is written as its escape by the URL layer's own rule; the reference's error
wording, which this port keeps as typed cases; the size cap, which the fetcher applies before this
layer sees the bytes and which no icon case reads; and the basis the empty-body rule measures, which
is `Content-Length` upstream and the bytes read here, so a chunked empty body differs — recorded
rather than pinned.

`IconRepositoryTests` adds the storage half: the dedupe is by hash, the content type is compared as
the whole value so one carrying a parameter is not a known icon type, the link replaces what the
feed row had rather than adding a second mapping, and the orphan pass deletes only icons no feed
points at. The count that pass returns can fail, and is read through `SELECT changes()` because this
SQLKit version gives no row count for a raw statement. The pins cannot fail on the randomness of
`external_id`, which they read only as the shape, nor on the single transaction the reference wraps
the dedupe and the link in — the same boundary the pipeline records. The request headers the icon
path sends are the fetch suite's rules, pinned in `FetchRequestTests` as following the options; that
the icon path sends no conditional headers cannot fail, because there are no stored validators on it
to send.

`IconCheckerTests` adds the checker half — the wiring that runs the search for one stored feed. The
guard stops the search when the feed already has an icon, and it reads the mapping for this feed
rather than the icon table, so a patch that answers from any stored row with the same hash fails the
pin that runs the search for a feed with no mapping of its own. Storing and pointing are two
decisions that both run on either branch, so a patch that stores without pointing, and a patch that
points only on the branch it inserted on, fail the pins that name those; the guard belongs to the
missing path only, which a patch that applies it to the other path fails. A failing search writes
nothing, and the request carries the feed's user agent, which a patch that hands the builder nothing
fails. What the pins cannot fail on is stated in the header: the reference logs each failure, so a
swallowed failure reads only as the call completing with nothing written, and the reference can
answer
with no icon and no error through its resize step, which is not ported, so no case here can answer
without an icon. The dedupe, the content-type normalization, the single transaction and the join
table
are the storage suite's rules, read here only as the values the checker passes on, and the guard
read
cannot show that a read which fails answers the same as a read that finds nothing: the pins name the
decision, not the mechanism. The user agent is pinned only as the value the checker hands to the
builder, not as which value wins when the feed row carries none.

`RefreshIconTests` pins the call the refresh path makes for a feed, which is where the checker is
reached from: the modified branch runs it and the conditional-hit branch does not, so a patch that
calls it on the other branch fails the pin that reads a hit against a stored validator. The fork the
forced flag selects is pinned from both sides — the guard on the path the flag does not select, and
the mapping moving on the path it does, which a patch reading a flag of its own fails. The icon URL
is the value the parse produced, read by giving the parse's path and the scan's path different
answers on the stub server, and the site URL and the user agent are read from the row, which a patch
reading the parse's site URL or handing the checker nothing fails. What the pins cannot fail on is
stated in the header: the order of the statements inside the transaction, because a pin reads what
the commit left rather than the order the writes ran in, so the checker running before the error
counter is reset and before the validators are written cannot be shown.

What the selector and data suites cannot fail on is stated in their headers: the selector's test
that the `href`
attribute is there at all, because a missing attribute reads as the empty value and the same guard
answers for both; the checksum function itself, since the reference hashes an icon with FNV-128a and
this port with SHA-256 — the pins can fail only on which bytes the checksum is taken over; Go's
base64 decoder accepting an unpadded last quantum, which this port refuses; and the reference's
logging, which this port has no layer for. What the pins do reach through another layer — the URL
resolution and escaping, the charset layer, the tokenizer's lowercasing and value decoding — is
named in the headers as read through the scan, with the rules themselves pinned by those suites.

## Soak

`Scripts/soak.sh` is the stage-4 artifact the plan names: at least 2h over at least 20 local stub
feeds, one round per cadence step, with a `status --json` snapshot after each pass. It is not a test
and it is not in CI — it is a real-time run against a real HTTP server and the process clock, so the
determinism rules above do not apply to it, and `swift test` stays the suite CI runs.

Its checks are `Scripts/soak_check.py`, and each is a function over the data a round leaves behind —
the two snapshots, the instants the round recorded, the values the run declared and what the
database answers — rather than an assertion about a live process. That is what makes each of them
falsifiable: `python3 Scripts/soak_check.py --probe` crafts one input per rule that violates it and
asserts that the rule reports it alone, and the same rules read a real round's files, so a probe is
not a different machine from the run. What the rules read is the contract `StatusSnapshotTests` and
`StatusCommandTests` pin, so the soak re-reads a pinned shape over 2h rather than pinning it again.
A probe falsifies the report against the pick the checker computes, not the pick's own rules — those
are pinned by `SchedulerBatchTests` — and the two probes that break a count state which of the two
they report on.

What the soak shows is the rule each round reports: the pass ran exactly the pick the rules make,
the last-fetch stamp moved forward on every row it ran, the schedule moved forward and landed after
the round, the counts match the rows, the error feed increments while the pick can reach it, the
document is the documented contract, and the database kept no duplicate `(feed_id, hash)` pair. The
three control rows are what make the gates readable in the run — one row that is never due, one
disabled, one seeded at the error limit — because a rule that excludes a row needs a row to exclude.

What it cannot show, and the script and the checks say so:

- that the run slept, or that the cadence was the scheduler's: the in-process loop is stage 6's, so
  the shell is the cadence here, and the number of rounds is not evidence that anything was fetched,
  because a round that finds nothing due runs no job;
- the request itself: the checks read the stamps the storage wrote, so a run that stored the same
  stamps by another route would read the same. The live run does reach the server, and the log keeps
  the reports the command printed, which is the part a check cannot turn into an assertion;
- the cadence the schedule keeps: the interval is the mode's, not the `<ttl>` the stub feeds
  carry, because the policy takes the maximum of the two, so "the stamps advance" means two
  advances per feed in 2h — the two hour boundaries inside the window — and the conditional-hit path
  is reached on the second fetch of a feed that did not change, which is the last fetch a 2h window
  reaches;
- the instant the due check compares against is the one the shell recorded just before the status
  command read it, so a row crossing the due boundary between the two reads as a violation — a false
  failure rather than a false pass, which the check states;
- the guards on the run's own numbers — the duration, the number of feeds, the window being at least
  as large as the rows, the database being fresh — can fail, and each was seen to fail by declaring
  a value below what it requires; that is the whole of what they can show.

## Running

- `swift test` — everything (unit + integration); this is what CI runs.
- `swift test --filter RivuletCoreTests` — unit only (fast loop).
- `swift test --filter RivuletIntegrationTests` — integration only.
- `Scripts/soak.sh` — the soak run, outside CI. `python3 Scripts/soak_check.py --probe` checks that
  each of its rules can fail on the rule it names.
- Heavy suites (100k-entry benchmarks, big-feed scenarios) are disabled by default and enabled
  by an `.enabled(if:)` trait gated on `RIVULET_HEAVY`; run them explicitly with
  `RIVULET_HEAVY=1 swift test --filter HeavyTests`.
- A few storage tests need at least two event loops (one pooled connection per loop); they
  `Test.cancel` on single-loop runners. CI runners always expose ≥2 event loops.

CI runs on Linux: `ubuntu-latest` with the `swift:latest` container and a 15-minute job timeout.
Keep the default suite well under that. Stage 7 adds a cheap CI slice (reduced hostile corpus +
reduced large-feed smoke); the full parity harness runs on demand via `Scripts/parity.sh`.

## Framework

Swift Testing everywhere (`import Testing`, `@Suite`/`@Test`, `#expect`/`#require`) — one
framework, no mixing; XCTest and `XCTVapor` are not in the tree. Tests run in parallel by
default and every test owns its resources (temp directories, kernel-assigned ports), so no
suite depends on execution order. Use the `.serialized` trait only where a suite must share
process-wide state.
