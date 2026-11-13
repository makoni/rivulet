#!/usr/bin/env python3
"""The parsers the DocC check half reads the catalog, the pages and the tool answer with.

Split from the rules the way `Tools/clients/parsers.py` is split from the client-matrix check half:
this file turns files into shapes and reports nothing, so the rule list stays the readable part.
Every function here is what one rule reads, so a crafted input in `probes.py` changes the parsed
form and never a file, and the round hashes every file named here before and after.

What the round reads as data: the document the run left, which carries the answer the DocC tool gave
for the catalog - the pages it built, the findings it answered, and the program the run invoked; the
catalog as the shapes its pages write; the sources the rules read the names and the values against -
the manifest, the dispatch, the config parser, the two route files, the storage wrapper and the
free-space check; the committed example, which is where the values the pages write are read against;
the client matrix, which is where the client names are read against; the plan table and the root
README, which are the two documents the stage-state rule reads; the contents table and the documents
it names; the report document, which is where the two lists are read against the check half; and the
Swift sources, read for the public declarations and the comment each one has.

The shapes this file reads are the keys one page writes, named in `PAGE_KEYS`, together with the
keys `build()` writes, so the coverage rule can read which rule reads which shape. The child
directives the tool requires, the directive kind, and the version line the tool answers for itself
are named in `docs_check.py` as the part no rule reads.

Usage: read by `docs_check.py`, which names the files it needs.
"""

import hashlib
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

DEFAULTS = {
    "document": os.path.join(ROOT, "Tools", "docs", "docs.json"),
    "catalog": os.path.join(ROOT, "Sources", "RivuletCore", "RivuletCore.docc"),
    "manifest": os.path.join(ROOT, "Package.swift"),
    "cli": os.path.join(ROOT, "Sources", "RivuletApp", "RivuletCLI.swift"),
    "config": os.path.join(ROOT, "Sources", "RivuletCore", "Config", "Config.swift"),
    "fetcher": os.path.join(ROOT, "Sources", "RivuletCore", "Config", "FetcherOptions.swift"),
    "routes": os.path.join(ROOT, "Sources", "RivuletApp", "Routes", "GoogleReaderRoutes.swift"),
    "fever_routes": os.path.join(ROOT, "Sources", "RivuletApp", "Routes", "FeverRoutes.swift"),
    "storage": os.path.join(ROOT, "Sources", "RivuletCore", "Storage", "SQLiteStorage.swift"),
    "free_space": os.path.join(ROOT, "Sources", "RivuletCore", "Storage", "FreeSpaceCheck.swift"),
    "example": os.path.join(ROOT, ".env.example"),
    "clients": os.path.join(ROOT, "docs", "clients.md"),
    "readme": os.path.join(ROOT, "README.md"),
    "plan": os.path.join(ROOT, "docs", "plan", "README.md"),
    "contents": os.path.join(ROOT, "docs", "README.md"),
    "report": os.path.join(ROOT, "docs", "docc.md"),
    "docs_dir": os.path.join(ROOT, "docs"),
    "sources": os.path.join(ROOT, "Sources"),
}

# The phrase each page states a value with, read as the value the source that writes it carries. The
# pragma, the factor and the listener are read on the line that states the marker with these words.
VALUE_PHRASES = {"pragma": "synchronous to", "factor": "factor it uses",
                 "listener": "loopback listener"}

# The shapes one page writes, which is what the coverage rule reads against the bookkeeping.
PAGE_KEYS = ("path", "kind", "args", "children", "references", "images", "fenced", "calls", "flags",
             "sets", "values", "stated", "routes", "clients", "links", "repo_paths", "version",
             "todo")

REPORT_SECTIONS = ("The rules this check half reads", "What this harness cannot show")


def text(name):
    """The committed file read as the bytes it has."""
    return open(DEFAULTS[name], encoding="utf-8").read()


