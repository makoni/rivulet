#!/usr/bin/env bash
set -euo pipefail

# Stage 7's client run: one real client against the served port, read as the calls it actually sent.
# This is the run half of the manual client matrix item named in `docs/plan/stage-7-acceptance.md`.
# It is not a test and it does not run in CI: the client is a GUI app, so the person walks the
# checklist in the app while the observer records what arrived, and the check half reads the record
# rather than the app. The observer writes one line per request it forwarded, in the order the
# requests arrived, and writes the answer as the key names it carried imply, so the record is what
# the run saw rather than what the matrix expected to see. The run half asserts nothing about a
# line: the rule that reads the record is `Tools/clients/run_record.py`.
#
# What the guards read, and what each can fail on: the record path against the file the check half
# reads in `Tools/clients/parsers.py`; the client the run names against the client the matrix has a
# row for; the two ports against each other and against the ports the machine already holds; the
# base the run writes for the client against the observer's own port, so a base naming the port the
# observer forwards to is a base the run would never see a request on; the version the run names
# against the version the app's own metadata on the machine writes; the pair row the run wrote,
# which the guard reports when the command wrote nothing there, because the record line that names
# the pair is the half the run reaches only when a request carried it; the entry rows the pass wrote
# against the value the run declares its seeded feed page carries, which is the half the client
# reads and marks; and the record being empty, which is what a check half that reads no record line
# cannot show. The guards that read the machine fail only on a machine, and the two that read the
# rows the run writes fail only on a run.
#
# Usage, one guard per line, each run against the value that line names:
#
#   Scripts/client-run.sh                                   # the run, then the guards
#   CLIENT_RECORD=<a path the check half does not read> Scripts/client-run.sh   # the record path
#   CLIENT_NAME=<a client the matrix has no row for> Scripts/client-run.sh        # the client row
#   CLIENT_OBSERVE_PORT=8099 CLIENT_TARGET_PORT=8099 Scripts/client-run.sh         # the ports
#   CLIENT_BASE=http://127.0.0.1:8098/fever Scripts/client-run.sh                   # the base
#   CLIENT_VERSION=<a version the app metadata does not write> Scripts/client-run.sh  # the version
#   CLIENT_USER=<a name the run wrote no row for> Scripts/client-run.sh             # the pair row
#   DECLARED_ITEMS=2 Scripts/client-run.sh                                   # the entry rows
#   CLIENT_RECORD=<an empty record> CLIENT_RUN_SECONDS=1 Scripts/client-run.sh     # the empty run
#
# The checklist the person walks is the one `docs/clients.md` writes for this client; the run half
# keeps no part of it, because a click is not a rule.


ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=${CLIENT_WORK:-$(mktemp -d)}
RIVULET=${RIVULET:-$(cd "$ROOT" && swift build --show-bin-path)/rivulet}
CLIENT=${CLIENT_NAME:-NewsFlash}
APP_ID=io.gitlab.news_flash.NewsFlash
CLIENT_USER=${CLIENT_USER:-client-run}
CLIENT_PASSWORD=${CLIENT_PASSWORD:-client-run-password}
RECORD=${CLIENT_RECORD:-$ROOT/Tools/clients/client-run.txt}
OBSERVE_PORT=${CLIENT_OBSERVE_PORT:-8099}
TARGET_PORT=${CLIENT_TARGET_PORT:-8098}
RUN_SECONDS=${CLIENT_RUN_SECONDS:-180}
BASE=${CLIENT_BASE:-http://127.0.0.1:$OBSERVE_PORT/fever}
METAINFO="${CLIENT_METAINFO:-/var/lib/flatpak/app/$APP_ID/current/active/files/share/metainfo/$APP_ID.metainfo.xml}"
export DATABASE_URL="$WORK/client.sqlite3"
export FETCHER_ALLOW_PRIVATE_NETWORKS=true

if [ -z "${CLIENT_VERSION:-}" ]; then
    CLIENT_VERSION=$(grep -o '<release version="[0-9.]*"' "$METAINFO" | head -1 | cut -d'"' -f2)
fi

trap 'kill "${stub_pid:-}" "${serve_pid:-}" "${observer_pid:-}" 2>/dev/null || true' EXIT

fail() { printf 'guard: %s\n' "$1"; exit 1; }

answers() {
    python3 -c 'import socket,sys; s = socket.socket(); sys.exit(0 if s.connect_ex(("127.0.0.1", int(sys.argv[1]))) else 1)' "$1"
}

# The wait the run makes for a port it started itself: the ports guard names the ports, and a
# run started is not something a guard can fail on, only a machine.
wait_for() {
    for attempt in 1 2 3 4 5 6 7 8 9 10 11 12; do
        answers "$1" && return 0
        sleep 1
    done
    return 1
}

run_guards() {
    [ "$RECORD" = "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import parsers; print(parsers.DEFAULTS["record"])' "$ROOT/Tools/clients")" ] ||
        fail "the record path $RECORD is not the file the check half reads"
    grep -q "^| $CLIENT |" "$ROOT/docs/clients.md" || fail "the matrix has no row for $CLIENT"
    [ "$OBSERVE_PORT" != "$TARGET_PORT" ] || fail "the observer forwards to the port it listens on"
    answers "$OBSERVE_PORT" || fail "the machine already holds the observer port $OBSERVE_PORT"
    answers "$TARGET_PORT" || fail "the machine already holds the served port $TARGET_PORT"
    # The base carries the path the port registers: the app sends to the base as it is typed, so a
    # base without the path reaches the root and answers Vapor's 404, which is what this run's login
    # showed.
    [ "$BASE" = "http://127.0.0.1:$OBSERVE_PORT/fever" ] ||
        fail "the base the run writes names the port the observer forwards to, not its own port"
    [ "$(python3 "$ROOT/Tools/clients/version_read.py" "$METAINFO")" = "$CLIENT_VERSION" ] ||
        fail "the run names a version the file it reads does not write"
}

pair_guard() {
    stored=$(python3 -c 'import os, sqlite3; row = sqlite3.connect(os.environ["DATABASE_URL"]).execute("select fever_token from users where username = ?", (os.environ["CLIENT_USER"],)).fetchone(); print(row[0] if row and row[0] else "")')
    [ -n "$stored" ] || fail "the pair row the run wrote carries no Fever value, so the name the record reads for the pair can never be on a line"
}

# The value the run declares its seeded feed page carries, read against the rows the pass wrote:
# this guard fails only on a run, because it reads the storage the run writes.
DECLARED_ITEMS=${DECLARED_ITEMS:-1}

entry_guard() {
    stored=$(python3 -c 'import os, sqlite3; print(sqlite3.connect(os.environ["DATABASE_URL"]).execute("select count(*) from entries").fetchone()[0])')
    [ "$stored" = "$DECLARED_ITEMS" ] || fail "the pass wrote $stored entry rows, not the $DECLARED_ITEMS the run declares its feed page carries"
}

seed_feed() {
    {
        printf '<?xml version="1.0" encoding="UTF-8"?>\n'
        printf '<rss version="2.0"><channel><title>client feed</title>'
        printf '<link>http://127.0.0.1:%s/site</link><ttl>1</ttl>\n' "$STUB_PORT"
        printf '<item><guid>client-1</guid><title>the item the run seeds</title>'
        printf '<description>the item the client will read</description></item>\n'
        printf '</channel></rss>\n'
    } >"$WORK/feed.xml"
}

mkdir -p "$WORK"
: >"$RECORD"
run_guards

"$RIVULET" migrate
STUB_PORT=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
seed_feed
python3 -m http.server "$STUB_PORT" --directory "$WORK" >>"$WORK/stub.log" 2>&1 &
stub_pid=$!

# The wait the run makes for the feed page it serves itself: the refresh reads the row it built, so
# the run has to wait for the page before it runs the pass that reads it.
wait_for "$STUB_PORT"

# The pass takes only the batch that is due, so the run puts the row it seeded in that batch.
# Without this the client has no entries to read, and the checklist half that marks one item cannot
# be reached.
due_feed() {
    python3 -c 'import os, sqlite3, time; db = sqlite3.connect(os.environ["DATABASE_URL"]); db.execute("update feeds set next_check_at = ?", (int(time.time()) - 60,)); db.commit()'
}

LISTEN_ADDR="127.0.0.1:$TARGET_PORT" BASE_URL="http://127.0.0.1:$TARGET_PORT" \
    "$RIVULET" serve >>"$WORK/serve.log" 2>&1 &
serve_pid=$!

# The pair the run declares, in the order each command reads its prompts: `create-admin` reads the
# two values, and `integration-credentials` reads the account, then the Fever pair, then the Google
# Reader pair, so the same two values answer the place each command reads a value at. Which prompt
# produced which value is not something the record can state, so the order is declared here and
# named rather than asserted, as `Tools/clients/run_record.py` reads the name rather than the value.
export CLIENT_FEED="$CLIENT_USER
$CLIENT_PASSWORD"
wait_for "$TARGET_PORT"
python3 "$ROOT/Tools/clients/feed_prompts.py" "$RIVULET" create-admin
export CLIENT_FEED="$CLIENT_USER
$CLIENT_USER
$CLIENT_PASSWORD
$CLIENT_USER
$CLIENT_PASSWORD"
python3 "$ROOT/Tools/clients/feed_prompts.py" "$RIVULET" integration-credentials
export CLIENT_USER
pair_guard
"$RIVULET" add "http://127.0.0.1:$STUB_PORT/feed.xml"
due_feed
"$RIVULET" refresh
entry_guard

export CLIENT_RECORD="$RECORD" CLIENT_OBSERVE_PORT="$OBSERVE_PORT" CLIENT_TARGET_PORT="$TARGET_PORT"
export CLIENT_NAME="$CLIENT"
python3 "$ROOT/Tools/clients/observer.py" >>"$WORK/observer.log" 2>&1 &
observer_pid=$!

printf 'client: %s %s, base %s, pair %s/%s, record %s\n' "$CLIENT" "$CLIENT_VERSION" "$BASE" \
    "$CLIENT_USER" "$CLIENT_PASSWORD" "$RECORD"
printf 'walk the checklist, then the guards read the record the observer wrote\n'
sleep "$RUN_SECONDS"

[ -s "$RECORD" ] || fail "the run wrote no record line, so the check half reads no record"
cat "$RECORD"
