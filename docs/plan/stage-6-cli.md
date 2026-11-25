# Stage 6 — CLI & operations

**Goal:** everything is manageable without touching the database or a web UI.
**Status:** every exit criterion met. **Effort:** M. **Depends on:** stages 1–5.

## Decisions this stage set

- The commands are runs through the in-process console: `add`, `remove`, `list` for the feeds, `list`
  for the categories and the accounts, `backup`, `vacuum`, `refresh`, `status`. The flag that names
  which read `list` makes is a flag rather than an argument, because an argument has no default, so a
  run cannot name an optional listing.
- `status --json` is stable for monitoring and for the soak: it is the contract stage 4 set, and `list`
  does not grow a second machine-readable form.
- The process harness reads events rather than time — a line the child writes, a response, an exit —
  and kills the child on both paths, so the rules it holds cannot be pinned by a patch to production
  code; the suite names them in its header.
- The wiring runs the cadence loop to its end and the shutdown hook once after it, which is the
  reference's position for the teardown; this is what the process checks read as "no lost refresh
  batch". The signal seam answers through the first path to reach the decision, and the handler is put
  in place before the server command runs, so a signal arriving while the server starts answers the
  wait instead of ending the child on the default disposition. `SIGHUP` is not ported.
- One finding stays open, and `Sources/RivuletCore/ServerSignalSource.swift` names it: the handler
  answers through a lock and a continuation, which is not async-signal-safe, so a signal delivered on a
  thread that already holds the source's lock can block there. Nothing the pins read changes; if the
  handler moves to a dispatch source, as the server command uses, the answer leaves the signal context
  and the finding closes.

## Exit criteria

- [x] The deployment runbook needs nothing beyond these commands: `docs/deploy.md` calls only commands
  the dispatch registers and only flags those signatures declare, and every command it calls is one the
  plan pins as a run. The one tool the page names outside that set is Litestream, named there as
  outside the port.

The tests that pin these are named in `docs/testing.md`.
