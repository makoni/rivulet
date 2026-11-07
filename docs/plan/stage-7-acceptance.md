# Stage 7 — Acceptance & hardening

**Goal:** prove real-world compatibility with clients and parity with Miniflux; harden the edges.
**Status:** in progress — the first slice is the robustness work and opens as PR #55: the hostile
bodies the fetcher cannot read as written, and the reduced 10k-entry scenario with the budgets the
suite documents. The parity harness, the client matrix and the replay of captured request sequences
follow. **Effort:** M. **Depends on:** Stages 5–6.

## Scope

- [ ] Client acceptance matrix (`docs/clients.md`): NetNewsWire (macOS/iOS), lire (iOS),
      FeedFlow (iOS/Android), optionally Reeder Classic — setup instructions and a manual
      checklist (subscribe, add a feed from the client, sync read state, star, counts).
- [ ] Parity harness (`Tools/parity/`, driven by `Scripts/parity.sh`): run real Miniflux in Docker
      and Rivulet against the same local feed corpus; semantic diff of observable behavior
      (entries, counts, ids, endpoint payloads); tolerances and known deviations documented in
      `docs/parity.md`.
- [ ] Replay of captured real-client request sequences (redacted) as contract tests where
      possible.
- [x] Robustness opens as PR #55 on the fetcher side and the reduced corpus: the hostile bodies —
      a stream that inflates far past the size it is stored in, and a stream the decoder cannot
      finish — read as which limit answers, and the 10k-entry scenario with the budgets documented.
      The malformed corpora the stage-3 fixtures already hold are read as they are, not rewritten.
      New cases for the parser side follow when the harness produces them.
- [x] Cheap CI slice in the default job, which is what these two suites are: the reduced hostile
      corpus and the reduced large-feed scenario are both ungated, so `swift test` runs them in the
      job CI already runs.
- [ ] Security pass: SSRF, size/time caps, auth behavior, sanitizer bypass review, dependency
      audit.
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
- Client checklist executed manually and attached to the stage status.

## Exit criteria

- [ ] `docs/parity.md`: deviations listed, each either fixed or consciously accepted.
- [ ] Manual client matrix green (or deviations documented with client-specific notes).
- [ ] Security checklist done; no critical findings open.
