#!/usr/bin/env bash
set -euo pipefail

#  Stage 8's smoke job: the static artifact in a base that carries no toolchain and no libc, read
# as the document the run leaves behind. This is the run half of the clean-container job the stage
# names; the rules are in `Tools/smoke/smoke_check.py`, which reads what the run recorded rather
# than the container it ran. It is not a test and it does not run in CI: the CI container has no
# Docker and no SDK, so the run is on demand, and the shell is checked here by `bash -n` and by
# the guards below. What the guards read, and what each can fail on: the base the run declares
# against the line the committed Dockerfile writes; the artifact against the product path
# `Scripts/build-release.sh` names for the triple's arch, and against the file being there at all;
# the corpus against the number of records the manifest declares and against every file the
# manifest names being present; the held delay against the stop grace, because a round cannot be
# in flight when the stop lands before the delay ends; the stop grace against the bound the run
# names; the record path against the document the check half reads; the ports against what the
# machine already holds; the wait against the cadence the run declares; the address policy against
# the name the config reads the flag by, the value forms the switch reads, and the address class
# the policy names; the build context against the file the Dockerfile's COPY line names; the held
# file against the last record the manifest declares, because the run takes its read at the point
# the records before the held one are answered; the gap between the `add` calls against the second
# the value is stored in, because the rule reads the values those calls recorded as an order and the
# clause fixes none between equal values; and the credentials run's prompt count against the number
# of prompts the command declares, read from the file the check half reads it from. The guard that
# reads Docker itself fails only on a machine without it, which is the point of the job. What the
# run cannot show is named in the document and in `docs/testing.md`: that the fetch was still in
# flight when the signal landed, that the container had nothing beyond the file the Dockerfile
# writes, the wording of the lines the binary printed, the exit code a stop signal that never lands
# would leave, the value a fetcher with the policy off would have refused before the round, the
# titles the corpus documents declare, which the fetch does not store, which prompt produced which
# value in the credentials run, the order the round's jobs ran in, which the worker pool does not
# fix, and the runbook, because `docs/deploy.md` does not exist yet.
#
# Usage, one guard per line, each run against the value that line names:
#
#   Scripts/smoke.sh                                        # the run, then the rules
#   SMOKE_BASE=alpine Scripts/smoke.sh                      # the base guard
#   SMOKE_TRIPLE=aarch64-swift-linux-musl Scripts/smoke.sh  # the product-path guard
#   SMOKE_ARTIFACT=<a path the release script does not name> Scripts/smoke.sh  # the same guard
#   SMOKE_MIN_CORPUS=6 Scripts/smoke.sh                     # the corpus count guard
#   SMOKE_HELD_SECONDS=1 Scripts/smoke.sh                   # the in-flight guard
#   SMOKE_STOP_GRACE=0 Scripts/smoke.sh                     # the stop-grace bound
#   SMOKE_RECORD=/tmp/other.json Scripts/smoke.sh           # the record-path guard
#   SMOKE_PORT=9010 SMOKE_STUB_PORT=9010 Scripts/smoke.sh  # the port guard, on one name for both
#   SMOKE_PORT=9010 with something already listening        # the port guard, on either port
#   SMOKE_WAIT_SECONDS=30 Scripts/smoke.sh                  # the wait-against-cadence guard
#   SMOKE_ALLOW_PRIVATE=0 Scripts/smoke.sh                  # the policy guard, on the value
#   SMOKE_POLICY_NAME=FETCHER_ALLOW_PRIVATE Scripts/smoke.sh  # the same guard, on the name
#   SMOKE_TARGET=93.184.216.34 Scripts/smoke.sh            # the same guard, on the class
#   SMOKE_DOCKERFILE=<a file naming another COPY name> Scripts/smoke.sh  # the build-context guard
#   SMOKE_HELD_FILE=smoke_alpha.xml Scripts/smoke.sh        # the held-position guard
#   SMOKE_ADD_GAP=1 Scripts/smoke.sh                        # the add-gap guard
#   SMOKE_CRED_FEED with fewer values than the command declares prompts  # the prompt-count guard

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CHECK="$ROOT/Tools/smoke/smoke_check.py"
SOURCES="$ROOT/Tools/smoke/sources.py"
COLLECT="$ROOT/Tools/smoke/collect.py"

