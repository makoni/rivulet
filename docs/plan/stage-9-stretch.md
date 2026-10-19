# Stage 9 — Post-MVP backlog

Not scheduled, not estimated. Pick from here after the MVP is deployed and stable.
When an item is scheduled, split it into a proper stage plan with scope, tests and exit criteria.

- **Integrations**: webhook, ntfy, Gotify, Telegram (port a subset of
  `miniflux/internal/integration`).
- **Media proxy**: route entry media through Rivulet (`MEDIA_PROXY` semantics).
- **XPath scraper rules**: per-feed custom extraction for broken feeds.
- **Feed discovery**: given a website URL, find its feed (`<link rel="alternate">`) — improves
  the `add` UX.
- **OPML import from URL**; scheduled OPML sync.
- **REST v1 subset**: endpoints powering Miniflux's own apps where they matter
  (saved entries, etc.).
- **OIDC auth**; **multi-user** (per-user data isolation is already designed into the schema).
- **Search improvements**: query operators, saved searches.
- **Adaptive scheduling**: tune intervals from observed feed update frequency.
- **More Google Reader features**: shared items, tags beyond star, etc.
