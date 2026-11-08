#!/usr/bin/env bash
set -euo pipefail

# Stage 7 parity harness: real Miniflux and Rivulet read the same corpus, and the difference
# between the two answers is read class by class.
#
# This is the parity exit criterion named in `docs/plan/stage-7-acceptance.md`. It is not a test
# and it does not run in CI: it is a run against two live systems, so the determinism rules in
# `docs/testing.md` do not apply to it. The halves are separated the way the soak's are: this
# shell is the run half, `Tools/parity/parity_check.py` is the check half, and
# `Tools/parity/collect.py` writes the pair document the check half reads. The tolerance table is
# read as data from `docs/parity.md` by the check half, so nothing here decides what may differ.
#
# What is guarded here is what a pair document cannot state: that the reference is the pinned
# version rather than a newer image, that the corpus is the inputs the manifest names, that the
# run reached both sides at all, that the reference ran with the media proxy off so its content
# values are the stored bytes, that the account name is one rule on both sides, and that the
# report was written from the table before the rules read it. Each guard fails on a value the run
# declares below what it requires, and that is the half checkable on this machine.
#
# What the run needs from the machine is two things the guards read: the Docker daemon for the
# reference side, and a Postgres server, which the reference needs because its `go.mod` has no
# SQLite driver. Both are read at the run, not in the dry run, so on a machine that gives neither
# the guards are the half that says so; on a machine that gives both the run executes and the pair
# document is what the rules read.
#
# Usage: Scripts/parity.sh                                   # one comparison run
#        PARITY_DRY_RUN=1 Scripts/parity.sh                  # the guards, and nothing else
#        MINIFLUX_REF=deadbeef PARITY_DRY_RUN=1 Scripts/parity.sh        # the pinned commit guard
#        MINIFLUX_TAG=2.3.4 PARITY_DRY_RUN=1 Scripts/parity.sh           # the pinned tag guard
#        PARITY_MIN_CORPUS_FILES=6 PARITY_DRY_RUN=1 Scripts/parity.sh    # the corpus count guard
#        PARITY_MIN_REQUEST_SHAPES=4 PARITY_DRY_RUN=1 Scripts/parity.sh  # the shapes count guard
#        PARITY_MIN_EXERCISED_ROWS=6 PARITY_DRY_RUN=1 Scripts/parity.sh  # the table guard
#        PARITY_PROXY_MODE=http-only PARITY_DRY_RUN=1 Scripts/parity.sh  # the proxy guard
#        PARITY_PRIVATE_NETWORKS=false PARITY_DRY_RUN=1 Scripts/parity.sh # the policy guard
#        PARITY_USER=pärity PARITY_DRY_RUN=1 Scripts/parity.sh            # the ASCII guard
#        PARITY_PGHOST=127.0.0.2 Scripts/parity.sh                        # the Postgres guard
#        PARITY_BASE_PORT=<a port something already holds> Scripts/parity.sh  # the port guard
#        PARITY_CONTAINER_NETWORK=bridge PARITY_DRY_RUN=1 Scripts/parity.sh # the network guard
#        RIVULET=/bin/true Scripts/parity.sh                 # the guard that its own side answers

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CORPUS="$ROOT/Tools/parity/corpus"
MANIFEST="$CORPUS/manifest.txt"
TABLE="$ROOT/docs/parity.md"
REPORT="$ROOT/docs/parity-report.md"
COLLECT="$ROOT/Tools/parity/collect.py"
CHECK="$ROOT/Tools/parity/parity_check.py"
STUB="$ROOT/Tools/parity/stub_server.py"
FEED="$ROOT/Tools/parity/console_feed.py"
WORK=${PARITY_WORK:-$(mktemp -d)}