def repo_name(path):
    """A path as the repository root names it, which is the form the document records.

    The run records its record path and its catalog path this way, so the rule that reads them reads
    the same name on the machine that ran it and on the machine that runs the probe round; the build
    path is recorded as the run wrote it, because it is the part of the run that is outside
    the repository.
    """
    return os.path.relpath(path, ROOT)


def document():
    """The document the run left behind, read as the JSON it wrote."""
    with open(DEFAULTS["document"], encoding="utf-8") as handle:
        return json.load(handle)


def catalog_files():
    """The files the catalog has, split as the tool reads them: pages and assets."""
    pages, assets = [], []
    for path, _, names in os.walk(DEFAULTS["catalog"]):
        for name in sorted(names):
            full = os.path.relpath(os.path.join(path, name), DEFAULTS["catalog"])
            (pages if name.endswith(".tutorial") else assets).append(full)
    return sorted(pages), sorted(assets)


def catalog_file(file):
    """One catalog file as the committed path the run read its copy from."""
    return os.path.join(DEFAULTS["catalog"], file)


def digest(file):
    """The bytes a committed catalog file has, as the run compares them with the copy it wrote."""
    return hashlib.sha256(open(catalog_file(file), "rb").read()).hexdigest()


def fenced(body):
    """The lines a page writes inside its fences, which are the lines a person runs.

    A fence is read at the indentation the page writes it at, because the tool reads a fenced block
    inside a directive with the page's own indentation, so a fence inside `@Intro` is the same shape
    as a fence at the top level and the indentation is not part of what the fence says.
    """
    found, inside = [], False
    for line in body.splitlines():
        if line.strip().startswith("```"):
            inside = not inside
        elif inside:
            found.append(line.strip())
    return found


def spans(body):
    """The inline code a page writes, as the page writes it."""
    return [match.group(1) for match in re.finditer(r"`([^`\n]+)`", body)]


def directive(body):
    """The top directive of a page, as the tool reads it: its kind and the arguments it carries."""
    match = re.search(r"@(\w+)(?:\(([^)]*)\))?", body)
    args = {}
    if match and match.group(2):
        for part in match.group(2).split(","):
            key, _, value = part.partition(":")
            args[key.strip()] = value.strip().strip('"')
    return (match.group(1) if match else None), args


def children(body):
    """The child directives a page writes, as the names the tool reads them as."""
    return sorted({match.group(1) for match in re.finditer(r"^\s*@(\w+)", body, re.M)})


def references(body):
    """The pages the table of contents names, as the tool reads the reference."""
    return sorted({match.group(1) for match in
                   re.finditer(r'@TutorialReference\(tutorial: "doc:([^"]+)"', body)})


def images(body):
    """The assets the table of contents names, as the tool reads the source."""
    return sorted({match.group(1) for match in re.finditer(r'@Image\(source: "([^"]+)"', body)})


def calls(body):
    """The commands a page calls, read from its fenced lines and its inline code.

    Both shapes are read, because the tool allows a step to carry only a paragraph, so a command in
    a step is inline code while a command in an article's prose can be a fenced line.
    """
    return sorted({one for one in (line.strip("`") for line in fenced(body) + spans(body))
                   if one.split()[:1] == ["rivulet"]})


def flags(body):
    """The flags the calls a page writes carry, read per call."""
    return {call: sorted(one[2:] for one in call.split()[1:] if one.startswith("--"))
            for call in calls(body)}


def sets(body):
    """The environment names a page sets, read from the assignment lines its fences write.

    The names a page names in prose are the part no rule reads, so this shape is only what the page
    actually sets: a line of the form `NAME=value` inside a fence. The rule that reads it compares
    these names with the names the config sources read.
    """
    return sorted({line.split("=", 1)[0].split()[-1] for line in fenced(body) if "=" in line})


def values(body):
    """The name-and-value pairs the fenced lines write, as the page writes them.

    The name is read as the last word before the `=`, because the page writes a fence line as
    `export NAME=value`, and that is the name the sets shape reads and the committed example names.
    """
    out = {}
    for line in fenced(body):
        if "=" in line:
            name, _, value = line.partition("=")
            out[name.split()[-1]] = value.strip()
    return out


