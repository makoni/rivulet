# Rivulet documentation

Rivulet is a lightweight, self-hosted feed reader for personal servers — a Swift port of
[Miniflux](https://github.com/miniflux/v2) (behavioral reference: v2.3.3) with SQLite storage,
a CLI-first interface and no web UI.

## Contents

| Document | Description |
| --- | --- |
| [Implementation plan](plan/README.md) | Stage-by-stage plan: scope, tests, exit criteria, effort |
| [Architecture](architecture.md) | Module layout, data model, SQLite design decisions |
| [Testing strategy](testing.md) | Unit, fixture, integration and acceptance testing; TDD workflow |
| [Reference notes](reference-notes.md) | Verified Miniflux v2.3.3 behavior condensed for the plan |
| [AGENTS.md](../AGENTS.md) | Working agreement for AI agents and contributors (TDD-first) |

Planned documents (created by the stages that need them): `clients.md` (stage 7),
`parity.md` (stages 3+ / 7), `deploy.md` (stage 8). API documentation and tutorials are built
with DocC and published later (stage 8).

## Plan at a glance

Ten stages, from foundation to post-MVP backlog. Stage 0 (foundation) is in progress;
the MVP is stages 0–8. See [plan/README.md](plan/README.md) for the full table.
