#!/usr/bin/env bash
set -euo pipefail

# Stage 7 parity harness: real Miniflux and Rivulet read the same corpus, and the difference between
# the two answers is read class by class.
#
# This is the parity exit criterion named in `docs/plan/stage-7-acceptance.md`. It is not a test and
# it does not run in CI: it is a run against two live systems, so the determinism rules in
# `docs/testing.md` do not apply to it. The halves are separated the way the soak's are: this shell
# is
# the run half, `Tools/parity/parity_check.py` is the check half, and `Tools/parity/collect.py`
# writes
# the pair document the check half reads. The tolerance table is read as data from `docs/parity.md`
# by
# the check half, so nothing here decides what may differ.
#
# What is guarded here is what a pair document cannot state: that the reference is the pinned
# version
# rather than a newer image, that the corpus is the inputs the manifest names, that the run reached
# both
# sides at all, that the reference ran with the media proxy off so its content values are the stored
# bytes, and that the report exists before the rules read it. Each guard fails on a value the run
# declares below what it requires, and that is the half checkable on this machine.
#
# The run half cannot execute here: the Docker daemon is not reachable for this user, and no
# Postgres
# server answers, which the reference needs because its `go.mod` has no SQLite driver. The guards
# are
# what say so.
#
# Usage: Scripts/parity.sh                                   # one comparison run
#        PARITY_DRY_RUN=1 Scripts/parity.sh                  # the guards, and nothing else
#        PARITY_MIN_CORPUS_FILES=6 PARITY_DRY_RUN=1 Scripts/parity.sh   # the corpus guard failing
#        PARITY_MIN_REQUEST_SHAPES=4 PARITY_DRY_RUN=1 Scripts/parity.sh # the shapes guard failing
#        PARITY_MIN_EXERCISED_ROWS=6 PARITY_DRY_RUN=1 Scripts/parity.sh # the table guard failing
#        PARITY_PROXY_MODE=http-only PARITY_DRY_RUN=1 Scripts/parity.sh # the proxy guard failing
# PARITY_PRIVATE_NETWORKS=false PARITY_DRY_RUN=1 Scripts/parity.sh # the policy guard failing
#        PARITY_USER=pärity PARITY_DRY_RUN=1 Scripts/parity.sh            # the ASCII guard failing
#        MINIFLUX_REF=deadbeef PARITY_DRY_RUN=1 Scripts/parity.sh         # the pinned-version guard
# PARITY_PGHOST=127.0.0.2 Scripts/parity.sh # the Postgres guard failing

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CORPUS="$ROOT/Tools/parity/corpus"
MANIFEST="$CORPUS/manifest.txt"
TABLE="$ROOT/docs/parity.md"
REPORT="$ROOT/docs/parity-report.md"
COLLECT="$ROOT/Tools/parity/collect.py"
CHECK="$ROOT/Tools/parity/parity_check.py"
WORK=${PARITY_WORK:-$(mktemp -d)}

