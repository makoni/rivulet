#!/usr/bin/env bash
set -euo pipefail

# Stage 8's release build: the full dependency stack compiled for the static musl target with
# the Swift Static Linux SDK, and the artifact read after the build rather than the build log.
#
# What the guards read: that the toolchain is on PATH; that the SDK the run names is the one the
# toolchain has installed, read from its own list; that the installed bundle names its
# `swift-sdk.json` and that the triple the run names is one of the static targets that file
# declares; that the artifact is where the build leaves it for the triple's arch; that it is a
# statically linked executable, which is the whole point of the SDK, so the host build's
# dynamically linked binary is not what this run produces; that it runs, and that its answer is
# the version the committed source declares, so a binary printing another value is not the build
# this run made; and that the storage layer works inside it, read as the two answers it gives on
# a database the run builds for itself — the migration the schema file names, and the
# `status --json` contract read as the key names the source declares, each carrying 0 on a fresh
# database, with the feed list empty.
#
# What this run half cannot show: which branch the compiler takes for the two C reads the spike
# found, because on the glibc CI container only the glibc branch is in scope — the build itself is
# the check for the musl half, which is why the two shapes are named in production code rather
# than worked around here; that the binary runs on a machine without this toolchain, which is the
# clean-container smoke job stage 8 names; the size after stripping, reported as a measurement
# taken on this machine; that the top-level `feeds` key is the feed list rather than one of the
# counts — the answer carries both, and only the empty array names which is which; that the key
# order in the answer is not fixed, so the contract is read key by key rather than as one string;
# and that the row a migration created is the row a fetch would write, which the tests pin and
# this run cannot answer without a network.
#
# This run half is on demand and not in CI, so it is checked here by `bash -n` and by its 13
# checks, 12 of which name a value the run declares against the toolchain's own list, the installed
# bundle, or a committed file, each seen to fail here on such a value or by taking the file it names
# away. The 13th reads the machine, so it fails only on a machine without the toolchain. One craft
# reaches more than one check: the seeded database is what both the migration check and the status
# checks read, so it fires the migration check first and reaches the two status checks as well,
# which are seen on that same craft by reading its answer alone. `RIVULET_SKIP_BUILD=1` runs the
# checks against an artifact already on disk, which is what made each of them checkable without a
# rebuild.
#
# The two C reads the spike found are the reason production code names them once: `SOCK_STREAM` is
# the struct with a `rawValue` glibc exports and the plain `Int32` the musl module exports, and
# `EXIT_FAILURE` is a macro the importer exports on glibc and Darwin but not on musl.
#
# Usage: Scripts/build-release.sh                             # build and read the artifact
#        RIVULET_SWIFT_SDK=not-installed Scripts/build-release.sh  # the SDK guard
#        RIVULET_STATIC_TRIPLE=x86_64-unknown-linux-musl Scripts/build-release.sh
#                                                            # the triple guard
#        RIVULET_STATIC_TRIPLE=aarch64-swift-linux-musl RIVULET_SKIP_BUILD=1 \
#            RIVULET_BUILD_DIR=<a scratch path built for x86_64> Scripts/build-release.sh
#                                                            # the artifact-path guard
#        RIVULET_SKIP_BUILD=1 RIVULET_BUILD_DIR=<a path holding a dynamically
#            linked artifact> Scripts/build-release.sh        # the static-link guard
#        RIVULET_SKIP_BUILD=1 Scripts/build-release.sh       # the version guard, after the
#            source declares another version
#        RIVULET_SKIP_BUILD=1 Scripts/build-release.sh       # the migration guard, on a
#            database that already holds the migration
#        RIVULET_SKIP_BUILD=1 Scripts/build-release.sh       # the status guard, after a key
#            name in the source is renamed, or on a database that holds one feed row

SDK="${RIVULET_SWIFT_SDK:-swift-6.4.2-RELEASE_static-linux-0.1.0}"
TRIPLE="${RIVULET_STATIC_TRIPLE:-x86_64-swift-linux-musl}"
OUT="${RIVULET_BUILD_DIR:-.build/static}"
SDKS_PATH="${RIVULET_SWIFT_SDKS_PATH:-$HOME/.config/swiftpm/swift-sdks}"
SKIP_BUILD="${RIVULET_SKIP_BUILD:-0}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { printf 'guard failed: %s\n' "$1" >&2; exit 1; }

if ! command -v swift >/dev/null 2>&1; then
    fail "the run needs the Swift toolchain on PATH"
