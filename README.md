# Rivulet

A lightweight, self-hosted feed reader — a Swift port of [Miniflux](https://github.com/miniflux/v2)
(behavioral reference: v2.3.3).

> **Status:** the MVP works end to end; the 0.1.0 release scope is still open. Open work is tracked
> as issues in this repository.

Stage states as `docs/plan/README.md`'s table states them:

- Stage 0 - Foundation: done
- Stage 1 - Storage layer: done
- Stage 2 - Feed fetching: done
- Stage 3 - Parsing & sanitization: merged
- Stage 4 - Ingestion & scheduling: done
- Stage 5 - Client APIs & OPML: complete
- Stage 6 - CLI & operations: criteria met
- Stage 7 - Acceptance & hardening: in progress
- Stage 8 - Packaging & deployment: in progress
- Stage 9 - Post-MVP backlog: in progress
- Stage 10 - Miniflux REST v1 subset: in progress

## What it does

A small, single-binary RSS/Atom reader for a personal server:

- **Feed aggregation** — scheduled fetching with conditional requests (ETag / Last-Modified), RSS /
  Atom / RDF / JSON Feed parsing, HTML sanitization, feed icons.
- **SQLite storage** — one database file in WAL mode with FTS5 full-text search, retention,
  backups and vacuum. No external database service.
- **Client APIs** — Google Reader API (`/reader/api/0`), Fever API (`/fever`) and the subset of the
  Miniflux REST v1 API (`/v1`) that Capy Reader uses, so existing native clients keep working:
  NetNewsWire, FeedFlow, NewsFlash, Reeder Classic, Capy Reader.
- **CLI-first** — no web interface; everything is managed with commands and environment variables.
- **Built with** — [Vapor 4](https://vapor.codes),
  [Fluent](https://docs.vapor.codes/fluent/overview/) + [SQLite](https://www.sqlite.org),
  [SwiftSoup](https://github.com/scinfu/SwiftSoup) for the entry text. The feed parser and the HTML
  sanitizer are Rivulet's own; `docs/plan/spike-3-parser.md` records why.

## Commands

| Command | What it does |
| --- | --- |
| `rivulet serve` | Runs the HTTP server and the background refresh loop (`LISTEN_ADDR`; Vapor's `--hostname`, `--port`, `--bind` also work) |
| `rivulet migrate` | Creates or updates the SQLite schema |
| `rivulet version` | Prints the version |
| `rivulet refresh` | Refreshes the feeds that are due once, then exits |
| `rivulet status` | Shows each feed's last fetch, errors and next check, plus totals; `--json` for machine-readable output |
| `rivulet create-admin` | Creates the admin account (and its default category) |
| `rivulet integration-credentials` | Sets the account's Fever and Google Reader login pairs |
| `rivulet create-api-key <description>` | Creates an API key for the REST v1 API (`X-Auth-Token`) |
| `rivulet add <url>` | Subscribes to a feed (`--user` picks the account when there is more than one) |
| `rivulet remove <url>` | Unsubscribes from a feed and deletes its entries |
| `rivulet list` | Lists feeds; `--categories` lists categories, `--users` lists accounts |
| `rivulet import <file>` | Imports subscriptions from an OPML file |
| `rivulet export` | Writes the subscriptions as OPML to stdout, or to `--file` |
| `rivulet backup <destination>` | Writes a consistent copy of the database; refuses to overwrite unless `--force`; `--verify` checks the copy |
| `rivulet vacuum` | Rebuilds the database file to release free pages |

`--help` and `version` work without any configuration; every other command needs `DATABASE_URL`.
The full list of environment variables and a deployment walkthrough are in `docs/deploy.md`.

## Development

Requires Swift 6.x on Linux or macOS.

```sh
swift build
swift test
```

See `AGENTS.md` for the working agreement and `docs/README.md` for the rest of the documentation.

## License and attribution

Rivulet is an independent Swift implementation, inspired by and aiming for compatibility with
[Miniflux](https://github.com/miniflux/v2) — Copyright (c) Frédéric Guillot and contributors,
licensed under the Apache License 2.0. See [NOTICE](NOTICE) for details.

Rivulet itself is licensed under the Apache License, Version 2.0 — see [LICENSE](LICENSE).
