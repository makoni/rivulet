# Rivulet

A lightweight, self-hosted feed reader — a Swift port of [Miniflux](https://github.com/miniflux/v2)
(behavioral reference: v2.3.3).

> **Status:** the MVP (stages 0–8) is done in code; the manual pre-release checks are in the
> release checklist (issue #130), and the rest of the 0.1.0 scope is tracked as issues.

Stage states as `docs/plan/README.md`'s table states them:

- Stage 0 - Foundation: done
- Stage 1 - Storage layer: done
- Stage 2 - Feed fetching: done
- Stage 3 - Parsing & sanitization: merged
- Stage 4 - Ingestion & scheduling: done
- Stage 5 - Client APIs & OPML: complete
- Stage 6 - CLI & operations: criteria met
- Stage 7 - Acceptance & hardening: done in code
- Stage 8 - Packaging & deployment: done in code
- Stage 9 - Post-MVP backlog: in progress
- Stage 10 - Miniflux REST v1 subset: in progress

## What it does

A small, single-binary RSS/Atom reader for a personal server:

- **Feed aggregation** — scheduled fetching with conditional requests (ETag / Last-Modified), RSS /
  Atom / RDF / JSON Feed parsing, HTML sanitization, feed icons.
- **SQLite storage** — one database file in WAL mode with FTS5 full-text search, backups and
  vacuum (the retention pass exists but is not scheduled yet, issue #131). No external database service.
- **Client APIs** — Google Reader API (`/accounts/ClientLogin`, `/reader/api/0`), Fever API
  (`/fever`) and the subset of the Miniflux REST v1 API (`/v1`) that Capy Reader uses, so existing
  native clients can connect. The acceptance clients are NetNewsWire, FeedFlow, NewsFlash, Reeder
  Classic and Capy Reader; `docs/clients.md` records what each one was checked against.
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
| `rivulet add <url>` | Subscribes to a feed; it is fetched on the next refresh (`--user` picks the account when there is more than one) |
| `rivulet remove <url>` | Unsubscribes from a feed and deletes its entries |
| `rivulet list` | Lists feeds; `--categories` lists categories, `--users` lists accounts |
| `rivulet import <file>` | Imports subscriptions from an OPML file |
| `rivulet export` | Writes the subscriptions as OPML to stdout, or to `--file` |
| `rivulet backup <destination>` | Writes a consistent copy of the database; refuses to overwrite unless `--force`; `--verify` checks the copy |
| `rivulet vacuum` | Rebuilds the database file to release free pages |

`--help` and `version` work without any configuration; every other command needs `DATABASE_URL`.

## Configuration

Configuration is read from environment variables. Only `DATABASE_URL` is required.

| Variable | Default | Meaning |
| --- | --- | --- |
| `DATABASE_URL` | — | Path of the SQLite database file |
| `LISTEN_ADDR` | `127.0.0.1:8080` | `host:port` the server listens on |
| `BASE_URL` | `http://localhost` | Public URL of the instance |
| `RUN_MIGRATIONS` | `true` | Apply the schema on startup |
| `LOG_LEVEL` | `info` | Log level |
| `LOG_FORMAT` | `text` | `text` or `json` |
| `POLLING_FREQUENCY` | `60` | Minutes between scheduler passes |
| `BATCH_SIZE` | `100` | Feeds refreshed per pass |
| `WORKER_POOL_SIZE` | `16` | Concurrent feed refreshes |
| `POLLING_PARSING_ERROR_LIMIT` | `3` | Errors after which a feed stops being polled (`0` = no limit) |
| `POLLING_LIMIT_PER_HOST` | `0` | Feeds from one host picked per batch (`0` = no limit) |
| `HTTP_CLIENT_TIMEOUT` | `20` | Fetch timeout, in seconds |
| `HTTP_CLIENT_MAX_BODY_SIZE` | `15` | Largest feed body, in MiB |
| `HTTP_CLIENT_USER_AGENT` | Rivulet's own | User-Agent sent with fetches |
| `HTTP_CLIENT_PROXY` | — | Proxy URL for fetches |
| `FETCHER_IGNORE_HTTP_CACHE` | `false` | Ignore ETag / Last-Modified for every feed |
| `FETCHER_ALLOW_PRIVATE_NETWORKS` | `false` | Allow fetching from private and loopback addresses |

`docs/deploy.md` walks through a deployment on a fresh server.

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
