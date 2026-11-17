#!/usr/bin/env python3
"""The parsers the client-matrix check half reads the committed data with. Split out of `replay.py`
so the rules stay the readable part of the check half: this file only turns files into rows,
records and sets, and reports nothing. Every function here is what one rule reads, so a crafted
input in `probes.py` changes the parsed form and never a file. Read `docs/clients.md` first: the
parsers read its sections as data, so the rule names, the counts, the classes and the report
items are part of what is checked.
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
    # The records the client runs wrote, read as data by the rule the run half leaves behind. One
    # file per client, and each line names the client it was written for, so the rule reads a record
    # for the client that run wrote it for.
    "record_dir": os.path.join(ROOT, "Tools", "clients"),
    # The files that write the key names the record carries, read as the write, not as the comment:
    # one for the path that writes its documents through a shape function, one for the path that
    # writes them through the response builder.
    "port_shape": os.path.join(ROOT, "Sources", "RivuletApp", "Routes", "FeverShape.swift"),
    "port_gr_shape": os.path.join(ROOT, "Sources", "RivuletApp", "Routes",
                                  "GoogleReaderShape.swift"),
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
    # The handlers the route file gives each path, read as the directory that writes them, so the
    # handler a record line is read against is the one the port answers this path with.
    "routes_dir": os.path.join(ROOT, "Sources", "RivuletApp", "Routes"),
    # The pin that pins the response builder's status mapping, read as data for the pair (shape,
    # status): the file that writes the shapes writes them as status names, so the pair is only
    # written down as data on the pin's own expectation lines.
    "status_pin": os.path.join(ROOT, "Tests", "RivuletAppTests",
                               "GoogleReaderResponseStatusTests.swift"),
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
    """The record files as data: each line is a record with the parts split at `|`. A comment line
    is not a record, which is what makes the empty file a case the rule can be shown to report:
    the rules read the records, so a file with no record lines reports nothing for them.
    """
    out = []
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        parts = [part.strip() for part in line.split("|")]
        out.append({"key": parts[0], "rest": parts[1:]})
    return out


def set_file_name(client):
    """The name the set files are read under for one client. The run half reads this name through
    the same reader, so the record file it names and the set the rule reads for that client are
    one name: the client as the document writes it, lowercased with the spaces as the mark the
    file names use.
    """
    return client.lower().replace(" ", "-")


def set_for(client, paths=DEFAULTS):
    """One client's calling set, read as the round reads it."""
    return json.loads(read(os.path.join(paths["sets"], set_file_name(client) + ".json")))


def prefix_for(client):
    """The prefix the halves name for one client, which is the path the base has to carry. A base
    carrying another prefix reaches the root, which is the half the run half reads the base
    against.
    """
    return set_for(client)["halves"][0]["prefix"]


def prefix_form_for(client):
    """How the base carries that prefix for one client. The set names the form when the client
    builds the prefix itself rather than sending the base as it is typed: for such a client the
    base holds only the host and port, and the prefix reaches the port through the path the
    client adds. When the half names no form, the client sends the base as typed, so the base
    itself is the whole prefix.
    """
    return set_for(client)["halves"][0].get("prefix_form", "")


def add_call(client):
    """The add call the set names for one client, or nothing when its set has no call that can write
    a feed row. This is the half that decides where the feed row the entry guard reads comes
    from: for a client whose set names the call the run leaves the row to the client, because
    writing the row here would put the duplicate rule in front of the call the run is there to
    show.
    """
    return next((call["key"] for call in set_for(client)["calls"]
                 if call["key"].endswith("/quickadd")), "")


