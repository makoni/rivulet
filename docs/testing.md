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
tolerance table and the parser error corpus | | Integration | `Tests/RivuletIntegrationTests` | Real
SQLite in a temp dir, local stub feed server, the full Vapor app over real HTTP | | Soak |
`Scripts/soak.sh` with `Scripts/soak_check.py` | A real-time run over local stub feeds, run by hand
and not in CI: its checks read the data each round leaves behind |
| Acceptance | `Tools/parity` with `Scripts/parity.sh` (stage 7) | Semantic comparator over observable behaviour against real Miniflux in Docker, run by hand and not in CI: its rules read the pair document the run leaves behind, and the tolerance table is read as data from `docs/parity.md` |

The integration test target is added to `Package.swift` in stage 0 (no `XCTVapor`: app tests speak
to a real socket through Vapor's client). Fixture files are target resources (`resources:
[.copy("Fixtures")]`, read via `Bundle.module`), as stage 3 landed them. Part of this level spawns
the built executable rather than running the app in-process; that is the process harness described
below, and it is what reads the facts only a process can answer.

## Workflow (TDD)

1. Write a failing test that describes the behavior. 2. Implement the minimal change to make it
pass. 3. Refactor with tests green. 4. Bug fixes start with a regression test that reproduces the
bug.

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
answer as they did before it. It moved out of `MaintenanceCommandTests` with PR #53, when a second
suite started reading it.
- `RecordingVerifier.swift` — the `DatabaseVerifier` seam the verify pins drive: answers the
problems the pin names and records the calls the run made through it, with whether the file was
already there at the call, which is how a pin reads the check as running after the write rather
than before it. The recording is a read the helper makes on the filesystem itself, not a rule the
check applies, so a pin that reads the check as not running answers a control that does run it.

- `DatabaseContent.swift` — the content read the command suites share: the tables a file holds and
one digest line per entry, ordered by id, read through SQL, so a pin is not satisfied by the read it
is testing. `content(at:on:as:)` reads a file through its own driver, which is what the copy pins
need, because the copy is not the connection the test seeded with. It moved out of
`MaintenanceCommandTests` with PR #53, the third suite reading the content read after
`MaintenanceTests` and `MaintenanceCommandTests` themselves, which read it at different levels.

- `StubFeedServer.swift` — in-process HTTP server serving feed fixtures with configurable behavior:
status codes, `ETag`/ `Last-Modified`, gzip, redirects, delays (before the answer, or after the head
so a body can arrive later than a deadline), cut connections, chunked responses, charset headers.
**Binds port 0** and exposes the assigned address; no fixed ports. It records every request it
receives (target and headers) so a test can check what the client actually sent, and
`waitForRequest(for:)` waits for one to arrive — check and wait in one step under the lock — so a
test can act while a request is in flight without polling or sleeping, which holds only while the
answer is still pending: a quick response releases the client before the test can act. The cache
test therefore holds the body back. The proxy tests use `StubProxy`, not this server.
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

The cache has four behaviour tests. The first pins the one effect that can be observed from outside
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
and the entry the trim closes being the one whose expiry comes first — 2 pins and 2 probes, which
the security-checklist section below lists with the rest of this pass. That a call overlapping the
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
`Fixtures/sanitizer/hostile_corpus.txt`: 146 inputs that try to make the sanitizer write active
content, each with the output the reference produced for it and the rule that output pins (145 from
stage 3, plus the entity-table case the stage-7 security checklist added). The
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
`docs/reference-notes.md` records what the reference reports rather than a difference, and
`docs/parity.md` gained no new row there beyond the modeling choice for the end of the stream. The
30 cases that can fail on the rule they name are committed as the fixture
`Tests/RivuletCoreTests/Fixtures/xml/tolerance_corpus.txt`; a case is left out when a wrong
implementation of its rule writes the same stream, so the suite reads the fixture rather than
carrying the inputs inline. What the corpus cannot pin: the production a run of text came from,
which `Token()` reports as character data either way, and a stream that ends at the end of the
document inside a CDATA section, because the port reports that as the one failure case it has. A pin
cannot fail on the wording of a failure message either, which is why the test compares the case the
message names, and it cannot tell a clean end of the stream from an end reached inside an element,
which is the equivalence recorded in `docs/parity.md`.

The typed error on the parser path (`ParserErrorTests`) is read from the same reference, with the
same method: 10 inputs, each with the rule its line names, comparing what `DetectFeedFormat`
answers, which branch `ParseFeed` takes for that answer, and how the scan ends. The run found no
divergence, so `docs/reference-notes.md` records what the reference reports rather than a
difference. Every case can fail on the rule it names, checked by patching each rule and reverting: a
different case for the typed error fails the five pins that name it; the JSON rule read after the
tokens fails the case whose JSON content is followed by a real element; the first character read as
written, or one buffer read instead of reading until the first character, fails the case whose
whitespace is longer than the buffer; the count checked after the switch on the name, or read as 60,
fails the case whose root is read as the 51st token; a `version` attribute matched only without a
prefix fails the prefixed case; and an angle bracket inside a quoted attribute value tolerated fails
the case that names the failure. The number the cap counts is pinned only by the pair whose roots
sit on the two sides of the boundary — a cap read as 49 fails the case read as the 50th token and a
cap read as 60 the case read as the 51st — so no case pins it alone, and a case for a root read far
past the cap is left out because a wrong number writes the same answer for it. What no case can pin:
the buffer size, because a larger one writes the same decision for every case; the characters above
ASCII that Go's whitespace class counts, U+0085 and U+00A0, because no case here has one; the
wording of the sentinel; and which adapter the switch calls, since the outcome compares the branch,
not a call.

The format adapters have no fixture corpus of their own. The RSS and RDF suites are the ported cases
from `internal/reader/rss/parser_test.go` and `internal/reader/rdf/parser_test.go`, split by what
the adapter writes — the feed level, the entry level, the attachments, the identity — plus the pins
traced against the reference where the corpus does not reach. The RDF suite has no attachment or
identity cases because the structs this format reads have no such fields, so the two negative pins
there are what the model starts with. Every traced case states the value the reference produces, and
the tree rules the adapters read through — `",chardata"` at the element's own level, the CDATA
marker inside `Inner`, the markup a child contributes to it, and the last match at the element's own
level, which is what the reference assigns a field — are pinned in `XMLTreeTests` and
`RDFEntryTests`, while the default space standing in for a name with no prefix is pinned in
`RSSFeedTests`. The clock the date fallback reads is injected as a parameter, so no case depends on
the machine's time; nothing else in this layer reads a clock, a locale or the network.

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

The JSON Feed adapter ports `internal/reader/json/parser_test.go` (40 test functions) into six
suites: `JSONFeedTests` for the feed-level chains, `JSONEntryTests`, `JSONAuthorTests`,
`JSONEnclosureTests` and `JSONHashTests` for the entry rules, and `JSONFieldReadTests` for the field
read the adapter reads through, which the reference has no code for and so no corpus of its own.
Each case names the upstream test it comes from, and a traced case states the value the reference
produces. What cannot be pinned is the byte offset `UnmarshalTypeError` carries and the message the
reference builds from it, because nothing in the port reads the message; the pins name the value
word and the type. The rules that can only be pinned by this layer are the three branches of
`JSONAuthors.UnmarshalJSON` and the order the first failure is recorded in, because the reference
has no code of its own for them. One case asserts a deviation recorded in `docs/parity.md` — the
name match is exact, where `foldName` would also fold — so it states what this layer does rather
than what the reference does.

The refresh pipeline suite (`RefreshPipelineTests`) is the integration suite where the fetcher, the
parser, the sanitizer and the storage layer meet: each case runs the pipeline against the stub
server and reads what landed in the database through its own checkout. The pipeline opens the single
write transaction it owns, so a test must not hold a connection across `refresh`: the SQLite driver
keeps one pooled connection per event loop and a nested checkout would wait for it forever. The
clock is the injected seam (`Support/TestClock.swift`), so every stamp a pin reads is the instant
the test supplied, which the process clock could not produce; `SystemClockTests` pins the other side
of the seam, that the production clock answers Unix seconds. `NextCheckPolicyTests` pins that the
delay is added to the clock with the reference's second precision, which no integration case can
show because its delay sources answer whole minutes. Entry order is pinned through insertion order
read by `ORDER BY id`, not through `created_at`, because the storage clock is not a seam there. Pins
compare the typed error case, not the message wording, because Rivulet has no locale layer. What the
suite cannot pin is stated in the file: the single transaction itself, because nothing can make one
statement inside it fail while the others succeed; the two columns the reference gates the
entry-update branch on, which the schema does not have; the rules the plan leaves for the later
stages; and the icon rules, which this suite does not read at all and which `IconCheckerTests` and
`RefreshIconTests` pin.

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
with are pinned as the reference's defaults in `SchedulerOptionsTests`, and as the readings of the
five variables in `ConfigTests`: each default, and the validators that read three of them as at
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
because the icon checker the run calls asks the server for the site URL: a feed whose site path were
its feed path could not tell the job's request from the checker's. What the pins cannot fail on is
stated in the header: that the pass is one pass (a patch that looped would hang the suite rather
than fail it), the pool cap, the closing of the fetcher the command created, and the reference's
check that the schema is up to date, which this port does not port.

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
zero count answering the maximum, and through the pipeline that the count is read before the entries
land. What cannot be pinned there: the order of the two entry-frequency clamps, because for a pair
the reference's validator accepts they commute and for the pair it would reject the mode's cap is
applied again after the delay; the `NULLIF` guard, because SQLite answers a division by zero as
null, which `COALESCE` turns into the same 0; the mode gate in the pipeline, because the round-
robin mode reads the count for nothing; the shape of the ceiling, because exact integer arithmetic
answers the same value as `CEIL` of the reference's real division for every case these pins read;
and the transaction the count read runs inside.

The merge and tombstone half (`PipelineMergeAndTombstoneTests`) pins what the entry loop does not
write: an entry the document no longer declares is left in place, and a tombstoned (feed_id, hash)
pair is refused by the insert guard once the entry loop runs on a forced refresh, which is what
makes sure the answer is not a conditional hit. Both pins read the rows through their own checkout,
and the archive runs inside `withTransaction`, because the delete and the tombstone insert are one
atomic step only there. What these pins cannot fail on is stated in the suite header: the age
boundary, the batch limit and the starred rule of the archive, which `RetentionTests` pins, because
the pin that runs the archive runs it on an instant past every stored row and on a single row; the
atomicity itself; the user state an update must not touch, which the storage suite pins; and the
reference's return value, which counts the tombstone rows it inserted rather than the rows it
deleted.

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
answer with no icon and no error through its resize step, which is not ported, so no case here can
answer without an icon. The dedupe, the content-type normalization, the single transaction and the
join table are the storage suite's rules, read here only as the values the checker passes on, and
the guard read cannot show that a read which fails answers the same as a read that finds nothing:
the pins name the decision, not the mechanism. The user agent is pinned only as the value the
checker hands to the builder, not as which value wins when the feed row carries none.

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
that the `href` attribute is there at all, because a missing attribute reads as the empty value and
the same guard answers for both; the checksum function itself, since the reference hashes an icon
with FNV-128a and this port with SHA-256 — the pins can fail only on which bytes the checksum is
taken over; Go's base64 decoder accepting an unpadded last quantum, which this port refuses; and the
reference's logging, which this port has no layer for. What the pins do reach through another layer
— the URL resolution and escaping, the charset layer, the tokenizer's lowercasing and value decoding
— is named in the headers as read through the scan, with the rules themselves pinned by those
suites.

The stage-5 contract suites pin the reference's output as values inside the suite rather than as
fixture files, because each of those pins reads one answer for one rule rather than a corpus.

The suites PR #42 built are `GoogleReaderItemIDTests`, `GoogleReaderStreamTests`,
`GoogleReaderQueryTests` and `GoogleReaderRequestModifiersTests`; their goldens are the reference's
output at the toolchain `go.mod` pins, and each pin was seen to fail on the rule it names by
patching that rule and reverting — one probe per rule. The probe for the escape bounds traps instead
of answering, which is what the pin says that rule does: it reads past the end of the pair. Two pins
that were written and then removed are recorded here because they cannot fail on their own: the
continuation rule answers the sum for whatever count it is given, so which count the handler gives
it is not a rule the pure side can pin — the handler suite pins it over a socket, on the page where
the sum is below the total and the page where it is not; and the pin that only said the read reports
no error for `?s=`, which the list read's skip of the empty value already settles, so it could not
fail on its own. The other rules these four headers name as unpinnable are the count `fmt.Sscanf`
reports, which has no input that can fail, the order the two stream prefixes are removed in, which
no input this side can build is affected by, the error `r.URL.Query()` discards, which has no answer
this side can show, and the read `WithOffset` never reaches, because the parameter read already
answers the default for the value that would reach it.

PR #43 adds three suites pinned the same way: `GoogleReaderTagsTests`, `GoogleReaderOutputTests` and
`GoogleReaderShapeTests` — one probe per rule, 28 probes, all showing their pin failing. Four probes
could not bite at first and are recorded here. The order pin reads `add read` with `remove
kept-unread`, where the add loop's write is what the remove guard sees; moving only the loop headers
did not change that answer, so the probe patches the whole two loop blocks. The guard patch for the
same pin includes the value the guard writes, because the guard line alone appears in both loops.
The unsupported pin could not fail on a patch that wrote that wording for every type, so it now
reads a second type the same branch answers for; and the escape pin could not fail on a patch that
named the pair from its start, because the value it read began at the percent, so that probe patches
both guard sites. One pin was written and then removed because it cannot fail on its own: the pin
that said a `+` in the value is the space the read gives answers the check's error whatever the
mapping does, because the guard compares the value with `json`, and no value that carries a `+` can
equal it; the `+` rule is pinned by the query suite and by the login's form read. What these headers
name as unpinnable: the add loop's `read` guard, which asks for a map key that loop never writes so
it can never fire; the guard that an empty add and an empty remove answer the reference's own
wording, which is the handler's rule; which document a handler builds, which is the handler's
choice; and the `%q` quoting of the escape wording, which `docs/parity.md` already records as a
divergence. Which endpoints apply the output check was named there as the handler's choice and is
now pinned by the handler suite.

### The handlers (`GoogleReaderHandlerTests`, PR #44)

The handlers are pinned over a real socket, and the status the response builder writes for each
error is pinned by `GoogleReaderResponseStatusTests`, which reads the builder directly. 40 probes,
one per rule, each showing its pin failing on the rule it names, all of them biting on the first
attempt. Two rules need two patches because the wrong handler is a place the code does not read: the
output check `user-info` does not apply has to be added to the handler and the query has to reach it
through the route, and the order that reports the tag error before the item read needs the guard
moved as well as the read moved. The form read's PostForm rule needs two inputs so each side name
bites on its own assertion: the input where the body has no `a` at all, and the input where only `r`
is in the query.

What the handler pins cannot fail on is named in the suite header. The user-info guard that a row
found by the auth read is read back has no request this suite can build, because a request that
reaches the handler already authenticated against that row, so the status mapping for that shape is
pinned directly. The handler's own answer for a form the read cannot parse is answered as 401 by the
transport first; the two storage write sets are disjoint for every input that reaches them, so their
order cannot be read; the reference reads the integration settings after the write, which this port
has none of; a storage-layer failure has no input this suite can make it report; and the method
mismatch, where the reference answers 405 for a path that has an exact pattern for another method,
is recorded in `docs/parity.md` rather than pinned here.

### The three write handlers (`GoogleReaderWriteHandlerTests`, PR #45)

`rename-tag`, `disable-tag` and `mark-all-as-read` are pinned over the same socket, with the storage
reads they use pinned by `CategoryRepositoryTests` and the `ts` rule pinned as pure logic by
`GoogleReaderTimestampTests`. 51 probes, one per rule, each showing its pin failing on the rule it
names, all of them biting on the first attempt. A probe is a patch run, so the counts are records of
the runs rather than counts of assertions: one probe can patch several places, and one patch can be
read through two pins.

One probe patches three places, because the rule it names is which handlers apply the output check:
a patch that added the check to one handler left the other two answering the write, so the three are
patched at once. One probe reads the same pick patch through both pins the pick reaches — the
storage pin and the socket pin — because the socket pin is the handler reading the same rule. Two
pins need an input that applies to both halves of the rule: the input that fails the type check and
the empty-destination guard at once, which is what shows which of the two runs first, and the input
where the first value of the list passes the guard and the second does not, which is what pins that
the guard runs per value rather than on the first value only. The guard-before-delete pin needs a
row it can actually delete: the pin seeds the row the failing input names, so a patch that ran the
guard after the delete answered `OK` and deleted that row. The pin then runs a write that does
delete it, so the two halves of the rule are shown by the same pin.

The delete pin needs data where the pick has two rows to choose between, because a pick with one
candidate answers the same whatever it compares; its input names two of the user's categories and
leaves two, and the pick is pinned as the smallest title left, which a patch that reversed the
comparison fails on. What the row order that read answers its rows in cannot be pinned: the
statement has no `ORDER BY`, so the rule the pins read is the comparison, not the order the rows
come back in. Each `ts` pin reads its own feed, so a request that marks the whole feed cannot mark
the row another assertion reads, and what the sign guard pins is its presence rather than its order
against the length test, because both apply to every value the guard accepts. The two per-user
filters of the delete path are pinned separately, because each has its own: the guard read is pinned
by the input that would leave this user with no row while another user has rows the same input
names, and the delete statement is pinned by another user's row with the same title as one of the
names, which the read that builds the ids cannot show.

What these pins cannot fail on is named in the suite header: the handler's own answer for a form the
read cannot parse, which the transport reports as 401 first; the transaction boundary the delete
path runs inside, because no pin can make a statement fail in the middle of one; the rule that a
feed id of 0 selects nothing, which a patch that skipped a non-positive value answers the same way;
the message the handler writes for the rule the socket cannot reach, because the empty-destination
guard answers before it; the storage wordings for a failure this suite cannot trigger, apart from
the guard the delete path makes itself; the reference's localized strings for the two category
rules, which the port does not reproduce — it writes the rule name, and the keys are recorded in
`docs/reference-notes.md`; and the order of the two statements of the delete path, which is the same
for every input that reaches them.

### The content handler (`GoogleReaderContentHandlerTests`, PR #46)

`stream/items/contents` is pinned over the same socket, with the storage read it builds on pinned by
`EntryContentsReadTests`, the categories rule for one item by `GoogleReaderItemCategoriesTests` and
the document shapes by `GoogleReaderShapeTests`. 47 probes, one per rule, each showing its pin
failing on the rule it names, all of them biting on the first attempt. The goldens are the
reference's own output for the same inputs at the toolchain `go.mod` pins.

Four pins needed data that is not what the fixture default already is, because a pin whose data
follows the rule cannot show a wrong read. The read suite's order pins read the column and the
direction separately, so the row published later is seeded first: the id order and the publication
order are then two different answers, and a patch that ordered by the id fails on both — the handler
pin reads the source of the order value instead, which bites on its own input. The origin pins need
the feed id and the entry id to be two different numbers, so an extra feed row is seeded before the
entry is. The status and the flag pins seed the row with values that are not the fixture defaults
for those two columns. The item id is written by the pin's own helper in the full reference form,
with the prefix, because the first golden program wrote the padded hex without it, and a pin that
reused that output could not fail on a patch that dropped the prefix or wrote the decimal form.

Two pins read names they have to keep distinct: the document author pin seeds the account name and
the integration column with two different values, and the item author pin writes the entry's own
author, so the three names in the answer are three values. The attachment pins seed two rows with
two different sets, because a patch that attached the whole page's attachments to every row answered
the same for one row.

One rule cannot fail here, and the suite header names it as unpinnable rather than pinning it: the
page size, because this port's read for this endpoint has no `LIMIT` clause at all — the reference's
`fetchEntries` has none either — so a handler that passed the value `n` to the query could not
change the answer. The pin that names it records that both rows the ids name are written, whatever
the page size says.

The document time is pinned by the assertion that compares it with the time the request ran at; the
other whole-document pins read the time from the answer, because a pin that wrote the time it
computed before the request could fail on the handler running at a later second. The shape probes
patch the key order inside the `.object([...])` lists of `GoogleReaderShape`, where each entry
carries a trailing comma that the patch has to keep, and the attachments probe reads a dictionary's
values, so its patch writes `Array(...)` rather than the sequence.

### The feed commands (`FeedCommandTests`, PR #47)

The three commands are pinned through the in-process console over a temp database, with the rule as
pure logic (`FeedValidationTests`), the storage reads as reads (`FeedManagementReadsTests`) and the
commands as runs (`FeedCommandTests`): 17 pins and 25 probes, one per rule, each showing its pin
failing on the rule it names, all of them biting on the first attempt.

The guard's category half is read with `0` and with a negative id, so the pin shows the rule is the
positive-number rule rather than the zero test: the patch that reads `== 0` answers `nil` for the
negative input.

Pins that name an order need data where two rules conflict on one input. The empty url fails the
guard and the URL rule at once, so the rule the run reports is the one that runs first; the relative
url is seeded as a row the account already has, so the same input fails the URL rule and the
duplicate read. The listing pins read the two halves of the order apart: the counts put a row with
the alphabetically first title last, and the pair inside the equal counts is the pair that separates
only under the lowercased reading. The delete pin seeds the same url on two accounts, because a pin
that read one row could not show which account the delete applied to.

The pins read the rows back through SQL, so a pin is not satisfied by the read it is testing, and
each pin is handed both all the rows read back and the rows the run wrote: "a failing run writes
nothing" is read as the rows that were not seeded, which counting every row could not tell apart
from the seed. The account pins need different account sets — one account, several accounts, and a
run whose named account has no row — so the helper takes the accounts it seeds rather than a fixed
graph.

What the headers name as unpinnable: the single-row limit of the duplicate read, because the
schema's `UNIQUE (user_id, url)` means that read can never have two rows to choose between; the
order between the duplicate read and the category read at the command level, which the pure suite
pins and which the command cannot reach, because a category name it cannot resolve answers `0` and
the guard runs before the category read; the rows below the feed at the command level, which the
read suite pins for the same delete; the case-insensitivity of the account lookup as a storage rule,
where the command pin is pinnable only on the patch that compares the name as read rather than
reading it through the lookup; the wording of the console lines and of the reported failures; the
rules the port names rather than the reference; the fetch these commands do not make; and the
columns the listing selects.

### The maintenance commands (`MaintenanceCommandTests`, PR #48)

The two commands are pinned as runs through the in-process console over a temp database: 12 pins and
17 probes, one per rule, each showing its pin failing on the rule it names — the 9 pins and 12
probes landed with PR #48, the 3 pins and 5 probes for the free-space check with PR #52. The storage
rules they call are pinned as storage rules by `MaintenanceTests`, so what these pins read is the
command's own choice: the destination as the command read it, the copy as the snapshot rather than
the file bytes, a destination the command did not create, and the file rebuilt without losing a row.

The run helper and the content read these pins use moved to `Support/` with PR #53, which is the
second suite reading them, so the 17 probes were re-run on the moved shape: the boundary read as
strictly less still flips the two run pins that read the room. The pins read the same rules as
before, only through the shared helper.

The pins are falsifiable through the shape the data has to be in. The snapshot pin needs the source
to hold free pages and one row that lives only in the WAL, so a patch that copied the file bytes
answered a copy without that row and with the size of the bloated source. The independence pin needs
a row written after the run, so a patch that pointed the destination at the source — a link —
answered it with that row, which a pin that read the copy only at the run could not have shown. The
refusal pin needs a row written after the control run, so an overwrite answers a copy that carries
it while the copy read after the refused run does not; the same pin reads the bytes it wrote on a
destination that is not a database, which a pin that read only the failure could not tell from an
overwrite. The source pin reads the file at the path the environment names, not its size, because
the checkpoint at the end of a run moves the rows from the WAL into the main file, so a patch that
moved the source is shown by the file being gone rather than by a content read on a connection that
had already opened it. The migration pin reads the schema the command created rather than one the
test built, on both sides of the flag and on both commands.

What the headers name as unpinnable: the truncating checkpoint `vacuum()` ends with, because
`RivuletApplication.shutdown()` runs a best-effort truncating checkpoint after every command, so a
patch that dropped the checkpoint from the run still left an empty WAL; which file the environment
names, which `ConfigTests` pin, so the vacuum pin can fail only on the patch that does not run the
rebuild at all; reusing an existing empty destination file, which `MaintenanceTests` pin; the size
of the main file before the run, for the reason above; that the copy is a plain file with no `-wal`
beside it, which no implementation of this command would write; the shape guards that read what the
pin built before the run — the WAL holding one row, the file bloated past the size the pin reads,
the copy being openable as a database — which bite only on the storage rules `MaintenanceTests`
pins, not on a patch of the command; the wording of the lines and of the reported failures; that
these commands fetch nothing and sleep nothing; and the rules the port names rather than the
reference, which has no command here to compare with.

### The listing command (`ListingCommandTests`, PR #49)

`list` answers one listing per run: the flags name which read the run makes, and no flag means the
feeds. 9 pins and 13 probes, one per rule, each showing its pin failing on the rule it names, all of
them biting on the first attempt. The two orders the reads answer in are already pinned as reads by
`CategoryRepositoryTests` and `UserRepositoryTests`, so what these pins read is the command's own
choice: the read the flag names, the account the run applies to the categories and not to the
accounts, the rule the run reports for the pair of flags, the values on the line as the stored rows,
one line per row, and that the run writes nothing.

The dispatch pin needs data where three readings answer differently: the position read puts `Tech`
first, the title read puts `News` first, and the feed row carries a title no category has, so a
patch that ran the feed read for both flags answered this pin with the feed title and no username,
and a patch that ran the position read answered `Tech` first. The account pin needs two accounts
with their own categories, because a pin that read one row could not show which account the run
applied, and the same pin reads that both accounts answer for the account listing, which is the
shape of the upstream read: it has no account condition, so the run resolves no account for it.

Pins that read a value off the line are falsifiable only against the default the schema would
answer. The position pin seeds `7` on a row whose id is not 7, so the number on the line has to be
the stored one, and the flag pin seeds `true` on one account while another keeps `false`, so a patch
that printed the default answered the wrong value on both sides. The line pin reads the header as
the one line that carries no row, so it can fail on a row printed twice or on two rows folded into
one line, and not on the wording of the header.

What the header names as unpinnable: the wording of the lines and of the reported failures apart
from the values the pins read off a line and the rule name the run writes; a flag the command does
not know, which the command-signature parser rejects before the command runs, so no pin can reach
it; which fields a line carries and in what order on the line, which is the port's choice; the
header line, read only as the one line that is not a row; the `position` column, which is the port's
own and has no reference counterpart, and the `hide_globally` column the reference's read selects
and this port's schema does not have; the single-row limit of the reads; the account resolution
itself, which `FeedCommandTests` pin, so what is new here is only that the resolution reaches these
reads; the flag that gates the migrations, pinned for the same command there; that these commands
fetch nothing and sleep nothing; the two guards that read what the pin built before the run — the
three row ids in the dispatch pin and the row id in the position pin, which the default category the
user create writes makes always the second row — which bite only on the storage rules; and the
collation the reference's Postgres answers `ORDER BY title` with, which this port cannot have, so
the pin reads the port's byte order only.

### The cadence loop (`CadenceLoopTests`, PR #50)

The loop is pinned as the calls it makes through its seam, which is all a sleeping loop leaves a
test to read: the pins drive a recorder that writes the interval it was given, the instant each read
answered, and each job the runner saw, so a pin can name which call happened without waiting. 8 pins
and 8 probes, one per rule, each showing its pin failing on the rule it names. The probe for the
interval rule was first written as `Duration.hours(1)`, which does not compile, and bites when
written as `Duration.seconds(3600)`; after that all eight bite with byte-identical revert. The red
run is the absence of the loop and the seam: the pins name rules the port did not have yet.

What the pins read: that the loop waits before the first read, which is the reference's shape,
because `for range time.Tick` fires only after the interval; that every wait is given the interval
the loop was built with, named apart from the reference's hour so a pin can tell the value it was
handed from the value it could have written itself; that there is one read per wait; that each read
answers the instant the clock gives at that read; that a failing read is reported and the loop runs
again; that an empty read reports nothing; that nothing is read after the seam answers stop; and
that the jobs of a tick run before the next read, which is the port's shape, since the reference
pushes the batch to a channel without awaiting it.

The rows the pins seed are due before the read that answers them, because the batch rule is strict
`<`: a row stamped at the read's own instant answers nothing, so a pin that read only the order of
the calls could be satisfied by a loop that never read. The recorder and the clock are classes
marked `@unchecked Sendable`, because the `Clock` seam has a synchronous `now()`, which an actor
cannot conform to; the loop reads the clock once per read and the test moves it between reads, so
nothing is read while it is moved; the appends to the recorder run under a lock, because the workers
of one tick can record at the same time.

What the header names as unpinnable: that any time passes, since the seam stands in for a sleep; the
number of iterations, which is the answer the seam gives rather than a rule of the loop; the order
the jobs of one tick are recorded in, which concurrency does not fix, so the pins read the calls
across the boundary of a tick; the shape and the field names of a report, which are the port's
choice; the names the pins read the calls by, which the test writes; that the reference has no stop
rule at all, so these pins read only that the loop obeys the seam's answer; the reference's second
ticker for the cleanup tasks, which this port has no loop for and which `RetentionTests` pin as
storage rules; the pool cap; the real seam implementation, which sleeps, so the pins read its
decisions through test seams with a zero interval (`SystemCadenceTests`) and the real signal path
lands with the process harness; the wiring that starts the loop for `serve` and the signal that asks
it to stop, which the process-level suite pins; and the reference's log lines, which have no layer
here.

### The process harness (`Support/SpawnedProcess.swift`, PR #51)

The harness spawns the built binary — the sibling of the test runner in `.build/debug`, which is
where CI leaves it — and reads events rather than time: the line the child writes naming its port, a
response on that port, the exit `waitpid` answers, and the WAL file the child leaves behind. The
port comes from a socket probe, not a fixed number, and the child is killed on both paths, so a
failing pin leaves no live process behind. These are harness rules, so no patch to production code
can make a pin fail on them; the pins read only what the process itself adds.

The pins read: that the binary answers on the port the argument names, as the port the serve event
reports and the response a request on that port answers — a binary that bound a port of its own
answers a different port, and the request answers as a connection failure; that the clean signal
path exits with 0, which is the reference's clean-stop exit; and that the WAL is empty after that
exit, which is what the run's shutdown leaves behind — a patch that skipped the shutdown left the
file. Which part of the shutdown emptied the WAL is not the pin's rule, because a clean close
checkpoints and removes the file on its own, and the suite names that; it is the same reason the
maintenance pins cannot read the checkpoint. 10 pins across the three suites: 3 here, 5 in
`ServeWiringTests`, 2 in `SystemCadenceTests`, each with a probe that patches the rule it names and
reverts byte-identically. The red run for this PR is the absence of the seams and the wiring —
compile errors for `SignalSource`, `ShutdownHook` and `ServeWiring` — so the pins that were already
green on the head are shown to fail by patching the production code, not by absence.

The exit is an event the pins assume rather than assert: a patch that made the child not exit at all
would only hang the read, so each pin asserts the content a patch can flip and carries its own time
limit, which is the rule every unbounded wait carries. For the limit to be a failure rather than a
hang, the harness has to answer the pin at the limit, so the exit read asks for the exit without
blocking and answers the pin's cancellation as the cancellation it was given, killing the child so
the run does not outlive the pin; the interval between those checks is the harness's own poll bound,
not a wait a pin names. A child that writes no line at all fails the pin the same way, through the
harness, which answers that read with no serve event, so the line is not an assumed fact. The
request on the probed port carries the client's own default bound of 30 seconds, so it cannot hang
either. The signal handler is put in place at construction, before the server command runs, which is
what makes these pins deterministic: a signal arriving in the window between the serve line and the
loop's first wait answers the wait instead of ending the child on the default disposition, and the
pins were intermittent before that change.

What the harness rules are: the waits answer on an event, the port is probed, the child is killed on
both paths, every unbounded wait carries a limit, and the line naming a port is recognized by the
harness — the pin reads the value off it, not the wording. What the process pins cannot fail on is
named in the suite header: that the child exits at all, which a patch can only hang until the pin's
limit fires; which line the harness reads as the serve event and its wording; and the order the two
paths of the decision answer on, which no in-process test can read either.

### The free-space check the `backup` run makes (`FreeSpaceCheckTests`, PR #52)

The rule is the port's own, recorded in `docs/parity.md`, so there is nothing upstream to compare
with: the estimate is the bytes the source holds as the filesystem reads them, times the factor the
stage-1 note documents for `VACUUM INTO` (2), the room is read at the directory the copy is written
to, and the comparison is strictly less. The 8 pins read the decision the rule answers — three of
them as the calls the seam recorded — and the room is the machine's, so the pins drive the
filesystem through `Support/RecordingSpace.swift`, which answers the numbers the pin names and
records the paths it was asked for; what a pin reads is the rule's use of those numbers — the
estimate, the boundary, the directory, the order of the reads — never the numbers of the machine
this suite runs on. Eight pins here with a probe each, three pins in `MaintenanceCommandTests` with
five, and two pins in `SystemFileSystemSpaceTests` with two: 13 pins and 15 probes for this rule.

What the pins can fail on, each with a probe that patches the rule and reverts byte-identically: the
factor, the bytes the WAL holds, the boundary read as strictly less, the room read at the
destination's directory rather than the source's, a destination named as a bare name read at the
current directory, a size the filesystem cannot read counting as nothing, a room it cannot read
answering a refusal, and the order the reads answer in — the estimate before the room.

The run pins are in `MaintenanceCommandTests`: that a run with less room than the estimate reports
it and writes nothing, which a patch that copied first and refused after fails; that the run at
equality writes the copy; and that the check is the `backup` run's, which a patch that read the room
inside `Vacuum` fails. That last pin is why `Vacuum` carries the filesystem it does not read:
without the property, a patch has nowhere to read the room from, so the pin could not fail. The run
pins also read which filesystem the run asked the room of, which is what a patch that used the
process filesystem instead of the seam the pin was given fails on.

What the two headers name as unpinnable: the numbers a real filesystem reports, because the pins
read the values the seam answers, so the room `statvfs` answers here is never read; the two answers
of that implementation a test can name without the machine — nothing for a path it cannot read, and
the bytes it holds for a file the test writes — are pinned in `SystemFileSystemSpaceTests`, each
with a probe; the factor the copy would truly need, which is the documented choice of the port
rather than a fact about SQLite; that the check runs before the migrations, which nothing in the run
answers, so the pins read only that it ran before the write, and not the order between the check and
the destination rules; and the wording of the reported failure.

### The `--force` flag the `backup` run reads (`BackupForceTests`, PR #53)
The flag is the port's own: the reference has no `backup` command, so there is nothing upstream to
compare with. 5 pins and 8 probes, one per rule, each showing its pin failing on the rule it names.
The rule is one: without the flag a destination that already holds something is refused and left as
it was, and with the flag the file the destination names is replaced by the snapshot the run writes,
read as the filesystem reads the path rather than as a database the run can open, while a path that
is a directory is reported rather than deleted. The flag does not skip the room check, a run that
cannot hold the copy removes nothing, and the flag does not build the directory the storage layer
needs.

What the pins can fail on, each with a probe that patches the rule and reverts byte-identically,
named by what it flips: the flag read as absent, which refused the pins reading a replacement and
the controls reading a run with room or a file replaced; the destination read as a database the run
can open, which refused the pin naming bytes and the two controls reading bytes replaced; the room
check skipped on the force path, which wrote a copy over the bytes the no-room pin named; the
destination removed before the check, which left no bytes for that pin to read; the removal taking
whatever the path is rather than a file, which deleted the directory the pin that names a directory
as the destination built; the directory built on the force path, which answered the pin reading
nothing created with a copy; the write skipped on the force path, which left nothing for the copy
reads that show the controls writing; and the flag read as always on, which replaced the bytes the
no-flag control reads and is the only patch that can flip that control.

What the header names as unpinnable: an empty destination file, which the flag path replaces and the
no-flag path reuses, both answers leaving the same path with the same content; the type guard's
other branches — a path read as something other than a regular file, one whose attributes cannot be
read, and a symlink, which reads as the type its target has so the link itself is removed — which no
path a pin builds answers; the shape guard that reads the row the pin wrote after the control run,
which no patch of the command flips and which bites only on the storage rules `MaintenanceTests`
pins; the order the removal and the migrations run in, which nothing in the run answers; the order
between the room check and the destination rule on the no-flag path, which no pin reads — what a pin
reads is that the check ran before anything was removed, written or read; the numbers a real
filesystem reports, which the seam answers in place of the machine; the flag that gates the
migrations, which `MaintenanceCommandTests` pin for both commands; the wording of the lines and of
the reported failures; and the rules the port names rather than the reference, which has no command
here to compare with.

## Robustness (stage 7)

`FetcherHostileInputTests` is the hostile body corpus for the fetcher: a stream that inflates far
past the size it is stored in, and a stream the decoder cannot finish. The rule is which limit
answers. The reference has the body cap, counted on the bytes the decoder produces because
`MaxBytesReader` wraps the decompression reader, and no limit on how far a stream may expand; the
port had a ratio guard of its own, which refused a body upstream would have read, and that guard is
gone, so the cap is the only limit. 4 pins and 5 probes, over the stub server.

`LargeFeedTests` is the reduced 10k-entry scenario the plan names, and it is what runs in the
default CI job: the plan the schema answers for the hot unread listing, the page the query is given,
the relevance order the FTS index answers at the corpus size, and the batch the retention pass takes
at the documented size with the rows it leaves for the next run. 5 pins and 6 probes, two of them on
the page pin: the page size dropped from the clause, and the order read in the direction the query
did not ask for, which is what the head of the page asserts. The plan pin reads the text the query
builder produces, which is internal for that reason: a pin cannot name a plan without the text the
read runs, so it reads the builder rather than writing its own `SELECT`.

The budgets the plan names are documented, not asserted, because a number this machine measured
cannot be a pin: the corpus read path measures 1 to 4 ms, and the one pin that reads a duration
reads a bound of 250 ms, which the probe that answers the ranked read row by row crosses by a second
or more; the suite runs in about 1.2 s, well inside the CI job. The memory budget is the corpus rows
plus the body the fetcher can hold, which is the 15 MiB cap the configuration reads by default; no
pin reads memory, so the budget is a documented number.

## Security checklist (stage 7)

The checklist itself is `docs/security.md`. What it could pin landed as pins, and what it could not
is named there and in the suite headers. 8 pins and 7 probes across five suites, each probe showing
its pin failing on the rule it names:

- `RepeatedResponseHeadersTests` — a response name that appears twice keeps the first value, as the
  reference's `Header.Get` answers, and one name written two ways is one name; the first `Location`
  is the hop the fetch takes. 3 pins and 2 probes over the stub server, which now writes headers as
  ordered pairs because `Behavior.headers` is a dictionary and cannot hold two values for one name.
  This is the finding the pass closed in production code.
- `FetcherSecurityTests` — the address policy runs on the hop that took its client from the cache,
  read as the seam's call count across two fetches of one host: 1 pin and 1 probe.
- `FetcherClientCacheTests` — the cache stays at the cap after a checkout that goes over it, and the
  entry the trim closes is the one whose expiry comes first, both read through an internal accessor,
  because nothing a fetch can answer changes when a different entry is closed: 2 pins and 2 probes.
- `SanitizerTests` — `width="+10"` is a positive integer, because `strconv.Atoi` reads the sign as
  part of the number: 1 pin and 1 probe, with the expected value taken from the reference.
- `SanitizerHostileCorpusTests` — the scheme check reads the value the entity table decodes, so
  membership in that table is part of the rule; the case is `href="http&colon;example.org"`, kept as
  an address with an allowed scheme: 1 pin and 1 probe, on the corpus growing from 145 to 146 cases.

The dependency audit is part of the checklist too: the 36 pins in `Package.resolved` were queried
against the GitHub Advisory DB on 2026-11-07, because OSV has no Swift ecosystem, and the 27
advisories over seven packages were all first patched below the pins this repository holds, so none
of them affects a pin. The table is in `docs/security.md`.

What the pass could not pin is documented instead: the connect timeout as a limit of its own, the
header-block size, which this port reads no limit of its own for and which the reference caps only
on the server side, the timing form of the constant-time token compare, the NUL byte in a password,
which the dependency measures with `strlen`, and the value of a hop that is not the last one.

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
- the cadence the schedule keeps: the interval is the mode's, not the `<ttl>` the stub feeds carry,
because the policy takes the maximum of the two, so "the stamps advance" means two advances per feed
in 2h — the two hour boundaries inside the window — and the conditional-hit path is reached on the
second fetch of a feed that did not change, which is the last fetch a 2h window reaches;
- the instant the due check compares against is the one the shell recorded just before the status
command read it, so a row crossing the due boundary between the two reads as a violation — a false
failure rather than a false pass, which the check states;
- the guards on the run's own numbers — the duration, the number of feeds, the window being at least
as large as the rows, the database being fresh — can fail, and each was seen to fail by declaring a
value below what it requires; that is the whole of what they can show.

## Parity harness

`Scripts/parity.sh` is the stage-7 artifact the plan names: real Miniflux and Rivulet read the same
corpus, and the difference between the two answers is read class by class against the tolerance
table. It is not a test and it is not in CI — it is a run against two live systems, so the
determinism rules above do not apply to it. The halves are separated the way the soak's are: the
shell is the run half, `Tools/parity/parity_check.py` is the check half, and
`Tools/parity/collect.py` writes the pair document the check half reads.

Each rule is a function over the data a run leaves behind — the pair document, the table, the
manifest, the committed report — rather than an assertion about a live process, and that is what
makes each of them falsifiable: `python3 Tools/parity/probes.py` crafts one input per rule that
violates it and asserts that the rule reports it alone. 18 rules, 20 crafted inputs, and the
baseline, which is asserted to report nothing: the baseline is one run where every difference the
comparator sees is covered by a recorded row, so a probe that reports a second rule is a probe that
did not isolate its own input.

The rules were written after the probe set: with the rules stubbed, all 20 crafted inputs fail on
the rule they name, and the patch round shows the same for each rule read as data — one patch per
rule that changes what the rule reads (the header rule reading the last value of a list instead of
the first, the order rule reading sorted lists instead of order, the counts rule recomputing instead
of reading what the side reports, the map rule reading an id as the other side's row, the table rule
reading only the presence of a name, the version rule accepting any version string that starts with
the major number), the probe for that rule seen to fail, and the file reverting byte-identically.

What the rules read is the tolerance table in `docs/parity.md` as data, and the corpus manifest, so
the comparator has no preference of its own: a row marked `accepted` is a deviation the port keeps,
a row marked `fixed` is a rule the port already keeps, and a difference whose class no row names is
a finding. Requests are paired by key rather than by position, so a run that answered the same
requests in a different order still matches, and the row ids of the two databases are read as the
map rather than as values.

The shapes the collector arranges are what the rules read, and each is a shape, not a value: a
response name kept as the list of its values in the order they arrive, which is what `Header.Get`
reads through, because keeping one value per name would make the header rule impossible to fire on a
run — `Tools/parity/stub_server.py` is the stub that writes one name twice, and it was seen to
answer two values for it on a live socket; the login recorded as the first request, on the route the
reference registers for it with the form names it reads, because a pair document carrying requests
before the login answer is a run that never authenticated; the token sent as the `Authorization`
name the auth read reads, `GoogleLogin auth=`, split as `strings.Fields` splits it; the status taken
from a failed response, because the status rule can otherwise never see the 404 or the 405 it
compares; the manifest key carried as the name the run added the feed under, resolved through the
feed url, because neither side has a column that holds it; and the version named on the reference
side only, because the port side names the build it ran.

What it cannot show, and the harness and the docs say so:

- that the run ran at all, because it is on demand and not in CI;
- that the two sides read the same bytes over the network, because each fetch is its own hop;
- the row order a storage read answers for rows sharing one value, which SQL does not fix;
- the clock fields, which each side wrote at its own write instant. The rule that reads the parse
  results can never fail on a clock difference, because it never reads one: that half of its name is
  the rule, not an assertion, so no probe covers it;
- the rules the stage-3 corpora already pin, which the run re-reads rather than pins;
- the other half of the table rule: a class the manifest reaches but no row names is a difference
  nothing covers, so the difference rules read it, and a probe cannot make the table rule report it
  alone — removing the row also makes the difference itself a finding;
- the rules that are tautologies on run data because the collector writes both sides from one
  source: the input digests, the flags, and the names the run asked with. They can only be shown on
  crafted data, where the two sides are written apart, and the probes for them are crafted, not run;
- the pinned version on the port side, which the rule that reads it does not read: the probe that
  changes the version shows which half the rule reads by failing on the reference side alone;
- the eleven guards that read a declared value — the pinned tag, the pinned commit, the two corpus
  counts, the exercised-row count, the proxy mode, the address policy, the account name, the report
  being present, the two declared ports, and the Postgres host. Each was seen to fail by declaring a
  value below what it requires, and that is the whole of what they show; the two checks that read
  data rather than a declared value — a manifest key with no file beside it, and a side the run
  recorded nothing for — fail only on a run;
- the classes no corpus input can reach — the grapheme and code-point counts, the bracketed host,
  the media proxy, the wording of a rule the port names — which are named in the table as not
  reachable here rather than asserted;
- the run half itself, on this machine: the Docker daemon is not reachable for this user and no
  Postgres server answers, which the reference needs because its `go.mod` has no SQLite driver. So
  the collector is checked here only by `bash -n` and by the guards above, not by a run;
- what the width rule does not reach: the manifest's record lines, which are one record, and the
  shell's command lines and guard messages, which cannot be broken at a word without changing what
  the run reads.

## Running

- `swift test` — everything (unit + integration); this is what CI runs.
- `swift test --filter RivuletCoreTests` — unit only (fast loop).
- `swift test --filter RivuletIntegrationTests` — integration only.
- `Scripts/soak.sh` — the soak run, outside CI. `python3 Scripts/soak_check.py --probe` checks that
each of its rules can fail on the rule it names.
- `Scripts/parity.sh` — the parity run, outside CI.
  `python3 Tools/parity/probes.py` checks that each of its rules can fail on the rule it names, and
  `PARITY_DRY_RUN=1 Scripts/parity.sh` runs the guards alone.
- Heavy suites (100k-entry benchmarks, big-feed scenarios) are disabled by default and enabled by an
`.enabled(if:)` trait gated on `RIVULET_HEAVY`; run them explicitly with `RIVULET_HEAVY=1 swift test
--filter HeavyTests`. The reduced large-feed scenario (`LargeFeedTests`) is the one that runs in the
default job, and it is not gated.
- A few storage tests need at least two event loops (one pooled connection per loop); they
`Test.cancel` on single-loop runners. CI runners always expose ≥2 event loops.

CI runs on Linux: `ubuntu-latest` with the `swift:latest` container and a 15-minute job timeout.
Keep the default suite well under that. Stage 7's cheap CI slice is in the default job — the reduced
hostile corpus and the reduced large-feed scenario, both ungated — and the full parity harness runs
on demand via `Scripts/parity.sh`.

## Framework

Swift Testing everywhere (`import Testing`, `@Suite`/ `@Test`, `#expect`/ `#require`) — one
framework, no mixing; XCTest and `XCTVapor` are not in the tree. Tests run in parallel by default
and every test owns its resources (temp directories, kernel-assigned ports), so no suite depends on
execution order. Use the `.serialized` trait only where a suite must share process-wide state.

