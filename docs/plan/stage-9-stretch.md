# Stage 9 — Post-MVP backlog

Not scheduled, not estimated. Pick from here after the MVP is deployed and stable.
When an item is scheduled, split it into a proper stage plan with scope, tests and exit criteria.

- **Integrations**: webhook, ntfy, Apprise, Pushover, Telegram Bot (the reference has no Gotify).
- **Media proxy**: `MEDIA_PROXY_MODE` (default `http-only`), `MEDIA_PROXY_CUSTOM_URL`,
  `MEDIA_PROXY_RESOURCE_TYPES`, private-key mode.
- **XPath scraper rules**: per-feed custom extraction for broken feeds.
- **Advanced feed discovery**: beyond the minimal `<link rel="alternate">` scan used by
  `quickadd` (e.g., common feed paths).
- **OPML import from URL**; scheduled OPML sync.
- **REST v1 subset** and API keys (`X-Auth-Token`) — only if a real consumer appears.
- **OIDC auth**; **multi-user** (per-user data isolation is already designed into the schema).
- **Search improvements**: query operators, saved searches.
- **Adaptive scheduling**: tune intervals from observed feed update frequency (an explicit
  deviation from the reference).
- **More Google Reader features**: shared entries (`share_code`), tags beyond star.
- **Per-feed retention policies** (extension; the reference uses global settings only).