SMOKE_WORK=${SMOKE_WORK:-$(mktemp -d)}
SMOKE_IMAGE=${SMOKE_IMAGE:-rivulet-smoke}
SMOKE_BASE=${SMOKE_BASE:-scratch}
SMOKE_TRIPLE=${SMOKE_TRIPLE:-x86_64-swift-linux-musl}
SMOKE_PORT=${SMOKE_PORT:-9010}
SMOKE_STUB_PORT=${SMOKE_STUB_PORT:-9011}
SMOKE_RECORD=${SMOKE_RECORD:-$ROOT/Tools/smoke/run.json}
SMOKE_EVENTS=${SMOKE_EVENTS:-$SMOKE_WORK/events.txt}
SMOKE_HELD_FILE=${SMOKE_HELD_FILE:-smoke_epsilon.xml}
SMOKE_HELD_SECONDS=${SMOKE_HELD_SECONDS:-15}
SMOKE_STOP_GRACE=${SMOKE_STOP_GRACE:-4}
SMOKE_MAX_GRACE=${SMOKE_MAX_GRACE:-6}
SMOKE_POLLING_FREQUENCY=${SMOKE_POLLING_FREQUENCY:-1}
SMOKE_ERROR_LIMIT=${SMOKE_ERROR_LIMIT:-0}
SMOKE_BATCH_SIZE=${SMOKE_BATCH_SIZE:-100}
SMOKE_MIN_CORPUS=${SMOKE_MIN_CORPUS:-5}
SMOKE_CORPUS=${SMOKE_CORPUS:-$ROOT/Tools/smoke/corpus}
SMOKE_DOCKERFILE=${SMOKE_DOCKERFILE:-$ROOT/Dockerfile}
SMOKE_MANIFEST=${SMOKE_MANIFEST:-$ROOT/Tools/smoke/corpus/manifest.txt}
SMOKE_WAIT_SECONDS=${SMOKE_WAIT_SECONDS:-180}
SMOKE_ADD_GAP=${SMOKE_ADD_GAP:-2}
SMOKE_USER=${SMOKE_USER:-smoke}
SMOKE_PASSWORD=${SMOKE_PASSWORD:-smoke-password}
SMOKE_TARGET=${SMOKE_TARGET:-127.0.0.1}
SMOKE_POLICY_NAME=${SMOKE_POLICY_NAME:-FETCHER_ALLOW_PRIVATE_NETWORKS}
SMOKE_ALLOW_PRIVATE=${SMOKE_ALLOW_PRIVATE:-1}
#  The values in the order the command reads its prompts, which is what the terminal half writes.
SMOKE_FEED=${SMOKE_FEED:-$(printf '%s\n%s' "$SMOKE_USER" "$SMOKE_PASSWORD")}
#  The values for the credentials run, in the order the command declares its prompts: the account,
# the two names and the two passwords, one line per prompt the file writes.
SMOKE_CRED_FEED=${SMOKE_CRED_FEED:-$(printf '%s\n%s\n%s\n%s\n%s' "$SMOKE_USER" "$SMOKE_USER" \
    "$SMOKE_PASSWORD" "$SMOKE_USER" "$SMOKE_PASSWORD")}
SMOKE_DOCKER=${SMOKE_DOCKER:-docker}

fail() { echo "RULE FAIL: $1"; exit 1; }

#  Guard 1: the machine the run needs, which is the thing this job cannot show from inside CI.
if ! command -v "$SMOKE_DOCKER" >/dev/null; then
    fail "the run needs a container engine, and this machine gives none"
fi