# The reference is pinned twice, and the two are read separately: the image tag is what the run
# pulls, and the commit is what the clone the docs are written from holds. A newer tag with the
# same commit is still a different build.
PINNED_TAG=2.3.3
PINNED_REF=c4d54f87
PARITY_MIN_CORPUS_FILES=${PARITY_MIN_CORPUS_FILES:-5}
PARITY_MIN_REQUEST_SHAPES=${PARITY_MIN_REQUEST_SHAPES:-3}
PARITY_MIN_EXERCISED_ROWS=${PARITY_MIN_EXERCISED_ROWS:-5}
PARITY_PROXY_MODE=${PARITY_PROXY_MODE:-none}
PARITY_USER=${PARITY_USER:-parity}
PARITY_PASSWORD=${PARITY_PASSWORD:-not-a-secret}
PARITY_PRIVATE_NETWORKS=${PARITY_PRIVATE_NETWORKS:-true}
PARITY_PGHOST=${PARITY_PGHOST:-127.0.0.1}
PARITY_PGPORT=${PARITY_PGPORT:-5432}
PARITY_PGUSER=${PARITY_PGUSER:-parity}
PARITY_PGPASSWORD=${PARITY_PGPASSWORD:-parity}
PARITY_PGDATABASE=${PARITY_PGDATABASE:-parity}
# The network the reference runs in. It is declared, not chosen, because a container in its own
# namespace has its own loopback, and the corpus is served on this machine's.
PARITY_CONTAINER_NETWORK=${PARITY_CONTAINER_NETWORK:-host}
PARITY_BASE_PORT=${PARITY_BASE_PORT:-9001}
PARITY_REFERENCE_PORT=${PARITY_REFERENCE_PORT:-8080}
MINIFLUX_TAG=${MINIFLUX_TAG:-$PINNED_TAG}
MINIFLUX_REF=${MINIFLUX_REF:-$PINNED_REF}
PARITY_DRY_RUN=${PARITY_DRY_RUN:-0}
HEAD=${HEAD:-$(git -C "$ROOT" rev-parse --short HEAD)}

# One flag per name, not one string: the reference's config parser reads each name as its own
# environment variable, so the run hands them over one at a time, each with its own `-e`. A flag
# name handed without `-e` is not a flag at all: the first name after the last option is the image
# the run pulls, which is what `docker` reports it as.
FLAGS=(FETCHER_ALLOW_PRIVATE_NETWORKS=$PARITY_PRIVATE_NETWORKS BATCH_SIZE=100
       POLLING_LIMIT_PER_HOST=0 POLLING_PARSING_ERROR_LIMIT=0 RUN_MIGRATIONS=false
       MEDIA_PROXY_MODE=$PARITY_PROXY_MODE)
REFERENCE_FLAGS=()
for flag in "${FLAGS[@]}"; do
    REFERENCE_FLAGS+=(-e "$flag")
done

log() { printf '%s\n' "$1" | tee -a "$WORK/parity.log"; }
fail() { log "RULE FAIL: $1"; exit 1; }

# Guard 1: the pinned version. A pair document carries whatever the run wrote into it, so it
# cannot tell that the container the run started was a newer build than the one the docs read.
if [ "$MINIFLUX_TAG" != "$PINNED_TAG" ]; then
    fail "the run pulled the reference as tag $MINIFLUX_TAG, not the pinned $PINNED_TAG"
fi
if [ "$MINIFLUX_REF" != "$PINNED_REF" ]; then
    fail "the run read the reference as commit $MINIFLUX_REF, not the pinned $PINNED_REF"
fi

# Guard 2: the corpus. A pair document can carry digests for inputs the run never read, so the
# counts are what the shell reads, and every key the manifest names must have a file beside it.
if [ ! -f "$MANIFEST" ]; then
    fail "the manifest is not there, so the run has no inputs to read and nothing to name them by"
