# Rivulet documentation

Rivulet is a lightweight, self-hosted feed reader for personal servers — a Swift port of
[Miniflux](https://github.com/miniflux/v2) (behavioral reference: v2.3.3) with SQLite storage, a
CLI-first interface and no web UI.

## Contents

| Document | Description |
| --- | --- |
| [Implementation plan](plan/README.md) | The stage table and the decisions each stage set; open work is in issues |
| [Architecture](architecture.md) | Module layout, data model, SQLite design decisions |
| [Backup and restore](backup-restore.md) | Snapshots, restoring a database, disk-space housekeeping |
| [Testing strategy](testing.md) | Test levels, TDD workflow, infrastructure, fixtures, manual scripts |
| [Reference notes](reference-notes.md) | Verified Miniflux v2.3.3 behavior condensed for the plan |
| [Parity notes](parity.md) | Where Rivulet knowingly differs from Miniflux, and why |
| [Security checklist](security.md) | SSRF, size and time caps, auth, sanitizer bypass, dependency audit |
| [Clients](clients.md) | The supported client apps, how to connect each, and what has been verified |
| [Performance notes](performance.md) | Rough timings from `Scripts/perf.sh` |
| [Deploy runbook](deploy.md) | Installing, running, backing up and upgrading on a server |
| [AGENTS.md](../AGENTS.md) | Working agreement for AI agents and contributors (TDD-first) |

## Plan at a glance

Eleven stages, from foundation to the post-MVP backlog; the MVP is stages 0–8. The remaining work
is the open issues in this repository, and the stage table in [plan/README.md](plan/README.md)
names the issues that belong to each stage.

## User documentation

The user-facing documentation is the DocC catalog next to the code,
`Sources/RivuletCore/RivuletCore.docc/`: a table of contents, four concept articles and one
tutorial. `Scripts/build-docs.sh` builds the archive; publishing the site happens outside this
repository. `DocumentationConsistencyTests` keeps the catalog in sync with the CLI and the
configuration.