#  Guard 2: the base. The image is the point of the job, so the base the run declares must be the
# one the Dockerfile writes, read from the committed file rather than from the run's own word, and
# the run builds from that same file rather than from a copy of it.
if [ ! -f "$SMOKE_DOCKERFILE" ]; then
    fail "the run names a Dockerfile that is not there, so there is no base to read it against"
fi
written=$(sed -n 's/^FROM \([A-Za-z0-9:._-]*\).*/\1/p' "$SMOKE_DOCKERFILE" | head -1)
if [ "$SMOKE_BASE" != "$written" ]; then
    fail "the run declares base $SMOKE_BASE, while the Dockerfile writes $written"
fi

#  Guard 3: the artifact. The product path is read from the release script the stage landed, so a
# run that copies a file from somewhere else is not the build that script names. The script builds
# the product name from the triple's arch, read as its own `${TRIPLE%%-*}` reads it, so the run
# declares the triple it built for and the guard reads the product path that shape gives for it.
shape=$(grep -o 'out/Products/[^/$]*' "$ROOT/Scripts/build-release.sh" | head -1)
if [ -z "$shape" ]; then
    fail "the release script names no product path, so there is nothing to read the artifact against"
fi
product="${shape}${SMOKE_TRIPLE%%-*}"
SMOKE_ARTIFACT=${SMOKE_ARTIFACT:-$ROOT/.build/static/$product/rivulet}
if [ "$SMOKE_ARTIFACT" != "$ROOT/.build/static/$product/rivulet" ]; then
    fail "the run reads the artifact at $SMOKE_ARTIFACT, which is not the product path the release script names for the triple it declares ($product)"
fi
if [ ! -f "$SMOKE_ARTIFACT" ]; then
    fail "the artifact the run names is not there, so the image has nothing to carry"
fi

#  Guard 4: the corpus. A document can carry records for files the run never read, so the counts
# are what the shell reads, and every file the manifest names must be beside it.
if [ ! -f "$SMOKE_MANIFEST" ]; then
    fail "the manifest is not there, so the run has no inputs to read and nothing to name them by"
fi
records=$(grep -vc '^#\|^$' "$SMOKE_MANIFEST" || true)
if (( records < SMOKE_MIN_CORPUS )); then
    fail "the manifest holds $records records, below the $SMOKE_MIN_CORPUS the run requires"
