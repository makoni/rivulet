#!/usr/bin/env bash
set -euo pipefail

# Stage 7's client run: one real client against the served port, read as the calls it actually sent.
# This is the run half of the manual client matrix item named in `docs/plan/stage-7-acceptance.md`.
# It is not a test and it does not run in CI: the client is a GUI app, so the person walks the
# checklist in the app while the observer records what arrived, and the check half reads the record
# rather than the app. The observer writes one line per request it forwarded, in the order the
# requests arrived, and writes the answer as the registration the file writes for the path that
# answers on a route, or as the name the dispatch case answered on for the path that dispatches, so
# the record is what the run saw rather than what the matrix expected to see. The run half asserts
# nothing about a line: the rule that reads the record is `Tools/clients/run_record.py`.  The record
# is one file per client, in the record directory the check half reads, named as the round reads
# that client, so the rule reads a record for the client its lines name.  What the guards read, and
# what each can fail on: the record path against the record directory the check half reads in
# `Tools/clients/parsers.py`, which is the half that makes a record written somewhere else
# unreadable; the client the run names against the client the matrix has a row for; the host the run
# writes against the address the machine answers on, which is the address a client on another device
# reaches the observer through; the two ports against each other and against the ports the machine
# already holds — the observer port read on the host the run declares, and the served port read on
# the address the run's own serve half binds, because a served port bound to loopback is not a port
# a device reaches the observer through; the base the run writes for the client in three halves —
# the port half, so a base naming the port the observer forwards to is a base the run would never
# see a request on, and the prefix half plus the form the set names for how this client builds the
# prefix from the base, so a base carrying a path the set does not name for this client reaches the
# root, with the default base the run builds following that form so it does not reach the guard with
# the prefix twice for a client whose set names that it appends the prefix itself; the version the
# run names against the version the app's own metadata on the machine writes,
# which is the half a client run on a device cannot be read against here; the pair row the run
# wrote, read through the column the storage read names for the path the set gives this client,
# which is the value the login compares; the entry rows the pass wrote for the feed the run declares
# — for a client whose set names the add call that row is the row the client's own call writes —
# against the value the run declares that page carries; and the record being empty, which is what a
# check half that reads no record line cannot show. The nine guards are twelve read sites, one
# failure message each: six of them read one value, the ports item reads three, the base reads three
# halves at two sites, and the entry guard reads two halves at one site. The guards that read the
# machine fail only on a machine, and the three that read what the run itself wrote — the pair row,
# the entry rows, and the record being empty — fail only on a run.  Usage, one line per half the
# guards read, each run against the value that line names. Thirteen of the fourteen halves have a
# line; the one that does not is the observer port the machine already holds, which is seen by holding
# the port with a listener:
#   Scripts/client-run.sh                                   # the run, then the guards
#   CLIENT_RECORD=<a path outside the record directory the check half reads> Scripts/client-run.sh    # the record path
#   CLIENT_NAME=<a client the matrix has no row for> Scripts/client-run.sh        # the client row
#   CLIENT_HOST=10.10.10.10 Scripts/client-run.sh                                  # the host
#   CLIENT_OBSERVE_PORT=8099 CLIENT_TARGET_PORT=8099 Scripts/client-run.sh         # the ports
#   CLIENT_TARGET_PORT=<a port loopback already holds, with CLIENT_HOST set to another address> Scripts/client-run.sh  # the served port, read on the address the serve half binds
#   CLIENT_BASE=http://127.0.0.1:8098/reader/api/0 Scripts/client-run.sh           # the base, the port half
#   CLIENT_NAME=FeedFlow CLIENT_BASE=http://127.0.0.1:8099/fever Scripts/client-run.sh  # the base, the prefix half, for the client whose set names the Google Reader path
#   CLIENT_NAME=FeedFlow CLIENT_BASE=http://127.0.0.1:8099/reader/api/0 Scripts/client-run.sh  # the base, the form half, for the client whose set names that it builds the prefix itself
#   CLIENT_VERSION=<a version the file the run reads does not write> Scripts/client-run.sh            # the version, on the half that only exists on this machine
#   CLIENT_USER= Scripts/client-run.sh                                              # the pair row, on a name the command's rule refuses before the storage layer, read through the column each path names
#   DECLARED_ITEMS=2 Scripts/client-run.sh                                   # the entry rows
#   DECLARED_FEED=<a url the run wrote no row for> Scripts/client-run.sh            # the entry rows, the feed half
#   CLIENT_RECORD=<an empty record in a copy of the tree> CLIENT_RUN_SECONDS=1 Scripts/client-run.sh  # the empty run
#
# The checklist the person walks is the one `docs/clients.md` writes for this client; the run half
# keeps no part of it, because a click is not a rule.


