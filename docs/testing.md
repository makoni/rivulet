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
pass. 3. Refactor with tests green. 4. Bug fixes start with a regression test that reproduces
the bug.

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
answer as they did before it. It moved out of `MaintenanceCommandTests` with PR #53, when a second
suite started reading it.
- `RecordingVerifier.swift` — the `DatabaseVerifier` seam the verify pins drive: answers the
problems the pin names and records the calls the run made through it, with whether the file was
already there at the call, which is how a pin reads the check as running after the write rather than
before it. The recording is a read the helper makes on the filesystem itself, not a rule the check
applies, so a pin that reads the check as not running answers a control that does run it.

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
stage 3, plus the entity-table case the stage-7 security checklist added). The inputs are ours, not
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
reference's return value, which counts the tombstone rows it inserted rather than the rows
it deleted.

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
different things, with Go's `QueryUnescape` turning a `+` into a space and refusing a
truncated escape.

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
failure is skipped while the last step's failure is the answer, a step that answers nothing is
skipped too, which is what the resize answers for an image it rejects, a `data:` href answers
without a request and without the resize, and the feed's icon URL is read as the icon bytes rather
than scanned as a document. What these three cannot fail on is stated in their headers: the join
does not escape what it joins, which is Go's documented expectation and is pinned only as that it
does not escape, while a character the path mode escapes is written as its escape by the URL layer's
own rule; the reference's error wording, which this port keeps as typed cases; the size cap, which
the fetcher applies before this layer sees the bytes and which no icon case reads; and the basis the
empty-body rule measures, which is `Content-Length` upstream and the bytes read here, so a chunked
empty body differs — recorded rather than pinned; and the search answering nothing when every step
answers nothing, because a patch that changes that answer changes the resize rule, which is a
different pin.

`IconResizeTests` pins the resize step as pure logic: the content type is compared as the whole
value it was read with, the type list runs before the header read and its rejection, the dimensions
come from the file's own magic compared at the length of that magic, each WebP chunk shape answers
its own dimensions, the start-of-frame segment is read only for the three markers the walk
dispatches and only for the shapes `processSOF` accepts, the GIF read takes the 13 bytes of its own
header before it answers the logical screen, the segment walk finds the frame segment instead of
assuming it is the first one, a header the read cannot answer leaves the bytes as they were, a side
strictly greater than 4096 is the rejection, a file at or under 32×32 is left as it is, with the pin
holding a case in each direction so both sides of that guard can fail, and anything else becomes a
32×32 PNG written with the content type as the literal `image/png`, with the checksum still the
value the bytes as read produced. 17 pins and 25 probes, each seen to fail on the rule it names and
to revert the file byte-identically. What that header names as unpinnable: the SVG branch, because
this port has no minifier and no patch can part the branch from the type list before it; the content
type the document writes, because the only bytes this port's decoder can read are bytes the name
already calls `image/png`; the pixel-count term, which no patch can flip because a side above 4096
answers first; the guard that a dimension read as zero ends the resize; which pixels the scale
produces, which is the reference's `draw.BiLinear` against the port's own rounding; the encode
failure, which no input can make the encoder answer; and the pixel decode for GIF and WebP, which
this port has no decoder for, so those cases read only that the guard passes the bytes on.

`IconRepositoryTests` adds the storage half: the dedupe is by hash, the content type is compared as
the whole value so one carrying a parameter is not a known icon type, the link replaces what the
feed row had rather than adding a second mapping, and the orphan pass deletes only icons no feed
points at. The join for the per-user read answers one row per feed, so an icon two feeds point at
appears twice — a read that went through the icon table alone cannot answer that — and the order
that read answers is the icon row then the feed row, which is the order this port names; and the
`data` field is the stored content type, a semicolon and the standard base64 with its padding, so
neither the url-safe alphabet nor a patch that dropped the padding can be read here. 2 pins and 4
probes cover those two rules, 2 for the join and 2 for the `data` field. The count that pass returns
can fail, and is read through `SELECT changes()` because this SQLKit version gives no row count for
a raw statement. The pins cannot fail on the randomness of `external_id`, which they read only as
the shape, nor on the single transaction the reference wraps the dedupe and the link in — the same
boundary the pipeline records. The request headers the icon path sends are the fetch suite's rules,
pinned in `FetchRequestTests` as following the options; that the icon path sends no conditional
headers cannot fail, because there are no stored validators on it to send.

`IconCheckerTests` adds the checker half — the wiring that runs the search for one stored feed. The
guard stops the search when the feed already has an icon, and it reads the mapping for this feed
rather than the icon table, so a patch that answers from any stored row with the same hash fails the
pin that runs the search for a feed with no mapping of its own. Storing and pointing are two
decisions that both run on either branch, so a patch that stores without pointing, and a patch that
points only on the branch it inserted on, fail the pins that name those; the guard belongs to the
missing path only, which a patch that applies it to the other path fails. A failing search writes
nothing, and the request carries the feed's user agent, which a patch that hands the builder nothing
fails. What the pins cannot fail on is stated in the header: the reference logs each failure, so a
swallowed failure reads only as the call completing with nothing written, and the branch that reads
the search answering nothing — which the resize can answer for an image it rejects, as the pin in
`IconFinderTests` shows through the skip rule — reads only that nothing is written, because no patch
can store a nil answer. The dedupe, the content-type normalization, the single transaction and the
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
— is named in the headers as read through the scan, with the rules themselves pinned by
those suites.

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
run whose named account has no row — so the helper takes the accounts it seeds rather than a
fixed graph.

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
it to stop, which the process-level suite pins; and the reference's log lines, which have no
layer here.

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
cannot hold the copy removes nothing, and the flag does not build the directory the storage
layer needs.

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

### The three subscription endpoints (`GoogleReaderSubscriptionRoutesTests`, PR #59)

The three routes the reference registers for subscriptions are pinned over the same socket, through
the shared helper `Support/SubscriptionSocket.swift`, which carries the token as the form field the
merged read answers on the POST half and through the header the transport pins on the GET half, and
writes the rows through SQL so that no pin is satisfied by the read it is testing. 62 probes in this
slice, one per rule, each seen to fail on the rule it names and to revert the file byte-identically:
13 for the scan read as pure logic, 5 for the two steps the finder has, 6 for the document shapes, 4
for the three routes, 6 for the listing, 4 for the quickadd, 19 for the edit handler, and 5 for the
two storage reads this path calls — 3 for the title order the category read answers and 2 for the
write that names only the column the caller names.

Two pins had to read the answer as well as the document, because a wrong write is not something the
document states. The pin that names the status the integer read failure maps to here reads the
status as well as the wording: the wording is what the response builder writes for any status, so a
pin that read only the wording could not fail on the status. The pin that names the title guard
reads the title the write before it left, because the input that runs the rename first is the same
row the guard's input then reads, and a pin that read the seeded title would have passed on a patch
that ran the write for the empty value.

Two claims are named in the headers rather than pinned, because no patch can make them fail: the
order between the absolute rule and the duplicate read, which no input can fail both at once, and
`rename`'s own empty-title guard, which the handler's title test answers before the read, so no
input reaches it. The title guard's own branch is pinned, on the pin that reads the title the input
before it wrote, so a patch that ran the write for the empty value fails; the order between the
create and the validation is read as the guard's wording, because the read that found no row left 0
and the guard reads its own value before the duplicate read. The same is true of the discovery steps
this port does not have, of the title and format the reference's subscription value carries, and of
the reference parsing the discovered feed inside the request, where its `streamName` is the parsed
title while this port writes the row with the create defaults. These are recorded
in `docs/parity.md`.

### The Fever parameter set (`FeverMultipartReadTests`, `FeverShapeTests`, `FeverAuthTests`,
`FeverDispatchTests`, `FeverReadsTests`, `FeverItemsTests`, `FeverWriteTests`, merged as PR #61)

