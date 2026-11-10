#!/usr/bin/env python3
"""The parsers the client-matrix check half reads the committed data with.

Split out of `replay.py` so the rules stay the readable part of the check half: this file only turns
files into rows, records and sets, and reports nothing. Every function here is what one rule reads,
so a crafted input in `probes.py` changes the parsed form and never a file.

Read `docs/clients.md` first: the parsers read its sections as data, so the rule names, the counts,
the classes and the report items are part of what is checked.
"""

import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

DEFAULTS = {
    "clients": os.path.join(ROOT, "docs", "clients.md"),
    "performance": os.path.join(ROOT, "docs", "performance.md"),
    "sets": os.path.join(ROOT, "Tests", "RivuletIntegrationTests", "CallingSets"),
    "reference": os.path.join(ROOT, "docs", "reference-notes.md"),
    "parity": os.path.join(ROOT, "docs", "parity.md"),
    "run": os.path.join(ROOT, "Tools", "clients", "perf-run.txt"),
    "port_routes": os.path.join(ROOT, "Sources", "RivuletApp", "Routes",
                                "GoogleReaderRoutes.swift"),
    "port_fever": os.path.join(ROOT, "Sources", "RivuletApp", "Routes", "FeverHandlers.swift"),
    "port_auth": os.path.join(ROOT, "Sources", "RivuletApp", "Routes", "GoogleReaderAuth.swift"),
    "perf_script": os.path.join(ROOT, "Scripts", "perf.sh"),
    "perf_pin": os.path.join(ROOT, "Tests", "RivuletIntegrationTests", "LargeFeedTests.swift"),
    # The file that writes the response name a client acts on, read as data: the doc comment of the
    # auth path names the name, but the write is what a patch can change.
    "port_response": os.path.join(ROOT, "Sources", "RivuletApp", "Routes",
                                  "GoogleReaderResponse.swift"),
}


def read(path):
    return open(path).read()


def section(text, name):
    """The lines of one section, stopping at the next `## ` heading."""
    out = []
    for line in text[text.index(name) + len(name):].splitlines():
        if line.startswith("## "):
            break
        out.append(line)
    return out


def list_of(text):
    """The bullet list, read as the document writes it: one item per line."""
    return [match.group(1).strip("`") for match in
            (re.match(r"^- (.*?)(?: - .*)?$", line.strip()) for line in text) if match]


def table(text):
    """A Markdown table as rows of named columns. The separator row is not a row."""
    lines = [line for line in text if line.startswith("|")]
    if not lines:
        return []
    header = [cell.strip() for cell in lines[0].strip("|").split("|")]
    return [dict(zip(header, [cell.strip() for cell in line.strip("|").split("|")]))
            for line in lines[2:]]


def table_at(text, header):
    """A table read from the line its header is on, stopping at the first line that is not a row.

    The tolerance table in `docs/parity.md` is not under its own heading, so the rule finds it by
    the header row rather than by a section.
    """
    lines = []
    for line in text[text.index(header):].splitlines():
        if not line.startswith("|"):
            break
        lines.append(line)
    return table(lines)


def records(text):
    """The record files as data: each line is a record with the parts split at `|`.

    A comment line is not a record, which is what makes the empty file a case the rule can be shown
    to report: the rules read the records, so a file with no record lines reports nothing for them.
    """
    out = []
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        parts = [part.strip() for part in line.split("|")]
        out.append({"key": parts[0], "rest": parts[1:]})
    return out


def reference_sets(text, name):
    """The routes or dispatch names `docs/reference-notes.md` records for one path.

    A route is the method plus the path. A dispatch name is read from the sentence that names the
    implemented set, and a name the sentence writes with `|` counts as each of its parts, so
    `mark=item|feed|group` is read as the three names the client sends.
    """
    joined = " ".join(section(text, name))
    routes = {match.group(1) + " " + match.group(2) for match in
              re.finditer(r"`([A-Z]+) +(/[^`]*)`", joined)}
    dispatch = set()
    match = re.search(r"Implemented (?:parameters|routes).*?: (.*?);", joined)
    if match:
        for part in match.group(1).split(","):
            part = part.strip().strip("`")
            if "|" in part:
                head, _, rest = part.partition("=")
                dispatch.update(f"{head}={value}" for value in rest.split("|"))
            elif part:
                dispatch.add(part)
    return routes, dispatch