ROOT=$(cd "$(dirname "$0")/.." && pwd)
CLIENTS="$ROOT/Tools/clients"
CLIENT_NAME=${CLIENT_NAME:-NewsFlash}

# The reads the check half has, used here as the run declares the names it writes, so the record
# file, the prefix the base carries, the add call the row comes from and the path the pair column
# belongs to are the names the rule reads them with.
record_for() {
    python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import parsers; print(parsers.record_path(sys.argv[2]))' "$CLIENTS" "$CLIENT_NAME"
}

prefix_for() {
    python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import parsers; print(parsers.prefix_for(sys.argv[2]))' "$CLIENTS" "$CLIENT_NAME"
}

prefix_form_for() {
    python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import parsers; print(parsers.prefix_form_for(sys.argv[2]))' "$CLIENTS" "$CLIENT_NAME"
}

add_call_for() {
    python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import parsers; print(parsers.add_call(sys.argv[2]))' "$CLIENTS" "$CLIENT_NAME"
}

api_for() {
    python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import parsers; print(parsers.set_for(sys.argv[2])["api"])' "$CLIENTS" "$CLIENT_NAME"
}

WORK=${CLIENT_WORK:-$(mktemp -d)}
RIVULET=${RIVULET:-$(cd "$ROOT" && swift build --show-bin-path)/rivulet}
APP_ID=io.gitlab.news_flash.NewsFlash
# The default form is the unset-only one, so an empty name the run declares stays empty: the
# command's rule refuses an empty name before the storage layer, which is the value the pair guard
# fails on.
CLIENT_USER=${CLIENT_USER-client-run}
CLIENT_PASSWORD=${CLIENT_PASSWORD:-client-run-password}
HOST=${CLIENT_HOST:-127.0.0.1}
RECORD=${CLIENT_RECORD:-$(record_for)}
OBSERVE_PORT=${CLIENT_OBSERVE_PORT:-8099}
TARGET_PORT=${CLIENT_TARGET_PORT:-8098}
# The address the run's own serve half binds, which is the address the served port is read on: the
# observer port is read on the host the run declares, because that is the address a device reaches
# the observer through, while the served port answers only here.
SERVE_BIND=127.0.0.1
RUN_SECONDS=${CLIENT_RUN_SECONDS:-180}
POLL_INTERVAL=${CLIENT_POLLING_FREQUENCY:-10}
# The base the run declares, read as the run declares it: it stays empty until the guard for the
# client row has passed, because the prefix half reads the set, and a name the matrix has no row for
# has no set to read either.
BASE=${CLIENT_BASE:-}
METAINFO="${CLIENT_METAINFO:-/var/lib/flatpak/app/$APP_ID/current/active/files/share/metainfo/$APP_ID.metainfo.xml}"
export DATABASE_URL="$WORK/client.sqlite3"
export FETCHER_ALLOW_PRIVATE_NETWORKS=true

