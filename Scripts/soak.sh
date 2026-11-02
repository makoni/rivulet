#!/usr/bin/env bash
set -euo pipefail

# Stage 4 soak: the refresh pipeline driven over at least 2h against 24 local stub feeds.
#
# This is the stage-4 exit criterion named in `docs/plan/stage-4-ingestion.md`. It is not a test and
# it does not run in CI: it is a real-time run, so the determinism rules in `docs/testing.md` do not
# apply to it, and it is the only part of stage 4 that reaches a real HTTP server and a real clock.
# The in-process cadence loop is stage 6's, so the shell is the cadence here: each round runs the
# manual pass once and takes a snapshot. The checks live in `Scripts/soak_check.py`, which reads the
# data each round leaves behind rather than the process that produced it.
#
# What the run shows is the rule each round reports: the pass ran exactly the pick, the stamps moved
# forward, the schedule landed after the round, the counts match the rows, the error feed increments
# while the pick can reach it, the document is the documented contract, and the database keeps no
# duplicate (feed_id, hash) pair. What it cannot show is stated in `docs/testing.md`: that it slept
# at all, that the fetcher reached the network, and which round read a row.
#
# The schedule the pass leaves is the interval the policy applies — the reference default of 60
# minutes, because the command builds `NextCheckPolicy()` with the reference defaults — so a feed is
# fetched about three times in 2h, and the `<ttl>` the stub feeds carry cannot shorten that: the
# policy takes the maximum of the mode's interval and the delay the answer carries. "Stamps
# advancing" is read as those three advances, not as a faster cadence.
#
# Two numbers are the run's own rules and the script fails on them: the duration and the number of
# feeds, and a third — the window must not be smaller than the rows, so the pick the checks compute
# is the pick the rules make rather than the number the window happened to cut.
#
# Usage: Scripts/soak.sh                            # 2h, 24 feeds, work dir under mktemp
#        SOAK_SECONDS=120 SOAK_FEEDS=22 Scripts/soak.sh   # the same shape, for checking checks

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CHECK="$ROOT/Scripts/soak_check.py"

SOAK_SECONDS=${SOAK_SECONDS:-7200}
SOAK_FEEDS=${SOAK_FEEDS:-24}
SOAK_ROUND_SECONDS=${SOAK_ROUND_SECONDS:-30}
SOAK_ITEMS=${SOAK_ITEMS:-3}
SOAK_TTL=${SOAK_TTL:-1}
SOAK_MUTATE_EVERY=${SOAK_MUTATE_EVERY:-4}
SOAK_ERROR_LIMIT=${SOAK_ERROR_LIMIT:-2}
SOAK_MIN_SECONDS=${SOAK_MIN_SECONDS:-7200}
SOAK_MIN_FEEDS=${SOAK_MIN_FEEDS:-20}
SOAK_BATCH_SIZE=${SOAK_BATCH_SIZE:-100}
SOAK_WORKER_POOL=${SOAK_WORKER_POOL:-8}
SOAK_DIR=${SOAK_DIR:-$(mktemp -d)}
RIVULET=${RIVULET:-}

ROUND_RULES=document_shape,id_order,totals_match_rows,due_matches_pick,pick_ran_exactly,\
fetched_stamp_moves_forward,schedule_moved_forward,error_counter,no_crash,\
row_count_matches_the_declaration
FINAL_RULES=error_path_observed,entries_have_no_duplicate_pair,every_enabled_row_was_fetched,\
integrity_is_ok,row_count_matches_the_declaration

if (( SOAK_SECONDS < SOAK_MIN_SECONDS )); then
    echo "RULE FAIL: the run declared $SOAK_SECONDS seconds, below the $SOAK_MIN_SECONDS it requires"
    exit 1
fi
if (( SOAK_FEEDS < SOAK_MIN_FEEDS )); then
    echo "RULE FAIL: the run declared $SOAK_FEEDS feeds, below the $SOAK_MIN_FEEDS it requires"
    exit 1
fi
if (( SOAK_BATCH_SIZE < SOAK_FEEDS + 3 )); then
    echo "RULE FAIL: the window ($SOAK_BATCH_SIZE) is smaller than the rows the run seeds, so the"
    echo "pick the checks compute could be capped by the window instead of by the rules it names"
    exit 1
fi

export DATABASE_URL="$SOAK_DIR/soak.sqlite3"