fi

# Guard: the SDK is the one the run names, read from the toolchain's own list of installed SDKs.
if ! swift sdk list | grep -qx "$SDK"; then
    fail "the run names an SDK that is not installed (${SDK})"
fi

# Guard: the triple is one the installed bundle declares for its static target. The first attempt
# named `x86_64-unknown-linux-musl`, which the bundle does not have, and the toolchain refused to
# resolve the SDK for it, so the run reads the bundle's own list of triples before building.
sdk_json="$SDKS_PATH/$SDK.artifactbundle/$SDK/swift-linux-musl/swift-sdk.json"
if [ ! -f "$sdk_json" ]; then
    fail "the installed bundle names no swift-sdk.json for ${SDK}"
fi
if ! grep -q "\"$TRIPLE\"" "$sdk_json"; then
    fail "the SDK declares no static target for the triple the run names (${TRIPLE})"
fi

if [ "$SKIP_BUILD" != "1" ]; then
    swift build -c release --swift-sdk "$SDK" --triple "$TRIPLE" --scratch-path "$OUT"
fi

BIN="$OUT/out/Products/Release-staticlinux-${TRIPLE%%-*}/rivulet"
if [ ! -x "$BIN" ]; then
    fail "the build did not leave the artifact the run reads (${BIN})"
fi

# Guard: the artifact is statically linked, read from the file type the tool reports for it.
if ! file "$BIN" | grep -q "statically linked"; then
    fail "the artifact is not a statically linked executable: $(file "$BIN")"
fi

# Guard: the artifact runs, and its answer is the version the committed source declares.
declared="$(sed -n 's/.*public static let version = "\([^"]*\)".*/\1/p' \
    "$REPO/Sources/RivuletCore/RivuletCore.swift" || true)"
if [ -z "$declared" ]; then
    fail "the run cannot read the version the source declares"
fi
answer="$("$BIN" version)"
if [ "$answer" != "rivulet ${declared}" ]; then
    fail "the artifact answers with ${answer}, not the version the source declares (${declared})"
fi

# Guard: the storage layer works inside the static binary. The migration name is the one the schema
# file names, and the run reads the answer on a database it builds for itself, so an earlier run's
# database — which applies 0 migrations — is the failure this guard names.
migration="$(sed -n 's/.*struct \(Schema[A-Za-z0-9]*\).*/\1/p' \
    "$REPO/Sources/RivuletCore/Storage/Migrations/SchemaV1.swift" || true)"
if [ -z "$migration" ]; then
    fail "the run cannot read the migration the schema file names"
fi
db="$OUT/smoke.db"
applied="$(DATABASE_URL="$db" "$BIN" migrate 2>/dev/null | tail -1)"
if [ "$applied" != "Applied 1 migration(s): ${migration}." ]; then
    fail "the static run did not apply the migration the schema names (${migration}): ${applied}"
fi

# Guard: the `status --json` contract, read as the key names the source declares. The five counts
# are read from the CodingKeys block of the `Totals` struct — the file has another CodingKeys block
# for the feed rows, which the contract names no count for — so a source naming a different key is
# the failure this guard names; the values are read as 0 on the fresh database the run built, so a
# database that holds a row is the other failure it names.
snapshot="$REPO/Sources/RivuletCore/Storage/StatusSnapshot.swift"
keys="$(awk '
    $0 ~ /struct Totals/ { totals = 1 }
    totals && /^    }/ { totals = 0; next }
    totals && match($0, /case [A-Za-z]+( = "[^"]+")?/) {
        s = substr($0, RSTART, RLENGTH)
        if (match(s, /"[^"]+"/)) { print substr(s, RSTART + 1, RLENGTH - 2) }
        else { print substr(s, 6) }
    }
' "$snapshot" || true)"
if [ -z "$keys" ]; then
    fail "the run cannot read the contract's key names from the source"
fi
json="$(DATABASE_URL="$db" "$BIN" status --json)"
for name in $keys; do
    if ! printf '%s' "$json" | grep -q "\"${name}\":0"; then
        fail "the status answer carries no ${name} with 0, which the contract the soak reads names"
    fi
done
if ! printf '%s' "$json" | grep -q '"feeds":\[\]'; then
    fail "the status answer does not carry the feed list as an empty array on a fresh database"
fi

printf 'static build: %s (%s bytes, %s)\n' "$BIN" "$(stat -c %s "$BIN")" "$(file -b "$BIN")"