if [ -z "${CLIENT_VERSION:-}" ]; then
    if [ -f "$METAINFO" ]; then
        CLIENT_VERSION=$(grep -o '<release version="[0-9.]*"' "$METAINFO" | head -1 | cut -d'"' -f2)
    else
        # The half the document names as a report item: for a client on a device this machine has no
        # app metadata to read the version against, so the run declares what the app reports.
        CLIENT_VERSION="not read here: no app metadata for a client run on a device"
    fi
fi

trap 'kill "${stub_pid:-}" "${serve_pid:-}" "${observer_pid:-}" 2>/dev/null || true' EXIT

fail() { printf 'guard: %s\n' "$1"; exit 1; }

# The address the machine answers on for the network a device reaches it through, read as the source
# address the machine's own default route selects, with no packet sent.
machine_host() {
    python3 -c 'import socket; s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.connect(("8.8.8.8", 80)); print(s.getsockname()[0])'
}

# True when something already answers on the port, read as connect_ex answering 0 for a connection
# it can make at the address the run reads that port on: the host the run declares for the observer
# port, and the address the run's own serve half binds for the served port. The ports guard reads
# this as the machine already holding the port, and the wait below reads the same helper in the same
# sense, so both sites agree with their own messages.
answers() {
    python3 -c 'import socket,sys; s = socket.socket(); sys.exit(0 if s.connect_ex((sys.argv[1], int(sys.argv[2]))) == 0 else 1)' "${2:-$HOST}" "$1"
}

# The wait the run makes for a port it started itself: the ports guard names the ports, and a run
# started is not something a guard can fail on, only a machine.
wait_for() {
    for attempt in 1 2 3 4 5 6 7 8 9 10 11 12; do
        answers "$1" "${2:-$HOST}" && return 0
        sleep 1
    done
    return 1
}

base_host_port() { printf '%s\n' "$BASE" | sed -e 's|^http://||' -e 's|/.*$||'; }

base_prefix() { printf '%s\n' "$BASE" | sed -n 's|^http://[^/]*||p'; }

# The prefix as the client builds it: the base as typed for a client that sends the base as the
# whole prefix, and the base plus what the client appends for a client whose own resource table
# builds the prefix, which is the form the set names for that client.
effective_prefix() {
    if [ -z "$(prefix_form_for)" ]; then
        base_prefix
    else
        printf '%s%s\n' "$(base_prefix)" "$(prefix_for)"
    fi
}

# The column the login read compares for the path the set names: the storage read for the Fever path
# takes the derived value, the read for this path takes the stored value the login builds against.
pair_column() {
    case "$(api_for)" in
        fever) printf 'fever_token\n' ;;
        google-reader) printf 'google_reader_password_hash\n' ;;
    esac
}

run_guards() {
    [ "$RECORD" = "$(record_for)" ] ||
        fail "the record path $RECORD is not the file the check half reads for $CLIENT_NAME"
    grep -q "^| $CLIENT_NAME |" "$ROOT/docs/clients.md" || fail "the matrix has no row for $CLIENT_NAME"
    [ "$HOST" = "127.0.0.1" ] || [ "$HOST" = "$(machine_host)" ] ||
        fail "the run writes a host the machine does not answer on ($HOST, not $(machine_host))"
    [ "$OBSERVE_PORT" != "$TARGET_PORT" ] || fail "the observer forwards to the port it listens on"
    answers "$OBSERVE_PORT" && fail "the machine already holds the observer port $OBSERVE_PORT"
    answers "$TARGET_PORT" "$SERVE_BIND" && fail "the machine already holds the served port $TARGET_PORT"
    if [ -z "$BASE" ]; then
        # The default base is the base this client would type, read as the form the set names for it:
        # the prefix for a client that sends the base as the whole prefix, and the port alone for a
        # client whose own resource table appends the prefix. A default that carried the prefix for
        # that client reached the base guard with it twice, so the run failed by construction before
        # the client sent anything, which is the half the usage line for this half shows.
        if [ -z "$(prefix_form_for)" ]; then
            BASE="http://$HOST:$OBSERVE_PORT$(prefix_for)"
        else
            BASE="http://$HOST:$OBSERVE_PORT"
        fi
    fi
    # The base carries the host and the port the run reads, and the prefix is read as the form the
    # set names for this client: the base as typed for a client that sends it as the whole prefix,
    # and the base plus what the client appends for a client whose own resource table builds the
    # prefix, which is the form FeedFlow's set names. A base carrying a path the set does not name
    # for this client reaches the root, which is what the login of the first run showed as Vapor's
    # 404.
    [ "$(base_host_port)" = "$HOST:$OBSERVE_PORT" ] ||
        fail "the base the run writes names a port the observer does not listen on"
    [ "$(effective_prefix)" = "$(prefix_for)" ] ||
        fail "the base the run writes gives the prefix as $(effective_prefix), which is not the prefix the set names for $CLIENT_NAME ($(prefix_for))"
    if [ -f "$METAINFO" ]; then
        [ "$(python3 "$CLIENTS/version_read.py" "$METAINFO")" = "$CLIENT_VERSION" ] ||
            fail "the run names a version the file it reads does not write"
    fi
}

