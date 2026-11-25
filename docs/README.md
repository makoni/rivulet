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

Eleven stages, from foundation to the post-MVP backlog, the MVP being stages 0–8. Readiness is counted
as the open issues plus the code: the open issues in this repository are the remaining plan, and the
stage table in [plan/README.md](plan/README.md) names them per stage. What a run showed for a stage that
is done is recorded in the documents the check halves read as data and in [testing.md](testing.md).

## The documentation layer

The pages a person reads are the DocC catalog next to the code,
`Sources/RivuletCore/RivuletCore.docc/`: one table of contents, four concept articles and one
tutorial. The site the layer is served on is outside this repository, and the archive that site
is built from is written by `Scripts/build-docs.sh`, so no CI job here shows a served site and
nothing here reads what a web server answers. That layer is written so it can be published as is —
no local-only references, no TODOs — and the rule that reads it as data is what keeps the claims in
it falsifiable: a page that names a command the dispatch does not register is a finding.
[docc.md](docc.md) names the 21 rules, the run half, the shapes read, and what no rule reads.