def stated(body):
    """The value a page states for each marker, as the page writes it.

    A marker is read on the line that states it with the phrase `VALUE_PHRASES` names, which is the
    shape a stated value has; the first code span or the number inside parentheses on that line is
    the value. The integer minimums are read on the line that names the config name as inline code.
    """
    out = {}
    for marker, phrase in VALUE_PHRASES.items():
        line = next((one for one in body.splitlines() if phrase in one), "")
        match = re.search(r"`([^`]+)`", line) or re.search(r"\((\d+)\)", line)
        out[marker] = match.group(1) if match else None
    for name in integer_minimums():
        line = next((one for one in body.splitlines() if f"`{name}`" in one), "")
        match = re.search(r"\((\d+)\)", line)
        out[name] = int(match.group(1)) if match else None
    return out


def integer_minimums():
    """The minimum each integer read carries, as the source writes it."""
    return {name: int(minimum) for name, minimum in
            re.findall(r'parseInteger\(variable: "([A-Z_0-9]+)",[^)]*?minimum: (\d+)\)', text("config"))}


def routes(body):
    """The routes a page names, as the tool reads a method with a path."""
    return sorted({one for one in spans(body) if re.fullmatch(r"[A-Z]+ /[^\s`]+", one)})


def registered_routes():
    """The routes the port registers, read from the two files that register them.

    The Google Reader path is registered on the group its prefix names, the Fever path on the group
    the file writes, and the login on the application, so the prefix is read from the line the call
    is on rather than assumed for the whole file.
    """
    out = set()
    for line in text("routes").splitlines():
        match = re.search(r"\b(get|post)\((.*?)((?=\", use)|\))", line)
        if match:
            parts = [one.strip().strip('"') for one in match.group(2).split(",")]
            prefix = "/reader/api/0" if "protected." in line else ""
            out.add(f"{match.group(1).upper()} {prefix}/{'/'.join(parts)}")
    for line in text("fever_routes").splitlines():
        match = re.search(r"on\(\.(GET|POST|HEAD)\b", line)
        if match:
            out.add(f"{match.group(1)} /fever")
    return out


def clients_named(body):
    """The clients a page names, read from the bullet list it writes.

    A client is named as a plain bullet, while a route is written as inline code, so a bullet that
    carries a code span is read as the other shape rather than as a client.
    """
    out = set()
    for line in body.splitlines():
        match = re.match(r"^- (.*?)(?: - .*)?$", line.strip())
        if match and "`" not in match.group(1):
            out.add(match.group(1).strip())
    return sorted(out)


def matrix_clients():
    """The client names the client matrix records, read from the table of its matrix section.

    The document has more than one table, so the matrix section is the part this rule reads: the row
    that names a client is read as the first cell the table writes for it.
    """
    rows = [line for line in section(text("clients"), "## The matrix") if line.startswith("|")]
    header = [cell.strip() for cell in rows[0].strip("|").split("|")]
    out = set()
    for line in rows[2:]:
        row = dict(zip(header, [cell.strip() for cell in line.strip("|").split("|")]))
        out.add(row["Client"])
    return out


def section(document, name):
    """The lines of one section, stopping at the next `## ` heading."""
    lines = document[document.index(name) + len(name):].splitlines()
    stop = next((index for index, one in enumerate(lines) if one.startswith("## ")), len(lines))
    return lines[:stop]


def links(body):
    """The links a page carries, as the page writes them."""
    return sorted({match.group(1) for match in re.finditer(r"\[(?:[^\]]*)\]\(([^)]+)\)", body)})


def repo_paths(body):
    """The repository paths a page names, as the inline code writes them."""
    prefixes = ("docs/", "Tools/", "Scripts/", "Sources/", "Tests/", "deploy/")
    return sorted({one for one in spans(body) if one.startswith(prefixes) or one.startswith("./")})


def version(body):
    """The reference version a page names, as the page writes it."""
    match = re.search(r"\b(v\d+\.\d+\.\d+)\b", body)
    return match.group(1) if match else None


