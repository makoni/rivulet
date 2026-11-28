# Stage 8 — Packaging & deployment

**Goal:** one static binary on a VPS; dead-simple backups; published documentation.
**Status:** done in code; running the binary on another machine and following the runbook on a fresh
server are in the release checklist (issue 130). **Effort:** S–M. **Depends on:** stage 6.

## What this stage delivered

- `Scripts/build-release.sh`: the static musl build with the Swift Static Linux SDK, checked by
  running the artifact (statically linked, version, `migrate`, `status --json`). CI cannot build it,
  because the SDK has no download URL a workflow can use; `.github/workflows/release.yml` publishes
  the glibc build for a tag.
- The runbook `docs/deploy.md`, the backup guide `docs/backup-restore.md`, and the deployment examples
  `Dockerfile`, `deploy/compose.yml`, `deploy/rivulet.service` and `.env.example`.
- The DocC catalog in `Sources/RivuletCore/RivuletCore.docc` and `Scripts/build-docs.sh`, which builds
  the archive for static hosting; the site is published by hand outside this repository.
  `DocumentationConsistencyTests` keeps the catalog, the README and the runbook in step with the CLI
  and the configuration.