pair_guard() {
    stored=$(python3 -c 'import os,sqlite3; row = sqlite3.connect(os.environ["DATABASE_URL"]).execute("select " + os.environ["PAIR_COLUMN"] + " from users where username = ?", (os.environ["CLIENT_USER"],)).fetchone(); print(row[0] if row and row[0] else "")')
    [ -n "$stored" ] || fail "the pair row the run wrote carries nothing for the $PAIR_COLUMN value the login read compares on this path, so the name the record reads for the pair can never be on a line"
}

# The feed the run declares: the page it serves carries the feed link the scan answers, so the entry
# rows are read for that one row, whether the row came from the run's own command or from the
# client's own add call.
DECLARED_ITEMS=${DECLARED_ITEMS:-1}

entry_guard() {
    stored=$(python3 -c 'import os,sqlite3; db = sqlite3.connect(os.environ["DATABASE_URL"]); print(db.execute("select count(*) from entries where feed_id = (select id from feeds where url = ?)", (os.environ["DECLARED_FEED"],)).fetchone()[0])')
    [ "$stored" = "$DECLARED_ITEMS" ] || fail "the pass wrote $stored entry rows for the feed the run declares, not the $DECLARED_ITEMS the run declares its page carries"
}

# The page the client is asked to add, and the feed page it carries: the scan reads the link the
# page declares, so the add call reaches the write the run is there to show.
seed_pages() {
    {
        printf '<!doctype html><html><head><title>client page</title>'
        printf '<link rel="alternate" type="application/rss+xml" href="/feed.xml"></head><body>x</body></html>\n'
    } >"$WORK/discovery.html"
    {
        printf '<?xml version="1.0" encoding="UTF-8"?>\n'
        printf '<rss version="2.0"><channel><title>client feed</title>'
        printf '<link>http://127.0.0.1:%s/discovery.html</link><ttl>1</ttl>\n' "$STUB_PORT"
        printf '<item><guid>client-1</guid><title>the item the run seeds</title>'
        printf '<description>the item the client will read</description></item>\n'
        printf '</channel></rss>\n'
    } >"$WORK/feed.xml"
}

mkdir -p "$WORK"
# The guards that read a value the run declares run before the record is written, and they read the
# record path as a name rather than as a file, so a run that fails one of them leaves the record the
# previous run wrote alone. The guards that read what the run wrote run after the run, at the end.
run_guards
: >"$RECORD"