def plan_version():
    """The version the plan pins as the behavioral reference, as the plan writes it."""
    return re.search(r"\*\*(v\d+\.\d+\.\d+)\*\*", text("plan")).group(1)


def plan_stages():
    """The plan's stage table as rows: stage number, title, and the state part the rule reads.

    The document has more than one table, so the stages section is the part this rule reads. The
    state is read as the first part of the cell, because the rest of the cell names the slices the
    stage has merged, which the rule compares with nothing.
    """
    rows = []
    for line in section(text("plan"), "## Stages"):
        if not line.startswith("|") or line.startswith("| Stage") or set(line) <= {"|", "-", " "}:
            continue
        cells = [cell.strip() for cell in line.strip("|").split("|")]
        rows.append({"stage": cells[0], "title": re.sub(r"\[([^\]]*)\].*", r"\1", cells[1]),
                     "state": cells[2].split(" — ")[0], "effort": cells[3]})
    return rows


def readme_stages():
    """The stage states the root README names, as the list it writes."""
    return [{"stage": match.group(1), "title": match.group(2), "state": match.group(3)}
            for match in re.finditer(r"^- Stage (\d+) - ([^:]+): (.+)$", text("readme"), re.M)]


def contents_rows():
    """The documents the contents table names, as the table writes them."""
    rows = [line for line in text("contents").splitlines() if line.startswith("|")]
    header = [cell.strip() for cell in rows[0].strip("|").split("|")]
    out = []
    for line in rows[2:]:
        row = dict(zip(header, [cell.strip() for cell in line.strip("|").split("|")]))
        match = re.search(r"\(([^)]+)\)", row["Document"])
        out.append({"document": row["Document"], "path": match.group(1) if match else "",
                    "description": row["Description"]})
    return out


def docs_documents():
    """The documents the docs directory has, as the directory writes them.

    The contents page itself is not one of them, because it is the page that names the others, so
    the rule that reads the table against the directory does not require a row naming the page
    it reads.
    """
    return sorted(name for name in os.listdir(DEFAULTS["docs_dir"]) if name.endswith(".md")
                  and name != "README.md")


def declarations():
    """The public declarations in the Swift sources, with the comment each one has.

    The kinds read are the named ones; an initializer is not among them, so its comment is read by
    no rule and named as a gap in `docs_check.py`.
    """
    out = []
    for path, _, names in os.walk(DEFAULTS["sources"]):
        for name in sorted(names):
            if not name.endswith(".swift"):
                continue
            lines = open(os.path.join(path, name), encoding="utf-8").read().splitlines()
            for position, line in enumerate(lines):
                if re.match(r"\s*(public|open)\s+(final\s+)?(struct|enum|class|protocol|func|typealias"
                            r"|var|let)", line):
                    out.append({"file": os.path.relpath(os.path.join(path, name), ROOT),
                                "line": position + 1, "has_comment": has_comment(lines, position)})
    return out


def has_comment(lines, position):
    """Whether the declaration has a documentation comment, read as the comment attached to it.

    An attribute line belongs to the declaration rather than to the comment, so a comment separated
    from the declaration by one is still the comment attached to it, which is what DocC attaches
    it as.
    """
    cursor = position - 1
    while cursor >= 0 and lines[cursor].strip().startswith("@"):
        cursor -= 1
    return cursor >= 0 and lines[cursor].strip().startswith("///")


def dispatch_commands():
    """The commands the dispatch registers, as the names its lines write."""
    return sorted(set(re.findall(r'as: "([a-z-]+)"', text("cli"))))


def flags_for(command):
    """The flags one command's signature declares, read from the file its dispatch line names."""
    line = next(one for one in text("cli").splitlines() if f'as: "{command}"' in one)
    path = os.path.join(ROOT, "Sources", "RivuletApp", "Commands",
                        line.split("commands.use(")[1].split("(")[0] + ".swift")
    return [match.group(1) for match in
            re.finditer(r'@(?:Option|Flag)\(name: "([^"]+)"', text_at(path))]