if [ -e "$DATABASE_URL" ]; then
    echo "RULE FAIL: $DATABASE_URL already has rows; the run seeds a fresh database, so a check that"
    echo "reads the state the run left cannot tell it from the state it found"
    exit 1
fi

log() { printf '%s\n' "$1" | tee -a "$SOAK_DIR/soak.log"; }

export FETCHER_ALLOW_PRIVATE_NETWORKS=true
export POLLING_PARSING_ERROR_LIMIT=$SOAK_ERROR_LIMIT
export POLLING_LIMIT_PER_HOST=0
export BATCH_SIZE=$SOAK_BATCH_SIZE
export WORKER_POOL_SIZE=$SOAK_WORKER_POOL
export RUN_MIGRATIONS=false
export LOG_LEVEL=info

echo "soak: $SOAK_SECONDS s, $SOAK_FEEDS feeds + 3 control rows, $SOAK_ROUND_SECONDS s rounds, dir $SOAK_DIR"

swift build >/dev/null
RIVULET=${RIVULET:-$(swift build --show-bin-path)/rivulet}

mkdir -p "$SOAK_DIR/feeds" "$SOAK_DIR/snapshots"

# The port is chosen by the kernel, not fixed, so two runs cannot collide. The server is bound to
# that number afterwards, which is why nothing here is a test.
PORT=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
python3 -m http.server "$PORT" --directory "$SOAK_DIR/feeds" >>"$SOAK_DIR/server.log" 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT

write_feed() {
    {
        printf '<?xml version="1.0" encoding="UTF-8"?>\n'
        printf '<rss version="2.0"><channel><title>soak feed %s</title>' "$1"
        printf '<link>http://127.0.0.1:%s/site</link><ttl>%s</ttl>\n' "$PORT" "$SOAK_TTL"
        for item in $(seq 1 "$SOAK_ITEMS"); do
            printf '<item><guid>soak-%s-%s</guid><title>item %s</title>' "$1" "$item" "$item"
            printf '<link>http://127.0.0.1:%s/site/item-%s</link>' "$PORT" "$item"
            printf '<description>the %s item of feed %s</description></item>\n' "$item" "$1"
        done
        printf '</channel></rss>\n'
    } >"$2"
}

for n in $(seq 1 "$SOAK_FEEDS"); do
    write_feed "$n" "$SOAK_DIR/feeds/feed-$n.xml"
done

# The control content: bytes that are not a feed, so the parse fails and the error counter runs.
printf 'These are not a feed: the parser reads no root element here.\n' >"$SOAK_DIR/feeds/not-a-feed.txt"

# The schema comes from the port's own migrate command, not from a copy of the DDL, so the run reads
# the same schema the commands read.
"$RIVULET" migrate

now=$(date +%s)
sqlite3 "$DATABASE_URL" <<SQL
INSERT INTO users (id, username, password_hash, created_at, updated_at)
    VALUES (1, 'soak', 'not-a-secret', $now, $now);
INSERT INTO categories (id, user_id, title, position, created_at, updated_at)
    VALUES (1, 1, 'soak', 0, $now, $now);
INSERT INTO feeds (id, user_id, category_id, url, next_check_at, created_at, updated_at)
    SELECT value, 1, 1, 'http://127.0.0.1:' || '$PORT' || '/feed-' || value || '.xml', $now, $now, $now
    FROM generate_series(1, $SOAK_FEEDS);
INSERT INTO feeds (id, user_id, category_id, url, next_check_at, created_at, updated_at)
    VALUES ($((SOAK_FEEDS + 1)), 1, 1, 'http://127.0.0.1:' || '$PORT' || '/not-a-feed.txt', $now, $now, $now);
INSERT INTO feeds (id, user_id, category_id, url, next_check_at, created_at, updated_at, disabled)
    VALUES ($((SOAK_FEEDS + 2)), 1, 1, 'http://127.0.0.1:' || '$PORT' || '/feed-disabled.xml', $now, $now, $now, 1);
INSERT INTO feeds (id, user_id, category_id, url, next_check_at, created_at, updated_at,
                   parsing_error_count, parsing_error_message)
    VALUES ($((SOAK_FEEDS + 3)), 1, 1, 'http://127.0.0.1:' || '$PORT' || '/feed-at-limit.xml',
            $now, $now, $now, $SOAK_ERROR_LIMIT, 'seeded at the limit');
SQL

ERROR_FEED=$((SOAK_FEEDS + 1))

