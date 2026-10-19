# Stage 8 — Packaging & deployment

**Goal:** one static binary on a VPS; dead-simple backups.
**Status:** not started. **Effort:** S. **Depends on:** Stage 6.

## Scope

- [ ] Release build with the Swift Static Linux SDK (musl), version stamping;
      `Scripts/build-release.sh`.
- [ ] Dockerfile (scratch-based) + docker-compose example + `.env.example`.
- [ ] systemd unit and install instructions for Ubuntu.
- [ ] Backup recipes: `VACUUM INTO` plus optional Litestream; documented restore procedure.
- [ ] `docs/deploy.md`: zero-to-running on a fresh VPS; upgrade procedure.
- [ ] Optional: GitHub release workflow on tag.

## Tests

### Integration (smoke)

- The built static binary in a clean container: `migrate` → `serve` → `/healthz` → `add` +
  `refresh` against the stub corpus → Google Reader responds.
- Restart mid-refresh: no corruption; scheduling resumes.
- Backup → restore → data equal.

## Exit criteria

- [ ] A fresh VPS follows `docs/deploy.md` and ends with a working reader; optional CI smoke job
      green.