"$RIVULET" migrate
# The port the run serves its feed page on, and the two values it declares: the page the client is
# asked to add, and the url the row the entry guard reads holds, which is the value the scan answers
# for the link that page declares. The device types the page url as a name; the fetch is the
# machine's own, which is why the address policy is left on for this run.
STUB_PORT=${CLIENT_STUB_PORT:-$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')}
DECLARED_PAGE=${DECLARED_PAGE:-http://$HOST:$STUB_PORT/discovery.html}
DECLARED_FEED=${DECLARED_FEED:-http://$HOST:$STUB_PORT/feed.xml}
export DECLARED_PAGE DECLARED_FEED DECLARED_ITEMS PAIR_COLUMN
PAIR_COLUMN=$(pair_column)
seed_pages
python3 -m http.server "$STUB_PORT" --directory "$WORK" --bind "$HOST" >>"$WORK/stub.log" 2>&1 &
stub_pid=$!

# The wait the run makes for the feed page it serves itself: the refresh reads the row it built, so
# the run has to wait for the page before it runs the pass that reads it.
wait_for "$STUB_PORT"

# The pass takes only the batch that is due, so the run puts the row it seeds in that batch.
due_feed() {
    python3 -c 'import os, sqlite3, time; db = sqlite3.connect(os.environ["DATABASE_URL"]); db.execute("update feeds set next_check_at = ?", (int(time.time()) - 60,)); db.commit()'
}

LISTEN_ADDR="$SERVE_BIND:$TARGET_PORT" BASE_URL="http://$SERVE_BIND:$TARGET_PORT" \
    POLLING_FREQUENCY="$POLL_INTERVAL" "$RIVULET" serve >>"$WORK/serve.log" 2>&1 &
serve_pid=$!

# The pair the run declares, in the order each command reads its prompts: `create-admin` reads the
# two values, and `integration-credentials` reads the account, then the Fever pair, then the Google
# Reader pair, so the same two values answer the place each command reads a value at. Which prompt
# produced which value is not something the record can state, so the order is declared here and
# named rather than asserted, as `Tools/clients/run_record.py` reads the name rather than the value.
export CLIENT_FEED="$CLIENT_USER
$CLIENT_PASSWORD"
export CLIENT_USER CLIENT_PASSWORD
wait_for "$TARGET_PORT" "$SERVE_BIND"
python3 "$CLIENTS/feed_prompts.py" "$RIVULET" create-admin
export CLIENT_FEED="$CLIENT_USER
$CLIENT_USER
$CLIENT_PASSWORD
$CLIENT_USER
$CLIENT_PASSWORD"
python3 "$CLIENTS/feed_prompts.py" "$RIVULET" integration-credentials
pair_guard

# Where the feed row comes from is read through the set: for a client whose set names the add call
# the row has to be the row that call writes, because a row written here would put the duplicate
# rule in front of the call the run is there to show. For a client whose set has no call that can
# write a row the run writes it itself, so the half of the checklist that marks one item has a row
# to mark.
add_call=$(add_call_for)
if [ -z "$add_call" ]; then
    "$RIVULET" add "$DECLARED_FEED"
    due_feed
    "$RIVULET" refresh
else
    printf 'the feed row is left to the call the set names (%s); the pass the cadence loop makes during the window writes its rows\n' "$add_call"
fi

export CLIENT_RECORD="$RECORD" CLIENT_OBSERVE_PORT="$OBSERVE_PORT" CLIENT_TARGET_PORT="$TARGET_PORT"
export CLIENT_NAME="$CLIENT_NAME" CLIENT_HOST="$HOST"
python3 "$CLIENTS/observer.py" >>"$WORK/observer.log" 2>&1 &
observer_pid=$!

printf 'client: %s %s, base %s, pair %s/%s, record %s\n' "$CLIENT_NAME" "$CLIENT_VERSION" "$BASE" \
    "$CLIENT_USER" "$CLIENT_PASSWORD" "$RECORD"
printf 'walk the checklist, then the guards read the record the observer wrote\n'
sleep "$RUN_SECONDS"

[ -s "$RECORD" ] || fail "the run wrote no record line, so the check half reads no record"
entry_guard
cat "$RECORD"
