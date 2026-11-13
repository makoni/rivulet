#!/usr/bin/env bash
set -euo pipefail

# Stage 8 DocC build: the catalog read as the tool reads it, written as the archive a site is built
# from, with the pages the symbol graph writes and a link to the markdown version of the pages the
# tool answered markdown for. This is the build half, not the run half: `Scripts/docs.sh` is the run
# half that leaves the document the check half reads, and this script writes the archive a person
# publishes outside this repository. No rule here reads an archive, so what the harness can show for
# this build stops at the catalog read as data. The script is checked by `bash -n` and by its nine
# guards, thirteen read sites, each seen to fail here on the value the usage lines name.

# The tool is called directly, because SwiftPM answers no plugin for the tool, so the symbol graph
# comes from SwiftPM's own subcommand, which answers `dump-symbol-graph` without a plugin. That is
# the half that makes a symbol page possible here at all. `--disable-indexing` is a plugin flag and
# not a `docc convert` flag, so the navigator index is written as the tool writes it. SwiftPM writes
# the graph in the build directory it writes its build in, which the working agreement names as
# generated and never committed. A single build answers for one module, while the graph dir holds
# every module the manifest resolves, so the run copies the one file for the target the manifest
# writes, and that copy is the graph the tool reads.

# What the guards read, and what each can fail on: the output path against the repository, which is
# the half a build that writes inside the tree fails; the catalog against the path the check half
# reads it at; the program the run invokes against the answer it gives for its own run, for the tool
# and for SwiftPM; the base against the base each page the build wrote carries, which is the half a
# build that asks for an empty base fails; the names the markdown manifest carries against the
# markdown files the build wrote; the copy against the file SwiftPM wrote, which is the half a build
# that reads a graph it did not copy fails; the module the copy names against the target the
# manifest writes, which is the half a copy that names another module fails; and each page against
# the link it carries, which is the half a build that wrote no link fails. The guards that read a
# program fail here on a stand-in for that program, which is why this build stays on demand rather
# than in CI. The thirteen read sites, one read for each value a guard names: the output path, the
# catalog path, the tool's answer, SwiftPM's answer, the base value, the base as the page set
# carries it, the manifest, the markdown file as the name set carries it, the copy and the file
# SwiftPM wrote, the module the copy names and the target the manifest writes, and the link as the
# page set carries it. The base is read as the tool writes it, the slashes at each end taken off, so
# the guard, the tool and the link half read one base rather than two forms of it.

# The link is put on every page the build wrote; the hrefs are the routes the build has a markdown
# file for, which with a graph are the pages the symbol graph writes as well as the tutorial, so the
# page the site opens first keeps the link hidden rather than pointing at a file the build never
# wrote.

# Usage, one line per guard, and the first line, which is the build itself, is what the guards run
# after. Each line is run against the value it names:

#   Scripts/build-docs.sh                                                      # the build
#   DOCC_OUTPUT_PATH=<an archive inside the repository> Scripts/build-docs.sh  # the output path
#   docs_catalog=<a path the check half does not read> Scripts/build-docs.sh   # the catalog
#   docs_tool=/bin/false Scripts/build-docs.sh                                 # the tool
#   docs_swiftpm=/bin/false Scripts/build-docs.sh                              # SwiftPM
#   DOCC_HOSTING_BASE_PATH="" Scripts/build-docs.sh                            # the base
#   docs_extra_md=<a name the build wrote no file for> Scripts/build-docs.sh   # the manifest
#   docs_extra_copy=<a copy the build wrote no file for> Scripts/build-docs.sh # the copy
#   docs_extra_module=<a module the copy names for no target> Scripts/build-docs.sh  # the module
#   docs_no_link=1 Scripts/build-docs.sh                                       # the link half

ROOT=$(cd "$(dirname "$0")/.." && pwd)

fail() { printf 'guard: %s\n' "$1"; exit 1; }

# The names read through the same reader the rules use, so this build cannot name a path, a target
# or a page set the check half does not read. One value per line, so a name with a space in it stays
# one value, and each guard reads its list a line at a time.
read_value() {
    python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import parsers as read; print(read.DEFAULTS[sys.argv[2]])' "$ROOT/Tools/docs" "$1"
}

read_target() {
    python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import parsers as read; print(read.manifest_target())' "$ROOT/Tools/docs"
}

read_pages() {
    python3 -c 'import json,sys; print("\n".join(sorted(json.load(open(sys.argv[1]))["tool"]["pages"])))' "$(read_value document)"
}