The parameter set is the one the acceptance client calls: the base document, the five read
documents, the three `mark` branches, and the reachability check that client sends as `HEAD`. 32
pins and 67 probes across the seven Fever suites — two unit and five integration — and the icon
read: 8 pins and 17 probes for the multipart read as pure logic, 5 and 8 for the document shapes, 3
and 5 for the transport over a real socket, 2 and 6 for the dispatch, 4 and 8 for the storage reads
the documents are built from, 4 and 8 for the items read, 4 and 11 for the three write branches, and
2 and 4 for the icon read. Each probe patches one rule, is seen to fail on the rule it names, and
reverts the file byte-identically.

What the probes read, with the number of patches the suite header gives each rule: the multipart
read's 17 — 2 for the media type compared lowercased and only `multipart/form-data` reaching the
body read, 1 for the boundary being a parameter of the content type rather than the read's own, 4
for the parameter rules (a pair with no `=`, an unquoted empty value being the error, a trailing
semicolon not being the error, and the media type surviving the error on the urlencoded half), 1 for
a part that cannot be read ending the whole body read, 4 for the three guards of the part loop —
disposition, name, and the filename parameter being empty rather than present, which is what makes
the part a value part — 1 for a header line with no colon ending the read, 2 for the part value
being the bytes as written, with no percent decoding, and a line ending that can be a bare `LF`, and
2 for the order per name and the method guard. The shapes' 8: the base document's three fields
before the document's own, the reported version, and the two zeros of the failure document; the
field order the value documents write, read on the group document's pair; the nine fields of the
item document with `is_saved` before `is_read` and `total_items` as a number; `favicon_id` written
as the zero for a row with no icon; and `[]` for an empty list on every document of this path. The
transport's 5: the failure answer at 200 rather than the common-value document and rather than 401,
the key read through the merged form rather than through the header the sibling path reads, the
order for a name both halves carry, and the pairs the query half put in the form surviving a body
read that failed. The `HEAD` pin in that suite has no patch: neither its registration nor the length
it reads can fail — Vapor forwards a `HEAD` request to the `GET` route, and the failure document and
the common-value document are the same length, so that pin reads only that the method reaches the
handler. The dispatch's 6: 2 for the precedence, 2 for presence whatever the value is, 1 for the
mark name coming from the merged form, and 1 for the default answer. The storage reads' 8: 3 for the
groups document — the title order, the feed ids inside a group, the group order — 2 for the feeds
document — the sort order and the icon row — and 3 for the id documents — the comma join and the two
filters. The items read's 8: 1 for the page of 50 with the count read without the page, 1 for the
precedence, 2 for a negative value — the sign guard and the half of the branch the default lands in,
so a negative `max_id` is the zero half — 1 for the zero the list read answers for a value it cannot
read, 1 for its trim, and 2 for the item document — the two flags and the publication time the
reference's `entry.Date` holds, read on data where the two columns differ. The write branches' 11: 2
for the guards, 4 for the item switch, 2 for the feed branch not reading the state name and
comparing strictly before, and 3 for the three branches of the group guard. The icon read's 4: 2 for
the join answering one row per feed with the order this port names, and 2 for the standard alphabet
and the padding of the `data` field; the join and the `data` field are pinned as a read there, so
the favicons pin of this suite reads those rules through the document and no patch is run against
it here.

Two claims are named in the headers rather than asserted, because no patch can make them fail on the
rule they name: that the port registers `HEAD` itself, since Vapor forwards a `HEAD` request to the
GET route when no HEAD route is registered, so taking the registration away changes nothing the pin
can read and that pin reads only that the method reaches the handler; and the order the reference's
icon join answers, which its statement has no `ORDER BY` for, so the order the pins read is the
order this port names.

`MissingRow` moved from `Support/SubscriptionSocket.swift` to `Support/EntryFixtures.swift` as the
setup error both helper files throw, because the nested type was not visible to the Fever helper.

### The OPML read, write and commands (`OPMLReadTests`, `OPMLSerializeTests`, `OPMLImportTests`,
`OPMLCommandTests`, PR #64) The read is over the tokens the tolerant tokenizer already builds: the
reference's value layer (`UnmarshalXML`) has no port counterpart, so the shape rules are read as the
reference reads them and the record is assembled from the tree, and the write reproduces the bytes
the reference's encoder answers for this model. 57 pins and 76 probes across the four suites — 17
pins and 17 probes for the read as pure logic, 24 and 34 for the write, 12 and 19 for the handler's
steps over a temp database, and 4 and 6 for the two commands as runs over the in-process console.
Each probe patches one rule, is seen to fail on the pin it names and no other pin of these four
suites, and reverts the file byte-identically; the round runs the four suites as one run per probe.
It runs in copies of the tree on the real disk, so the probes never touch the files being committed,
and four copies run at once, which is where this machine saturates: one probe is the one patched
file plus the relinks, so it uses about two cores, and past four copies the memory the builds need
makes the round slower rather than faster. The results are cached by the hash of the seven probed
files and the four suites, so a delta round re-runs only the probes whose patch region or pin
changed. Several probes share a pin, because one rule answers several bytes: the escape set has 9
probes on one pin, the settings that reach the row 7, the field order 3, the date rule 3, and the
two command runs 2 each. Two pins have no probe of their own: the two round-trip pins of the write
read the writer and the read together, so any patch that breaks one also breaks the pin naming the
side it reads. One probe patches outside the OPML files: the handler pin that reads the duplicate
answer as the row of the account is probed by taking the account out of the storage read, and it
fires alone among these four suites.

What the read's probes read: the root name the model tags, which the reference checks even with
`Strict = false`; the read failure reaching as the read's own failure; the outline level the field
path names, and the element name the path matches, which is `outline`; the subscription test as the
url value alone, with no `type` test, and the whitespace class it trims with; the url reaching the
record as the attribute holds it; the title chain in the order the model's method defines; the
site-url fallback; the branch running before the recursion; the category being the parent's title
through the same chain; the miniflux names read against the resolved namespace, so an undefined
prefix answers empty; the name set as the gate, since a patch that added `proxyUrl` to it fails the
pin while the switch has no case for a name outside it and the value half cannot be observed; the
set `ParseBool` accepts; the error naming the attribute it was reading; a string name not being read
through the bool rule; and the read walking every outline rather than only the records.

What the write's probes read: the header line as the constant the pinned toolchain carries; the root
at column 0; the four-space indent; the document ending at the root close with no trailing newline;
the layout rule that keeps a close tag on the open line only when the element wrote nothing, read as
a line with the open tag and not the close; the version written whatever the record holds; the
`omitempty` halves of the namespace and of the three head fields; the three constants the build
sets; the date layout, the time the build reads its date from, and the zone the port answers; `text`
written always against `title` written only when carried; the field order read three ways — the
format fields, the miniflux names, and `type` last; a false bool not being written; `type` written
only for a subscription; the nine branches of the escape set; the categories sorted as bytes, on a
name where byte order and Swift's canonical order differ; the group key being the name as bytes, so
a decomposed name is its own group; and the order inside a category being the order the records
arrived in.

What the handler's probes read: the duplicate answer running before the resolution and the rules on
the input that fails all three at once; the duplicate answer being the row of the account the run
works for; the duplicate answer taking the url the record carries as the feed half rather than the
site half, on the record whose two halves are different values; the empty name reaching the smallest
title rather than the row the position-ordered listing answers; the named title compared as given,
and a name the account has no row for being created; the first record the rules fail stopping the
run after the earlier write; the url reaching the row from the record; the export listing order the
query builder answers; the export join reading the title from the row; and the fields the port
schema has on both sides of the mapping.

What the command probes read: that the import run reads the bytes of the file the argument names and
hands them to the handler for the account the run resolves; that a path the run cannot read is
reported and reaches no write; that the export run prints the document to stdout, which is where the
reference prints it; and that it writes the file when the option names one and prints only the line
that names the path it wrote.

The pins are shaped so a probe cannot reach more than the rule it names: the namespace pin reads a
value the bool rule accepts as well, the round-trip pins read through the writer and the read with
the site url equal to the feed url, the grouping pin reads two titles that are not in byte order,
the import pins read a row by its title or its category wherever another pin names the url, the
export pins read fragments without the `>` the layout rule writes, the CLI import pin carries the
title as the url, and the CLI file pin reads a path the run cannot read at all. Every parsed input
carries `type="rss"`, which the read rule ignores, so a patch that read the branch through `type`
answers the same records here.

