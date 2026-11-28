#!/usr/bin/env bash
set -euo pipefail

# Manual client check: serve Rivulet on a throwaway database with one account, one feed and one entry,
# put a logging proxy (`Tools/clients/observer.py`) in front of it, and let a person point a real
# client at the proxy. Every request the client sends is appended to the record as one JSON line
# (method, path, parameter names, status, response keys — never values). Stop with Ctrl-C, or set
# CLIENT_RUN_SECONDS.
#
# Point the client at http://<CLIENT_HOST>:<CLIENT_OBSERVE_PORT> and log in with CLIENT_USER /
# CLIENT_PASSWORD:
#   Google Reader API  base URL as above (the client appends /accounts/ClientLogin, /reader/api/0)
#   Fever API          <base>/fever
#   Miniflux REST v1   base URL as above, basic auth, or the printed API key as X-Auth-Token
#
# Environment (all optional):
#   CLIENT_HOST          address the client reaches this machine on (default 127.0.0.1; use the
#                        LAN address for a phone)
#   CLIENT_OBSERVE_PORT  port the client talks to (default 8099)
#   CLIENT_TARGET_PORT   port Rivulet serves on, loopback only (default 8098)
#   CLIENT_USER, CLIENT_PASSWORD   the account and both integration logins (default client-run /
#                        client-run-password)
#   CLIENT_RECORD        record file (default <work dir>/record.jsonl)
#   CLIENT_RUN_SECONDS   stop after this many seconds instead of waiting for Ctrl-C
#   CLIENT_WORK          work directory (default: a new temporary directory)
#   RIVULET              binary to run (default: the debug build)

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=${CLIENT_WORK:-$(mktemp -d)}
RIVULET=${RIVULET:-$(cd "$ROOT" && swift build --show-bin-path)/rivulet}
HOST=${CLIENT_HOST:-127.0.0.1}
OBSERVE_PORT=${CLIENT_OBSERVE_PORT:-8099}
TARGET_PORT=${CLIENT_TARGET_PORT:-8098}
CLIENT_USER=${CLIENT_USER:-client-run}
CLIENT_PASSWORD=${CLIENT_PASSWORD:-client-run-password}
RECORD=${CLIENT_RECORD:-$WORK/record.jsonl}

[ -x "$RIVULET" ] || { echo "no binary at $RIVULET; run swift build first" >&2; exit 1; }
[ "$OBSERVE_PORT" != "$TARGET_PORT" ] || { echo "the two ports must differ" >&2; exit 1; }

mkdir -p "$WORK"
: >"$RECORD"
export DATABASE_URL="$WORK/client.sqlite3"
export FETCHER_ALLOW_PRIVATE_NETWORKS=true

trap 'kill "${stub_pid:-}" "${serve_pid:-}" "${observer_pid:-}" 2>/dev/null || true' EXIT

wait_for_port() {
    for _ in $(seq 1 20); do
        python3 -c 'import socket,sys; s = socket.socket(); sys.exit(s.connect_ex((sys.argv[1], int(sys.argv[2]))))' \
            "$1" "$2" && return 0
        sleep 0.5
    done
    echo "nothing answers on $1:$2" >&2
    exit 1
}

# One local feed with one item, served from the work directory.
STUB_PORT=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
cat >"$WORK/feed.xml" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel><title>client feed</title><link>http://127.0.0.1:$STUB_PORT/</link>
<item><guid>client-1</guid><title>The seeded item</title><description>An item for the client to read.</description></item>
</channel></rss>
XML
python3 -m http.server "$STUB_PORT" --bind 127.0.0.1 --directory "$WORK" >>"$WORK/stub.log" 2>&1 &
stub_pid=$!
wait_for_port 127.0.0.1 "$STUB_PORT"

"$RIVULET" migrate
CLIENT_FEED="$CLIENT_USER
$CLIENT_PASSWORD" python3 "$ROOT/Tools/clients/feed_prompts.py" "$RIVULET" create-admin
CLIENT_FEED="$CLIENT_USER
$CLIENT_USER
$CLIENT_PASSWORD
$CLIENT_USER
$CLIENT_PASSWORD" python3 "$ROOT/Tools/clients/feed_prompts.py" "$RIVULET" integration-credentials
api_key=$("$RIVULET" create-api-key client-run --user "$CLIENT_USER" | sed -n 's/^Api key token: //p')
"$RIVULET" add "http://127.0.0.1:$STUB_PORT/feed.xml" --user "$CLIENT_USER"
# A new feed is scheduled for later; make it due so the first refresh writes the seeded entry.
python3 -c 'import os, sqlite3, time; db = sqlite3.connect(os.environ["DATABASE_URL"]); db.execute("update feeds set next_check_at = ?", (int(time.time()) - 60,)); db.commit()'
"$RIVULET" refresh

LISTEN_ADDR="127.0.0.1:$TARGET_PORT" BASE_URL="http://$HOST:$OBSERVE_PORT" \
    "$RIVULET" serve >>"$WORK/serve.log" 2>&1 &
serve_pid=$!
wait_for_port 127.0.0.1 "$TARGET_PORT"

RECORD="$RECORD" OBSERVE_HOST=0.0.0.0 OBSERVE_PORT="$OBSERVE_PORT" TARGET_HOST=127.0.0.1 \
    TARGET_PORT="$TARGET_PORT" python3 "$ROOT/Tools/clients/observer.py" >>"$WORK/observer.log" 2>&1 &
observer_pid=$!
wait_for_port 127.0.0.1 "$OBSERVE_PORT"

cat <<INFO
Server:   http://$HOST:$OBSERVE_PORT  (Fever: http://$HOST:$OBSERVE_PORT/fever)
Login:    $CLIENT_USER / $CLIENT_PASSWORD
API key:  $api_key
Record:   $RECORD
Logs:     $WORK
Walk the client, then press Ctrl-C.
INFO

if [ -n "${CLIENT_RUN_SECONDS:-}" ]; then
    sleep "$CLIENT_RUN_SECONDS"
else
    wait "$serve_pid" || true
fi
echo "--- record ($(wc -l <"$RECORD") requests)"
cat "$RECORD"
