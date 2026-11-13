#!/usr/bin/env bash
set -euo pipefail

# Stage 8 DocC build: the catalog read as the tool reads it, written as the archive a site is built
# from, with a link to the markdown version of each page the tool answered markdown for. This is the
# build half, not the run half: `Scripts/docs.sh` is the run half that leaves the document the check
# half reads, and this script writes the archive a person publishes outside this repository. No rule
# here reads an archive, so what the harness can show for this build stops at the catalog read as
# data. The script is checked by `bash -n` and by its six guards, twenty read sites, each seen to
# fail here on the value the usage lines name.

# The tool is called directly, because SwiftPM answers no plugin for the symbol graph the tool reads
# on this toolchain, which is also why the build writes no symbol page. `--disable-indexing` is a
# plugin flag and not a `docc convert` flag, so the navigator index is written as the tool
# writes it.

# What the guards read, and what each can fail on: the output path against the repository, which is
# the half a build that writes inside the tree fails; the catalog against the path the check half
# reads it at; the program the run invokes against the answer it gives for its own run; the base path
# against the base each page the build wrote carries, which is the half a build that asks for an
# empty base fails; the names the markdown manifest carries against the markdown files the build
# wrote; and each page the build wrote against the link it carries, which is the half a build that
# wrote no link fails. The guard that reads the tool fails only on a machine without it, which is
# why this build stays on demand rather than in CI. The twenty read sites: the output path reads
# one, the catalog reads one, the tool reads one answer, the base path reads its own value and the
# base each of the seven pages the build wrote carries, the markdown half reads the manifest and one
# file for each name it carries, and the link half reads one for each page the build wrote.

# The link is written for the pages the tool answered markdown for, which on this toolchain is the
# tutorial: the pages the catalog writes as chapters answer markdown for the tutorial alone. The
# routes the build has a markdown file for are written into the page as the hrefs the page can open,
# so a page outside that set keeps the link hidden rather than pointing at a file the build never
# wrote.

# Usage, one guard per line, each run against the value that line names:

#   Scripts/build-docs.sh                                                      # the build, then the guards
#   DOCC_OUTPUT_PATH=<an archive inside the repository> Scripts/build-docs.sh  # the output path
#   docs_catalog=<a path the check half does not read> Scripts/build-docs.sh   # the catalog
#   docs_tool=/bin/false Scripts/build-docs.sh                                 # the tool
#   DOCC_HOSTING_BASE_PATH="" Scripts/build-docs.sh                            # the base path
#   docs_extra_md=<a name the build wrote no file for> Scripts/build-docs.sh   # the manifest
#   docs_no_link=1 Scripts/build-docs.sh                                       # the link half

ROOT=$(cd "$(dirname "$0")/.." && pwd)

fail() { printf 'guard: %s\n' "$1"; exit 1; }

# The catalog read through the same reader the rules use, so this build cannot name a path the check
# half does not read.
path_of() {
    python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import parsers as read; print(read.DEFAULTS[sys.argv[2]])' "$ROOT/Tools/docs" "$1"
}

tool_answers() {
    "$1" "${@:2}" >/dev/null 2>&1 || fail "the tool $1 answers nothing for the run"
}

# The pages the build wrote, one path per line, as the archive lays them out: a page is the
# directory with the file the site opens.
written_pages() {
    find "$DOCC_OUTPUT_PATH" -name index.html | sort
}

# The names the manifest carries, as the archive names them on disk: the lowercased identifier,
# which is the name the markdown half writes the file under.
manifest_names() {
    python3 -c 'import json,sys; from pathlib import Path; out = Path(sys.argv[1]); name = json.load(open(out / "metadata.json"))["bundleID"]; data = json.load(open(out / f"{name}-markdown-manifest.json")); print("\n".join(sorted(one["identifier"].strip("/").lower() for one in data["documents"])))' "$DOCC_OUTPUT_PATH"
}