What these headers name as unpinnable: the flags the reference's decoder is configured with, which
are the tokenizer's rules pinned by its own suites; `EscapeText` as the encoder exports it on its
own, which this path does not read; the zone name the reference answers for the date, which this
port answers as `UTC` and which `docs/parity.md` records; the validation rules past the four ported
ones, which read settings this port's schema has no column for, so no input reaches them; the
duplicate answer and the category answer inside those rules, which always answer true for a record
that reaches them; the single-row limit of the storage reads the handler calls; and the wordings of
the reported failures and of the lines the commands print.

Two pins were removed with `Planned.swift`, whose `Planned.all` loop `RivuletCLI.swift` no longer
has: the two `CommandLineTests` pins that read that list. `OPMLCommandTests` is the pin for the
import and export runs, and `helpListsEveryCommandWithoutConfiguration` remains the surface pin for
the command set.

### The icon route (`CachingRulesTests`, `IconRouteTests`, PR #65)

The four rules the reference's response builder applies for a cached asset are pinned as pure logic,
and the route that answers an icon row is pinned over a real socket on top of them. 17 pins and 28
probes, 27 of them seen to fail on the rule they name: 10 pins and 18 probes for the rules, 7 pins
and 10 probes for the answer, one of which is the row recorded below as not biting. Each probe
patches one rule, is seen to fail on the pin it names and reverts the file byte-identically; the
round runs the two suites as one run per probe, in copies of the tree, and caches by the hash of the
two probed files and the two suites.

Ten pins are read by more than one patch, one patch per rule they name, and three rows reach more
than one pin, which is why the round reports those rows as a set rather than as a failure. In the
rules: the trim pin reads the order and the class — the class is Unicode `White_Space`, read per
scalar, which is the form the repo's other trim reads use, and the pin's input carries a newline, so
a patch that narrowed the class fired it — and the quoted-half patch reaches it as well, because its
input is already quoted; the star pin reads the star and the trim of the same read; the match pin
reads the prefix drop, the contains read and the whole-tag read; the `Cache-Control` pin reads the
whole seconds and the directive order; and the `Expires` pin reads the bound, the zone, the weekday
field and the day field. On the socket: the token pin reads that the token read is not run and that
the answer carries the bytes of the row, and the caching-headers pin reads the bound and that
`Expires` is written on this path, each with one patch per rule; the patch for the empty side of the
guard reaches the token pin, the content-type pin and the policy pin together, because the branch
the answer takes is chosen by that read, while the caching-headers pin is not reached, because the
headers it reads are written before the read runs; and the match pin is read by its own patch and by
the patch naming which value the `ETag` is built from, because it reads the header value the route
builds from the row.

The three rows the round records as reaching more than one pin are those reaches: the quoted-half
patch, which fires its own pin and the trim pin; the patch for the empty side of the guard, which
fires the guard pin and the three pins that read the callback branch; and the patch naming which
value the `ETag` is built from, which fires its own pin and the match pin. Every other patch fires
one pin.

One row is recorded as not biting: the body half of the match pin, because the framework writes no
body for a `304` answer, so a patch that writes the bytes on that branch still answers an empty
body. The pin stays, because it reads what the reference's builder answers on that branch.

The pin for the empty side of the match read cannot be falsified by taking the guard away: an empty
value is inside every value for Go's `strings.Contains`, which is the other half of the rule, while
Swift's read answers false for an empty value, so the guard and its absence answer the same here.
That probe flips the answer the guard gives instead, and the difference is the row
`docs/parity.md` records.

The socket pins that read a response shape carry the token as the transport reads it for a GET, so
the probe for the unauthenticated rule fires only the pin that names it. The token read itself is
pinned by `GoogleReaderAuthTests`, and the read the route runs is pinned as a read by
`IconRepositoryTests`, so no patch here shows either alone. The three headers the response builder
writes are the same rule this path reads and are pinned on the other path by
`GoogleReaderAuthTests`, so a patch to them fires that suite as well. Routing is the framework's
rule, not this file's, so no pin here claims it. The instant `Expires` is built from is the clock
the run reads, so the pins hand the rule an instant; the zone rule fires only on a machine whose
local zone is not UTC, which is where the round ran, and the fixed locale cannot be shown on a
machine already reading English month and weekday names.

### The acceptance journey (`AcceptanceJourneyTests`, PR #66)

One suite reading the chain `docs/plan/stage-5-apis.md` names as the acceptance backbone: the two
console runs that build the account and its credential pairs, the OPML run that writes the rows, the
pass over the batch that writes the entries, and the socket the client requests go to. 14 pins and
16 probes, every probe seen to fail on the pins it names and to revert its file byte-identically.
The run half asserts nothing, so every failure is recorded by a pin, and each pin asserts a document
or a line built from the test's own inputs, with the stored values read through SQL digest lines so
a pin is not satisfied by the read it tests. The round runs only this suite, in copies of the tree,
and caches by the hash of the 13 probed files and the two suite files; no row is recorded as
not biting.

Seven pins are read by one patch and seven by more than one, one patch per rule they name, and four
rows reach more than one pin, because a pin reads a value an earlier link of the chain wrote: the
login-compare patch fires the pin for the three text lines as well, because both read the same
answer; the import-write patch fires the listing pin, the pass pin, the contents pin and the Fever
feeds pin, because all four read the row that patch wrote; the patch for the site url the pass
writes on the row fires the same four, because that read answers from the parse; and the patch for
the first-appearance order fires the groups pin and the feeds pin together, because both documents
are built from it.

What the pins read as the orders the reads answer: the subscription listing in the error-count then
title order its read builds, the Google ids answer and the contents document in publication time
newest first, the Fever items document and `unread_item_ids` in publication time oldest first, which
is the default order that read has, the Fever groups in the byte order the titles answer in with the
default row the schema writes for the account named too, and `feeds_groups` in the order the
categories first appear in the feeds listing. The goldens are the reference's own answers for the
values the fixture declares: the Fever token for the pair the run reads, and the `SHA256` for the
value each item declares.

What no pin here can show: the ids the runs assign, because the pass runs the jobs of the batch
through the pool and the order the writes land in is not fixed, so the pins read the ids through SQL
and assert the values per row; the clock fields, read as the placeholder `0` — the document's
`updated`, which the handler builds from the instant it runs at, and the item's `crawlTimeMsec` and
`updated`, which it builds from the row's created and changed instants; the column the Fever feeds
document reads the stamp from, because the run creates the row and stamps it in the same second, so
the pin cannot tell the stamp from the create time, and the zero half of that read, which has no row
without a stamp here; the wordings of the console lines and of the reported failures; the batch
comparison, which `SchedulerBatchTests` pins, because the pins here read the arrivals they count
rather than the comparison itself; the two stored values the login pin reads as data, the name as
the console read it and the flag the run writes, which its own suites pin; the icon path, which has
no row here because the fixture page carries no icon link, so the icon field is read as the zero;
and the rules pinned by their own suites, which the round reads only through this suite, so a patch
to one of them fires the pin in that suite as well, a reach reasoned there rather than shown here:
the two token derivations, the document shapes, the item-id forms, the stream and query reads, the
storage reads and their orders, the sanitizer, the date parse, the bcrypt compare, and the
single-row limits.

The harness runs the chain once per pin on a database and a server started for that pin only, in
`Support/AcceptanceJourney.swift`, split as the three console runs, the stamp, and the socket half.
`CommandRun.swift` gained the inputs the console reads for the two prompts of `create-admin` and the
four of `integration-credentials`, and `withServedApp` gained the database path another helper owns,
so the console runs and the app read one file. The rows the import wrote are put in the batch by SQL
the way the batch read compares them, and the fetch needs the name that lets the fetcher reach the
stub server. The console runs are not nested inside a held storage checkout, which is what lets a
pin read the rows the run wrote through the same connection.

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
reference's `Header.Get` answers, and one name written two ways is one name; the first `Location` is
the hop the fetch takes. 3 pins and 2 probes over the stub server, which now writes headers as
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
violates it and asserts that the rule reports it alone. 19 rules, 21 crafted inputs, and the
baseline, which is asserted to report nothing. The baseline is crafted data, not run data: it is one
document where every difference the comparator sees is covered by a recorded row, so a probe that
reports a second rule is a probe that did not isolate its own input.

