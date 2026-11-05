# Rivulet

A lightweight, self-hosted feed reader — a Swift port of [Miniflux](https://github.com/miniflux/v2)
(behavioral reference: v2.3.3).

> **Status:** early development. The foundation, the storage layer, the fetcher, the parser and the
> sanitizer are in place: configuration, the SQLite storage wrapper with its pragmas, the CLI
> skeleton, `/healthz`, entry queries and FTS5 search, retention and maintenance (backup, vacuum,
> checkpoint on shutdown, startup integrity check), the per-feed refresh pipeline with the
> scheduler's due-batch selection, the icon path, and the CLI commands `refresh` and `status`,
> together with the soak artifact that drives the pipeline over 2h against local stub feeds. Stage 4
> stays open for its in-process cadence loop and for the icon image resizing, which needs a
> dependency that has not been approved, and the client APIs land with stage 5.

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
| `rivulet backup <destination>` | Writes a point-in-time copy of the database to `destination`, used as the path is read |
| `rivulet vacuum` | Rebuilds the database file, releasing the free pages the rows left behind |
| `rivulet --help` | Lists all commands, including the planned ones |

The remaining commands are registered placeholders that report the stage implementing them:
`import` and `export`, the OPML path of stage 5.

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
