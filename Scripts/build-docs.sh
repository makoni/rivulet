#!/usr/bin/env bash
set -euo pipefail

# Builds the DocC archive for RivuletCore as a static site: the catalog in
# `Sources/RivuletCore/RivuletCore.docc` plus the symbol pages from SwiftPM's symbol graph, with a
# Markdown version of each page and a "Markdown" link on the pages that have one. The archive is
# written outside the repository and published by hand; nothing here runs in CI.
#
# SwiftPM has no DocC plugin in this package, so the symbol graph comes from
# `swift package dump-symbol-graph` and the archive from the toolchain's `docc convert`.
#
# Environment (optional):
#   DOCC_OUTPUT_PATH        where the archive goes (default ~/Downloads/rivulet; must be outside
#                           the repository)
#   DOCC_HOSTING_BASE_PATH  the path the site is served under (default docs/rivulet)
#
# Usage: Scripts/build-docs.sh

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TARGET=RivuletCore
CATALOG="$ROOT/Sources/RivuletCore/RivuletCore.docc"
DOCC_OUTPUT_PATH=${DOCC_OUTPUT_PATH-$HOME/Downloads/rivulet}
DOCC_HOSTING_BASE_PATH=${DOCC_HOSTING_BASE_PATH-docs/rivulet}
# The tool puts the base between slashes itself, so strip any the value carries.
BASE=$(printf '%s\n' "$DOCC_HOSTING_BASE_PATH" | sed 's|^/*||; s|/*$||')

fail() { printf 'build-docs: %s\n' "$1" >&2; exit 1; }

case "$DOCC_OUTPUT_PATH" in
    "$ROOT"/*) fail "DOCC_OUTPUT_PATH is inside the repository; generated archives are never committed" ;;
esac
[ -n "$BASE" ] || fail "DOCC_HOSTING_BASE_PATH is empty"
command -v docc >/dev/null || fail "docc is not on PATH (it ships with the Swift toolchain)"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# The graph directory holds every module the manifest resolves; DocC gets only the target's file.
cd "$ROOT"
answer=$(swift package --scratch-path "$ROOT/.build" dump-symbol-graph 2>&1 | tail -1)
graphs=${answer#Files written to }
[ -f "$graphs/$TARGET.symbols.json" ] || fail "SwiftPM wrote no symbol graph for $TARGET ($answer)"
cp "$graphs/$TARGET.symbols.json" "$WORK/"

rm -rf "$DOCC_OUTPUT_PATH"
mkdir -p "$(dirname "$DOCC_OUTPUT_PATH")"
docc convert "$CATALOG" \
    --additional-symbol-graph-dir "$WORK" \
    --output-path "$DOCC_OUTPUT_PATH" \
    --transform-for-static-hosting \
    --hosting-base-path "$BASE" \
    --enable-experimental-markdown-output \
    --enable-experimental-markdown-output-manifest

add_markdown_link() {
    python3 - "$DOCC_OUTPUT_PATH" "$BASE" <<'PY'
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

add_markdown_link

printf 'archive: %s\nbase: /%s/\npages: %s\n' "$DOCC_OUTPUT_PATH" "$BASE" \
    "$(find "$DOCC_OUTPUT_PATH" -name index.html | wc -l | tr -d ' ')"