The rules were written after the probe set: with the rules stubbed, all 21 crafted inputs fail on
the rule they name, and the patch round shows the same for each rule read as data — one patch per
rule that changes what the rule reads (the header rule reading the last value of a list instead of
the first, the order rule reading sorted lists instead of order, the counts rule recomputing instead
of reading what the side reports, the map rule reading an id as the other side's row, the table rule
reading only the presence of a name, the version rule accepting any version string that starts with
the major number), the probe for that rule seen to fail, and the file reverting byte-identically.
The patch for the login-half rule reads the reference's own stored value instead of the one this
port wrote, which is what makes the two sides hold two different hashes; that patch was seen to fire
on run data and reverted byte-identically.

What the rules read is the tolerance table in `docs/parity.md` as data, and the corpus manifest, so
the comparator has no preference of its own: a row marked `accepted` is a deviation the port keeps,
a row marked `fixed` is a rule the port already keeps, and a difference whose class no row names is
a finding. Requests are paired by key rather than by position, so a run that answered the same
requests in a different order still matches, and the row ids of the two databases are read as the
map rather than as values.

The shapes the collector arranges are what the rules read, and each is a shape, not a value: a
response name kept as the list of its values in the order they arrive, taken once per name in the
order it first appears, which is what `Header.Get` reads through, so `Tools/parity/stub_server.py`
is the stub that writes one name twice on the hop the corpus is served on, and the read takes each
name once, in the order it first appears; but the pair document carries the response each side
answered the collector with, and the fetch hop is not in it, so on run data the value the rule
compares is written from the same read as the list it reads, and only crafted data can fire it; the
login recorded as the first request, on the route the reference registers for it with the form names
it reads, because a pair document carrying requests before the login answer is a run that never
authenticated; the token asked with as `T` on the POST shapes, which is the half the auth read takes
a form field for on both sides, and as the `Authorization` name — `GoogleLogin auth=`, split as
`strings.Fields` splits it — on the others, and the names put where the reads take them for the
method, because a body makes the transport POST, so the method the record carries is the method the
shape names; the status taken from a failed response, because the status rule can otherwise never
see the 404 or the 405 it compares, and a non-JSON answer recorded as the text it is, as is a JSON
answer that is not an object, because the key-set rule reads no key set from an array; the manifest
key carried as the name the run added the feed under, resolved through the feed url, because neither
side has a column that holds it and the stored title is the parsed feed title; the storage read
keeping the fields as the storage answers them, with the reference side parsed as CSV over the whole
text rather than line by line — a field holding the delimiter or a newline is one field, not two
rows — and this port's driver answering rows as fields, which needs no delimiter at all, and a value
the storage cannot read being the empty string on both sides rather than the name of nothing; and
the version named on the reference side only, because the port side names the build it ran.

What the run hands over, and what the first live run here showed: the flags are handed to the
reference one name at a time with its own `-e`, because a flag name handed bare is read as the image
the run pulls; the reference runs on the host network, because a container in a namespace of its own
has its own loopback and the corpus is served on this machine's; its connection string has to name
the SSL mode, because the driver it reads that string through defaults to `require` when the string
names no mode; `CREATE_ADMIN` is a boolean for its parser, with the account as two names beside it,
so a value written as `name:password` is an invalid boolean; the schema is applied by a run of its
own through its own flag, with the migrations gated off as the guard says; the name `DATABASE_URL`
is not one value for the two sides, so each side is handed its own; the port's own side is served
before the collector reads it; the secure console read takes its value from a terminal rather than
from a pipe, so the run gives that command one; and the due rule is strict, so the batch read cannot
see a feed written at the same instant it reads.

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
source: the input digests, the flags, the names the run asked with, and the response name read with
the value that response answered, which are one read on a run. They can only be shown on crafted
data, where the two sides are written apart, and the probes for them are crafted, not run;
- the login half beyond the answer the run recorded: which path wrote the value the read compares,
and which prompt the value came from. The reference reads the integration row the login runs on,
where the enabled flag that read requires is set only by its web form, which this port has no
equivalent of — it has no integration table and no flag, and its own path for the pair is the
console command — so the run writes the value through two paths, and no pair document can state
which of the two put it there, nor in what order the command read its prompts. What the rule can
read is the answer, and it was seen to report a run where the two sides held two different values:
the run that read the pair as the reference's own value reported it, and the run that writes one
value through both paths reports nothing;
- the pinned version on the port side, which the rule that reads it does not read: the probe that
changes the version shows which half the rule reads by failing on the reference side alone;
- the twenty checks the shell makes. Twelve name a value the run declares or a count the run
declares against the committed files — the pinned tag, the pinned commit, the two counts, the
exercised-row count, the manifest being there and the file each of its keys names, the proxy mode,
the address policy, the account name, the report being present, and the network the run declares —
and each was seen to fail, by declaring a value below what it requires or by taking the file it
names away. That is the whole of what they show. The eight that read the machine or the run's own
data — the check over the two ports the run declares, the Postgres server, the daemon, the two bases
answering, the login answer, the rows each side recorded, and the stored rows read against the port
this run served — fail only on a run, and four of them were seen to fail here: a port something
already holds, the base its own side answers on, by pointing the run at a binary that exits at once,
the login answer, by the run itself, and the stored rows, by running the same declared database
twice, which is the second run reading rows the first one wrote;
- the seven classes no coverage-reading rule can see — the grapheme and code-point counts, the
bracketed host, the media proxy, the wording of a rule the port names, the two scan classes, and the
row the login half names, which is which row the read ran on and which path wrote the value — are
named in the table as not reachable here rather than asserted: the corpus cannot reach the scan
classes because every corpus file is a feed document, answered by the format check before the scan
reads a `link`, and no pair document states a row or a path. The one row this path adds that a shape
reaches is the title inside the request: the quickadd request is asked with a feed document, and the
only thing its answer can part on is the key set, which the rule that reads key sets reads without
consulting the table. For a run that arranges its rows before the collector reads them, the quickadd
answer is the duplicate one, so what that shape shows is the key set both sides write for a name the
read already has;
- the run half itself, which is not in CI and cannot be probed: it runs only when the machine gives
the daemon and a Postgres server, which the reference needs because its `go.mod` has no SQLite
driver. Here it executed end to end through the collector twice: once before the run wrote the
credential pair, where what it reported was the login half, and once after, where the login answer
is one value on both sides and the only thing the rules reported was the key set the method-mismatch
row names — the reference answers a method its mux has no pattern for with a text body, this port
with the shape its router writes — because the rule that reads key sets reads no coverage. The
committed report is the one the harness writes from the table before the rules read it, which is the
same document a run writes from the same table;
- what the width rule does not reach: the manifest's record lines, which are one record, the
report's item lines, which are one item each and read as whole strings by the rule that reads the
report, and the shell's command lines and guard messages, which cannot be broken at a word without
changing what the run reads.

## Client matrix (stage 7)