PINNED_REF=c4d54f87
PARITY_MIN_CORPUS_FILES=${PARITY_MIN_CORPUS_FILES:-5}
PARITY_MIN_REQUEST_SHAPES=${PARITY_MIN_REQUEST_SHAPES:-3}
PARITY_MIN_EXERCISED_ROWS=${PARITY_MIN_EXERCISED_ROWS:-5}
PARITY_PROXY_MODE=${PARITY_PROXY_MODE:-off}
PARITY_USER=${PARITY_USER:-parity}
PARITY_PASSWORD=${PARITY_PASSWORD:-not-a-secret}
PARITY_PRIVATE_NETWORKS=${PARITY_PRIVATE_NETWORKS:-true}
PARITY_PGHOST=${PARITY_PGHOST:-127.0.0.1}
PARITY_BASE=${PARITY_BASE:-http://127.0.0.1:9001}
PARITY_REFERENCE_BASE=${PARITY_REFERENCE_BASE:-http://127.0.0.1:8080}
MINIFLUX_REF=${MINIFLUX_REF:-$PINNED_REF}
PARITY_DRY_RUN=${PARITY_DRY_RUN:-0}
HEAD=${HEAD:-$(git -C "$ROOT" rev-parse --short HEAD)}
PARITY_FLAGS=${PARITY_FLAGS:-"FETCHER_ALLOW_PRIVATE_NETWORKS=$PARITY_PRIVATE_NETWORKS BATCH_SIZE=100 POLLING_LIMIT_PER_HOST=0 POLLING_PARSING_ERROR_LIMIT=0 RUN_MIGRATIONS=false"}

log() { printf '%s\n' "$1" | tee -a "$WORK/parity.log"; }
fail() { log "RULE FAIL: $1"; exit 1; }

# Guard 1: the pinned version. A pair document carries whatever version the run wrote into it, so it
# cannot tell that the container the run started was a newer image.
if [ "$MINIFLUX_REF" != "$PINNED_REF" ]; then
    fail "the run declared the reference as $MINIFLUX_REF, not the pinned $PINNED_REF"
fi

# Guard 2: the corpus. A pair document can carry digests for inputs the run never read, so the
# number
# of inputs is what the shell reads, and the manifest is what it reads them against.
inputs=$(grep -vc '^#\|^$' "$MANIFEST" || true)
corpus_files=$(grep -c '^corpus/' "$MANIFEST" || true)
if (( corpus_files < PARITY_MIN_CORPUS_FILES )); then
    fail "the run read $corpus_files corpus inputs, below the $PARITY_MIN_CORPUS_FILES it requires"
fi
shapes=$((inputs - corpus_files))
if (( shapes < PARITY_MIN_REQUEST_SHAPES )); then
    fail "the run read $shapes request shapes, below the $PARITY_MIN_REQUEST_SHAPES it requires"
fi
for key in $(grep -v '^#\|^$' "$MANIFEST" | cut -d'|' -f1 | tr -d ' '); do
    case "$key" in
        corpus/*) [ -f "$CORPUS/$(basename "$key")" ] || fail "the manifest names $key, which the corpus does not hold" ;;
    esac
done

# Guard 3: the half of the table a pair document cannot state — that a class the corpus can reach is
# recorded as a row, so the number of rows naming a corpus input is what the run must have.
exercised=$(sed -n "/^## Parity harness (stage 7)/,\$p" "$TABLE" | grep -c '| accepted | corpus/' || true)
if (( exercised < PARITY_MIN_EXERCISED_ROWS )); then
    fail "the harness table names $exercised rows read from a corpus input, below the $PARITY_MIN_EXERCISED_ROWS"
fi

# Guard 4: the three values the check half reads but cannot set. The proxy must be off on the
# reference side, otherwise its content values are its rewrite rather than the stored bytes; the
# corpus is served on loopback, so the address policy must be the one that allows it on both sides;
# and the account name must be ASCII, because `LOWER` on SQLite folds ASCII only.
if [ "$PARITY_PROXY_MODE" != "off" ]; then
    fail "the run declared the proxy mode as $PARITY_PROXY_MODE, so the content values are the rewrite"
fi
if [ "$PARITY_PRIVATE_NETWORKS" != "true" ]; then
    fail "the corpus is served on loopback and the run declares the address policy as $PARITY_PRIVATE_NETWORKS"
fi
if [ "$PARITY_USER" != "${PARITY_USER//[^ -~]/}" ]; then
    fail "the account name $PARITY_USER is not ASCII, so the auth read is not one rule on both sides"
fi
if [ ! -f "$REPORT" ]; then
    fail "the report is not written, so the rule that reads it cannot be applied"
fi

if [ "$PARITY_DRY_RUN" = "1" ]; then
    log "guards pass: reference $MINIFLUX_REF, $corpus_files corpus inputs, $shapes request shapes,"
    log "$exercised exercised classes, proxy off, name ASCII, report present"
    exit 0
fi

# Guard 5: the two things this machine cannot give the run. The reference has no SQLite driver, so
# its
# side needs a server, and nothing in a pair document can show which engine answered its rows.
if ! pg_isready -h "$PARITY_PGHOST" -q >/dev/null 2>&1; then
    fail "the reference side needs a Postgres server, and the run declared $PARITY_PGHOST, which answers nothing"
fi
if ! docker info >/dev/null 2>&1; then
    fail "the Docker daemon is not reachable for this user, so the reference side cannot run here"
fi

# The port is chosen by the kernel, so two runs cannot collide, and the stub that serves the corpus
# is
# bound to it afterwards — which is why nothing here is a test.
PORT=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
python3 -m http.server "$PORT" --directory "$CORPUS" >>"$WORK/server.log" 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT

swift build >/dev/null
RIVULET=${RIVULET:-$(swift build --show-bin-path)/rivulet}
export PARITY_CORPUS="$CORPUS" PARITY_MANIFEST="$MANIFEST" PARITY_PAIR="$WORK/pair.json"
export PARITY_USER PARITY_PASSWORD PARITY_FLAGS PARITY_BASE PARITY_REFERENCE_BASE PARITY_PROXY_MODE
export PARITY_PORT="$PORT" MINIFLUX_REF HEAD
export DATABASE_URL="$WORK/parity.sqlite3"

docker run -d --name parity-reference -e DATABASE_URL=postgres://parity:parity@127.0.0.1:5432/parity \
    -e BASE_URL="$PARITY_REFERENCE_BASE" -e MEDIA_PROXY_MODE="$PARITY_PROXY_MODE" \
    -e FETCHER_ALLOW_PRIVATE_NETWORKS="$PARITY_PRIVATE_NETWORKS" \
    miniflux/miniflux:"$MINIFLUX_REF" >/dev/null

# The port's side is read through its own commands, with the migrations gated off as the guard says,
# so
# the rows the pair document carries are the rows this port's read path answers.
"$RIVULET" migrate
for key in $(grep -v '^#\|^$' "$MANIFEST" | cut -d'|' -f1 | tr -d ' '); do
    case "$key" in
        corpus/*) "$RIVULET" add "http://127.0.0.1:$PORT/$(basename "$key")" --user "$PARITY_USER" ;;
    esac
done
"$RIVULET" refresh

python3 "$COLLECT"

for side in reference port; do
    row_count=$(python3 -c 'import json, sys; print(len(json.load(open(sys.argv[1]))[sys.argv[2]]["entries"]))' "$WORK/pair.json" "$side")
    if [ "$row_count" -eq 0 ]; then
        fail "the run recorded nothing for the $side side, so the pair document is not a run"
    fi
done

# The report is written from the table before the rules read it, which is what lets the rule that
# reads
# the report read the same table the run read.
python3 "$CHECK" --render --recorded "$TABLE" --manifest "$MANIFEST" --report "$REPORT"
python3 "$CHECK" --pair "$WORK/pair.json" --recorded "$TABLE" --manifest "$MANIFEST" --report "$REPORT"

log "run end: pair $WORK/pair.json, report $REPORT"
