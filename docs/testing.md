# Testing strategy

Rivulet is developed test-first (TDD): red → green → refactor. Integration tests are not an
afterthought — they run in CI together with unit tests.

## Levels

| Level | Location | Scope |
| --- | --- | --- |
| Unit | `Tests/RivuletCoreTests`, `Tests/RivuletAppTests` | Pure logic: date parsing, charset, sanitizer rules, merge decisions, scheduling math, config, OPML, log formatting |
| Fixture/golden | `Tests/RivuletCoreTests/Fixtures/` (target resources, added in stage 3) | Ported Miniflux corpora: encoding (11 files), parser (8), XML (3), sanitizer (2) — input bytes → golden output — plus the hostile sanitizer corpus, whose outputs are the reference's |
| Integration | `Tests/RivuletIntegrationTests` | Real SQLite in a temp dir, local stub feed server, the full Vapor app over real HTTP |
| Acceptance | `Tools/parity` (stage 7) | Real clients checklist + semantic diff against real Miniflux in Docker |

The integration test target is added to `Package.swift` in stage 0 (no `XCTVapor`: app tests
speak to a real socket through Vapor's client).
Fixture files will be target resources (`resources: [.copy("Fixtures")]`, read via `Bundle.module`)
when stage 3 ports them.

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

## Running

- `swift test` — everything (unit + integration); this is what CI runs.
- `swift test --filter RivuletCoreTests` — unit only (fast loop).
- `swift test --filter RivuletIntegrationTests` — integration only.
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