The client matrix is the half that records the calling sets of the acceptance clients, and
`Tools/clients/replay.py` is its check half. It reads the sets, the record files, `docs/clients.md`,
`docs/performance.md`, `docs/reference-notes.md`, the port's own route, dispatch, auth and response
sources, and the field the timed pin's print writes as data, so every rule is a function over data
rather than an assertion about a client that was never run here. `Tools/clients/parsers.py` holds
only the read: the sections, tables, record lines, the two sentences the rules parse as sets, the
names read in the order a record line carries them, and the routes the port registers, so the rules
stay the readable part of the check half. `Tools/clients/probes.py` crafts one input per rule that
violates it and asserts that the rule reports it alone; the baseline — the committed data — reports
nothing, so each probe is single-firing: 19 rules, 30 crafted inputs and the baseline, so 31 cases,
the performance rule having one for each of the five kinds of finding it reads, the route rule one
for each of its two halves, because an input that violates one half of a rule still satisfies the
other, and the rule that reads the run record one for each of its seven halves, on the record the
run wrote here. One of those seven reaches two parts of the data at once, the record line and the
paragraph that names the calls this run showed, because the half reads the record against the
paragraph and this run reached no call outside the recorded set. Every craft changes the parsed data
in memory and never a file, and the round hashes every file the check half reads before and after,
so a craft that reached a file is reported. What the 19 rules read: the source each set names and
its commit, the redaction as the placeholders the half reads rather than as values, the matrix rows
against the manifest lines, the classes against the parity table and the output-check class against
the endpoints the reference applies the check on, the routes the port registers against the answer
each row names with the catch-all read as the registration line the file writes, the reference's
route and dispatch sets, the two halves of a client that reaches one half only, the order the source
declares, the login being first and the token coming before every call that carries it, the token
half per method, the stream forms as the prefix and suffix sets the branch reads, the counts table
against the records it counts, the replay records against the matrix's own column, the performance
table against the run that answered it and the shape the document names, the rule list and the
report items against what the check half has, the response name a client acts on against the name
the response builder writes, and the record the client run wrote against the set, the matrix row,
the response shape, the redaction and the paragraph the document writes for the calls this run
showed. The rule that reads the run record has seven halves: the order column against the order the
document names the calls this run showed, a call the set cannot name against the document naming it
as shown, the answer against the matrix row, the answer for a call the reference records no case for
against the default branch, the key names against the names the response shape writes, the name the
redaction names for the credential pair, and the guarded call against the document naming it as
shown. What this half cannot show, and is named in `docs/clients.md` rather than asserted: the
clients that have not been run against this port here, the calling set of a client whose source
cannot be read, the order a client reaches its calls at on a device, which the run record carries
for the client run here and the source declares for the others, the values the calls carry, which
are redacted, the app-level choice of which calls a library-based client makes, the guard a client
applies before it sends, read as the bound on the list size, which no record line can show firing,
the side of the bound the guard applies, which the record carries as names and not as values, the
token half of a client that sends the stored value as the token, the numbers of another machine, and
the query latency at the 100k corpus. The run half is `Scripts/client-run.sh` with
`Tools/clients/observer.py`, outside CI: the observer writes one record line per request it
forwarded and asserts nothing, and the check half reads the record the run left behind rather than
the processes. It is checked here by `bash -n` and by its eight guards — ten read sites, because the
ports item reads the two ports against each other and each of them against the machine — each seen
to fail on the value it names: the record path, the client row, the two ports by naming the same
port twice and by a port the machine already holds, seen by holding one port with a listener, the
base, the version, the pair row, the entry rows, and the record being empty. The three guards that
read what the run itself wrote — the pair row, the entry rows, and the record being empty — fail
only on a run, and the guards that read the machine fail only on a machine. The guards that read a
value the run declares run before the record is written, so a guard that fires leaves the committed
record alone, which is what kept it untouched through the ports demos; the guard that reads the
record itself runs after the run, on a record written outside the repo path. The Swift half is
`Tests/RivuletIntegrationTests/ClientSequenceReplayTests`: 9 pins and 10 probes, reading the same
files through `Bundle.module` as data — the recorded order, which call reaches a registered route
and which reaches the catch-all, the two item-id forms the same client sends, the page size above
the clamp against the value at the clamp, the token half per method, the guard the merged form
answers for the call with no add and no remove pair, the name the dispatch switch has no case for,
and the prefix this port registers no route for. Each probe was seen to fire on the rule it names;
the transport read is the assumption the other pins run through, so no patch can show it alone, and
the transport rules are pinned by `GoogleReaderAuthTests`. The login half and the token half are
pinned as the answer they write, not as the order they happen in, which is what no pin can read. The
performance half records measurements taken here rather than bounds: `Scripts/perf.sh` is the run,
`Tools/clients/perf-run.txt` is the recorded run, and the rule compares the table in
`docs/performance.md` against the numbers the run answered, the fields its sources declare and the
shape the document names, the timed pin's own file being read as data for that. It is not in CI, so
`python3 Tools/clients/replay.py` is the check that runs it, and the numbers are not asserted
as bounds.

## Static release build (stage 8)

`Scripts/build-release.sh` is stage 8's run half for the release build, outside CI: the shell builds
the full dependency stack for the static musl target with the Swift Static Linux SDK and reads the
artifact rather than the build log. The CI container has no SDK installed, so the run half is
checked here by `bash -n` and by its 13 checks. Twelve compare what the run reads against a value
the run declares, the toolchain's own list, the installed bundle, or a committed file, and each was
seen to fail here on such a value or by taking the file it names away: the SDK name, by a name the
toolchain does not list; the bundle read, by the `swift-sdk.json` it names taken away, and the
triple read, by `x86_64-unknown-linux-musl`, the name the first attempt used; the artifact path, by
`aarch64-swift-linux-musl`, a triple the bundle declares but this run did not build; the file type,
by a dynamically linked artifact named at the path the check reads; the three source reads, by the
committed file each names taken away (`RivuletCore.swift`, `SchemaV1.swift`,
`StatusSnapshot.swift`); the version answer, against a source declaring `1.2.3`; the migration
answer, against the name `SchemaV2` and against the answer on a database that already holds the
migration; the key-value check, by a key renamed to `due_x` and by the values read as 0 against a
database that holds one feed row; and the feed-list check, by that same database. The thirteenth
check reads the machine, so it fails only on a machine without the toolchain. Two checks are fired
by more than one craft — the migration answer and the key-value check — and one craft reaches more
than one check: the seeded database is read by the migration answer and by the contract checks, so
it fires the migration answer first and reaches the contract checks as well, which are seen on that
same craft by reading its answer alone. The run builds the database it reads, so a build directory
an earlier run left is the failure the migration answer names rather than something the run
prevents. `RIVULET_SKIP_BUILD=1` runs the checks against an artifact already on disk, which is what
made each of them checkable without a rebuild.

What the run half cannot show is named in its header: which branch the compiler takes for the two C
reads the spike found — on the glibc CI container only the glibc branch is in scope, so the build
itself is the check for the musl half, which is why the two shapes are named in production code
rather than worked around in the script, in `Sources/RivuletCore/Reader/SystemAddressResolver.swift`
and in `Sources/rivulet/main.swift`; that the binary runs on a machine without this toolchain, which
is the clean-container smoke job stage 8 names; the size after stripping, reported as a measurement
taken on this machine; that the top-level `feeds` key is the feed list rather than one of the
counts, which the run reads only as the empty array; the key order in the answer, which is not
fixed, so the contract is read key by key rather than as one string; and that the row a migration
created is the row a fetch would write, which the tests pin and this run cannot answer without
a network.

The two production-code sites the spike found are named once for the platforms rather than pinned,
and what the glibc side can show is narrower than the naming suggests: `AddressResolutionTests`
reads the resolver's answer, so a patch to the socket type bites only when the value breaks the
lookup, not when it is another socket type the lookup still accepts, and the exit-code site in
`Sources/rivulet/main.swift` has no pin at all, because the top level of the executable is not
something a test can read.

The version value is read by two pins in `RivuletCoreTests`: that the value is not empty, and that
the digits it carries read as a positive integer, which mirrors the reference's
`TestVersionConvertedToInteger` because a client converts the version string to a number. The value
this port carried read as 0 on that rule, and the finding is closed at the production site the rule
names: the constant. Three crafts, each patching the value and reverting the file byte-identically:
`dev` fires the digit-presence half, whose conversion half can fire only as a consequence of that
same empty digit set; `0.0.0-dev` fires the sign guard alone; and the empty string fires the
presence pin and reaches the digit pin, because both read the same value. Single-firing holds only
for the `0.0.0-dev` craft. What no craft can show is the conversion as a rule of its own, which no
code in this port performs, and the digit class, which no version this port carries can tell apart
from Swift's `isNumber`.

