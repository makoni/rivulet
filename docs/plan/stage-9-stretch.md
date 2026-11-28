# Stage 9 — Post-MVP backlog

**Goal:** the 0.1.0 scope. **Status:** in progress. **Depends on:** stages 0–8.

Each criterion is one issue, and each is closed by the run that shows it. The order below is the order
this file names them in, which is not the order the issue numbers run in.

## Closed

- Issue 98 — quoted-printable: a multipart part that declares the
  `Content-Transfer-Encoding: quoted-printable` transfer encoding is decoded as the MIME reader of
  the reference decodes it. The pins are in `FeverMultipartReadTests`.
- Issue 117 — the process harness read that tells a child exiting before writing its serve line from
  no event at all: the end of the stream is the exit event, so that read answers the status the
  harness recorded for the exit rather than no serve event. The pins are in `ServeProcessTests`.

## Group A — provable on this machine

1. Issue 99 — media proxy: the four config names the reference reads, and the rewrite the reference
   rewriter does for the shapes it answers. A fetch of a real media asset is a report item.
2. Issue 100 — search: the query operators read as data, the saved-search half as a schema read plus a
   command run.
3. Issue 101 — per-feed retention: the pick the retention pass takes per feed, recorded as a deviation,
   the reference having no per-feed rule.
4. Issue 102 — advanced feed discovery: the halves beyond the minimal `<link rel="alternate">` scan,
   read as the order the search tries, with the stub server answering the paths.
5. Issue 103 — OPML import by address: the fetch half and the read half, pinned as the calls the run
   makes through the fetcher seam.
6. Issue 104 — shared entries (`share_code`) and the tags beyond star, pinned as the handler branches
   and the storage reads they call.
7. Issue 105 — scraper rules as CSS selectors, as the reference applies them. The port reads
   `scraperRules` from OPML as a field today and applies nothing.
8. Issue 106 — adaptive scheduling: the intervals tuned from the observed update frequency, recorded as
   a deviation.

## Group B — delivery needs something outside this machine

9. Issue 107 — five integration providers, each pinned as the request it sends through a stub server,
    through the port fetcher so the private-network guard and the body cap apply. That a real service
    received the entry is a report item.
10. Issue 108 — OIDC auth: the rules the reference reads, pinned as pure logic plus the stub provider's
    answer. A real provider round trip is a report item.
11. Issue 109 — multi-user: the isolation the schema already carries, reaching the auth reads and the
    command surface.

## The rest

12. Issue 110 — the REST v1 subset and API keys, worked as stage 10. The calls the matrix has no row for
    stay open there, which is the phone half the stage-7 file keeps open.
13. Issue 111 — versioned migrations start here: the framework, and the first migration read as a run.
14. Issue 112 — the release deliverable: the tag `v0.1.0`, the static musl binary as a release asset, and
    `CHANGELOG.md`.
15. Issue 113 — the DocC site is not a deliverable here: `Scripts/build-docs.sh` writes the archive, and
    the person runs the script and publishes it outside the repository.
16. Issue 114 — the stage 8 criterion of a fresh server following `docs/deploy.md` is the last step,
    after this backlog is done.
17. Issue 115 — the two open stage-7 criteria are closed by the Capy Reader run against the reference
    clone here, run as a container, walking the login, the subscription list and the rename so a record
    line lands on `/v1`. The matrix row for that call is written from the record, and the rule that reads
    the halves gains the half it cannot read today.
18. Issue 116 — the process suite's flake, recorded as the runs showed it: the pin that failed is
    `ServeProcessTests.theWalIsEmptyAfterTheCleanSignalExit`, which failed with `.noServeEvent` once in a
    full local run and once on the build machine, and passed on a re-run each time. It is closed as the
    record; the half that could be pinned is issue 117, closed above, which is the answer that shape
    now gets.
