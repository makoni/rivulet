# Stage 8 — Packaging & deployment

**Goal:** one static binary on a VPS; dead-simple backups; published documentation.
**Status:** in progress — the static-build spike landed; the rest is not started. **Effort:** S–M.
**Depends on:** Stage 6.

## Scope

- [x] **Spike first:** static musl build of the full dependency stack (the Swift Static Linux SDK
      is already installed; a hello-world static build was verified during planning — the risk is
      the whole Vapor + SQLite + FeedKit stack). Green: the whole stack compiles and links
      statically, the artifact runs, and the result and the decision are recorded below. The stack
      this port builds is SwiftSoup rather than FeedKit, which this line named before the parser
      adapters landed.
- [ ] Release build with the Swift Static Linux SDK, version stamping; `Scripts/build-release.sh`.
      The script landed with the spike: the build and the checks that read the artifact. Version
      stamping is the half still open, so the run half reads the version the committed source
      declares against the artifact's answer.
- [ ] Dockerfile (scratch-based) + docker-compose example + `.env.example`; systemd unit and
      install instructions for Ubuntu.
- [ ] `docs/deploy.md`: zero-to-running on a fresh VPS; upgrade procedure; time/NTP notes;
      durability notes (`synchronous=NORMAL` RPO); backup recipes (`VACUUM INTO` + optional
      Litestream, including free-space requirements) and restore procedure.
- [ ] Documentation publishing: generate DocC (API docs + tutorials) and publish, planned via
      GitHub Pages, wired into the release process.
- [ ] Release workflow on tag.

## Spike result

The Static Linux SDK builds the whole stack, so the distro-linked fallback named below is not
needed.

- The SDK `swift-6.4.2-RELEASE_static-linux-0.1.0` is installed as an artifact bundle under
  `~/.config/swiftpm/swift-sdks/`. Its toolset adds `-static-executable -static-stdlib`, and its
  `swift-sdk.json` declares two static targets: `x86_64-swift-linux-musl` and
  `aarch64-swift-linux-musl`. Those are the canonical names the run declares: a triple outside
  that list — the first attempt used `x86_64-unknown-linux-musl` — is not resolved against the SDK
  at all, so the toolchain answers "No Swift SDK found matching query" rather than building for it.

- The full dependency stack compiles and links for that target: Vapor, Fluent and the SQLite
  driver, AsyncHTTPClient, NIO with BoringSSL, SwiftSoup, console-kit, swift-log, swift-crypto and
  the approved PNG and JPEG packages. The artifact is
  `out/Products/Release-staticlinux-x86_64/rivulet`, and `file` reports it as statically linked. It
  runs on this glibc host: `version`, `--help`, `migrate` applying `SchemaV1`, and `status --json`
  answering the contract the soak reads.

- Two sites in this port's own code read a C value the way glibc exports it, and they are the only
  two the musl target refused: `SOCK_STREAM`, which glibc exports as a struct with a `rawValue` and
  the musl C module exports as the plain `Int32`, and `EXIT_FAILURE`, a macro the importer exports
  on glibc and Darwin but not on musl. Both are named once in production code, in
  `Sources/RivuletCore/Reader/SystemAddressResolver.swift` and in `Sources/rivulet/main.swift`, with
  the two shapes separated by which C module the platform has, and the exit code is the number both
  platforms read, 1. No pin can show the musl branch, because on the glibc CI container only the
  glibc branch is in scope for the compiler, so the static build itself is the check for the musl
  half; the glibc half is pinned by `AddressResolutionTests` through the resolver it runs. The other
  C reads this port has — `SIGINT`, `SIGTERM`, `EILSEQ`, `EINVAL` — built for the musl target
  unchanged.

- Sizes measured here, as measurements rather than as bounds: the static artifact is 287,748,480
  bytes unstripped and 88,570,920 stripped. The glibc release build of the same head is 146,076,544
  unstripped and 33,157,728 stripped, so the static artifact is the larger one: the runtime and
  these C libraries are inside the file rather than resolved at run time.

- What the spike does not cover: version stamping, which the stage names as part of the release
  build and which this slice does not implement, and the clean-container smoke job, which is the
  next slice, because running the artifact on a machine without this toolchain is what that job
  shows.

## Implementation notes

- If the static musl build proves impractical for the full stack, fall back to a distro-linked
  container binary and record the decision here. Not taken: the spike's result above is that the
  SDK is usable for the whole stack, so this line stays as the record of what was decided instead.

## Tests

### Integration (smoke — required, not optional)

- The built binary in a clean container: `migrate` → `serve` → `/healthz` → `add` + `refresh`
  against the stub corpus → Google Reader responds.
- Restart mid-refresh: no corruption; scheduling resumes.
- Backup → restore → data equal.
- The runbook's exact commands from `docs/deploy.md` execute in the smoke job.

## Exit criteria

- [ ] A fresh VPS follows `docs/deploy.md` and ends with a working reader; the smoke job is green.
