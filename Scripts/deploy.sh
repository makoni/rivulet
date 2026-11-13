#!/usr/bin/env bash
set -euo pipefail

# Stage 8 deploy run: the three deploy artifacts read as the data the two tools read them as. This
# is the run half of the deploy slice; the rules are in `Tools/deploy/deploy_check.py`, which reads
# the document this run leaves behind rather than a container or a service, and
# `Tools/deploy/collect.py` writes that document from the two tool answers. It is not a test and it
# does not run in CI: the CI container has neither Docker nor systemd, so the run is on demand, and
# the shell is checked here by `bash -n` and by the guards below.

# What the guards read, and what each can fail on: the record path against the document the check
# half reads in `Tools/deploy/parsers.py`; the three committed artifacts against the paths the check
# half reads them at; the file this run builds against the gitignored name the file a deployment
# reads has; the four copies this run wrote against the bytes the committed files have, which is the
# run being allowed to copy and not to change; the two tools against the answer each gives for the
# run; the first line the unit tool printed against the file this run read the unit as, which is the
# name it passed for the finding about the program and the copy it wrote for a finding about a key;
# the service key the compose writes against the service this run declares; and the document this
# run wrote against the answer both tools gave, which is the half a run that never ran cannot show.
# The guards that read a tool fail only on a machine without it, which is the point of the job; the
# guards that read what this run wrote fail only on a run. The eight guards are fourteen read sites:
# the record path reads one, the three committed artifacts read three, the env name reads one, the
# copies read four, the tools read two answers, the unit line reads one, the service key reads one,
# and the document reads two, one for each answer it carries. Eleven of the fourteen were seen to
# fail here, because the copy item fires on the first of the four copies it reads and the document
# item on the first of the two answers it reads, which is the order this run reads them in.

# This run reads and never builds: the tool resolves the compose without reading the artifact the
# Dockerfile names, so the published port is read as a value the file writes and never as a port the
# machine holds, and the unit is read as a parse, so the program the unit names is read as the tool
# finding rather than as a service that ran.

# Usage, one guard per line, each run against the value that line names:

#   Scripts/deploy.sh                                        # the run, then the guards
#   deploy_record=<a path the check half does not read> Scripts/deploy.sh     # the record path
#   deploy_compose=<a path the check half does not read> Scripts/deploy.sh    # the compose artifact
#   deploy_unit=<a path the check half does not read> Scripts/deploy.sh        # the unit artifact
#   deploy_example=<a path the check half does not read> Scripts/deploy.sh     # the example artifact
#   deploy_env_name=<a name .gitignore does not carry> Scripts/deploy.sh       # the env name
#   deploy_extra_byte=x Scripts/deploy.sh                                           # the four copies
#   deploy_compose_tool=/bin/false Scripts/deploy.sh                             # the compose tool
#   deploy_analyze_tool=/bin/false Scripts/deploy.sh                             # the unit tool
#   deploy_unit_named=<a name the tool line does not carry> Scripts/deploy.sh   # the unit name
#   deploy_service=<a name the compose writes no key for> Scripts/deploy.sh     # the service key
#   deploy_empty=1 Scripts/deploy.sh                                               # the document half, through the data writer

# The guards that read a value this run declares run before the document is written, so a run that
# fails one of them leaves the document the previous run wrote alone.

ROOT=$(cd "$(dirname "$0")/.." && pwd)
export deploy_work=${deploy_work:-$(mktemp -d)}
export deploy_record=${deploy_record:-$ROOT/Tools/deploy/deploy.json}
export deploy_project=${deploy_project:-rivulet}
export deploy_compose_tool=${deploy_compose_tool:-docker}
export deploy_analyze_tool=${deploy_analyze_tool:-systemd-analyze}
export deploy_env_name=${deploy_env_name:-.env}
export deploy_service=${deploy_service:-rivulet}
export deploy_unit_named=${deploy_unit_named:-rivulet.service}
export deploy_compose=${deploy_compose:-$ROOT/deploy/compose.yml}
export deploy_unit=${deploy_unit:-$ROOT/deploy/rivulet.service}
export deploy_example=${deploy_example:-$ROOT/.env.example}