def port_routes(text):
    """The routes the port registers, read from the file that registers them.

    The login is registered on the application, every other route on the group the path names, so
    the prefix is read from the line the call is on rather than assumed for the whole file. The
    catch-all is read as the registration the file writes, `on(.GET, "**")`, not as the word in its
    comment, which is what lets a patch that removes the branch be reported.
    """
    registered = set()
    for line in text.splitlines():
        match = re.search(r'\b(get|post)\((.*?)((?=", use)|\))', line)
        if match is not None:
            parts = [part.strip().strip('"') for part in match.group(2).split(",")]
            prefix = "/reader/api/0" if "protected." in line else ""
            registered.add(f"{match.group(1).upper()} {prefix}/{'/'.join(parts)}")
            continue
        match = re.search(r'\bon\(\.(GET|POST), "\*\*"', line)
        if match is not None:
            registered.add(f"catch-all {match.group(1)}")
    return registered


def paragraph(text, first):
    """One paragraph or one bullet, read as the whole string the check half parses it as.

    The sentences the rules read are wrapped at the width the file is written at, so a rule that
    reads a sentence as data has to read the whole block, not the line it happens to start on. The
    block ends at a blank line, at the next bullet, or at a heading.
    """
    lines = text.splitlines()
    start = next(i for i, line in enumerate(lines) if line.startswith(first))
    block = [lines[start]]
    for line in lines[start + 1:]:
        if not line.strip() or line.startswith("- ") or line.startswith("#"):
            break
        block.append(line)
    return " ".join(line.strip() for line in block)


def names(text):
    """The backticked names inside one part of a sentence, read as the sets the sentence writes."""
    return {match.group(1) for match in re.finditer(r"`([^`]*)`", text)}


def output_check_endpoints(text):
    """The endpoints the reference names as applying the output check, read from its own note.

    The note writes the two sets in one sentence, so the names after `apply it are` are the ones
    that do and the names after `do not apply it are` are the ones that do not. A row the matrix
    reads as `output_check` has to name an endpoint in the first set, which is what makes that class
    falsifiable rather than a label.
    """
    sentence = paragraph(text, "- Which handlers apply the output check")
    _, rest = sentence.split("that apply it are ", 1)
    applied, _, refused = rest.partition("; the endpoints that do not apply it are ")
    return names(applied), names(refused)


def perf_shape(text):
    """The shape the performance document names as the shape every run had, read as data.

    A shape read as data is what lets a document that names a different shape than the run answered
    be reported; a shape written as a constant in the check half could never be reported.
    """
    sentence = paragraph(text, "The shape every run here had")
    out = {}
    for pattern, name in ((r"(\d+) feeds", "feeds"), (r"(\d+) items per feed", "items"),
                          (r"a (\w+) build", "build"),
                          (r"`FETCHER_ALLOW_PRIVATE_NETWORKS=(\w+)`", "allow_private_networks")):
        match = re.search(pattern, sentence)
        out[name] = match.group(1) if match else ""
    return out


def perf_run(text):
    """The recorded run as data: the run, source, field of each record line, and the values it has.
    """
    out = {}
    for record in records(text):
        if len(record["rest"]) != 3:
            continue
        key = (record["key"], *record["rest"][:2])
        out.setdefault(key, []).append(record["rest"][2])
    return out


def build_matrix(paths):
    clients_doc = read(paths["clients"])
    performance = read(paths["performance"])
    sets = {}
    for name in sorted(os.listdir(paths["sets"])):
        if name.endswith(".json"):
            sets[name[:-5]] = json.loads(read(os.path.join(paths["sets"], name)))
    data = {
        "clients": clients_doc,
        "performance": performance,
        "sets": sets,
        "reference": read(paths["reference"]),
        "parity": read(paths["parity"]),
        "run": read(paths["run"]),
        "port_routes": read(paths["port_routes"]),
        "port_fever": read(paths["port_fever"]),
        "port_auth": read(paths["port_auth"]),
        "perf_script": read(paths["perf_script"]),
        "perf_pin": read(paths["perf_pin"]),
        "port_response": read(paths["port_response"]),
        "run_records": perf_run(read(paths["run"])),
        "matrix": table(section(clients_doc, "## The matrix")),
        "classes": table(section(clients_doc, "## The classes this matrix reads")),
        "counts": table(section(clients_doc, "## The counts the matrix reports")),
        "perf_table": table(section(performance, "## The numbers measured here")),
        "rule_names": list_of(section(clients_doc, "## The rules the comparator reads")),
        "not_shown": list_of(section(clients_doc, "## What this matrix cannot show")),
        "manifest": records(read(os.path.join(paths["sets"], "manifest.txt"))),
        "replayed": records(read(os.path.join(paths["sets"], "replayed.txt"))),
        "shape": perf_shape(performance),
        "class_names": set(),
        "client_sections": {name: [line for line in section(clients_doc, "## Client by client")
                                   if line.startswith(f"### {sets[name]['client']}")]
                            for name in sorted(sets)},
    }
    data["class_names"] = {row["Class"] for row in data["classes"]}
    return data