def record_path(client, paths=DEFAULTS):
    """The record file the round reads for one client: the record directory plus the name it reads
    that client under."""
    return os.path.join(paths["record_dir"], set_file_name(client) + ".txt")


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
    """The routes the port registers, read from the file that registers them. The login is
    registered on the application, every other route on the group the path names, so the prefix
    is read from the line the call is on rather than assumed for the whole file. The catch-all is
    read as the registration the file writes, `on(.GET, "**")`, not as the word in its comment,
    which is what lets a patch that removes the branch be reported.
    """
    registered = set()
    for line in text.splitlines():
        match = re.search(r"\b(get|post)\((.*?)((?=\", use)|\))", line)
        if match is not None:
            parts = [part.strip().strip('"') for part in match.group(2).split(",")]
            prefix = "/reader/api/0" if "protected." in line else ""
            registered.add(f"{match.group(1).upper()} {prefix}/{'/'.join(parts)}")
            continue
        match = re.search(r"\bon\(\.(GET|POST), \"\*\*\"", line)
        if match is not None:
            registered.add(f"catch-all {match.group(1)}")
    return registered


def route_handlers(text):
    """The handler each registration line gives the path it registers, read as the call the line
    writes. The route rule reads the same file for the registration, so the handler the status half
    reads is the one the port answers this path with, not the file the function happens to sit in.
    The handler call is the line the registration hands to the auth wrapper, so the pair is read
    inside one block: a route whose block writes no handler call answers nothing here, and the block
    ends at the line that closes it.
    """
    out = {}
    current = None
    for line in text.splitlines():
        match = re.search(r"\b(get|post)\((.*?)((?=\", use)|\))", line)
        handler = re.search(r"handlers\.(\w+)\(", line)
        if match is not None:
            parts = [part.strip().strip('"') for part in match.group(2).split(",")]
            prefix = "/reader/api/0" if "protected." in line else ""
            current = f"{match.group(1).upper()} {prefix}/{'/'.join(parts)}"
        elif handler is not None and current is not None:
            out[current] = handler.group(1)
            current = None
        elif current is not None and line.strip() == "})":
            current = None
    return out


def handler_shapes(paths):
    """The response-builder shapes each handler answers with, read as the function that writes it.
    Only the handler's own block is read, so a shape another handler answers is not read for this
    path, which is the half that makes a status this handler has no branch for a finding.
    """
    out = {}
    for name in sorted(os.listdir(paths["routes_dir"])):
        if not name.startswith("GoogleReaderHandlers"):
            continue
        text = read(os.path.join(paths["routes_dir"], name))
        for block in re.split(r"\n(?=\s*(?:private )?func )", text):
            head = re.match(r"\s*(?:private )?func (\w+)\(", block)
            if head is None:
                continue
            out[head.group(1)] = sorted({match.group(1) for match in
                                         re.finditer(r"GoogleReaderResponse\.(\w+)\(", block)})
    return out


def status_names(text):
    """The status each error shape the response builder writes, read from the pin that pins the
    mapping: the pin names the shape and the status on one expectation line, so a patch that moved a
    shape's status moves the pair read here.
    """
    return {match.group(1): match.group(2) for match in
            re.finditer(r"GoogleReaderResponse\.(\w+)\([^)]*\)\.status == \.(\w+)", text)}


def paragraph(text, first):
    """One paragraph or one bullet, read as the whole string the check half parses it as. The
    sentences the rules read are wrapped at the width the file is written at, so a rule that
    reads a sentence as data has to read the whole block, not the line it happens to start on.
    The block ends at a blank line, at the next bullet, or at a heading.
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


def names_in_order(text):
    """The backticked names inside one part of a sentence, read as the order the sentence writes.
    The run rule reads the order the paragraph names the calls in as part of what it reads, so
    the read keeps the order rather than the set, which is the half the plain read cannot carry.
    """
    return [match.group(1) for match in re.finditer(r"`([^`]*)`", text)]


def output_check_endpoints(text):
    """The endpoints the reference names as applying the output check, read from its own note. The
    note writes the two sets in one sentence, so the names after `apply it are` are the ones that
    do and the names after `do not apply it are` are the ones that do not. A row the matrix reads
    as `output_check` has to name an endpoint in the first set, which is what makes that class
    falsifiable rather than a label.
    """
    sentence = paragraph(text, "- Which handlers apply the output check")
    _, rest = sentence.split("that apply it are ", 1)
    applied, _, refused = rest.partition("; the endpoints that do not apply it are ")
    return names(applied), names(refused)


def perf_shape(text):
    """The shape the performance document names as the shape every run had, read as data. A shape
    read as data is what lets a document that names a different shape than the run answered be
    reported; a shape written as a constant in the check half could never be reported.
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