fi
while IFS='|' read -r name rest; do
    name=${name//[[:space:]]/}
    [ -z "$name" ] && continue
    case "$name" in \#*) continue ;; esac
    if [ ! -f "$SMOKE_CORPUS/$(basename "$name")" ]; then
        fail "the manifest names $name, which is not there, so the stub has nothing to answer with"
    fi
done < "$SMOKE_MANIFEST"

#  Guard 5: the round must still be reading when the stop lands, so the delay must outlast the
# grace.
if (( SMOKE_HELD_SECONDS <= SMOKE_STOP_GRACE )); then
    fail "the run holds the in-flight file for $SMOKE_HELD_SECONDS seconds, which does not outlast the stop grace of $SMOKE_STOP_GRACE, so the round cannot be in flight at the stop"
fi
if (( SMOKE_STOP_GRACE < 1 || SMOKE_STOP_GRACE > SMOKE_MAX_GRACE )); then
    fail "the stop grace is $SMOKE_STOP_GRACE, outside the 1 to $SMOKE_MAX_GRACE the run names"
fi

#  Guard 6: the record path, read from the default document the check half opens. The default is
# in the file readers the check half uses, so a run that writes somewhere else leaves the check
# half reading nothing.
check_default=$(sed -n 's#.*"document": os.path.join(HERE, "\([^"]*\)".*#\1#p' "$SOURCES" | head -1)
if [ "$SMOKE_RECORD" != "$ROOT/Tools/smoke/$check_default" ]; then
    fail "the run writes $SMOKE_RECORD, while the check half reads Tools/smoke/$check_default"
fi

#  Guard 7: the ports, which are the machine's and not the run's. The serve container answers on
# one and the stub holds the other, so the guard reads both: a run that named one port for both
# could only have read the answer the stub gave, and the half that reads a port already held reads
# the machine, so it fires only where `ss` is present.
if [ "$SMOKE_PORT" = "$SMOKE_STUB_PORT" ]; then
    fail "the run names $SMOKE_PORT for the boot and for the stub, so the answer it reads cannot be the boot's own"
fi
for port in "$SMOKE_PORT" "$SMOKE_STUB_PORT"; do
    if command -v ss >/dev/null && ss -ltn "sport = :$port" | grep -q LISTEN; then
        fail "the port the run declares, $port, is already held"
    fi
done

#  Guard 8: the wait the run names, read against the cadence it declares, because the round the
# run calls mid-way is one the run can only see by waiting for it: the loop waits before its first
# read, and `POLLING_FREQUENCY` is read as minutes, so a wait shorter than the cadence reports a
# round the run never saw.
if (( SMOKE_WAIT_SECONDS < SMOKE_POLLING_FREQUENCY * 60 + 30 )); then
    fail "the run waits $SMOKE_WAIT_SECONDS for a round, which is shorter than the cadence of $((SMOKE_POLLING_FREQUENCY * 60)) it declares"
fi

#  Guard 9: the address policy the run declares. The target the run fetches from is the loopback
# address, which is a class the policy names as refused, so the round the document reports
# happened only because the run named the escape hatch. The name is read as the file that calls
# the config read writes it, the value forms as the config read's own switch names them, and the
# class as the policy names it.
CONFIG="$ROOT/Sources/RivuletCore/Config/Config.swift"
FETCHER="$ROOT/Sources/RivuletCore/Config/FetcherOptions.swift"
POLICY="$ROOT/Sources/RivuletCore/Reader/NetworkAddressPolicy.swift"
read_name=$(grep -o 'variable: "[A-Z_]*ALLOW_PRIVATE_NETWORKS"' "$FETCHER" | head -1 | sed 's/.*"\(.*\)"/\1/')
if [ "$SMOKE_POLICY_NAME" != "$read_name" ]; then
    fail "the run exports $SMOKE_POLICY_NAME, while the config read takes the flag by $read_name"
fi
classes=$(sed -n '/func isPrivateV4/,/^    }/p' "$POLICY" | grep -o 'case [0-9]*:' | sed 's/case //; s/://')
on_form=$(grep 'case "1", "yes", "true", "on"' "$CONFIG" | head -1)
if printf '%s\n' "$classes" | grep -qx "${SMOKE_TARGET%%.*}"; then
    case "$on_form" in
        *"\"$SMOKE_ALLOW_PRIVATE\""*) ;;
        *) fail "the policy as the run declares it ($SMOKE_ALLOW_PRIVATE) is not a value the switch reads as on, so it refuses the target $SMOKE_TARGET, which is a class the policy names, and no round could have been recorded" ;;
    esac
else
    fail "the target the run declares, $SMOKE_TARGET, is not a class the policy refuses, so the escape hatch the run declares is not what the round it reports needed"
fi

mkdir -p "$SMOKE_WORK/volume"
cp "$SMOKE_ARTIFACT" "$SMOKE_WORK/rivulet"

# Guard 10: the build context. The check half reads the committed Dockerfile, so the file the run
# builds from must be that same file, and the context must hold the file its COPY line names.
read_dockerfile=$(sed -n 's#.*"dockerfile": os.path.join(ROOT, "\([^"]*\)".*#\1#p' "$SOURCES" | head -1)
if [ "$SMOKE_DOCKERFILE" != "$ROOT/$read_dockerfile" ]; then
    fail "the run builds from $SMOKE_DOCKERFILE, while the check half reads $ROOT/$read_dockerfile"