## Clean-container smoke job (stage 8)
`Scripts/smoke.sh` is the run half: it puts the static artifact into a base that carries no
toolchain and no libc, runs the chain the stage names — `migrate`, `create-admin`, the credential
pair through `integration-credentials`, the `add` calls, `serve`, the health read, the login, the
reader read, the round the stop catches in flight, the round after the restart, the copy `backup`
writes, and the `vacuum` run — and hands the run's data to `Tools/smoke/collect.py`, which writes
`Tools/smoke/run.json`. The check half, `Tools/smoke/smoke_check.py`, reads that document rather
than the container the run started, so each of its 20 rules is a function over data. It is not a
test and it does not run in CI: the CI container has no Docker and no SDK, so the run is on demand,
and the shell is checked here by `bash -n` and by its 13 guards, each seen to fail on the value it
names. `Tools/smoke/probes.py` crafts one input per rule that violates it — 61 crafts plus the
baseline over 20 rules, the baseline asserted to report nothing, so each probe is single-firing,
four rules having one craft and sixteen reading more than one half — and the file readers are in
`Tools/smoke/sources.py` so the rule list stays the readable part, with the runbook rule kept in
`Tools/smoke/runbook.py` because the check half is at the size cap the project sets. The run records
every command it calls as a step, which is the half the runbook rule reads as data rather than as a
list the run declares. Four helpers keep other rules out of the crafts that reach them:
`keep_copy_equal` reads the copy as the rows the second snapshot holds, `set_due` keeps the
mid-round count equal to the pick, `others` takes a row the scheduling rule does not read as the one
in flight, and `change_url` writes a url change to both reads, so a craft that changes the row set
does not also reach the corruption rule, which compares that field between the two reads. The
terminal half, `Tools/smoke/console_feed.py`, gives the container a terminal, and
`Tools/smoke/stub_server.py` declares which input it holds and writes one line per event; neither
asserts anything, so the round rules read a record rather than a process. What the guards read, and
each was seen to fail here on: the base against the line the committed Dockerfile writes, by
`alpine`; the artifact against the product path `Scripts/build-release.sh` names for the triple's
arch, by `aarch64-swift-linux-musl`, a triple this run did not build, so the half that fired here is
the file being there at all, and against the path the release script names by `SMOKE_ARTIFACT` set
outside it; the corpus against the number of records the manifest declares, by 6, and against every
file the manifest names being present, by taking `corpus/smoke_gamma.xml` away; the held delay
against the stop grace, by a delay that does not outlast it, because a round cannot be in flight
when the stop lands before the delay ends; the stop grace against the bound the run names, by 0; the
record path against the document the check half reads, by `/tmp/other.json`; the ports against the
two names being different, by naming one port for both, and against what the machine already holds,
by listening on 9010, which is the half that reads the machine and fires only where `ss` is present;
the wait against the cadence the run declares, by a wait shorter than the interval the first read
comes at; the address policy against the name the config reads the flag by, the value forms the
switch reads, and the address class the policy names, by the value, by the name, and by a target
outside the refused class; the build context against the file the Dockerfile's `COPY` line names, by
naming another name; the held file against the last record the manifest declares, by a file named
earlier; the gap between the `add` calls against the second the value is stored in, by 1, because
the order rule reads the values those calls recorded and the clause fixes none between equal values;
and the credentials run's prompt count against the number of prompts the command declares, read from
the file the check half reads it from, by feeding one value fewer. The guard that reads Docker
itself fails only on a machine without it, which is the point of the job. What the 20 rules read:
the base and the file the `COPY` line names against the Dockerfile and against the export; the
artifact as the pair of digests the run recorded — the file the build left at the path the release
script names against the copy the run put in its build context — the image's own layer being named
as what the run does not read; the corpus as the record count, the file set and the digests against
the manifest; the account line against the sentence the command writes for the name it was given;
the migration answer against the name the schema file declares; the health answer as the path the
route registers, the status and the body the route writes; the login as the field names the handler
binds, the order the credentials command declares its prompts in, the name the group registers that
command as, and the status its guard answers; the reader answer as the key set the shape writes, the
header name and the first word the auth read compares, the path the group and the registration
build, and the token the login answered with; the policy as the name the config read takes the flag
by, the value forms the switch reads, the default the file declares, and the address class the
policy names; the round as the record the stub wrote, read as the request and the answer for each
input and as the point the read was taken; the order the tick's pick takes the rows in as the value
each `add` call wrote, read back through the contract, against the order the manifest declares the
records in and against the column the batch file names, with the pick read as the four conditions
the builder applies and the per-host filter named as a rule the document declares no value for, so
only the default the file declares — off — is read there; the two snapshots as the contract the soak
documents, read key by key; the rows as one row per record the manifest declares, read through the
url the run asked with, with the counts against the records; the stop as the sentence the second
boot answered for the integrity rule, the row set, and the fields the stop does not write — the url
and `enabled`, which no fetch step writes, and the two parsing- error fields, read as unchanged
because the job the stop interrupted never reached its write; the scheduling as the pick the rules
take at the read with the row the run names as in flight unstamped at that read, the stamp landing
after the stop, the schedule landing after the round, and the mid- round count equal to the pick;
the copy as the sentence the command wrote for the destination it was given, read against the file
it wrote with no `-wal` beside it; the machine as the two reads compared through the label the run
writes; the runbook as the commands its fenced lines call, read against the case the dispatch
registers, the flag names each command's signature declares, the names the config reads, the
durability value against the pragma the storage wrapper runs, the room number against the factor the
free-space check uses, and the first record the run kept of each command the page names, read
against the order the page gives them. Only the fenced lines are read as calls, so the restore
recipe, which the page writes as steps to follow rather than as commands to run, is not read as a
call set; the order the rule compares is the order the fenced commands appear in. And the report
against the rule list and the items the check half has. Two read points are what make the mid-round
claim readable, and both are read as data rather than asserted. The first snapshot is taken at the
point the stub had recorded the answers for the inputs the round read before the held one and the
request for the held one without its answer: for that file every hop is held, so the answer for it
lands after the read, in the round after the restart. The second snapshot is taken once the pipeline
had written the row for the interrupted job, because the row is written at the end of a job and the
run waits on the answer the binary gave rather than on a hop count. The held file must be the last
record the manifest declares for the first read to be a read of a round that had covered the corpus
before it, which is why a guard reads the held file's position as data. The run here wrote the rows
in the order the manifest declares them, with the held row unstamped at the read and the mid-round
`due` equal to the pick, and the stub recorded the request for the held file without its answer for
that round — the connection the stop closed — which is the point the rule reads as mid-way. The
order the jobs of that round ran in is named as what no rule reads, because the pool fixes none: an
earlier run here showed the requests first arriving as beta, gamma, delta, alpha, epsilon, while the
values the `add` calls wrote put the rows in the declared order, and the record committed here shows
the arrivals in the declared order too, which is a fact about this run rather than something the
rule reads. Per feed the record shows the fetch hop and the icon hop, which asks the feed url again,
then the site root and `favicon.ico` as names the corpus does not hold, because the icon read takes
the root hop before the file it is given. The credential pair the login read compares is written
through `integration-credentials`, which is the port's own path: the reference reaches the same
values only through its web form, and `create- admin` writes the account hash alone, so the login
would have answered 401 and the reader 401 with no row for the auth read to find. The command reads
its five prompts, and the run writes them through the terminal the run gives the container, because
the secure read answers nothing on a pipe — which is what the parity harness's first live run
showed. The order the rule reads is the order the file declares the prompts in; which prompt
produced which value is named as what no document can say. The values the run feeds are the names
the shell declares as its defaults (`smoke` and `smoke- password`), so the committed document
carries the derivation of that pair rather than a credential. Twelve halves of the probe set cannot
be fired by a crafted document alone, and `Tools/smoke/probes.py` names them: the corpus rule's
missing-file half fires only by taking the file away, which is what the shell guard shows; the
runbook rule's five halves read the page itself, so they fire only on a patch to the page, which is
what was seen here — a command the dispatch registers no case for, a flag its signature does not
declare, a name no config read takes, `FULL` where the wrapper runs `NORMAL`, and 3 where the check
uses 2 — each patch reverted byte- identically. The command patch reached the steps half as well,
because that half reads the commands the page names against the order the run recorded, so the steps
half is named as reached there rather than shown alone; the order rule's clause half is read from
the batch file, so the crafts for that rule reach the values the run recorded rather than the
clause; the corruption rule has no WAL half to craft, because the checkpoint the process harness
reads as an empty WAL is blocked by the write transaction the stop interrupted; and two halves of
the machine rule are craftable only as the labels the run declares. Two more halves are craftable
only through a value a committed file declares, so a craft cannot set the value it compares: the
policy rule's default half reads the default the file declares, so a craft reaches it only with a
value the switch reads as neither on nor off, and the reader rule's endpoint half reads the route
registration, so a craft reaches it only by changing the run's word for the endpoint. The runbook
rule has one half a craft can move, the first record the run kept of each command the page names,
read against the order the page gives them: one craft drops a step the run did not run and another
puts a step out of that order. A command the run called twice is read once, so the half cannot show
the order of a repeat, which is named here as what the half reads only once. The order rule reads
the values the `add` calls wrote: one craft puts them out of the declared order and another makes
two of them one value. The order the jobs of the round ran in is not craftable, because the pool
dispatch fixes none, so that half is named as a gap rather than asserted. What the report names as
what no document can show — the 20 items `CANNOT_SHOW` holds, and the report rule compares the
document against them: that the run ran at all, because it is on demand and not in CI; that the
fetch was still in flight when the signal landed, which only the run knows; that the container held
no toolchain beyond the file the Dockerfile writes, because a scratch base has no shell to list it
with, so the run records the base and the file set; the wording of the lines the binary printed,
which are the port's own; which device the console read took its values from, since the container
has no terminal and the run gives it one through `Tools/smoke/console_feed.py`; the exit code the
stop signal left, because a signal that never lands hangs the run rather than reporting a code; the
WAL bytes the run recorded at the stop, which are the interrupted round's and are not read as the
harness reads them; that the copy the backup wrote is a plain file rather than a database the run
can open, beyond the listing the run read at the moment it looked; that the two machine reads came
from the same machine, because the rule reads two lists rather than one list read twice; that the
run created the containers the machine reads name; that a run which left a container behind would
have read it in the second pass, because the run lists only what it started; that a hop read the
same bytes as the corpus file holds, since the rule reads the record the stub wrote and the digest
of the file; the decision the address policy answered on the round, which the rule reads only as the
flag against the class; the value the config read answered with for the policy flag, since the run
records the value it declared rather than the value the read normalized it to; the order the round's
jobs ran in, which the pool fixes none of; the runbook executed on a machine that is not the one
that wrote it, because the run here ran on the machine that built the artifact, so the rule reads
the page against the dispatch, the signatures, the names the config reads, the pragma and the
factor, and against the first records the run kept of the commands the page names, while the stage's
criterion is a fresh VPS; the tool the runbook names as outside the port, because no command of the
port runs it, so the rule reads only that the page names it as external and not what a stream of it
would hold; the titles the corpus documents declare, because the fetch writes no title and neither
does the reference's refresh path, so the rows carry the empty value the create defaults writes and
the titles are read as declared data rather than as stored values; the whole set the export lists,
because the base puts names of its own in it at build time and a scratch base has no shell to list
them with, so only the file the run put there is read; and which prompt of the credentials run
produced which value, because the run records only the order the file declares the prompts in, never
the order they were answered in. The musl branch of the free-space read is what the run half showed
and no pin can show on the glibc CI, because the first branch is the only one the compiler reads
there: with the branch absent the read answered nothing for the directory the copy is written to, so
`backup` reported the refusal and wrote nothing, and the copy rule had no copy to read. The branch
is named in `Sources/RivuletCore/Storage/SystemFileSystemSpace.swift` and in the header of
`SystemFileSystemSpaceTests`, which names the musl half as checked by the static build rather than
by a pin.

