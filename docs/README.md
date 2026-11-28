# Rivulet documentation

Rivulet is a lightweight, self-hosted feed reader for personal servers — a Swift port of
[Miniflux](https://github.com/miniflux/v2) (behavioral reference: v2.3.3) with SQLite storage, a
CLI-first interface and no web UI.

## Contents

| Document | Description |
| --- | --- |
| [Implementation plan](plan/README.md) | The stage table, the open criteria as issues, and where each record lives |
| [Architecture](architecture.md) | Module layout, data model, SQLite design decisions |
| [Backup and restore](backup-restore.md) | Snapshots, restoring a database, disk-space housekeeping |
| [Testing strategy](testing.md) | Unit, fixture, integration and acceptance testing; TDD workflow |
| [Reference notes](reference-notes.md) | Verified Miniflux v2.3.3 behavior condensed for the plan |
| [Parity notes](parity.md) | Where Rivulet knowingly differs from Miniflux, and why |
| [Parity report](parity-report.md) | The last comparison run, read as data by the parity comparator |
| [Security checklist](security.md) | SSRF, size and time caps, auth behavior, sanitizer bypass, dependency audit: what is pinned, what cannot be |
| [Client matrix](clients.md) | Calling sets of the acceptance clients, the checks for each, and what the matrix cannot show |
| [Performance notes](performance.md) | The measured numbers, each matched to the run that produced it |
| [Deploy runbook](deploy.md) | The steps a fresh machine follows, read as data by the runbook rule |
| [DocC harness](docc.md) | The pages the catalog writes, the rules that read them as data, and what no rule reads |
| [AGENTS.md](../AGENTS.md) | Working agreement for AI agents and contributors (TDD-first) |

## Plan at a glance

Eleven stages, from foundation to the post-MVP backlog; the MVP is stages 0–8. The remaining work
is the open issues in this repository, and the stage table in [plan/README.md](plan/README.md)
names the issues that belong to each stage.

## User documentation

The user-facing documentation is the DocC catalog next to the code,
`Sources/RivuletCore/RivuletCore.docc/`: a table of contents, four concept articles and one
tutorial. `Scripts/build-docs.sh` builds the archive; publishing the site happens outside this
repository. [docc.md](docc.md) describes the checks that keep the catalog in sync with the code.