# The base as the tool writes it: the tool puts the base it is given between slashes, so the value
# the build asks for is the base with every slash at each end taken off, and the guard, the tool and
# the link half read that one value rather than two forms of it.
read_base() {
    printf '%s\n' "${DOCC_HOSTING_BASE_PATH}" | sed 's|^/*||; s|/*$||'
}

answers() {
    "$1" "${@:2}" >/dev/null 2>&1 || fail "the program $1 answers nothing for the run"
}

# The module a symbol graph names, as the file names it: the name the tool reads the pages under.
graph_module() {
    basename "$1" | sed 's/\.symbols\.json$//'
}

# The names the manifest carries, as the archive names them on disk: the lowercased identifier,
# which is the name the markdown half writes the file under.
manifest_names() {
    python3 -c 'import json,sys; from pathlib import Path; out = Path(sys.argv[1]); name = json.load(open(out / "metadata.json"))["bundleID"]; data = json.load(open(out / f"{name}-markdown-manifest.json")); print("\n".join(sorted(one["identifier"].strip("/").lower() for one in data["documents"])))' "$DOCC_OUTPUT_PATH"
}

# The pages the build wrote, one path per line, as the check half reads them: a page is the
# directory with the file the site opens, so the guard reads the page against the page the document
# names.
written_pages() {
    read_pages | while IFS= read -r page; do
        printf '%s\n' "$DOCC_OUTPUT_PATH/$page"
    done
}

export docs_tool=${docs_tool-docc}
export docs_swiftpm=${docs_swiftpm-swift}
export docs_catalog=${docs_catalog-$(read_value catalog)}
export docs_work=${docs_work-$(mktemp -d)}
export docs_graph=${docs_graph-$docs_work/$(read_target).symbols.json}
export docs_extra_md=${docs_extra_md-}
export docs_extra_copy=${docs_extra_copy-}
export docs_extra_module=${docs_extra_module-}
export docs_no_link=${docs_no_link-}
export DOCC_OUTPUT_PATH=${DOCC_OUTPUT_PATH-$HOME/Downloads/rivulet}
export DOCC_HOSTING_BASE_PATH=${DOCC_HOSTING_BASE_PATH-docs/rivulet}