## Deploy artifacts (stage 8)
`Scripts/deploy.sh` is the run half of the deploy slice and `Tools/deploy/deploy_check.py` is its
check half. The run copies the four committed files it reads - the three artifacts and the image
file - into the directory it ran in, asks the two tools to read them there - `docker compose config
--format json` for the compose file and `systemd-analyze verify` for the unit - and hands the
answers to `Tools/deploy/collect.py`, which writes `Tools/deploy/deploy.json`. The check half reads
that document rather than a container or a service, so each of its 16 rules is a function over data.
It is not a test and it does not run in CI: the CI container has neither Docker nor systemd, so the
run is on demand, and the shell is checked here by `bash -n` and by its eight guards, each seen to
fail on the value it names. `Tools/deploy/parsers.py` holds only the reads, so the rule list stays
the readable part, and `Tools/deploy/probes.py` crafts at least one input per rule that violates it:
22 cases over 16 rules, 21 crafts (four rules having more than one, because those rules read more
than one half) plus the baseline, the baseline asserted to report nothing, so each craft reports its
own rule alone or the rules its patch reaches.

What the 16 rules read: the compose as the tool resolved it, key by key, with each port and volume
pair read as the tool took it and the volume name read as the tool resolved it with the project the
run declared, plus the values the tool read from the env file against the committed example, because
the tool puts those values into the service environment rather than answering a key for them; the
build context against the directory the run ran in, and each of the four copies against the bytes
the committed file has, which is the run being allowed to copy and not to change; the subcommand the
tool resolves for the container against the names the dispatch registers, with the entrypoint read
as the file the image copy line writes; the published port against the port the address the tool
resolved names, read as one port on both halves of the pair and against the port the runbook names,
with a value that is the listener the read answers for a value it does not read being reported as
the default rather than as a value the example writes; every name the three files write against the
names the config sources read; each value as the kind of value the source reads that name as, with
the integer reads carrying their minimum and the plus the number read takes as part of it, the
choice reads carrying the case set the enum declares read after the read lowercases what it is
given, the boolean read carrying the forms the switch has after the same lowercase, and the three
reads that take a value as a shape of their own named by the function that reads them; no value in
the example reading as the shape a credential has, read as the marker the hasher writes and the
width the pin names for the hex form the token derivation writes, with the file the run built read
as the gitignored name the file a deployment reads has; the data path as the three files name it;
the unit subcommand against the names the dispatch registers; the program the unit names against the
file the image copy line writes and against the program the tool printed; the tool lines as data,
with the file each names read in the shape the tool prints it in - the name the run passed for the
finding about the program and the path the run built the copy at for a finding about a key - and the
key each names read against the section the tool named it in; the restart policy the two files name
as one value; the signal the unit names against the signals the handler has a case for; the project
name as the tool resolved it against the name the run declared; the keys the three artifacts write
against the bookkeeping the check half keeps; and the two lists the document carries against what
the check half has. The two unit keys that are structure rather than a value the port reads, the
description and the install target, are named in `NOT_READ` rather than left unread, the comment and
empty lines in the three artifacts are the part no rule reads, and the position the tool prints for
a key finding is recorded for the reader and read by no rule.

Two crafts reach more than one rule through one patch, which `Tools/deploy/probes.py` names as
`REACHES`: the restart policy and the container subcommand, because the rule that reads the compose
as the tool resolved it reads the same key each of those crafts changes. Every other craft is kept
single-firing by mirroring the change on the other side of a tool-versus-file read: `mirror` and
`mirror_file` keep the two sides of a key equal, `mirror_env` keeps the values the tool resolved
equal to the values the example writes, `mirror_pairs` keeps a pair list equal on both sides,
`keep_program_line` keeps the tool line for the unit equal to what the unit writes, and
`keep_covered` keeps the bookkeeping equal to the keys the artifacts write after the craft. The
round hashes every file the check half reads before and after, so a craft that reached a file
is reported.

