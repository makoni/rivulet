# Implementation plan

Rivulet is built in eleven stages. A stage is done when its exit criteria and the global definition
of done are met and CI is green.

Readiness is counted as the open issues plus the code: the open issues in this repository are the
remaining plan, and the code with the documents the check halves read as data is what is done. The
table below states the stage and names the issues that hold the open work; the record of what a run
showed for a stage that is done lives in those documents and in `docs/testing.md`.

## Reference implementation

Miniflux **v2.3.3** (commit `c4d54f87`, <https://github.com/miniflux/v2>) is the behavioral
specification for everything user-visible: parsing rules, sanitizer policy, scheduling, retention,
API payload shapes. Verified specifics are condensed in [reference notes](../reference-notes.md);
re-check the clone when in doubt. We re-implement in Swift; we do not transpile. Where storage
diverges (SQLite instead of PostgreSQL), behavior must match at the API level, not at the SQL level.

## Principles

1. **Miniflux compatibility is the spec.** When in doubt, read the reference implementation and
mirror the observable behavior. 2. **API-first.** Google Reader API and Fever API come before
anything else, so existing clients work. 3. **SQLite-first.** One file, WAL mode, FTS5. No
PostgreSQL, no Redis, no external cron. 4. **CLI-first, no web UI.** All management happens via
commands and environment configuration. 5. **TDD.** Every behavior lands test-first; integration
tests are first-class and run in CI. See [testing strategy](../testing.md). 6. **Small dependency
surface.** Linux-first. New dependencies require explicit approval.

## Stages

| Stage | Title | Status | Effort |
| --- | --- | --- | --- |
| 0 | Foundation | done | M |
| 1 | Storage layer | done | M |
| 2 | Feed fetching | done | M |
| 3 | Parsing & sanitization | merged | XL |
| 4 | Ingestion & scheduling | done | M |
| 5 | Client APIs & OPML | complete | XL |
| 6 | CLI & operations | criteria met | M |
| 7 | [Acceptance & hardening](stage-7-acceptance.md) | in progress — issues 95 and 96 | M |
| 8 | [Packaging & deployment](stage-8-deployment.md) | in progress — issue 97 | S–M |
| 9 | [Post-MVP backlog](stage-9-stretch.md) | in progress — issues 99 to 116 | — |
| 10 | [Miniflux REST v1 subset](stage-10-rest-v1.md) | in progress — issue 121 | — |

**MVP = stages 0–8.** Stage 9 is the 0.1.0 scope, and one of its items is worked as stage 10.

## Working agreement

- Stages are sequential: start the lowest not-started stage unless explicitly redirected.
- Update the status table in the same commit that completes a stage.
- Open work is an issue. A criterion closes only when a run shows it, and the issue is closed in the
  commit that closes it.

## Definition of done (every stage)

- [ ] New behavior is covered by tests written first (TDD).
- [ ] Integration tests cover anything that crosses a module boundary (HTTP, SQLite,
scheduler, API).
- [ ] `swift test` is green locally and in CI.
- [ ] Docs updated (`README.md`, stage status, `docs/` as needed); public APIs carry DocC comments.
- [ ] Ported code/fixtures carry provenance comments and `NOTICE` stays accurate.
- [ ] No compiler warnings, from the project or the test targets; no skipped or disabled tests
(except the documented heavy/on-demand suites).

## Non-goals (MVP)

- Web UI of any kind.
- PostgreSQL, Redis, external cron, message queues.
- Multi-user (single user; the schema leaves room for more).
- Full Miniflux REST v1 parity. The subset one real consumer declares is worked as stage 10, outside
  the MVP; the rest of the v1 surface stays in the stage-9 backlog.
- Native apps of our own — we reuse the existing client ecosystem.

## Known risks

- Feed parser fidelity: the adapters cover RSS 2.0 with 0.91 and 0.92 through the same root name, RDF,
  Atom 1.0 and 0.3, and JSON Feed, but the corpus holds fixtures for RSS, Atom 1.0 and RDF only, so the
  older formats are pinned by the adapter rules rather than by a fixture of their own. Deviations are
  recorded in `docs/parity.md`.
- FTS5 ranking differs from PostgreSQL `tsvector`; the tests are rank sanity tests, not exact-score
  tests.
- Upstream Fever has no tests, so the reference code is the spec; the contract matrix is derived from
  the reference handler and recorded in `docs/reference-notes.md`.
- The static musl artifact is proven for the whole dependency stack, but not on a machine that is not
  the one that built it, and the runbook has not been followed on a fresh server. That is issue 97.