value_guards() {
    case "$DOCC_OUTPUT_PATH" in
        "$ROOT"/*) fail "the build wrote the archive at $DOCC_OUTPUT_PATH, which is inside the repository" ;;
    esac
    [ "$docs_catalog" = "$(read_value catalog)" ] ||
        fail "the build reads the catalog at a path the check half does not read"
    answers "$docs_tool" convert --help
    answers "$docs_swiftpm" package dump-symbol-graph --help
    [ -n "$DOCC_HOSTING_BASE_PATH" ] ||
        fail "the build asks for an empty base, which answers the root the site is served at"
}

answer_guards() {
    while IFS= read -r page; do
        grep -q "baseUrl = \"/$docs_base/\"" "$page" ||
            fail "the page $page carries a base the build did not ask the tool for"
    done < <(written_pages)

    while IFS= read -r name; do
        [ -n "$name" ] || continue
        [ -f "$DOCC_OUTPUT_PATH/data/$name.md" ] ||
            fail "the manifest names $name, which the build wrote no markdown file for"
    done < <(manifest_names; printf '%s\n' "$docs_extra_md")

    while IFS= read -r file; do
        [ -n "$file" ] || continue
        cmp -s "$file" "$graph_wrote/$(basename "$file")" ||
            fail "the tool reads the copy $file, which is not the file SwiftPM wrote"
    done < <(printf '%s\n' "$docs_graph"; printf '%s\n' "$docs_extra_copy")

    while IFS= read -r module; do
        [ -n "$module" ] || continue
        [ "$module" = "$(read_target)" ] ||
            fail "the copy names the module $module, which is not the target the manifest writes"
    done < <(graph_module "$docs_graph"; printf '%s\n' "$docs_extra_module")

    while IFS= read -r page; do
        grep -q 'id="docc-markdown-link"' "$page" ||
            fail "the page $page carries no markdown link, which is the half a build that wrote no link"
    done < <(written_pages)
}

# The build: SwiftPM writes the graph, the run copies the file for the target the manifest writes,
# then the tool writes the archive from the catalog and the copy, then the link half puts the
# markdown link on each page the archive has, with the routes the build has a markdown file for
# written into the page as the hrefs the page can open.
build_symbol_graph() {
    cd "$ROOT"
    answer=$("$docs_swiftpm" package --scratch-path "$ROOT/.build" dump-symbol-graph 2>&1 | tail -1)
    graph_wrote=${answer#Files written to }
    mkdir -p "$docs_work"
    cp "$graph_wrote/$(read_target).symbols.json" "$docs_graph"
}

build_archive() {
    rm -rf "$DOCC_OUTPUT_PATH"
    mkdir -p "$(dirname "$DOCC_OUTPUT_PATH")"
    "$docs_tool" convert "$docs_catalog" \
        --additional-symbol-graph-dir "$docs_work" \
        --output-path "$DOCC_OUTPUT_PATH" \
        --transform-for-static-hosting \
        --hosting-base-path "$docs_base" \
        --enable-experimental-markdown-output \
        --enable-experimental-markdown-output-manifest
}

add_markdown_link() {
    python3 - "$DOCC_OUTPUT_PATH" "$docs_base" <<'PY'
import json
import os
import sys
from pathlib import Path

output = Path(sys.argv[1])
base = sys.argv[2]
marker = 'id="docc-markdown-link"'

manifest = output / f"{json.load(open(output / 'metadata.json'))['bundleID']}-markdown-manifest.json"
routes = sorted(one["identifier"].strip("/").lower() for one in json.load(open(manifest))["documents"])

link_html = (
    '<a id="docc-markdown-link" href="#" aria-label="Open Markdown version" '
    'style="position:fixed;right:16px;bottom:16px;z-index:2147483647;padding:8px 12px;'
    'border-radius:9999px;background:rgba(255,255,255,0.94);border:1px solid rgba(0,0,0,0.08);'
    'box-shadow:0 2px 8px rgba(0,0,0,0.18);color:#06c;font:500 13px -apple-system,'
    'BlinkMacSystemFont,sans-serif;text-decoration:none" hidden>Markdown</a>'
)

script_html = """
<script>
(function () {
  const link = document.getElementById("docc-markdown-link");
  if (!link) return;
  const hrefs = %s;
  const base = "%s";

  function trimmed(value) {
    return value.replace(/^\\/+/, "").replace(/\\/+$/, "");
  }

  function route(pathname) {
    const prefix = "/" + base + "/";
    let path = base && pathname.startsWith(prefix) ? pathname.slice(prefix.length) : pathname;
    return trimmed(path.replace(/index\\.html$/, ""));
  }

  function update() {
    const href = hrefs[route(window.location.pathname)];
    link.hidden = !href;
    if (href) link.href = href;
    else link.removeAttribute("href");
  }

  for (const name of ["pushState", "replaceState"]) {
    const original = history[name];
    history[name] = function () {
      const result = original.apply(this, arguments);
      queueMicrotask(update);
      return result;
    };
  }

  window.addEventListener("popstate", update);
  update();
})();
</script>
"""

def hrefs_for(page):
    hrefs = {}
    for name in routes:
        markdown = output / "data" / f"{name}.md"
        if markdown.exists():
            hrefs[name] = os.path.relpath(markdown, page.parent).replace(os.sep, "/")
    return hrefs


for page in sorted(output.rglob("index.html")):
    contents = page.read_text()
    if marker in contents:
        continue

    route = page.relative_to(output).as_posix()
    route = route[:-len("/index.html")] if route.endswith("/index.html") else ""
    hrefs = hrefs_for(page)
    page_link = link_html.replace('href="#"', f'href="{hrefs.get(route, "#")}"', 1)
    page.write_text(contents.replace("</body>", f"{page_link}{script_html % (json.dumps(hrefs), base)}</body>"))
PY
}

# The run: the guards that read what this build declares, the build, then the guards that read what
# the build wrote. A build that writes no link is the half the link guard reads; a build that asks
# for an empty base is the half the base guard reads; a build that reads a copy it did not write is
# the half the copy guard reads; a copy that names another module is the half the module guard
# reads.
value_guards
docs_base=$(read_base)
build_symbol_graph
build_archive
[ -n "$docs_no_link" ] || add_markdown_link
answer_guards

printf 'archive: %s\nbase: %s\ngraph: %s\ncopy: %s\npages: %s\nmarkdown: %s\n' \
    "$DOCC_OUTPUT_PATH" "$docs_base" "$graph_wrote" "$docs_graph" \
    "$(find "$DOCC_OUTPUT_PATH" -name index.html | wc -l | tr -d ' ')" \
    "$(manifest_names | wc -l | tr -d ' ')"
