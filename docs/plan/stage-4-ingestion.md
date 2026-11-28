# Stage 4 — Ingestion & scheduling

**Goal:** unattended refresh loop; parsed entries land in the database correctly.
**Status:** done. **Effort:** M. **Depends on:** stages 3 and 1.

## Decisions this stage set

- The clock is a seam, which is what `Sources/RivuletCore/Scheduler/Clock.swift` reads: an injected
  clock answers one instant, so the pins are deterministic. Tests drive the scheduler with explicit
  `tick()` calls.
- The cadence loop is not pinned here, because nothing can pin a sleeping loop; it landed with stage 6
  as the calls the loop makes through its seam.
- The refresh pipeline is one write transaction per feed: fetch, parse, normalize, sanitize, merge,
  store, then feed state. Merge keeps user state: new entries are inserted, changed entries update
  content only, entries missing upstream stay, and a tombstoned `(feed_id, hash)` pair is refused. The
  transaction boundary itself is what no test can pin, so it is stated in `docs/parity.md`.
- The icon path is the selector, the data-URL read, the download order, the checker wiring for one
  stored feed, and the resize step. The scan reads through the port's tokenizer subset, which is the
  precedent stage 3 set for the sanitizer.
- `status --json` is the minimal machine-readable contract the soak reads, and its keys are the column
  names; `docs/parity.md` records that it is the port's own shape.

## Exit criteria

- [x] Soak artifact: `Scripts/soak.sh` runs at least 2h with at least 20 local stub feeds, and the
  snapshots show `fetched_at` and `next_check_at` advancing with no crashes. The checks in
  `Tools/soak/soak_check.py` read the data each round leaves behind rather than the process that
  produced it; the numbers the run left are in the log the run wrote, which is not committed.

Each test suite's header comment names what its tests pin.