def observed(text):
    """The record the client run wrote, as the rules read it: one line per request the client sent.
    The header comment is not a record, so a record file with no record lines reports nothing for
    the rules that read it, which is the half a probe cannot move.
    """
    out = []
    for record in records(text):
        if len(record["rest"]) != 6:
            continue
        out.append({"client": record["key"], "order": int(record["rest"][0]),
                    "call": record["rest"][1], "method": record["rest"][2],
                    "answer": record["rest"][3], "keys": record["rest"][4].split(),
                    "fields": record["rest"][5].split()})
    return out


def shape_keys(text):
    """The key names the response shape writes, read from the file that writes them. Read as the
    write rather than as the comment that names the document, so a patch that renames a key in
    the code can be reported against the record the run wrote.
    """
    return [match.group(1) for match in re.finditer(r"\(key: \"([^\"]*)\"", text)]


def shape_keys_by_path(paths):
    """The key names each path writes, keyed by the api the set names for a client. The Fever path
    writes them through one shape function; the Google Reader path writes them through its own
    shape file and the response builder. The key half reads a record line against the names the
    file writes for the path that client's set is read on, which is what makes a key the other
    path writes a finding rather than a name that happens to appear somewhere.
    """
    return {
        "fever": shape_keys(read(paths["port_shape"])),
        "google-reader": sorted(set(shape_keys(read(paths["port_gr_shape"])))
                                | set(shape_keys(read(paths["port_response"])))),
    }


def record_files(paths, named):
    """The record directory as the half reads it: the files named as the record for a client the
    matrix has a row under, and present in the directory. A `*.txt` that sits there without being
    named that way is read by the rule that reads it at its own path, which is the performance
    record, so it is not a client record read here.
    """
    return sorted(entry for entry in os.listdir(paths["record_dir"]) if entry in named)


def observed_by_client(paths, named):
    """The record files as data, grouped by the client each line names. A file with no record lines
    contributes nothing, which is what a round cannot move for a client this machine has not run:
    the run wrote no record, so no half reads it.
    """
    out = {}
    for entry in record_files(paths, named):
        for line in observed(read(os.path.join(paths["record_dir"], entry))):
            out.setdefault(line["client"], []).append(line)
    return out


def base_shape_keys(path):
    """The names the base document writes, read from the function that writes them. `FeverShape`
    writes these in the function every document of this path calls, which is the last function in
    the file, so the read of that function is the set the answer half excludes. The path is given
    so the run half reads the same file through the same read, which is what keeps the answer the
    record writes and the answer the rule reads derived from one read.
    """
    text = read(path)
    start = text.find("static func document(")
    return shape_keys(text[start:])


def build_matrix(paths):
    clients_doc = read(paths["clients"])
    performance = read(paths["performance"])
    sets = {}
    for name in sorted(os.listdir(paths["sets"])):
        if name.endswith(".json"):
            sets[name[:-5]] = json.loads(read(os.path.join(paths["sets"], name)))
    rows = table(section(clients_doc, "## The matrix"))
    # The record files as the round names them: one file per client, under the name it reads that
    # client under. The file the performance rule reads at its own path is not one of these names.
    named = {set_file_name(row["Client"]) + ".txt" for row in rows}
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
        "status_pin": read(paths["status_pin"]),
        "route_handlers": route_handlers(read(paths["port_routes"])),
        "handler_shapes": handler_shapes(paths),
        "run_records": perf_run(read(paths["run"])),
        "record_files": record_files(paths, named),
        "observed": observed_by_client(paths, named),
        "shape_keys": shape_keys_by_path(paths),
        "matrix": rows,
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