fi
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
        corpus/*) [ -f "$CORPUS/$(basename "$key")" ] \
            || fail "the manifest names $key, which the corpus does not hold" ;;
    esac
done

# Guard 3: the half of the table a pair document cannot state — that a class the corpus can reach
# is recorded as a row, so the number of rows naming a corpus input is what the run must have.
exercised=$(sed -n "/^## Parity harness (stage 7)/,\$p" "$TABLE" | grep -c '| accepted | corpus/' || true)
if (( exercised < PARITY_MIN_EXERCISED_ROWS )); then
    fail "the harness table names $exercised rows read from a corpus input, below the $PARITY_MIN_EXERCISED_ROWS"
fi

# Guard 4: the three values the check half reads but cannot set, and the report it reads but cannot
# write. The proxy must be `none` on the reference side, otherwise its content values are its
# rewrite rather than the stored bytes; the corpus is served on loopback, so the address policy must
# be the one that allows it on both sides; and the account name must be ASCII, because `LOWER` on
# SQLite folds ASCII only.
if [ "$PARITY_PROXY_MODE" != "none" ]; then
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

# Guard 5: the two ports the run declares. The stub's port is chosen by the kernel, so two runs
# cannot collide on it; the two bases are declared, so the run has to find them free itself, and
# a run that cannot is reported before anything is started. A declared port the run cannot bind
# is not the port the pair document will name.
for port in "$PARITY_BASE_PORT" "$PARITY_REFERENCE_PORT"; do
    if ! python3 -c 'import socket, sys; s = socket.socket(); s.bind(("127.0.0.1", int(sys.argv[1]))); s.close()' "$port" 2>/dev/null; then
        fail "the run declares port $port, which something already holds, so it is not the port the pair document will name"
    fi
done

# Guard 6: the network the reference runs in, which a pair document cannot state. The corpus is
# served on this machine's loopback, and a container in its own namespace has its own, so a run that
# keeps the reference in a namespace of its own reads a corpus it cannot reach and reports rows it
# never fetched. The declared mode is what the run hands to `docker run`, so this is the half that
# fails on a declared value.
if [ "$PARITY_CONTAINER_NETWORK" != "host" ]; then
    fail "the run puts the reference in the $PARITY_CONTAINER_NETWORK network, where its own loopback is not the loopback the corpus is served on"
fi

if [ "$PARITY_DRY_RUN" = "1" ]; then
    log "guards pass: reference $MINIFLUX_TAG at $MINIFLUX_REF, $corpus_files corpus inputs,"
    log "$shapes request shapes, $exercised exercised classes, proxy none, name ASCII, report present,"
    log "reference on the host network"
    exit 0
fi

# Guard 7: the two things this machine has to give the run, which a pair document cannot state. The
# reference has no SQLite driver, so its side needs a server, and nothing in a pair document can
# show which engine answered its rows; the daemon is the half that runs the reference at all.
if ! pg_isready -h "$PARITY_PGHOST" -p "$PARITY_PGPORT" -q >/dev/null 2>&1; then
    fail "the reference side needs a Postgres server, and the run declared $PARITY_PGHOST:$PARITY_PGPORT, which answers nothing"
fi
if ! docker info >/dev/null 2>&1; then
    fail "the Docker daemon is not reachable for this user, so the reference side cannot run here"
fi

swift build >/dev/null
RIVULET=${RIVULET:-$(swift build --show-bin-path)/rivulet}
export PARITY_CORPUS="$CORPUS" PARITY_MANIFEST="$MANIFEST" PARITY_PAIR="$WORK/pair.json"
export PARITY_USER PARITY_PASSWORD PARITY_DATABASE_URL="$WORK/parity.sqlite3"
export PARITY_PROXY_MODE PARITY_PRIVATE_NETWORKS HEAD MINIFLUX_REF PARITY_FLAGS="${FLAGS[*]}"
export PGHOST="$PARITY_PGHOST" PGPORT="$PARITY_PGPORT" PGUSER="$PARITY_PGUSER"
export PGPASSWORD="$PARITY_PGPASSWORD" PGDATABASE="$PARITY_PGDATABASE"

# The reference reads its own config names, so the bases and the flags are handed over as
# environment, one name each. The reference runs on the host network, which is what makes the
# loopback the corpus is served on the same server for both sides, so the Postgres host the guard
# read is the name the reference uses and the port it listens on is the one the run declared.
export PARITY_BASE="http://127.0.0.1:$PARITY_BASE_PORT"
export PARITY_REFERENCE_BASE="http://127.0.0.1:$PARITY_REFERENCE_PORT"
export "${FLAGS[@]}"
# The reference's url names the mode, because a string that names none takes the driver's default,
# which is `require`, and a server that does not offer SSL answers an error before anything is read;
# that is what the first live execution here showed. The reference's own config default is
# `disable`, but that is what it uses only when no connection string is given at all, and the read
# on this side is libpq, which prefers rather than requires.
REF_DATABASE_URL="postgres://$PARITY_PGUSER:$PARITY_PGPASSWORD@$PARITY_PGHOST:$PARITY_PGPORT/$PARITY_PGDATABASE?sslmode=disable"

# The name `DATABASE_URL` is not one value for the two sides: for the reference it is the server its
# config reads, for this port it is the file its rows are written to. So the port is handed its own
# value for that name, and the base its response builder reads is its own, not the host the request
# came in on.
export DATABASE_URL="$PARITY_DATABASE_URL" BASE_URL="$PARITY_BASE" LISTEN_ADDR="127.0.0.1:$PARITY_BASE_PORT"

# The stub is the half that writes one response name twice, on purpose, because the header rule
# reads a name that appears twice as the list of its values in the order they arrive. It writes that
# name on the fetch hop, which is the hop the corpus is served on; the pair document carries the
# response each side answered the collector with, so on run data the rule reads the same read twice
# — the list of values and the value it says the side acted on — and only crafted data can fire it.
# The kernel chooses the stub's port, so two runs cannot collide on it, and the stub is started
# after the names it reads, because it reads the corpus through the environment the run declares for
# it.
PORT=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
export PARITY_PORT="$PORT"
python3 "$STUB" "$PORT" >>"$WORK/server.log" 2>&1 &
stub_pid=$!
# One trap for the three things a run leaves behind, set as soon as the first of them exists: the
# stub process, the reference container, and the port's own server. The one trap covers all three
# even when the run reached only the first, and the container is removed rather than stopped,
# because the name it holds is what a second run cannot take while the first still has it.
trap '{ [ -n "${serve_pid:-}" ] && kill "$serve_pid" 2>/dev/null; kill "$stub_pid" 2>/dev/null; } \
    || true; docker rm -f parity-reference >/dev/null 2>&1 || true' EXIT

answers() {
    python3 -c 'import socket, sys
try:
    s = socket.create_connection(("127.0.0.1", int(sys.argv[1])), 1); s.close()
except OSError:
    sys.exit(1)' "$1" 2>/dev/null
}
wait_for() {
    for attempt in 1 2 3 4 5 6 7 8 9 10 11 12; do
        answers "$1" && return 0
        sleep 1
    done
    return 1
}

# The reference's config read takes `CREATE_ADMIN` as a boolean and the account as two names beside
# it, so a value written as `name:password` is reported as an invalid boolean before anything runs,
# which is what the first live execution here showed. The migrations are gated off as the guard
# says, so the schema is applied by a run of its own through the reference's own flag, the same
# shape the port's `migrate` command is, and the account is created on the daemon branch, which is
# where the reference reads the two names. The image names its program as the command and not as an
# entrypoint, so the flag run has to name the program itself before the flag.
docker run --rm --network "$PARITY_CONTAINER_NETWORK" --entrypoint /usr/bin/miniflux \
    -e DATABASE_URL="$REF_DATABASE_URL" "${REFERENCE_FLAGS[@]}" \
    "miniflux/miniflux:$MINIFLUX_TAG" -migrate >/dev/null

docker run -d --name parity-reference --network "$PARITY_CONTAINER_NETWORK" \
    -e LISTEN_ADDR="127.0.0.1:$PARITY_REFERENCE_PORT" -e DATABASE_URL="$REF_DATABASE_URL" \
    -e BASE_URL="$PARITY_REFERENCE_BASE" -e CREATE_ADMIN=true -e ADMIN_USERNAME="$PARITY_USER" \
    -e ADMIN_PASSWORD="$PARITY_PASSWORD" "${REFERENCE_FLAGS[@]}" \
    "miniflux/miniflux:$MINIFLUX_TAG" >/dev/null

# The port's side is read through its own commands, with the migrations gated off as the guard says,
# so the rows the pair document carries are the rows this port's read path answers. The account is
# created on both sides: on the reference through its config read, on the port through
# `create-admin`, and the password half of that read is the secure path, which takes its value from
# a terminal rather than from a pipe. So the run gives the command a terminal, and the two values it
# feeds are the names the run already declares. A run that fed a pipe instead reported the
# min-length rule before any row was written, which is what the first live execution here showed.
"$RIVULET" migrate
RIVULET_BINARY="$RIVULET" RIVULET_COMMAND="create-admin" python3 "$FEED"
for key in $(grep -v '^#\|^$' "$MANIFEST" | cut -d'|' -f1 | tr -d ' '); do
    case "$key" in
        corpus/*) "$RIVULET" add "http://127.0.0.1:$PORT/$(basename "$key")" --user "$PARITY_USER" ;;
    esac
done
# The due rule is strict, so the batch read cannot see a feed written at the same instant it reads.
# The run lets the clock move past the instant the insert wrote; a run that read the batch at that
# same instant reported no feeds at all, which is what the first live execution here showed.
sleep 1
"$RIVULET" refresh

# Guard 8: the two bases the run declares, read as the answers they give. A pair document cannot
# carry an answer that never happened, so a side the run cannot reach is reported before anything is
# collected. The reference is a container, and it listens only after its own migrations answer, so
# the wait is what the run has to make for it.
"$RIVULET" serve >/dev/null &
serve_pid=$!
wait_for "$PARITY_REFERENCE_PORT" \
    || fail "the run declares $PARITY_REFERENCE_PORT as the base the reference side answers on, and nothing answers there, so the answers the pair document carries never happened"
wait_for "$PARITY_BASE_PORT" \
    || fail "the run declares $PARITY_BASE_PORT as the base its own side answers on, and nothing answers there, so the answers the pair document carries never happened"

python3 "$COLLECT"

# Guard 9: the login half, which the pair document can state only as the answer it recorded. The
# requests after the login are answered through the token that answer carries, so a run that
# recorded the unauthorized answer never authenticated, and every answer after it is the answer an
# unauthenticated read gives. On this machine that is what the run reports: the reference reads the
# integration row for this, and the only path that sets the enabled flag that read requires is its
# web form, while this port has no integration table and no flag at all, and its own path for the
# pair is the console command. The two sides cannot be set up through one path, so the run gets to
# the login and not past it here, and this guard is what says so.
for side in reference port; do
    login=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))[sys.argv[2]]["requests"][0]["status"])' "$WORK/pair.json" "$side")
    if [ "$login" != "200" ]; then
        fail "the login answer on the $side side is $login, so the run never authenticated and the requests after it are answers to an unauthenticated read"
    fi
done

# Guard 10: the rows each side recorded, which is what says the pair document is a run rather than
# an empty document a run wrote when it stored nothing.
for side in reference port; do
    row_count=$(python3 -c 'import json, sys; print(len(json.load(open(sys.argv[1]))[sys.argv[2]]["entries"]))' "$WORK/pair.json" "$side")
    if [ "$row_count" -eq 0 ]; then
        fail "the run recorded nothing for the $side side, so the pair document is not a run"
    fi
done

# The report is written from the table before the rules read it, which is what lets the rule that
# reads the report read the same table the run read.
python3 "$CHECK" --render --recorded "$TABLE" --manifest "$MANIFEST" --report "$REPORT"
python3 "$CHECK" --pair "$WORK/pair.json" --recorded "$TABLE" --manifest "$MANIFEST" --report "$REPORT"

log "run end: pair $WORK/pair.json, report $REPORT"
