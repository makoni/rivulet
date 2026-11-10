#!/usr/bin/env bash
set -euo pipefail

#Stage 7 performance run: one refresh pass over 100 local stub feeds, the shape the soak's rows
#have, plus the read path at the reduced corpus. This is the run half of the performance item named
#in `docs/plan/stage-7-acceptance.md`. It is not a test and it does not run in CI: it is a real-time
#run, so the determinism rules in `docs/testing.md` do not apply to it, and the numbers it prints
#are the numbers `docs/performance.md` records as taken here. The check half,
#`Tools/clients/replay.py`, reads the document's claims — which numbers were measured here and which
#are named as not measured here — rather than the times themselves, because a time is not a rule.
#The corpus the 100k figure belongs to is gated, so the run half cannot reach it; the numbers it
#prints are the reduced corpus and 100 feeds, and the document names the 100k half as not measured
#here. The rows are seeded so the due rule can find them: the rule is strictly less than the instant
#it reads, so a row stamped at the run instant is not due at that instant. The local stub server is
#a private-network host, so the run declares the flag the policy reads. The read path is reached
#through the timed pin, because that is the piece that reads the corpus of 10k rows; the run takes
#only the elapsed the pin prints, not the bound it asserts, so the run half keeps no check. The
#fields each line names are the fields `docs/performance.md` reads, which is what lets the check
#half match a number in the document to the line that produced it. Usage: Scripts/perf.sh

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=${PERF_WORK:-$(mktemp -d)}
PERF_FEEDS=${PERF_FEEDS:-100}
PERF_ITEMS=${PERF_ITEMS:-3}
RIVULET=${RIVULET:-$(cd "$ROOT" && swift build --show-bin-path)/rivulet}

trap 'kill "$server_pid" 2>/dev/null || true' EXIT

export PERF_WORK="$WORK"
export FETCHER_ALLOW_PRIVATE_NETWORKS=true

write_feed() {
    {
        printf '<?xml version="1.0" encoding="UTF-8"?>\n'
        printf '<rss version="2.0"><channel><title>perf feed %s</title>' "$1"
        printf '<link>http://127.0.0.1:%s/site</link><ttl>1</ttl>\n' "$PORT"
        for item in $(seq 1 "$PERF_ITEMS"); do
            printf '<item><guid>perf-%s-%s</guid><title>item %s</title>' "$1" "$item" "$item"
            printf '<link>http://127.0.0.1:%s/site/item-%s</link>' "$PORT" "$item"
            printf '<description>the %s item of feed %s</description></item>\n' "$item" "$1"
        done
        printf '</channel></rss>\n'
    } >"$2"
}

mkdir -p "$WORK/feeds"
PORT=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
for n in $(seq 1 "$PERF_FEEDS"); do write_feed "$n" "$WORK/feeds/feed-$n.xml"; done
python3 -m http.server "$PORT" --directory "$WORK/feeds" >>"$WORK/server.log" 2>&1 &
server_pid=$!
sleep 1

export DATABASE_URL="$WORK/perf.sqlite3"
"$RIVULET" migrate

now=$(date +%s)
sqlite3 "$DATABASE_URL" <<SQL
INSERT INTO users (id, username, password_hash, created_at, updated_at)
    VALUES (1, 'perf', 'not-a-secret', $now, $now);
INSERT INTO categories (id, user_id, title, position, created_at, updated_at)
    VALUES (1, 1, 'perf', 0, $now, $now);
INSERT INTO feeds (id, user_id, category_id, url, next_check_at, created_at, updated_at)
    SELECT value, 1, 1, 'http://127.0.0.1:' || '$PORT' || '/feed-' || value || '.xml', $((now - 60)), $now, $now
    FROM generate_series(1, $PERF_FEEDS);
SQL

started=$(date +%s%N)
"$RIVULET" refresh
ended=$(date +%s%N)
echo "pass: pass_wall_ms=$(( (ended - started) / 1000000 )) entries_written=$(sqlite3 "$DATABASE_URL" 'SELECT count(*) FROM entries')"

started=$(date +%s%N)
"$RIVULET" refresh
ended=$(date +%s%N)
echo "second pass: second_pass_wall_ms=$(( (ended - started) / 1000000 )) because nothing is due, the schedule each job left being the policy interval"

#The read path at the reduced corpus, through the pin that holds that corpus. The run takes the
#elapsed the pin prints; the bound the pin asserts is the check half, so nothing here reads a bound.
#The pin's own line is printed as it is, because that is the source the performance document names.
print_read_path() {
    swift test --filter theReadPathStaysInsideTheDocumentedBoundForTheCorpus 2>&1 \
        | grep 'read path at the reduced corpus'
}

print_read_path
print_read_path
echo "shape: feeds=$PERF_FEEDS items=$PERF_ITEMS build=debug allow_private_networks=true"
