# Stage 9 — Post-MVP backlog

**Goal:** the 0.1.0 scope. **Status:** in progress. **Depends on:** stages 0–8.

Each item is one issue. The order below is the suggested order of work.

## Done

- Issue 98 — a multipart part declaring `Content-Transfer-Encoding: quoted-printable` is decoded as
  Go's MIME reader decodes it (`FeverMultipartReadTests`).
- Issue 110 — the Miniflux REST v1 subset and API keys, worked as stage 10.
- Issue 117 — the process test harness reports a child that exits before it starts serving as that
  exit, not as "no serve event" (`ServeProcessTests`).

## Features that can be finished and tested locally

1. Issue 99 — media proxy: the four configuration variables Miniflux reads, and the URL rewrite.
2. Issue 100 — search: query operators, and saved searches.
3. Issue 101 — per-feed retention policies (a deliberate addition; Miniflux has none).
4. Issue 102 — feed discovery beyond the `<link rel="alternate">` scan.
5. Issue 103 — OPML import from a URL.
6. Issue 104 — Google Reader shared entries (`share_code`) and tags beyond star.
7. Issue 105 — scraper rules as CSS selectors; today `scraperRules` is read from OPML and not applied.
8. Issue 106 — adaptive scheduling from the observed update frequency.
9. Issue 125 — the multipart header-line read reports only a missing colon; Go also rejects a colon at
   position 0 and a line of two bytes or fewer.

## Features whose final check needs an outside service

The behaviour is tested against stub servers; a round trip with the real service is a manual check.

10. Issue 107 — five integration providers.
11. Issue 108 — OIDC authentication.
12. Issue 109 — multi-user: the per-user isolation the schema already has, through the auth reads and
    the commands.

## Release

13. Issue 121 — the four Capy Reader REST v1 calls without a route yet (see stage 10).
14. Issue 111 — versioned migrations, starting with the first release.
15. Issue 112 — the 0.1.0 release: tag, static binary as a release asset, `CHANGELOG.md`.
16. Issue 130 — the release checklist: the manual client, build and deployment checks.
