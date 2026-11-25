# Stage 7 — Acceptance & hardening

**Goal:** prove real-world compatibility with clients and parity with Miniflux; harden the edges.
**Status:** in progress. **Effort:** M. **Depends on:** stages 5–6.

## Open criteria

- [ ] Issue 95 — the client acceptance matrix (`docs/clients.md`): the half that needs a run outside
      this machine, the Capy Reader run against the reference clone so a record line lands on `/v1`,
      and the add half for the Fever client whose set has no call that can write a feed row.
- [ ] Issue 96 — the manual client matrix, open for the four Reeder Classic items the walk did not
      reach: `fever/favicons`, `fever/links`, marking a feed read before a time, marking a group read.

## What the runs showed

The halves the check half reads as data are closed: the calling sets of the five clients, three read
from their own source at a named commit and two from documentation; the records NewsFlash, FeedFlow
and NetNewsWire wrote against this port; the replay of the recorded order against the served app; the
walk on the phone for Reeder Classic's Fever half and for the Capy Reader checklist, whose records are
held as evidence outside the repository because those walks answered on this port while the halves name
the reference as the side the run answered on. The parity harness, the security checklist and the
performance numbers are closed as what their runs showed.

The record lives in the documents the halves read as data: `docs/clients.md`, `docs/parity.md`,
`docs/parity-report.md`, `docs/performance.md`, `docs/security.md`, and in `docs/testing.md`. The run
halves are `Scripts/parity.sh`, `Scripts/perf.sh` and `Scripts/client-run.sh` with
`Tools/clients/observer.py`; the check halves are `Tools/parity/` and `Tools/clients/`.
