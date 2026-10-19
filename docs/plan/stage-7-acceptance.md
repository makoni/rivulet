# Stage 7 — Acceptance & hardening

**Goal:** prove real-world compatibility with clients and parity with Miniflux; harden the edges.
**Status:** not started. **Effort:** M. **Depends on:** Stages 5–6.

## Scope

- [ ] Client acceptance matrix (`docs/clients.md`): NetNewsWire (macOS/iOS), lire (iOS),
      FeedFlow (iOS/Android), optionally Reeder Classic — setup instructions and a manual
      checklist (subscribe, add a feed from the client, sync read state, star, counts).
- [ ] Parity harness (`Tools/parity/`): run real Miniflux in Docker and Rivulet against the same
      local feed corpus; compare observable behavior (entries, counts, ids, endpoint payloads)
      with a semantic diff; document tolerances and known deviations in `docs/parity.md`.
- [ ] Robustness: malformed/hostile corpus (reuse stage 3 fixtures plus new cases); a 10k-entry
      feed with time/memory budgets.
- [ ] Security pass: SSRF, size/time caps, auth behavior, sanitizer bypass review, dependency
      audit.
- [ ] Performance notes: refresh of 100 feeds, query latency at 100k entries — numbers recorded
      in docs.

## Tests

### Integration

- Parity harness (on demand; not in default CI): produces a markdown report with any behavioral
  deltas.
- Large-feed scenario with documented budgets, runnable locally.
- Client checklist executed manually and attached to the stage status.

## Exit criteria

- [ ] `docs/parity.md`: deviations listed, each either fixed or consciously accepted.
- [ ] Manual client matrix green (or deviations documented with client-specific notes).
- [ ] Security checklist done; no critical findings open.
