# Stage 8 — Packaging & deployment

**Goal:** one static binary on a VPS; dead-simple backups; published documentation.
**Status:** not started. **Effort:** S–M. **Depends on:** Stage 6.

## Scope

- [ ] **Spike first:** static musl build of the full dependency stack (the Swift Static Linux SDK
      is already installed; a hello-world static build was verified during planning — the risk is
      the whole Vapor + SQLite + FeedKit stack).
- [ ] Release build with the Swift Static Linux SDK, version stamping; `Scripts/build-release.sh`.
- [ ] Dockerfile (scratch-based) + docker-compose example + `.env.example`; systemd unit and
      install instructions for Ubuntu.
- [ ] `docs/deploy.md`: zero-to-running on a fresh VPS; upgrade procedure; time/NTP notes;
      durability notes (`synchronous=NORMAL` RPO); backup recipes (`VACUUM INTO` + optional
      Litestream, including free-space requirements) and restore procedure.
- [ ] Documentation publishing: generate DocC (API docs + tutorials) and publish, planned via
      GitHub Pages, wired into the release process.
- [ ] Release workflow on tag.

## Implementation notes

- If the static musl build proves impractical for the full stack, fall back to a distro-linked
  container binary and record the decision here.

## Tests

### Integration (smoke — required, not optional)

- The built binary in a clean container: `migrate` → `serve` → `/healthz` → `add` + `refresh`
  against the stub corpus → Google Reader responds.
- Restart mid-refresh: no corruption; scheduling resumes.
- Backup → restore → data equal.
- The runbook's exact commands from `docs/deploy.md` execute in the smoke job.

## Exit criteria

- [ ] A fresh VPS follows `docs/deploy.md` and ends with a working reader; the smoke job is green.
