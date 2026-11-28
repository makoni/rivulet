#!/usr/bin/env bash
set -euo pipefail

# Rough performance numbers: one refresh pass over PERF_FEEDS local stub feeds (default 100, with
# PERF_ITEMS items each), a second pass when nothing is due, and the read path over the reduced 10k
# corpus (via the `LargeFeedTests` timing pin). Prints the numbers; asserts nothing. Real-time and
# machine-dependent, so it is not part of CI. The numbers last recorded are in `docs/performance.md`.
# Needs `sqlite3` and `python3`. Usage: Scripts/perf.sh

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

# The read path at the reduced 10k corpus: the elapsed time `LargeFeedTests` prints.
print_read_path() {
    swift test --filter theReadPathStaysInsideTheDocumentedBoundForTheCorpus 2>&1 \
        | grep 'read path at the reduced corpus'
}

print_read_path
print_read_path
echo "shape: feeds=$PERF_FEEDS items=$PERF_ITEMS build=debug allow_private_networks=true"
