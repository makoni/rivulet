# Rivulet

A lightweight, self-hosted feed reader — a Swift port of [Miniflux](https://github.com/miniflux/v2)
(behavioral reference: v2.3.3).

> **Status:** in progress. What is in place: configuration, the SQLite storage wrapper with its
> pragmas, the fetcher, the parser and the sanitizer, `/healthz`, entry queries and FTS5 search,
> retention and maintenance (backup, vacuum, checkpoint on shutdown, startup integrity check), the
> per-feed refresh pipeline with the scheduler's due-batch selection, the icon path with its resize
> step, the client APIs (Google Reader and Fever) with the storage reads the routers run, the CLI
> command set with the in-process cadence loop `serve` runs, and the acceptance harnesses that read
> their own runs as data. Stage 8's documentation layer is the DocC catalog, its four articles and
> its tutorial, read as data by the harness and published as a site outside this repository.

Stage states as `docs/plan/README.md`'s table states them:

- Stage 0 - Foundation: done
- Stage 1 - Storage layer: done
- Stage 2 - Feed fetching: done
- Stage 3 - Parsing & sanitization: merged
- Stage 4 - Ingestion & scheduling: done
- Stage 5 - Client APIs & OPML: in progress
- Stage 6 - CLI & operations: criteria met
- Stage 7 - Acceptance & hardening: in progress
- Stage 8 - Packaging & deployment: in progress
- Stage 9 - Post-MVP backlog: backlog

## What it will be

Rivulet aims to be a small, single-binary RSS/Atom reader for a personal server:

- **Feed aggregation** — scheduled fetching with conditional requests (ETag / Last-Modified), RSS /
  Atom / RDF / JSON Feed parsing, HTML sanitization.
- **SQLite storage** — a single database file in WAL mode with FTS5 full-text search. No external
  database service.
- **Client APIs** — Google Reader API and Fever API, so existing native clients keep working:
  NetNewsWire, lire, FeedFlow, Reeder Classic and friends.
- **CLI-first** — no web interface: `rivulet add`, `rivulet import feeds.opml`, `rivulet refresh`,
  `rivulet serve`.
- **Built with** — [Vapor 4](https://vapor.codes),
  [Fluent](https://docs.vapor.codes/fluent/overview/) + [SQLite](https://www.sqlite.org),
  [SwiftSoup](https://github.com/scinfu/SwiftSoup) for the entry text. The parser and the sanitizer
  are the port's own, read through its tokenizer subset; the external-library spike that chose that
  is recorded in `docs/plan/spike-3-parser.md`.

## Commands

Rivulet is CLI-first. The commands that exist so far:

| Command | What it does |
| --- | --- |
| `rivulet serve` | Runs the HTTP server (`LISTEN_ADDR`); Vapor's server flags (`--hostname`, `--port`, `--bind`) work |
| `rivulet migrate` | Creates or updates the SQLite schema |
| `rivulet version` | Prints the version |
| `rivulet refresh` | One pass over the due batch with the values the configuration gives the builder, then exits |
| `rivulet status` | The feed state: each row with its last fetch, errors and next check, plus the counts; `--json` prints the machine-readable document |
| `rivulet create-admin` | Creates the account the login path reads |
| `rivulet integration-credentials` | Sets the account's integration credentials |
| `rivulet add <url>` | Adds one feed row, for the account named by `--user` or the single account |
| `rivulet remove <url>` | Removes one feed row and the rows below it |
| `rivulet list` | Lists one listing: the feeds of one account in the order the reference's query builder answers, the categories in the order its category read answers, or every account in the order its user read answers; `--categories` and `--users` name which one, and no flag means the feeds |
| `rivulet backup <destination>` | Writes a point-in-time copy of the database to `destination`, used as the path is read, after the free-space check it makes at its start; a destination that already holds something is refused and left as it was, unless `--force` names it as one the run may replace; `--verify` reads the copy the run wrote through a connection of its own and reports what the check observed as the failure, leaving the copy as written |
| `rivulet vacuum` | Rebuilds the database file, releasing the free pages the rows left behind |
| `rivulet --help` | Lists all commands, including the planned ones |

Every command in the table is a run: the command set is complete, `import` and `export` being
the OPML commands of stage 5 that landed with PR #64.

`--help` and `version` work without any configuration; every other command reads the
configuration first and needs `DATABASE_URL`.

## Development

Requires Swift 6.x on Linux or macOS.

```sh
swift build
swift test
```

## License and attribution

Rivulet is an independent Swift implementation, inspired by and aiming for compatibility with
[Miniflux](https://github.com/miniflux/v2) — Copyright (c) Frédéric Guillot and contributors,
licensed under the Apache License 2.0. See [NOTICE](NOTICE) for details.

Rivulet itself is licensed under the Apache License, Version 2.0 — see [LICENSE](LICENSE).
