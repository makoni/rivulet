#!/usr/bin/env bash
set -euo pipefail

# Release build: the statically linked musl binary, built with the Swift Static Linux SDK, then
# checked by running it. CI cannot build it (the SDK has no download URL a workflow can use), so
# this runs by hand on a machine with the SDK installed.
#
# Checks: the SDK is installed and declares the triple; the artifact is a statically linked
# executable; `rivulet version` prints the version the source declares; `migrate` and
# `status --json` work on a fresh database inside the static binary.
#
# Environment (optional):
#   RIVULET_SWIFT_SDK      SDK name (default below)
#   RIVULET_STATIC_TRIPLE  target triple (default x86_64-swift-linux-musl)
#   RIVULET_BUILD_DIR      scratch path (default .build/static)
#   RIVULET_SKIP_BUILD=1   check an artifact already on disk without rebuilding
#
# Usage: Scripts/build-release.sh

SDK="${RIVULET_SWIFT_SDK:-swift-6.4.2-RELEASE_static-linux-0.1.0}"
TRIPLE="${RIVULET_STATIC_TRIPLE:-x86_64-swift-linux-musl}"
OUT="${RIVULET_BUILD_DIR:-.build/static}"
SDKS_PATH="${RIVULET_SWIFT_SDKS_PATH:-$HOME/.config/swiftpm/swift-sdks}"
SKIP_BUILD="${RIVULET_SKIP_BUILD:-0}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { printf 'check failed: %s\n' "$1" >&2; exit 1; }

cd "$REPO"

if ! command -v swift >/dev/null 2>&1; then
    fail "the run needs the Swift toolchain on PATH"
fi

# Check: the SDK is installed.
if ! swift sdk list | grep -qx "$SDK"; then
    fail "the run names an SDK that is not installed (${SDK})"
fi

# Check: the triple is one the installed bundle declares for its static target (the SDK names it
# `x86_64-swift-linux-musl`, not `x86_64-unknown-linux-musl`).
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

# Check: the artifact is statically linked.
if ! file "$BIN" | grep -q "statically linked"; then
    fail "the artifact is not a statically linked executable: $(file "$BIN")"
fi

# Check: the artifact runs and prints the version the source declares.
declared="$(sed -n 's/.*public static let version = "\([^"]*\)".*/\1/p' \
    "$REPO/Sources/RivuletCore/RivuletCore.swift" || true)"
if [ -z "$declared" ]; then
    fail "the run cannot read the version the source declares"
fi
answer="$("$BIN" version)"
if [ "$answer" != "rivulet ${declared}" ]; then
    fail "the artifact answers with ${answer}, not the version the source declares (${declared})"
fi

# Check: the storage layer works inside the static binary, on a database built for this run.
db="$(mktemp -d)/release-check.db"
applied="$(DATABASE_URL="$db" "$BIN" migrate 2>/dev/null | tail -1)"
case "$applied" in
    "Applied "*) ;;
    *) fail "the static binary did not apply the schema: ${applied}" ;;
esac
json="$(DATABASE_URL="$db" "$BIN" status --json)"
if ! printf '%s' "$json" | grep -q '"feeds":\[\]'; then
    fail "status --json on a fresh database did not answer an empty feed list: ${json}"
fi

printf 'static build: %s (%s bytes, %s)\n' "$BIN" "$(stat -c %s "$BIN")" "$(file -b "$BIN")"
