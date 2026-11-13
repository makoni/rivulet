# Stage 7 — Acceptance & hardening

**Goal:** prove real-world compatibility with clients and parity with Miniflux; harden the edges.
**Status:** in progress — the first slice is the robustness work, merged (PR #55): the hostile
bodies the fetcher cannot read as written, and the reduced 10k-entry scenario with the budgets the
suite documents. The second slice is the security checklist, merged (PR #56): the checklist is
`docs/security.md`, and the rules it could express as pins landed there — 8 pins and 7 probes across
five suites, one finding closed in production code. The third slice is the parity harness, merged as
PR #57: the comparator reads a comparison run as the pair document it leaves behind, the tolerance
table in `docs/parity.md` is read as data, and the probe set shows each rule can fail on the rule it
names — 19 rules, 21 crafted inputs plus the baseline. The fourth slice is merged as PR #58: the run
half executed here for the first time, with Postgres as a container, and what it reported was the
login half, which the run reaches and cannot pass. The fifth slice, which merged as PR #60, closes
that half as an accepted-divergence row: the run writes the credential pair through the two paths
the two sides have — SQL on the reference side, where the enabled flag the login read requires is
set only by its web form, and its own console command on this side, which has no integration table
and no flag — so what the rule can read is the answer, and the row names which path wrote the value
as not reachable here; the run that writes one value through both paths reports nothing but the key
set the method-mismatch row names. The sixth slice is the Fever parameter set sized to what the
acceptance client calls, which merged as PR #61: the base document, the five read documents, the
three `mark` branches and the `HEAD` reachability check, pinned as 32 pins and 67 probes across the
seven Fever suites and the icon read, each seen to fail on the rule it names and to revert the file
byte-identically, with the accepted row for the empty list this client's deserializer refuses added
to the tolerance table. The seventh slice is the client matrix and the performance notes, merged as
PR #63: `docs/clients.md` records the calling sets of five clients — three read from their own
source at a named commit, two from the project's documentation because their source cannot be read
here — and the check half reads those sets, the record files, the document and the port's own route,
dispatch, auth and response sources as data over 19 rules, with the parsers kept apart from the
rules so each rule stays a function over data. No set is a capture. NewsFlash is the client run
against this port here, through `Scripts/client-run.sh`, and the record that run wrote is read as
data by the rule that reads it, which is the nineteenth rule. That run half and that rule are the
eighth slice, merged as PR #71: seven halves over the record the run left behind, 30 crafted inputs
plus the baseline over 19 rules, and eight guards, ten read sites, seen to fail on the value each
names. The manual matrix criterion is closed for that client and stays open for the four this
machine has no device to run, which is what the report items name. The performance half records
measurements taken here rather than bounds. **Effort:** M. **Depends on:** Stages 5–6.

## Scope

- [ ] Client acceptance matrix (`docs/clients.md`): NetNewsWire (macOS/iOS), lire (iOS), FeedFlow
(iOS/Android), optionally Reeder Classic, and Newsflash (iOS) — the Fever client whose calling set
the sixth slice was sized to — setup instructions and a manual checklist (subscribe, add a feed from
the client, sync read state, star, counts). Done as the half this machine can do: the calling sets
are recorded for all five, three read from their own source at a named commit and two from
documentation, with the setup and the checklist written for each. No set is a capture. NewsFlash is
the client run against this port here, through the run half `Scripts/client-run.sh`, and its
checklist is the half that run walked. The manual half stays open for the four clients this machine
has no device to run, and the half that adds a feed stays open for the run here too, because the
Fever set has no call for adding a feed: the row the run reads was put there by `rivulet add`.
- [x] Parity harness (`Tools/parity/`, driven by `Scripts/parity.sh`): real Miniflux and Rivulet
read the same corpus, and the difference is read class by class against the tolerance table, which
is read as data from `docs/parity.md` rather than restated in the comparator. The corpus is the five
documents under `Tools/parity/corpus/` plus the six request shapes the manifest records, four of
which the table names and two of which reach no class it names, which is what lets a difference be
attributed to a class rather than accepted by the comparator's own preference; the manifest also
names the classes each input can reach, and the two shapes that reach none are the ones a difference
on can only be a finding by itself. what the corpus cannot reach is named there rather than
asserted. The run half executed here end to end through the collector, and the login half the first
run reported is closed as an accepted-divergence row: the reference reads the integration row the
login read runs on, where the enabled flag that read requires is set only by its web form, which
this port has no equivalent of — it has no integration table and no flag, and its own path for the
pair is the console command — so no single path sets the values for both sides, and the run writes
the pair through two: SQL on the reference side and its own command on this one. The report
committed under `docs/` is the one the harness writes from the table before the rules read it, which
is the same document a run writes from the same table, and the guards in the shell are the half that
can be checked without a run.
- [x] The calling sets read as data and replayed as pins where the port answers:
`Tests/RivuletIntegrationTests/CallingSets/` is the record both halves read — the pins through
`Bundle.module`, the check half from disk — and `ClientSequenceReplayTests` replays the recorded
order and the answer the matrix names for each call. Nothing was captured here, so this is the whole
of what a pin can show: 9 pins and 10 probes, each seen to fire on the rule it names.
- [x] Robustness landed with PR #55 on the fetcher side and the reduced corpus: the hostile bodies —
a stream that inflates far past the size it is stored in, and a stream the decoder cannot finish —
read as which limit answers, and the 10k-entry scenario with the budgets documented. The malformed
corpora the stage-3 fixtures already hold are read as they are, not rewritten. New cases for the
parser side follow when the harness produces them.
- [x] Cheap CI slice in the default job, which is what these two suites are: the reduced hostile
corpus and the reduced large-feed scenario are both ungated, so `swift test` runs them in the job CI
already runs.
- [x] Security pass done as `docs/security.md`, with the pins it could express landing as 8 pins and
7 probes across five suites (merged as PR #56): SSRF, the size and time caps, the auth behavior, the
sanitizer bypass surface and the dependency audit. The rules no patch can flip are named in the
document rather than asserted; one finding was closed in production code.
- [x] Performance notes: the refresh of 100 feeds is recorded as measurements taken here in
`docs/performance.md` — four runs with the wall time, the second pass that read an empty batch, the
entries written and the read path the timed pin printed. The query latency at the 100k corpus is not
recorded, because that corpus is gated and no number for it exists here.

## Implementation notes

- The parity harness is on demand (not in the default CI job); it produces a markdown report that is
committed under `docs/`.
- Anything the harness flags as a deviation is either fixed or consciously accepted with a note.

## Tests

### Integration

- Parity harness report with any behavioral deltas.
- Large-feed scenario runnable locally and (reduced) in CI.
- `FetcherHostileInputTests` — the hostile bodies over the stub server: the size cap counted on the
bytes the decoder produces, a body expanding over a ratio guard accepted under the cap, the body
read as the server sent it with decompression off, and a stream the decoder cannot finish read
through the category the cap does not own. 4 pins and 5 probes.
- `LargeFeedTests` — the reduced 10k-entry scenario in the default CI job: the plan the schema
answers for the hot unread listing, the page the query is given, the relevance order at the corpus
size, the batch the retention pass takes with the rows it leaves for the next run, and the
wall-clock bound the read path stays inside. 5 pins and 6 probes, two of them on the page pin: the
page size dropped from the clause, and the direction the order is read in.
- `RepeatedResponseHeadersTests` — a response name that appears twice, read as which value the
reference acts on: the first value wins, one name written two ways is one name, and the first
`Location` is the hop the fetch takes. 3 pins and 2 probes.
- The pins the checklist added to suites that already existed: the address policy running on a hop
that took its client from the cache (`FetcherSecurityTests`, 1 pin and 1 probe); the client cache
staying at its cap after a checkout that goes over it, and the entry the trim closing being the one
whose expiry comes first (`FetcherClientCacheTests`, 2 pins and 2 probes); the sign `strconv.Atoi`
reads as part of a number (`SanitizerTests`, 1 pin and 1 probe); and the entity table the
sanitizer's scheme check reads through (`SanitizerHostileCorpusTests`, 1 pin and 1 probe).
- The Fever parameter set the acceptance client calls, pinned as pure logic and over a real socket:
the base document, the five read documents, the three `mark` branches and the `HEAD` reachability
check. 32 pins and 67 probes across `FeverMultipartReadTests`, `FeverShapeTests`, `FeverAuthTests`,
`FeverDispatchTests`, `FeverReadsTests`, `FeverItemsTests` and `FeverWriteTests`, plus the icon
read, each seen to fail on the rule it names and to revert the file byte-identically. Three part
rules and two value rules are read as the reference reads them rather than recorded as divergences:
the header line with no colon, the malformed parameter, the empty filename, the publication time,
and the negative value that answers the default. What no patch can show is named in the headers
rather than asserted: the port's own `HEAD` registration, because Vapor forwards the method to the
GET route, and the order the reference's icon join answers, which its statement does not order.
- The client matrix: `Tools/clients/replay.py` with `Tools/clients/probes.py`, 19 rules over the
record files, `docs/clients.md`, `docs/performance.md`, the sentence `docs/reference-notes.md`
writes for the output-check sets, and the port's own route, dispatch, auth and response sources read
as data, each rule shown to report its own crafted input alone and the baseline to report nothing —
30 crafted inputs plus the baseline, so 31 cases, with the round hashing every file the check half
reads before and after, so a craft that reached a file is reported. The parsers are in
`Tools/clients/parsers.py`, so the rules stay the readable part.
- `Scripts/client-run.sh` with `Tools/clients/observer.py` — the run half of the client matrix,
outside CI: the observer writes one record line per request it forwarded and asserts nothing, and
the rule that reads the run record reads the record the run left behind as data in seven halves. The
run half is checked here by `bash -n` and by its eight guards, each seen to fail on the value it
names: the record path, the client row, the two ports, the base, the version, the pair row, the
entry rows, and the record being empty. The two guards that read the rows the run writes fail only
on a run, and the guards that read the machine fail only on a machine.
- `ClientSequenceReplayTests` — the recorded calling sets replayed against the served app over a
real socket, read through `Bundle.module` as data rather than restated: the order each set declares,
which recorded call reaches a registered route and which reaches the catch-all answer, the two
item-id forms the same client sends, the page size above the clamp against the value at the clamp,
the token half per method, the guard the merged form answers for the call with no add and no remove
pair, the name the dispatch switch has no case for, and the prefix this port registers no route for.
9 pins and 10 probes, each seen to fire on the rule it names and to revert the file it
patched byte-identically.
- `Scripts/perf.sh` with `Tools/clients/perf-run.txt` — the run half of the performance half,
outside CI: the rule matches each number `docs/performance.md` names as measured here to the record
line that produced it, and reports the five kinds of finding it reads: a claim the log does not
carry, a field no source declares, a record line the document does not name, a shape the document
names differently than the run answered it, and the value the table reports against the value the
log carries.
- Client checklist executed manually and attached to the stage status.
- `Tools/parity/parity_check.py` with `Tools/parity/probes.py` — the 19 rules over the data one run
leaves behind, each shown to fail on the rule it names: 21 crafted inputs plus the baseline, which
is asserted to report nothing, so each probe is single-firing. The rules were written after the
probe set: with the rules stubbed all 19 fail, and the patch round changes what each rule reads,
shows the probe for that rule failing, and reverts the file byte-identically; the patch for the
login-half rule reads the reference's own stored value instead of the one this port wrote, and was
seen to fire on run data. `Scripts/parity.sh` is the run half: twelve of its twenty checks name a
value the run declares or a count it declares against the committed files, and each was seen to fail
on such a value or by taking the file it names away; the eight that read the machine or the run's
own data fail only on a run, and four of them were seen to fail here — a port something already
holds, the base its own side answers on, by pointing the run at a binary that exits at once, the
login answer, by the run itself, and the stored rows, by running the same declared database twice.
The authenticated run here reports one finding, the key set the method-mismatch row names, and the
committed report is the document the harness writes from the table.

## Exit criteria

- [x] `docs/parity.md`: deviations listed, each either fixed or consciously accepted. The harness
section reads them as data, names the classes its corpus cannot reach, and the report it writes
(`docs/parity-report.md`) names every rule, every class and what the run cannot show. The machine
the run needs is here now, and the run executes end to end through the collector with an
authenticated pair; the login half is closed as the accepted-divergence row for the path that writes
the pair, and what is still open is the classes no corpus input can reach.
- [ ] Manual client matrix green (or deviations documented with client-specific notes). Closed for
the halves one real client can show here: NewsFlash connects and syncs against a locally served port
through `Scripts/client-run.sh`, and the record that run wrote is read as data. The four clients
this machine has no device to run are one open half, and the feed the client adds is another,
because the Fever set has no call for adding a feed.
- [x] Security checklist done (`docs/security.md`); no critical findings open. The one finding the
pass found — a repeated response header name keeping the last value instead of the first the
reference reads — is closed by this slice.