count_changed() {
    python3 -c 'import json, sys
prev = {row["id"]: row for row in json.load(open(sys.argv[1]))["feeds"]}
cur = json.load(open(sys.argv[2]))["feeds"]
print(sum(1 for row in cur if row["fetched_at"] != prev[row["id"]]["fetched_at"]))' "$1" "$2"
}

error_increment() {
    python3 -c 'import json, sys
prev = {row["id"]: row for row in json.load(open(sys.argv[1]))["feeds"]}
cur = json.load(open(sys.argv[2]))["feeds"]
row = next(row for row in cur if row["id"] == int(sys.argv[3]))
print(1 if row["parsing_error_count"] > prev[int(sys.argv[3])]["parsing_error_count"] else 0)' "$1" "$2" "$3"
}

read_total() { python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["totals"][sys.argv[2]])' "$1" "$2"; }
read_row_field() {
    python3 -c 'import json, sys
row = next(row for row in json.load(open(sys.argv[1]))["feeds"] if row["id"] == int(sys.argv[2]))
print(row[sys.argv[3]])' "$1" "$2" "$3"
}

start=$(date +%s)
round=0
error_increments=0
prev="$SOAK_DIR/snapshots/round-0.json"
instant_prev=$(date +%s)
"$RIVULET" status --json >"$prev"
log "run start: feeds=$SOAK_FEEDS error_feed=$ERROR_FEED limit=$SOAK_ERROR_LIMIT batch=$SOAK_BATCH_SIZE pool=$SOAK_WORKER_POOL port=$PORT due_before_first_pass=$(read_total "$prev" due)"

while (( $(date +%s) - start < SOAK_SECONDS )); do
    round=$((round + 1))
    instant_prev=$(date +%s)

    if (( round % SOAK_MUTATE_EVERY == 0 )); then
        # One feed's file is rewritten, so its next pass sees a changed mtime and answers 200 while
        # the untouched feeds answer 304 against the validator the row holds. The content is the
        # same, so the entry loop stores nothing from the rewritten one: the run exercises the
        # conditional-hit branch and the branch that parses and writes nothing new, not the insert
        # branch again.
        feed=$(( (round % SOAK_FEEDS) + 1 ))
        write_feed "$feed" "$SOAK_DIR/feeds/feed-$feed.xml"
    fi

    refresh_exit=0
    report=$("$RIVULET" refresh) || refresh_exit=$?
    cur="$SOAK_DIR/snapshots/round-$round.json"
    instant_cur=$(date +%s)
    status_exit=0
    "$RIVULET" status --json >"$cur" || status_exit=$?

    picked=$(count_changed "$prev" "$cur")
    error_increments=$((error_increments + $(error_increment "$prev" "$cur" "$ERROR_FEED")))

    log "round $round instant=$instant_cur ran=$picked due_after=$(read_total "$cur" due) error_feed_count=$(read_row_field "$cur" "$ERROR_FEED" parsing_error_count) report=[$report] exit_refresh=$refresh_exit exit_status=$status_exit"

    python3 "$CHECK" --prev "$prev" --cur "$cur" \
        --instant-prev "$instant_prev" --instant-cur "$instant_cur" \
        --error-limit "$SOAK_ERROR_LIMIT" --batch-size "$SOAK_BATCH_SIZE" --host-limit 0 \
        --min-feeds "$SOAK_FEEDS" --error-feed "$ERROR_FEED" \
        --error-increments "$error_increments" \
        --exit-refresh "$refresh_exit" --exit-status "$status_exit" \
        --rules "$ROUND_RULES"

    prev="$cur"
    sleep "$SOAK_ROUND_SECONDS"
done

python3 "$CHECK" --prev "$prev" --cur "$prev" \
    --instant-prev "$(date +%s)" --instant-cur "$(date +%s)" \
    --error-limit "$SOAK_ERROR_LIMIT" --batch-size "$SOAK_BATCH_SIZE" --host-limit 0 \
    --min-feeds "$SOAK_FEEDS" --error-feed "$ERROR_FEED" \
    --error-increments "$error_increments" \
    --exit-refresh 0 --exit-status 0 \
    --rules "$FINAL_RULES" --db "$DATABASE_URL"

log "run end: rounds=$round error_increments=$error_increments entries=$(sqlite3 "$DATABASE_URL" 'SELECT count(*) FROM entries') distinct_pairs=$(sqlite3 "$DATABASE_URL" 'SELECT count(*) FROM (SELECT DISTINCT feed_id, hash FROM entries)')"

echo "soak log: $SOAK_DIR/soak.log"
