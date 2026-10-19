# Stage 7 — Acceptance & hardening

**Goal:** prove real-world compatibility with clients and parity with Miniflux; harden the edges.
**Status:** not started. **Effort:** M. **Depends on:** Stages 5–6.

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
- [ ] Robustness: hostile/malformed corpus (reuse stage 3 plus new cases); 10k-entry feed with
      documented time/memory budgets.
- [ ] Cheap CI slice in the default job: reduced hostile corpus + reduced large-feed smoke.
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
- Client checklist executed manually and attached to the stage status.

## Exit criteria

- [ ] `docs/parity.md`: deviations listed, each either fixed or consciously accepted.
- [ ] Manual client matrix green (or deviations documented with client-specific notes).
- [ ] Security checklist done; no critical findings open.
