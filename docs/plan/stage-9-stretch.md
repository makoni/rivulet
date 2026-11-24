# Stage 9 — Post-MVP backlog

**Goal:** the whole backlog is in the first release, 0.1.0. **Status:** scheduled.
**Depends on:** Stage 8.

## Order

Group A — items that need nothing outside this machine to prove:

1. Quoted-printable part decoding
2. Media proxy
3. Search improvements
4. Per-feed retention policies
5. Advanced feed discovery
6. OPML import from URL
7. More Google Reader features
8. Scraper rules, as CSS selectors
9. Adaptive scheduling

Group B — items whose delivery needs something outside this machine:

10. Integrations — five providers
11. OIDC auth
12. Multi-user

The item the plan's non-goals named as a subset appearing later on demand is worked as stage 10,
ahead of this order: the REST v1 subset and API keys (`X-Auth-Token`), the subset Capy Reader's
`minifluxclient` declares. Its pins run on this machine; the calls the matrix has no row for stay
open there, and the walk that named the calls was made on the phone.

## Exit criteria

- [ ] Quoted-printable: a multipart part that declares the
      `Content-Transfer-Encoding: quoted-printable` transfer encoding is decoded as Go's MIME reader
      decodes it. Today the port has no such rule; it is named in `FeverMultipartRead.swift` and in
      `docs/parity.md`. The rule is read as data by a probe seen to fail on it.
- [ ] Media proxy: the four config names the reference reads — `MEDIA_PROXY_MODE` with its
      default `http-only`, `MEDIA_PROXY_CUSTOM_URL`, `MEDIA_PROXY_RESOURCE_TYPES`, and the
      private-key mode — are read as data, and the rewrite the reference's rewriter does is
      pinned for the shapes it answers. What no pin can show is a fetch of a real media asset
      from a real provider.
- [ ] Search improvements: the query operators are read as data, and the saved-search half is a
      schema read plus a command run.
- [ ] Per-feed retention policies: the extension over the reference's global settings, read as
      the pick the retention pass takes per feed. The reference has no per-feed rule, so this
      half is the port's own and is recorded as a deviation.
- [ ] Advanced feed discovery: the halves beyond the minimal `<link rel="alternate">` scan that
      `quickadd` uses, read as the order the search tries, with the stub server answering the
      paths.
- [ ] OPML import from URL: the fetch half and the read half, pinned as the calls the run makes
      through the fetcher seam.
- [ ] More Google Reader features: shared entries (`share_code`) and the tags beyond star,
      pinned as the handler branches and the storage reads they call.
- [ ] Scraper rules: CSS selectors, as the reference applies them through goquery. The port
      reads `scraperRules` from OPML as a field today and applies nothing; the criterion is that
      the rules reach the parse. XPath is not what the reference has, so no new dependency is
      needed.
- [ ] Adaptive scheduling: the intervals tuned from the observed feed update frequency, read as
      the decision the scheduler answers. This is an explicit deviation from the reference and is
      recorded in `docs/parity.md`.
- [ ] Integrations — five providers: webhook, ntfy, Apprise, Pushover, Telegram Bot. The settings
      are the reference's `integrations` table keyed by `user_id`, with one `*_enabled` flag per
      provider, so the parity row that says the flag is not ported closes here. The settings are
      set by extending `integration-credentials`, which is the port's own console path for the
      rules the reference's web form reads. Both trigger points are ported: `PushEntries` for the
      new entries a refresh leaves, and `SendEntry` for a saved entry, which the reference reaches
      from its web UI, its REST API, the Fever `mark` branch and the Google Reader `edit-tag` star
      branch. Every provider goes through the port's fetcher, as every reference integration
      client goes through `internal/http/client`, so the SSRF guard and the body cap apply. Each
      client is pinned as the request it sends through a stub server — the method, the path, the
      body shape, the names it writes, the secret, and the flag that decides whether the provider
      is called at all. That a real third-party service received the entry is a report item.
- [ ] OIDC auth: the rules the reference reads, pinned as pure logic plus the stub provider's
      answer. A real provider round trip is a report item.
- [ ] Multi-user: per-user data isolation, which the schema already carries, reaches the auth
      reads and the command surface.
- [ ] REST v1 subset and API keys: worked as stage 10, whose file carries the criteria for the calls
      the consumer declares and records three merged slices. The calls the matrix has no row for stay
      open there, which is the phone half the stage-7 file keeps open.

## Release criteria

- [ ] Versioned migrations start here: the framework, and the first migration read as a run.
- [ ] The release deliverable is the tag `v0.1.0`, the static musl binary as a release asset, and
      `CHANGELOG.md`.
- [ ] The DocC site is not a release deliverable here: `Scripts/build-docs.sh` writes the archive,
      and the person runs the script and publishes it outside the repository.
- [ ] Stage 8's criterion of a fresh VPS following `docs/deploy.md` is the last step, after the
      backlog is done.

## Closed by a run outside this machine

- [ ] The two open stage-7 criteria — the client acceptance matrix
      (`docs/plan/stage-7-acceptance.md`) and the manual client matrix — are closed by the Capy
      Reader run against the reference clone here, run as a container, walking the login, the
      subscription list and the rename so a record line lands on `/v1`. The matrix row for that
      call is written from the record, and the rule that reads the halves gains the half it cannot
      read today.
- [ ] The process suite's flake, recorded as the runs showed it: the pin that failed is
      `ServeProcessTests.theWalIsEmptyAfterTheCleanSignalExit`, not
      `theBuiltBinaryAnswersOnTheProbedPort` as this file named it. It failed with `.noServeEvent`
      once in a full local run and once on CI, on PR #90, and passed on a re-run each time. The
      harness answers a line read after the child's output closed as an empty line, and the
      serve-event read turns an empty line into `.noServeEvent`, so a child that exits before writing
      its serve line is reported as no event rather than as the exit it reached. The condition this
      file set — nothing written about it until it repeats — is met.