fi
copy_name=$(sed -n 's/^COPY \([^ ]*\).*/\1/p' "$SMOKE_DOCKERFILE" | head -1)
if [ ! -f "$SMOKE_WORK/$copy_name" ]; then
    fail "the build context does not hold $copy_name, which is the file the Dockerfile's COPY line names"
fi

#  Guard 11: the held file's position. The round reads the rows in the order their next_check_at
# lands, which is the order the run created them in, and the run takes its mid-round read at the
# point the records before the held one are answered, so the file the stub holds must be the last
# record the manifest declares. A held file named earlier than the last record was answered before
# that read, so the round the document reports was not mid-way.
last_record=$(grep -v '^#\|^$' "$SMOKE_MANIFEST" | tail -1 | cut -d'|' -f1 | tr -d '[:space:]' || true)
if [ "$(basename "$SMOKE_HELD_FILE")" != "$(basename "$last_record")" ]; then
    fail "the run holds $SMOKE_HELD_FILE, while the last record the manifest declares is $last_record, so the read the run takes after the records before it are answered cannot be mid-round"
fi

#  Guard 12: the gap between the `add` calls. The order the rule reads is the order the values these
# calls put the rows in, and that order is readable only when no two rows share one value, because
# the batch read orders by that column and SQL fixes no order between equal values, so the run names
# a gap that cannot put two rows inside one second. The order the jobs of the round ran in is
# read by no rule, because the pool dispatch fixes none.
if (( SMOKE_ADD_GAP < 2 )); then
    fail "the run leaves $SMOKE_ADD_GAP second between the add calls, which can put two rows inside one value, so the order the rule reads the recorded values in is not readable"
fi

#  Guard 13: the credentials run's prompt count, read from the file the check half reads it from.
# The run feeds one value per prompt the command declares, and the secure reads answer nothing on a
# pipe, so a run that fed fewer values than the file declares answered some prompt with nothing, and
# the login read compared a pair the run never wrote. No document can say which prompt produced
# which value, so the guard reads the count against the file and the rule reads the order as the file
# declares it.
cred_file=$(sed -n 's#.*"integration_credentials": os.path.join(ROOT, "\([^"]*\)".*#\1#p' "$SOURCES" | head -1)
if [ ! -f "$ROOT/$cred_file" ]; then
    fail "the run reads the credentials prompt order from a file that is not there, so the rule has nothing to read it against"
fi
declared=$(grep -c 'prompt: "' "$ROOT/$cred_file" || true)
fed=$(printf '%s\n' "$SMOKE_CRED_FEED" | grep -c . || true)
if [ "$fed" != "$declared" ]; then
    fail "the run feeds $fed values for a command that declares $declared prompts, so a prompt was answered with nothing and the pair the login read compares was not written"
fi

export SMOKE_WORK SMOKE_IMAGE SMOKE_BASE SMOKE_TRIPLE SMOKE_PORT SMOKE_STUB_PORT SMOKE_RECORD
export SMOKE_EVENTS SMOKE_DOCKERFILE SMOKE_HELD_FILE SMOKE_HELD_SECONDS SMOKE_STOP_GRACE
export SMOKE_ARTIFACT SMOKE_CORPUS SMOKE_MANIFEST SMOKE_WAIT_SECONDS SMOKE_FEED SMOKE_CRED_FEED
export SMOKE_USER SMOKE_PASSWORD SMOKE_ERROR_LIMIT SMOKE_BATCH_SIZE SMOKE_POLLING_FREQUENCY
export SMOKE_TARGET SMOKE_POLICY_NAME SMOKE_ALLOW_PRIVATE SMOKE_ADD_GAP

echo "run: $SMOKE_IMAGE from $SMOKE_BASE, artifact $SMOKE_ARTIFACT, port $SMOKE_PORT, stub port $SMOKE_STUB_PORT, target $SMOKE_TARGET, policy $SMOKE_POLICY_NAME=$SMOKE_ALLOW_PRIVATE"
python3 "$COLLECT"
python3 "$CHECK"
