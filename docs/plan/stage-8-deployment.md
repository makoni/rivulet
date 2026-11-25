# Stage 8 — Packaging & deployment

**Goal:** one static binary on a VPS; dead-simple backups; published documentation.
**Status:** in progress. **Effort:** S–M. **Depends on:** stage 6.

## Open criterion

- [ ] Issue 97 — a fresh server follows `docs/deploy.md` and ends with a working reader; the smoke job
      is green. This is the last step of the plan, and it needs a real server, so it is the person half.

## What the runs showed

The static build is closed as what the run showed here: the whole stack links statically and the artifact
runs on this host. The release script, the container file, the compose example, the `.env.example`, the
service unit, the runbook, the build half `Scripts/build-docs.sh` and the DocC catalog are closed as what
the rules read as data. That the artifact was not run on another machine, that no image was built or
started and that no unit was run is named as a report item in `docs/deploy.md`, so no run here shows it.
The site itself is outside this repository: the script writes the archive, and the person runs the script
and publishes it, so no job here shows a served site.

The record lives in the documents the halves read as data: `docs/deploy.md`, `docs/docc.md`,
`docs/testing.md`, and in the artifacts `deploy/compose.yml` and `deploy/rivulet.service`. The run
halves are `Scripts/smoke.sh`, `Scripts/deploy.sh`, `Scripts/docs.sh` and `Scripts/build-docs.sh`; the
check halves are `Tools/smoke/`, `Tools/deploy/` and `Tools/docs/`.

## Style findings left open

- `add_markdown_link` in `Scripts/build-docs.sh` is 83 lines, above the aim of about 40, because the
  link half is one script block rather than a function.
- The comment references in the sources are read by no rule, because a rule would have to resolve them
  the way the tool does.