What the eight guards read, each seen to fail here on the value it names: the record path against
the document the check half reads, by `/tmp/opencode/not-read.json`; the three committed artifacts
against the paths the check half reads them at, by `/tmp/opencode/dtest/deploy/compose.yml`,
`/tmp/opencode/dtest/deploy/rivulet.service` and `/tmp/opencode/dtest/.env.example`; the file the
run builds against the gitignored name the file a deployment reads has, by `env.local`; the four
copies against the bytes the committed files have, by writing one extra byte to a copy; the two
tools against the answer each gives for the run, by `/bin/false` for both; the first line the unit
tool printed against the file the run read the unit as - the name it passed for the finding about
the program and the copy it wrote for a finding about a key - by `reader.service`, which is the half
that reports the tool not finding the unit at all; the service key the compose writes against the
service the run declares, by `reader`; and the document the run wrote against the answer both tools
gave, by an empty document written through `deploy_empty=1`, which is the half a run that never ran
cannot pass. The eight guards are fourteen read sites: the record path reads one, the three
committed artifacts read three, the env name reads one, the copies read four, the tools read two
answers, the unit line reads one, the service key reads one, and the document reads two, one for
each answer it carries. Eleven of the fourteen were seen to fail here, because the copy item fires
on the first of the four copies it reads and the document item on the first of the two answers it
reads, which is the order this run reads them in.

What this harness cannot show is named as twelve report items in `docs/deploy.md`, and the same list
is what `deploy_check.py` keeps as `CANNOT_SHOW` and reads against the document, so the report is
data rather than prose: the run having run at all, the image being built or started, the artifact
the Dockerfile names being in the build context, the unit installed and run on a machine, the signal
a stop delivers, the values an operator fills in, the credential pair, the published port being free
on the machine, the wording of the lines the tools printed, the version of each tool the run names,
the runbook executed on a machine that is not the one that wrote it, and a value an operator
changes. One thing outside this harness is named here rather than asserted: the stage criterion of a
fresh VPS following `docs/deploy.md` cannot be closed on this machine, which is what the runbook
report item names, and the run that wrote the committed document is the run this machine ran.

## DocC harness (stage 8)

`Scripts/docs.sh` is the run half of the DocC slice and `Tools/docs/docs_check.py` is its check
half. The run copies the committed catalog into the directory it ran in, keeping the name the tool
reads it as, because the tool reads a directory as a catalog only when the name carries the
extension; it writes its build outside the repository, because a build inside the tree is an
artifact the working agreement does not allow to be committed; runs `docc convert` on the copy; and
hands the answer to `Tools/docs/collect.py`, which writes `Tools/docs/docs.json`. The check half
reads that document rather than a build, so each of its 21 rules is a function over data. It is not
a test: the shell is checked by `bash -n` and by its eight guards, thirteen read sites, each seen to
fail here on the value the usage line names — the record path, the catalog path, the tool, the seven
copies, one for each file the copy has, the asset, the build path, the page set and the document.

The 21 rules read the pages as the shapes they write — the top directive's kind and arguments, the
child directives, the references and assets the table of contents names, the fenced lines, the
commands a page calls, the flags each call carries, the names the page sets, the name-and-value
pairs the fences write, the stated values, the routes, the clients, the links, the repository paths,
the version and the TODO lines — against the sources that write those values: the manifest target,
the dispatch, the config parser and the fetcher options, the two route files, the storage wrapper,
the free-space check, the committed example, the client matrix, the plan table, the root README, the
contents table, the documents the docs directory has, the Swift sources and the report document. The
pages state only what a check here can show, so a page that names a command the dispatch does not
register, a flag no signature declares, a name no config read takes, or a client the matrix records
no row for is a finding rather than a sentence.

`Tools/docs/parsers.py` holds only the reads, so the rule list stays the readable part, and
`Tools/docs/probes.py` crafts at least one input per rule that violates it: 31 cases over 21 rules,
30 crafts plus the baseline asserted to report nothing, so each craft reports its own rule alone; no
craft here reaches more than one rule, and seven rules have more than one craft because each reads
more than one half. Every craft changes the parsed form and never a file, and the round hashes every
file the check half reads before and after, so a craft that reached a file is reported. The shapes
no rule compares are named as not read rather than left unread: the directive kind, the child
directives, and the fenced lines, which are read through the shapes they build.

The run half needs the tool, so CI runs the round, not the run; the Pages job builds the site from
the committed catalog with `docc convert` and publishes what the tool wrote. The tool answers no
version for its own run, so the document records the program the run invoked, which is the half no
rule reads. What this harness cannot show is named as seventeen report items in `docs/docc.md`, and
the same list is what `docs_check.py` keeps as `CANNOT_SHOW` and reads against the document, so the
report is data rather than prose. The symbol pages are the item that names a gap in the toolchain
rather than in the catalog: this toolchain's SwiftPM answers no plugin for the symbol graph the tool
reads, so the site publishes the pages the catalog writes and the rule that reads the sources reads
the comment attached to a declaration through its attribute lines.

## Running

- `swift test` — everything (unit + integration); this is what CI runs.
- `swift test --filter RivuletCoreTests` — unit only (fast loop).
- `swift test --filter RivuletIntegrationTests` — integration only.
- `Scripts/soak.sh` — the soak run, outside CI. `python3 Scripts/soak_check.py --probe` checks that
each of its rules can fail on the rule it names.
- `Scripts/parity.sh` — the parity run, outside CI. `python3 Tools/parity/probes.py` checks that
each of its rules can fail on the rule it names, and `PARITY_DRY_RUN=1 Scripts/parity.sh` runs the
guards alone.
- `python3 Tools/clients/replay.py` — the client matrix check half, outside CI. `python3
Tools/clients/probes.py` checks that each of its 19 rules can fail on the rule it names and that the
baseline reports nothing. `Scripts/perf.sh` is its run half, outside CI too.
- `Scripts/build-release.sh` — stage 8's static release build, outside CI. `RIVULET_SKIP_BUILD=1
Scripts/build-release.sh` runs its checks against an artifact already on disk, which is how each of
its checks was seen to fail on the value it names.
- `Scripts/smoke.sh` — stage 8's clean-container smoke run, outside CI. `python3
Tools/smoke/probes.py` checks that each of its 20 rules can fail on the rule it names and that the
baseline reports nothing, the runbook rule's five page-reading halves being seen to fail by patching
the page itself; the 13 guards run only as part of the run, because they read the machine's ports,
Docker, and the files the run names.
- `Scripts/deploy.sh` — stage 8's deploy run, outside CI. `python3 Tools/deploy/deploy_check.py
--probe` checks that each of its 16 rules can fail on the rule it names and that the baseline
reports nothing; its eight guards run only as part of the run, because they read the two tools and
the files the run writes.
- `Scripts/docs.sh` — stage 8's DocC run, outside CI, because the run half needs the tool. `python3
Tools/docs/docs_check.py` reads the committed document as data and `python3 Tools/docs/docs_check.py
--probe` checks that each of its 21 rules can fail on the rule it names and that the baseline
reports nothing. The run half was seen here to fail on the values its usage lines name, thirteen
read sites over eight guards.
- Heavy suites (100k-entry benchmarks, big-feed scenarios) are disabled by default and enabled by an
`.enabled(if:)` trait gated on `RIVULET_HEAVY`; run them explicitly with `RIVULET_HEAVY=1 swift test
--filter HeavyTests`. The reduced large-feed scenario (`LargeFeedTests`) is the one that runs in the
default job, and it is not gated.
- A few storage tests need at least two event loops (one pooled connection per loop); they
`Test.cancel` on single-loop runners. CI runners always expose ≥2 event loops.

CI runs on Linux: `ubuntu-latest` with the `swift:latest` container and a 15-minute job timeout.
Keep the default suite well under that. Stage 7's cheap CI slice is in the default job — the reduced
hostile corpus and the reduced large-feed scenario, both ungated — and the full parity harness runs
on demand via `Scripts/parity.sh`. The run halves are not in CI, because they read a machine, a tool
or a process: Docker, systemd, the terminal, the DocC tool. The probe rounds are, as their own job
on the runner host, because the Swift container has no `python3` — the five rounds read committed
files as data, so they run on any machine that has the repository and a Python, which is what makes
the job machine-independent; each round was seen to be green from a tree copied to a different root.
The Pages job publishes the DocC site from the committed catalog in the Swift container, where the
tool is on the image.

## Framework

Swift Testing everywhere (`import Testing`, `@Suite`/ `@Test`, `#expect`/ `#require`) — one
framework, no mixing; XCTest and `XCTVapor` are not in the tree. Tests run in parallel by default
and every test owns its resources (temp directories, kernel-assigned ports), so no suite depends on
execution order. Use the `.serialized` trait only where a suite must share process-wide state.