def text_at(path):
    """A file outside the named set, read as the bytes it has."""
    return open(path, encoding="utf-8").read()


def parser_names():
    """The environment names the config reads, as the sources that read them name them."""
    return sorted(set(re.findall(r'environment\["([A-Z_0-9]+)"\]', text("config") + text("fetcher"))))


def example_values():
    """The committed example read as the names and the values it writes, one pair per line."""
    out = {}
    for line in text("example").splitlines():
        if line and not line.lstrip().startswith("#") and "=" in line:
            name, _, value = line.partition("=")
            out[name.strip()] = value.strip()
    return out


def code_value(name, marker):
    """The value a source writes for a marker on the line that assigns it, as the file writes it."""
    line = next(one for one in text(name).splitlines() if marker in one and "=" in one)
    return line.split("=", 1)[1].strip().rstrip(",").strip('"')


def listen_default():
    """The listener the read answers for a value it does not read, read as the source writes it."""
    line = next(one for one in text("config").splitlines() if "ListenAddress(host:" in one)
    host = re.search(r'"([\d.]+)"', line).group(1)
    return f"{host}:{int(re.search(r'port: (\d+)', line).group(1))}"


def manifest_target():
    """The target the catalog sits under, as the manifest writes the target names."""
    return os.path.relpath(DEFAULTS["catalog"], os.path.join(ROOT, "Sources")).split(os.sep)[0]


def targets():
    """The target names the manifest writes."""
    return sorted({match.group(1) for match in re.finditer(r'name: "(\w+)"', text("manifest"))})


def page_shapes(data):
    """The pages as the shapes they write, one entry per file the catalog has."""
    out = {}
    for path in catalog_files()[0]:
        body = text_at(os.path.join(DEFAULTS["catalog"], path))
        kind, args = directive(body)
        out[path] = {"path": path, "kind": kind, "args": args, "children": children(body),
                     "references": references(body), "images": images(body), "fenced": fenced(body),
                     "calls": calls(body), "flags": flags(body), "sets": sets(body),
                     "values": values(body), "stated": stated(body), "routes": routes(body),
                     "clients": clients_named(body), "links": links(body), "repo_paths": repo_paths(body),
                     "version": version(body),
                     "todo": [line for line in body.splitlines() if "TODO" in line]}
    return out


def report_lists(body):
    """The two lists the report document writes, as the document writes them."""
    rules, gaps, section = [], [], ""
    for line in body.splitlines():
        if line.startswith("## "):
            section = line[3:]
        elif line.startswith("- ") and section in REPORT_SECTIONS:
            (rules if section == REPORT_SECTIONS[0] else gaps).append(line[2:].strip())
    return rules, gaps


def build():
    """The data the rules read: the document the run left, the pages, and the files they
    read against.
    """
    pages = page_shapes(None)
    data = {"document": document(), "pages": pages, "catalog": manifest_target(), "targets": targets(),
            "assets": catalog_files()[1], "commands": dispatch_commands(), "names": parser_names(),
            "example": example_values(), "integer_minimums": integer_minimums(),
            "routes": registered_routes(), "matrix_clients": matrix_clients(),
            "listen_default": listen_default(), "plan_version": plan_version(),
            "plan_stages": plan_stages(), "readme_stages": readme_stages(),
            "contents": contents_rows(), "docs_documents": docs_documents(),
            "declarations": declarations(), "report": text("report"),
            "command_flags": {command: flags_for(command) for command in dispatch_commands()}}
    data["shapes"] = shapes(data)
    return data


def shapes(data):
    """Every shape the pages and the document write, as the coverage rule reads it.

    A shape is a key `build()` writes, plus the key one page writes, plus the bookkeeping the check
    half keeps. The coverage rule reads this list as data, so a shape no rule reads has to be named
    in `NOT_READ` rather than be left unread.
    """
    out = [key for key in sorted(data) if key != "shapes"]
    out += [f"page.{key}" for key in PAGE_KEYS] + ["check.reads", "check.not_read"]
    return sorted(set(out))