export docs_tool=${docs_tool-docc}
export docs_catalog=${docs_catalog-$(path_of catalog)}
export docs_extra_md=${docs_extra_md-}
export docs_no_link=${docs_no_link-}
export DOCC_OUTPUT_PATH=${DOCC_OUTPUT_PATH-$HOME/Downloads/rivulet}
export DOCC_HOSTING_BASE_PATH=${DOCC_HOSTING_BASE_PATH-docs/rivulet}

value_guards() {
    case "$DOCC_OUTPUT_PATH" in
        "$ROOT"/*) fail "the build wrote the archive at $DOCC_OUTPUT_PATH, which is inside the repository" ;;
    esac
    [ "$docs_catalog" = "$(path_of catalog)" ] ||
        fail "the build reads the catalog at a path the check half does not read"
    tool_answers "$docs_tool" convert --help
    [ -n "$DOCC_HOSTING_BASE_PATH" ] ||
        fail "the build asks for an empty base path, which answers the root the site is served at"
}

answer_guards() {
    for page in $(written_pages); do
        grep -q "baseUrl = \"/${DOCC_HOSTING_BASE_PATH}/\"" "$page" ||
            fail "the page $page carries a base the build did not ask the tool for"
    done
    for name in $(manifest_names) $docs_extra_md; do
        [ -f "$DOCC_OUTPUT_PATH/data/$name.md" ] ||
            fail "the manifest names $name, which the build wrote no markdown file for"
    done
    for page in $(written_pages); do
        grep -q 'id="docc-markdown-link"' "$page" ||
            fail "the page $page carries no markdown link, which is the half a build that wrote no link"
    done
}

# The build: the tool writes the archive, then the half that opens each page the archive has and
# puts the markdown link on it, with the routes the build has a markdown file for written into the
# page as the hrefs the page can open, so a page outside that set keeps the link hidden.
build_archive() {
    rm -rf "$DOCC_OUTPUT_PATH"
    mkdir -p "$(dirname "$DOCC_OUTPUT_PATH")"
    "$docs_tool" convert "$docs_catalog" \
        --output-path "$DOCC_OUTPUT_PATH" \
        --transform-for-static-hosting \
        --hosting-base-path "$DOCC_HOSTING_BASE_PATH" \
        --enable-experimental-markdown-output \
        --enable-experimental-markdown-output-manifest
}

add_markdown_link() {
    python3 - "$DOCC_OUTPUT_PATH" "$DOCC_HOSTING_BASE_PATH" <<'PY'
import json
import os
import sys
from pathlib import Path

output = Path(sys.argv[1])
base = sys.argv[2].strip("/")
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

for page in sorted(output.rglob("index.html")):
    contents = page.read_text()
    if marker in contents:
        continue

    route = page.relative_to(output).as_posix()
    route = route[:-len("/index.html")] if route.endswith("/index.html") else ""
    hrefs = {}
    for name in routes:
        markdown = output / "data" / f"{name}.md"
        if markdown.exists():
            hrefs[name] = os.path.relpath(markdown, page.parent).replace(os.sep, "/")
    href = hrefs.get(route, "#")
    page_link = link_html.replace('href="#"', f'href="{href}"', 1)
    page.write_text(contents.replace("</body>", f"{page_link}{script_html % (json.dumps(hrefs), base)}</body>"))
PY
}

# The run: the guards that read what this build declares, then the build, then the guards that read
# what the build wrote. A build that writes no link is the half the link guard reads; a build that
# asks for an empty base is the half the base guard reads.
value_guards
build_archive
[ -n "$docs_no_link" ] || add_markdown_link
answer_guards

printf 'archive: %s\nbase path: %s\npages: %s\nmarkdown: %s\n' \
    "$DOCC_OUTPUT_PATH" "$DOCC_HOSTING_BASE_PATH" "$(written_pages | wc -l | tr -d ' ')" \
    "$(manifest_names | tr '\n' ' ')"
