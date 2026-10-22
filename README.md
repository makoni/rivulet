# Rivulet

A lightweight, self-hosted feed reader — a Swift port of [Miniflux](https://github.com/miniflux/v2) (behavioral reference: v2.3.3).

> **Status:** early development. The foundation and the storage layer are in place:
> configuration, the SQLite storage wrapper with its pragmas, the CLI skeleton, `/healthz`,
> entry queries and FTS5 search, retention and maintenance (backup, vacuum, checkpoint on
> shutdown, startup integrity check). Feed fetching and the client APIs land with the next
> stages.

## What it will be

Rivulet aims to be a small, single-binary RSS/Atom reader for a personal server:

- **Feed aggregation** — scheduled fetching with conditional requests (ETag / Last-Modified), RSS / Atom / RDF / JSON Feed parsing, HTML sanitization.
- **SQLite storage** — a single database file in WAL mode with FTS5 full-text search. No external database service.
- **Client APIs** — Google Reader API and Fever API, so existing native clients keep working: NetNewsWire, lire, FeedFlow, Reeder Classic and friends.
- **CLI-first** — no web interface: `rivulet add`, `rivulet import feeds.opml`, `rivulet refresh`, `rivulet serve`.
- **Built with** — [Vapor 4](https://vapor.codes), [Fluent](https://docs.vapor.codes/fluent/overview/) + [SQLite](https://www.sqlite.org), [SwiftSoup](https://github.com/scinfu/SwiftSoup). The feed parser is planned on [FeedKit](https://github.com/nmdias/FeedKit) and is not part of the build yet.

## Commands

Rivulet is CLI-first. The commands that exist so far:

| Command | What it does |
| --- | --- |
| `rivulet serve` | Runs the HTTP server (`LISTEN_ADDR`); Vapor's server flags (`--hostname`, `--port`, `--bind`) work |
| `rivulet migrate` | Creates or updates the SQLite schema |
| `rivulet version` | Prints the version |
| `rivulet --help` | Lists all commands, including the planned ones |

The remaining commands are registered placeholders that report the stage implementing them:
`create-admin`, `add`, `remove`, `list`, `import`, `export`, `refresh`, `status`,
`integration-credentials`, `backup`, `vacuum`.

`--help` and `version` work without any configuration; `serve` and `migrate` need `DATABASE_URL`.

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
