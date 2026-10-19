# Rivulet

A lightweight, self-hosted feed reader — a Swift port of [Miniflux](https://github.com/miniflux/v2).

> **Status:** early development. The repository skeleton has just been laid down; nothing here is usable yet.

## What it will be

Rivulet aims to be a small, single-binary RSS/Atom reader for a personal server:

- **Feed aggregation** — scheduled fetching with conditional requests (ETag / Last-Modified), RSS / Atom / RDF / JSON Feed parsing, HTML sanitization.
- **SQLite storage** — a single database file in WAL mode with FTS5 full-text search. No external database service.
- **Client APIs** — Google Reader API and Fever API, so existing native clients keep working: NetNewsWire, lire, FeedFlow, Reeder Classic and friends.
- **CLI-first** — no web interface: `rivulet add`, `rivulet import feeds.opml`, `rivulet refresh`, `rivulet serve`.
- **Built with** — [Vapor 4](https://vapor.codes), [Fluent](https://docs.vapor.codes/fluent/overview/) + [SQLite](https://www.sqlite.org), [FeedKit](https://github.com/nmdias/FeedKit), [SwiftSoup](https://github.com/scinfu/SwiftSoup).

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
