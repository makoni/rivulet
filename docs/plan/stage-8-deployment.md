# Stage 8 — Packaging & deployment

**Goal:** one static binary on a VPS; dead-simple backups; published documentation. **Status:** in
progress — seven slices are merged: the static-build spike (PR #67), the version value as a client
reads it (PR #68), the clean-container smoke job (PR #69), whose run half is `Scripts/smoke.sh` and
whose check half is `Tools/smoke/smoke_check.py`, reading the document run leaves behind rather than
the container it ran, the runbook `docs/deploy.md` with the rule that reads it as data (PR #70),
which sits in `Tools/smoke/runbook.py` because the check half is at the size cap the project sets,
the three deploy artifacts read as data (PR #72): `Scripts/deploy.sh` is its run half,
`Tools/deploy/deploy_check.py` its check half over 16 rules, `Tools/deploy/parsers.py` the reads,
and `Tools/deploy/probes.py` the 22 cases that show each rule can fail on the rule it names, the
documentation layer read as data over 21 rules in `Tools/docs/docs_check.py` (PR #73) with
`Scripts/docs.sh` as its run half and `Tools/docs/probes.py` as its round — the catalog being the
pages a site is built from, published outside this repository, the Pages publish half dropped as
PR #74 so no CI job here publishes it — and the build half `Scripts/build-docs.sh` (PR #75), which
writes the archive that site is built from outside the repository. **Effort:** S–M.
**Depends on:** Stage 6.

## Scope

- [x] **Spike first:** static musl build of the full dependency stack (the Swift Static Linux SDK is
already installed; a hello-world static build was verified during planning — the risk is the whole
Vapor + SQLite + FeedKit stack). Green: the whole stack compiles and links statically, the artifact
runs, and the result and the decision are recorded below. The stack this port builds is SwiftSoup
rather than FeedKit, which this line named before the parser adapters landed.
- [x] Release build with the Swift Static Linux SDK, version stamping; `Scripts/build-release.sh`.
The script landed with the spike: the build and the checks that read the artifact. The version half
landed as far as the port can have it: the value is the committed constant, the run half reads the
artifact's answer against that constant, and the pin reads the digits a client converts as a
positive integer, which is the rule the reference's own test asserts and which this port's value
failed on. What the build cannot stamp is recorded as unported in `docs/parity.md`: SwiftPM carries
no VCS build info, and Swift's compiler flag carries a name rather than a value while the
reference's value comes from a linker flag, so there is no commit or build-date half here to pin.
- [x] **Dockerfile (scratch-based):** landed with the smoke job (PR #69) — `FROM scratch`, one
`COPY` of the static artifact, no toolchain and no libc, so the run that starts the image shows that
the artifact does not depend on the machine that built it. The `FROM` and `COPY` lines are read as
data by the smoke check half, and the `ENTRYPOINT` line is read by the deploy check half as the
program it names against the file the `COPY` line writes, which is the half that shows the
entrypoint carries no subcommand of its own.
- [x] **The compose example, `.env.example` and the systemd unit:** landed with PR #72 as
`deploy/compose.yml`, `.env.example` and `deploy/rivulet.service`, read as data by
`Tools/deploy/deploy_check.py` over 16 rules. The compose is read as the key set the tool resolves
it as, the unit as the sections it puts its keys in, and the example as one name-and-value pair per
line; the two unit keys that are structure rather than a value the port reads are named as not read.
The env file the deployment reads is the gitignored name, so the committed example carries
placeholders only.
- [x] `docs/deploy.md`: zero-to-running on a fresh VPS; upgrade procedure; time/NTP notes;
durability notes (`synchronous=NORMAL` RPO); backup recipes (`VACUUM INTO` + optional Litestream,
including free-space requirements) and restore procedure. Landed with this slice: the page calls
only commands the dispatch registers, only flags those signatures declare and only names the config
reads, so the command surface the stage-6 criterion reads is the same set the page calls; Litestream
is named as a tool outside the port, with no command of the port running it, and the page names what
it cannot show as its own section.
- [ ] Documentation publishing: `Scripts/build-docs.sh` writes the archive the site is built from,
and the site itself is outside this repository and is published by hand, so no CI job here shows a
served site; the symbol pages stay open because this toolchain answers no plugin for the symbol
graph the tool reads.
- [ ] Release workflow on tag.

## Spike result

The Static Linux SDK builds the whole stack, so the distro-linked fallback named below is
not needed.

- The SDK `swift-6.4.2-RELEASE_static-linux-0.1.0` is installed as an artifact bundle under
`~/.config/swiftpm/swift-sdks/`. Its toolset adds `-static-executable -static-stdlib`, and its
`swift-sdk.json` declares two static targets: `x86_64-swift-linux-musl` and
`aarch64-swift-linux-musl`. Those are the canonical names the run declares: a triple outside that
list — the first attempt used `x86_64-unknown-linux-musl` — is not resolved against the SDK at all,
so the toolchain answers "No Swift SDK found matching query" rather than building for it.

- The full dependency stack compiles and links for that target: Vapor, Fluent and the SQLite driver,
AsyncHTTPClient, NIO with BoringSSL, SwiftSoup, console-kit, swift-log, swift-crypto and the
approved PNG and JPEG packages. The artifact is `out/Products/Release-staticlinux-x86_64/rivulet`,
and `file` reports it as statically linked. It runs on this glibc host: `version`, `--help`,
`migrate` applying `SchemaV1`, and `status --json` answering the contract the soak reads.

- Two sites in this port's own code read a C value the way glibc exports it, and they are the only
two the musl target refused: `SOCK_STREAM`, which glibc exports as a struct with a `rawValue` and
the musl C module exports as the plain `Int32`, and `EXIT_FAILURE`, a macro the importer exports on
glibc and Darwin but not on musl. Both are named once in production code, in
`Sources/RivuletCore/Reader/SystemAddressResolver.swift` and in `Sources/rivulet/main.swift`, with
the two shapes separated by which C module the platform has, and the exit code is the number both
platforms read, 1. No pin can show the musl branch, because on the glibc CI container only the glibc
branch is in scope for the compiler, so the static build itself is the check for the musl half; the
glibc half is pinned by `AddressResolutionTests` through the resolver it runs, which reads the
answer the lookup produces, so the pin can fail on a value that breaks the lookup rather than on
which socket type the value is, and the exit-code site has no pin at all because the top level of
the executable is not something a test can read. The other C reads this port has — `SIGINT`,
`SIGTERM`, `EILSEQ`, `EINVAL` — built for the musl target unchanged.

- Sizes measured here, as measurements rather than as bounds: the static artifact is 287,748,480
bytes unstripped and 88,570,920 stripped. The glibc release build of the same head is 146,076,544
unstripped and 33,157,728 stripped, so the static artifact is the larger one: the runtime and these
C libraries are inside the file rather than resolved at run time.

- What the spike does not cover: the clean-container smoke job, which is the next slice, because
running the artifact on a machine without this toolchain is what that job shows. The version half
the stage names landed after the spike, as the pin and the parity row above record; the stamping
half cannot land as the reference has it, and is recorded as unported.

## Implementation notes

- If the static musl build proves impractical for the full stack, fall back to a distro-linked
container binary and record the decision here. Not taken: the spike's result above is that the SDK
is usable for the whole stack, so this line stays as the record of what was decided instead.

## Tests

### Integration (smoke — required, not optional)

- The built binary in a clean container: `migrate` → `serve` → `/healthz` → `add` + `refresh`
against the stub corpus → Google Reader responds. Read by the smoke job (PR #69), with the pass over
the corpus being the cadence loop's own round rather than the `refresh` command the plan names,
which `RefreshCommandTests` pins as a run; the smoke run calls no `refresh` itself, so the rule
reads the round the loop made.
- Restart mid-refresh: no corruption; scheduling resumes. Read, apart from the WAL half, which the
checkpoint the process harness reads as empty cannot answer here because the write transaction the
stop interrupted blocks it.
- Backup → restore → data equal. Read as the copy against the source, and the copy as the file the
run wrote with nothing beside it; the restore half is not read, because restore is a recipe the
runbook names.
- The runbook's exact commands from `docs/deploy.md` execute in the smoke job. Read as the commands
its fenced lines call, against the case the dispatch registers, the flag names each command's
signature declares, the names the config reads, the durability value against the pragma the storage
wrapper runs and the factor the free-space check uses, and the order the page names its steps in
read as the first records the run kept of them. What the rule cannot show is that the steps ran on a
machine that is not the one that wrote the page, which is the criterion below, and what a stream of
the tool the page names as outside the port would hold.
- The three deploy artifacts as data, read by `Tools/deploy/deploy_check.py` over 16 rules and shown
to fail on the rule each names by 22 cases in `Tools/deploy/probes.py` (PR #72). The run half is
`Scripts/deploy.sh`, checked by `bash -n` and by its eight guards, fourteen read sites, eleven of
which were seen to fail on the value they name. Nothing here runs a container or a service, so the
twelve report items in `docs/deploy.md` name what the harness cannot show, and the run is on demand
rather than in CI because the CI container has neither Docker nor systemd.

### The documentation layer (DocC — the pages the harness reads as data)

- The catalog `Sources/RivuletCore/RivuletCore.docc/` — the table of contents, four concept articles
and one tutorial and the asset the table of contents names — is read as data by 21 rules in
`Tools/docs/docs_check.py`, with `Scripts/docs.sh` as the run half (eight guards, thirteen read
sites, all eight seen to fail here on the values the usage lines name) and `Tools/docs/probes.py`
crafting 31 cases over the 21 rules: 30 crafts plus the baseline asserted to report nothing, no
craft reaching more than one rule, and every craft changing the parsed form rather than a file. The
pages state only what a check here can show — the commands the dispatch registers, the flags the
signatures declare, the names the config reads, the values the sources write, the routes the port
registers, the clients the client matrix records and the version the plan pins — so a page naming
something the sources do not write is a finding. The seventeen report items in `docs/docc.md` name
the shapes no rule compares and what no rule can show, including the symbol pages, which the build
half writes from the file SwiftPM's own subcommand answers for its own run and which no rule reads
as the pages it writes. The 21 public declarations that had no documentation comment are read by the
same rule, through the comment attached to a declaration over its attribute lines, and are now
filled.
- The build half `Scripts/build-docs.sh` is checked by `bash -n` and by its nine guards, thirteen
- read sites, each seen to fail here on the value its usage line names: the archive path, the
- catalog path, the tool, SwiftPM, the base, the names the markdown manifest carries, the copy
- against the file SwiftPM wrote, the module the copy names against the target the manifest writes,
- and the link each page the build wrote carries. It writes the archive a site is built from outside
- the repository, the graph being the copy of the one file for the target the manifest writes, and
- the link stays hidden for a page the build has no markdown file for, which here is the page the
- site opens first. The round is what CI runs for this harness, in the probe-rounds job on the
- runner host, because the Swift container has no `python3`. Publishing the pages as a site happens
- outside this repository, so no CI job here shows a served site, and no rule here reads what a web
- server answers. The run half and the build half both need the tool, so they stay on demand.

## Exit criteria

- [ ] A fresh VPS follows `docs/deploy.md` and ends with a working reader; the smoke job is green.

## Backlog (style findings on the build half, from its review)

- `add_markdown_link` is 59 lines, above the ~40-line aim, because the link half is one script
  block rather than a function the way the other halves are.
- The comment references in the sources are read by no rule, because a rule would have to resolve
- them the way the tool does; the four the tool reported as findings for a build that reads the
- graph are fixed at the sites they name, and the tool answered nothing for the build run here.
- The manifest guard has nothing to compare when the tool writes no manifest at all, so it can fail
  only on a name it is given.
- The markdown href is relative to the directory of the page, so a page served at a url with no
  trailing slash resolves it one level short.
