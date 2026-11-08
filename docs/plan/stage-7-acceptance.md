# Stage 7 — Acceptance & hardening

**Goal:** prove real-world compatibility with clients and parity with Miniflux; harden the edges.
**Status:** in progress — the first slice is the robustness work, merged (PR #55): the hostile
bodies the fetcher cannot read as written, and the reduced 10k-entry scenario with the budgets the
suite documents. The second slice is the security checklist, merged (PR #56): the checklist is
`docs/security.md`, and the rules it could express as pins landed there — 8 pins and 7 probes across
five suites, one finding closed in production code. The third slice is the parity harness, merged as
PR #57: the comparator reads a comparison run as the pair document it leaves behind, the tolerance
table in `docs/parity.md` is read as data, and the probe set shows each rule can fail on the rule it
names — 18 rules, 20 crafted inputs plus the baseline. The fourth slice is merged as PR #58: the run
half executed here for the first time, with Postgres as a container, and what it reported was the
login half, which the run reaches and cannot pass. The client matrix and the replay of captured
request sequences follow. **Effort:** M. **Depends on:** Stages 5–6.

## Scope

- [ ] Client acceptance matrix (`docs/clients.md`): NetNewsWire (macOS/iOS), lire (iOS),
      FeedFlow (iOS/Android), optionally Reeder Classic — setup instructions and a manual
      checklist (subscribe, add a feed from the client, sync read state, star, counts).
- [x] Parity harness (`Tools/parity/`, driven by `Scripts/parity.sh`): real Miniflux and Rivulet
      read the same corpus, and the difference is read class by class against the tolerance table,
      which is read as data from `docs/parity.md` rather than restated in the comparator. The corpus
      is the five documents under `Tools/parity/corpus/` plus the three request shapes the table
      names, and the manifest names the classes each input can reach; what the corpus cannot reach
      is named there rather than asserted. The run half executed here for the first time, with
      Postgres as a container, and what it reported was the login half: the reference reads the
      integration row the login read runs on, where the enabled flag that read requires is set only
      by its web form, which this port has no equivalent of — it has no integration table and no
      flag, and its own path for the pair is the console command — so no single path sets the values
      for both sides. The
      report committed under `docs/` is therefore the one the harness writes from the table, not one
      a run wrote, and the guards in the shell are the half that can be checked without a run.
- [ ] Replay of captured real-client request sequences (redacted) as contract tests where
      possible.
- [x] Robustness landed with PR #55 on the fetcher side and the reduced corpus: the hostile bodies —
      a stream that inflates far past the size it is stored in, and a stream the decoder cannot
      finish — read as which limit answers, and the 10k-entry scenario with the budgets documented.
      The malformed corpora the stage-3 fixtures already hold are read as they are, not rewritten.
      New cases for the parser side follow when the harness produces them.
- [x] Cheap CI slice in the default job, which is what these two suites are: the reduced hostile
      corpus and the reduced large-feed scenario are both ungated, so `swift test` runs them in the
      job CI already runs.
- [x] Security pass done as `docs/security.md`, with the pins it could express landing as 8 pins and
      7 probes across five suites (merged as PR #56): SSRF, the size and time caps, the auth
      behavior, the sanitizer bypass surface and the dependency audit. The rules no patch can flip
      are named in the document rather than asserted; one finding was closed in production code.
- [ ] Performance notes: refresh of 100 feeds, query latency at 100k entries — numbers recorded.

## Implementation notes

- The parity harness is on demand (not in the default CI job); it produces a markdown report that
  is committed under `docs/`.
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
  staying at its cap after a checkout that goes over it, and the entry the trim closing being the
  one whose expiry comes first (`FetcherClientCacheTests`, 2 pins and 2 probes); the sign
  `strconv.Atoi` reads as part of a number (`SanitizerTests`, 1 pin and 1 probe); and the entity
  table the sanitizer's scheme check reads through (`SanitizerHostileCorpusTests`, 1 pin and 1
  probe).
- Client checklist executed manually and attached to the stage status.
- `Tools/parity/parity_check.py` with `Tools/parity/probes.py` — the 18 rules over the data one run
  leaves behind, each shown to fail on the rule it names: 20 crafted inputs plus the baseline, which
  is asserted to report nothing, so each probe is single-firing. The rules were written after the
  probe set: with the rules stubbed all 18 fail, and the patch round changes what each rule reads,
  shows the probe for that rule failing, and reverts the file byte-identically. `Scripts/parity.sh`
  is the run half: twelve of its nineteen checks name a value the run declares or a count it
  declares against the committed files, and each was seen to fail on such a value or by taking the
  file it names away; the seven that read the machine or the run's own data fail only on a run, and
  three of them were seen to fail here — a port something already holds, the base its own side
  answers on, by pointing the run at a binary that exits at once, and the login answer, by the run
  itself. The run half executed here for the first time, with Postgres as a container, and what it
  reported was the login half, so the committed report is the one written from the table by hand.

## Exit criteria

- [x] `docs/parity.md`: deviations listed, each either fixed or consciously accepted. The harness
      section reads them as data, names the classes its corpus cannot reach, and the report it
      writes (`docs/parity-report.md`) names every rule, every class and what the run cannot show.
      The machine the run needs is here now, and the run executes end to end through the collector;
      what is still open is the login half, which the run reaches and cannot pass here, and the
      classes no corpus input can reach.
- [ ] Manual client matrix green (or deviations documented with client-specific notes).
- [x] Security checklist done (`docs/security.md`); no critical findings open. The one finding the
      pass found — a repeated response header name keeping the last value instead of the first the
      reference reads — is closed by this slice.
