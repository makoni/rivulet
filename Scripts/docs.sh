#!/usr/bin/env bash
set -euo pipefail

# Stage 8 DocC run: the catalog read as the tool reads it. This is the run half of the DocC slice;
# the rules are in `Tools/docs/docs_check.py`, which reads the document this run leaves behind
# rather than a build, and `Tools/docs/collect.py` writes that document from the tool's answer. It
# is not a test, and the probe round is what CI runs; the shell is checked here by `bash -n` and by
# the guards below.

# What the guards read, and what each can fail on: the record path against the document the check
# half reads in `Tools/docs/parsers.py`; the catalog against the path the check half reads it at;
# the program
# the run invokes against the answer it gives for the run; the copy of the catalog this run wrote
# against the bytes each committed catalog file has, which is the run being allowed to copy and not
# to change; the asset the table of contents names against the files the copy has; the build path
# against the repository, which is the half a run that writes inside the tree fails; the page files
# this run declares against the
# pages the tool built for the copy; and the document this run wrote against the answer the tool
# gave, which is the half a run that never ran cannot show. The guard that reads the tool fails only
# on a machine without it, which is the point of the publishing job; the guards that read what this
# run wrote fail only on a run. The eight guards are thirteen read sites: the record path reads one,
# the catalog
# reads one, the tool reads one answer, the copies read seven, one for each file the copy has, the
# asset reads one, the build path reads one, the page set reads one, and the document reads one
# answer. All eight were seen to fail here, on the values the usage lines name.

# This run reads the catalog and writes its build outside the repository, because the tool writes a
# site and a build inside the tree is an artifact the working agreement does not allow to
# be committed.

# Usage, one guard per line, each run against the value that line names:

#   Scripts/docs.sh                                                      # the run, then the guards
#   docs_record=<a path the check half does not read> Scripts/docs.sh            # the record path
#   docs_catalog=<a path the check half does not read> Scripts/docs.sh           # the catalog
#   docs_tool=/bin/false Scripts/docs.sh                                           # the tool
# docs_extra_byte=x Scripts/docs.sh # the seven copies
#   docs_extra_asset=<an asset the catalog has no file for> Scripts/docs.sh        # the asset
#   docs_out=<a build inside the repository> Scripts/docs.sh                     # the build path
#   docs_extra_page=<a page the tool built no page for> Scripts/docs.sh            # the page set
# docs_empty=1 Scripts/docs.sh # the document half, through the data writer

ROOT=$(cd "$(dirname "$0")/.." && pwd)
export docs_work=${docs_work:-$(mktemp -d)}
export docs_record=${docs_record:-$ROOT/Tools/docs/docs.json}
export docs_tool=${docs_tool:-docc}
export docs_extra_page=${docs_extra_page:-}
export docs_extra_asset=${docs_extra_asset:-}
export docs_extra_byte=${docs_extra_byte:-}

fail() { printf 'guard: %s\n' "$1"; exit 1; }

# A value read through the same reader the rules use, so a guard cannot name a path or a shape the
# check half does not read. One path per line.
path_of() {
    python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import parsers as read; print(read.DEFAULTS[sys.argv[2]])' "$ROOT/Tools/docs" "$1"
}

read_value() {
    python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import parsers as read; value = eval(sys.argv[2], vars(read)); print("\n".join(value) if isinstance(value, (list, set, tuple)) else value)' "$ROOT/Tools/docs" "$1"
}

sha_of() {
    python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"
}

tool_answers() {
    "$1" "${@:2}" >/dev/null 2>&1 || fail "the tool $1 answers nothing for the run"
}

# The copy keeps the catalog name the tool reads it as, because the tool reads a directory as a
# catalog only when the name carries the extension, which is the half the copy guard reads. The copy
# is the same set the check half reads: the page files and the assets, split the way the tool
# reads them.
build_copy() {
    export docs_catalog=${docs_catalog:-$(path_of catalog)}
    export docs_out=${docs_out:-$docs_work/site}
    export docs_copy="$docs_work/$(basename "$(path_of catalog)")"
    mkdir -p "$docs_copy"
    for file in $(read_value 'catalog_files()[0] + catalog_files()[1]'); do
        mkdir -p "$(dirname "$docs_copy/$file")"
        cat "$(path_of catalog)/$file" >"$docs_copy/$file"
        [ -z "$docs_extra_byte" ] || printf '%s' "$docs_extra_byte" >>"$docs_copy/$file"
    done
}

value_guards() {
    [ "$docs_record" = "$(path_of document)" ] ||
        fail "the record path $docs_record is not the document the check half reads"
    [ "$docs_catalog" = "$(path_of catalog)" ] ||
        fail "the run reads the catalog at a path the check half does not read"
    tool_answers "$docs_tool" convert --help
    for file in $(read_value 'catalog_files()[0] + catalog_files()[1]'); do
        [ "$(read_value "digest('$file')")" = "$(sha_of "$docs_copy/$file")" ] ||
            fail "the run wrote a copy of $file that is not the bytes the committed catalog file has"
    done
    for asset in $(read_value 'catalog_files()[1]') $docs_extra_asset; do
        [ -f "$docs_copy/$asset" ] ||
            fail "the table of contents names the asset $asset, which is not a file the copy has"
    done
    case "$docs_out" in
        "$ROOT"/*) fail "the run wrote its build at $docs_out, which is inside the repository" ;;
    esac
}

answer_guards() {
    for file in $(read_value 'catalog_files()[0]') $docs_extra_page; do
        name=$(basename "$file" | sed 's/\.[^.]*$//' | tr 'A-Z' 'a-z')
        built=$(find "$docs_out" -type d -name "$name" | head -1)
        [ -n "$built" ] || fail "the run declares the page $file, which the tool built no page for"
    done
}

# The run: the copy, the guards that read what this run declares, the tool, the guard that reads its
# answer, then the document. The run asserts nothing about what the tool answers for the pages it
# builds, so a tool that answers nothing is a run that read nothing; the rules read the answer as
# data, and the guard that reads the document is the half a run cannot pass twice.
build_copy
value_guards
"$docs_tool" convert "$docs_copy" --output-dir "$docs_out" >"$docs_work/answer.txt" 2>/dev/null
answer_guards
python3 "$ROOT/Tools/docs/collect.py"

[ -z "${docs_empty:-}" ] || {
    answer=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("tool", {}))' "$docs_record")
    [ "$answer" != "{}" ] || fail "the document carries no answer for the tool"
}
cat "$docs_record"