fail() { printf 'guard: %s\n' "$1"; exit 1; }

# A value read through the same reader the rules use, so a guard cannot name a path or a key the
# check half does not read.
path_of() {
    python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import parsers as read; print(read.DEFAULTS[sys.argv[2]])' "$ROOT/Tools/deploy" "$1"
}

read_value() {
    python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import parsers as read; print(eval(sys.argv[2], vars(read)))' "$ROOT/Tools/deploy" "$1"
}

sha_of() {
    python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"
}

copy_of() {
    case "$1" in
        compose) printf '%s/deploy/compose.yml\n' "$deploy_work" ;;
        unit) printf '%s/deploy/rivulet.service\n' "$deploy_work" ;;
        example) printf '%s/%s\n' "$deploy_work" "$deploy_env_name" ;;
        dockerfile) printf '%s/Dockerfile\n' "$deploy_work" ;;
    esac
}

tool_answers() {
    "$1" "${@:2}" >/dev/null 2>&1 || fail "the tool $1 answers nothing for the run"
}

build_copies() {
    mkdir -p "$deploy_work/deploy"
    for name in compose unit example dockerfile; do
        copy="$(copy_of "$name")"
        export deploy_copy_$name="$copy"
        cat "$(path_of "$name")" >"$copy"
        [ -z "${deploy_extra_byte:-}" ] || printf '%s' "$deploy_extra_byte" >>"$copy"
    done
}

run_guards() {
    [ "$deploy_record" = "$(path_of document)" ] ||
        fail "the record path $deploy_record is not the document the check half reads"
    [ "$(path_of compose)" = "$deploy_compose" ] ||
        fail "the run reads the compose at a path the check half does not read"
    [ "$(path_of unit)" = "$deploy_unit" ] ||
        fail "the run reads the unit at a path the check half does not read"
    [ "$(path_of example)" = "$deploy_example" ] ||
        fail "the run reads the example at a path the check half does not read"
    [ "$deploy_env_name" = "$(read_value 'env_file_name()')" ] ||
        fail "the run builds $deploy_env_name, which is not the gitignored name the file a deployment reads has"
    for name in compose unit example dockerfile; do
        [ "$(read_value "digest(\"$name\")")" = "$(sha_of "$(copy_of "$name")")" ] ||
            fail "the run wrote a copy of $name that is not the bytes the committed file has"
    done
    [ "$deploy_service" = "$(read_value 'list(compose_tree()["services"])[0]')" ] ||
        fail "the run declares the service $deploy_service, which is not the key the compose writes"
    tool_answers "$deploy_compose_tool" compose version
    tool_answers "$deploy_analyze_tool" --version
    first=$(cd "$deploy_work/deploy" && "$deploy_analyze_tool" verify "$deploy_unit_named" 2>&1 | head -1 || true)
    [ -n "$first" ] || fail "the unit tool answered no line for the run"
    named=$(printf '%s' "$first" | cut -d: -f1)
    [ "$named" = "$deploy_unit_named" ] || [ "$named" = "$(copy_of unit)" ] ||
        fail "the line names $named, not the file the run read the unit as ($deploy_unit_named, or the copy it wrote at $(copy_of unit))"
}

# The run: the copies, the guards, the two tools, then the document. The run asserts nothing about
# what the tools answer, so a tool that answers nothing is a run that read nothing; the rules read
# the answers as data, and the guard that reads the document is the half a run cannot pass twice.
build_copies
run_guards
python3 "$ROOT/Tools/deploy/collect.py"

for key in compose analyze; do
    length=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1])).get(sys.argv[2], {})))' "$deploy_record" "$key")
    [ "$length" != "0" ] || fail "the document carries no answer for the $key tool"
done
cat "$deploy_record"
