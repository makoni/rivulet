#!/usr/bin/env python3
"""The rules the stage-7 client matrix reads over the calling sets it leaves behind.

This is the client matrix half of the acceptance harness, kept separate from `Tools/parity`: the
parity half compares two live processes, while this half reads the calling sets for clients that
were never run against this port here, so every fact it reads is data the matrix recorded. That is
what makes each of them falsifiable: a rule here is a function over the record files,
`docs/clients.md` and the port's own source, so a patch that breaks one rule can be seen to report
its own input.

The rules also read what the matrix has in common with the parity harness: the parity classes the
calling sets name, the reference's route and dispatch sets read from `docs/reference-notes.md`, and
the code that names the routes the port registers. The rule that reads the performance numbers does
not read a bound: it reads what the run half answered here, and the names the performance document
claims were measured here, and matches each claim to the recorded run.

The parsers are in `parsers.py`, so this file is the rules and nothing else: each rule returns the
findings its own input causes, and no rule reads another rule's output. `probes.py` crafts one input
per rule and asserts that the rule it names reports it alone.

Read `docs/clients.md` first: the rules read its sections as data, so the rule names, the counts and
the report items are part of what is checked.
"""

import re
import sys

import parsers as read

NOT_SHOWN = [
    "that no client has been run against this port here, which is the half the manual matrix keeps "
    "open",
    "the calling set of a client whose source cannot be read, which is named per client as read "
    "from its documentation",
    "the order a client reaches its calls at on a device, which this matrix reads from the source "
    "rather than from a run",
    "the values the calls carry, which are redacted, so no row can show a value",
    "the app-level choice of which calls a library-based client makes, which is read at the library "
    "boundary",
    "the guard a client applies before it sends, which no input reaches",
    "the token half of a client that sends the stored value as the token, which the read compares "
    "as a token",
    "the numbers of another machine, which the performance half records as measurements taken here "
    "or names as not measured here",
    "the query latency at the 100k corpus, which is gated",
]

# The forms the stream branch reads a value with, as `docs/reference-notes.md` writes them: the two
# forms of each prefix are an OR, and the seven suffixes are the cases the switch has.
PREFIXES = ["user/-/state/com.google/", "user/<account>/state/com.google/",
            "user/-/label/", "user/<account>/label/", "feed/"]
SUFFIXES = ["read", "starred", "reading-list", "kept-unread", "broadcast",
            "broadcast-friends", "like"]

# The shape every run had, read from the performance document's own paragraph.
SHAPE = {"feeds": "100", "items": "3", "build": "debug", "allow_private_networks": "true"}


def rule_source(data):
    found = []
    for name, set_data in data["sets"].items():
        source = set_data["source"]
        if source["kind"] not in {"source", "docs"}:
            found.append(f"{name}: a set whose source is neither a source nor documentation")
        if not source["project"] or not source["file"] or not source["read_on"]:
            found.append(f"{name}: a set with no source named")
        if source["kind"] == "source" and not source["commit"]:
            found.append(f"{name}: a set read from a source with no commit named")
        if source["kind"] == "docs" and set_data["calls"]:
            found.append(f"{name}: a set read from documentation still records a call")
    return found


def rule_redacted(data):
    """The redaction is what makes a set data rather than a capture: the fields are named, the token
    is the placeholder the half reads, and no name a call carries reads as a captured value."""
    found = []
    for name, set_data in data["sets"].items():
        redaction = set_data["redaction"]
        for field in ("token", "account", "password", "feed_list", "note"):
            if not redaction.get(field):
                found.append(f"{name}: a set with no {field} in its redaction")
        if not re.match(r"^(T|api_key)$", redaction["token"]):
            found.append(f"{name}: the redaction names the token as a value, not as the placeholder "
                         f"the half reads")
        for call in set_data["calls"]:
            for value in call.get("names", []):
                if re.match(r"^[0-9a-f]{8,}$", value):
                    found.append(f"{name}/{call['key']}: the set carries {value}, which reads as a "
                                 f"captured value")
    return found


def rule_matrix_and_manifest(data):
    found = []
    by_call = {(row["Client"], row["Call"]): row for row in data["matrix"]}
    by_record = {record["key"]: record for record in data["manifest"]}
    for name, set_data in data["sets"].items():
        for call in set_data["calls"]:
            key = f"{name}/{call['key']}"
            row = by_call.get((set_data["client"], call["key"]))
            if row is None:
                found.append(f"{key}: the matrix has no row for it")
            elif row["Class"] != by_record[key]["rest"][0]:
                found.append(f"{key}: the matrix row names {row['Class']}, the manifest names "
                             f"{by_record[key]['rest'][0]}")
        if not set_data["calls"]:
            key = f"{name}/no-call-recorded"
            if key not in by_record:
                found.append(f"{key}: the manifest has no line for a set with no calls")
            if not any(row["Client"] == set_data["client"] for row in data["matrix"]):
                found.append(f"{key}: the matrix has no row for a set with no calls")
    return found


def rule_classes_read(data):
    """A class is read by the matrix, or by the parity table, which has to have a row for it."""
    found = []
    parity_rows = {row["Class"] for row in
                   read.table_at(data["parity"], "| Class | Row it comes from")}
    for row in data["classes"]:
        if row["Read by"] == "client matrix":
            continue
        if row["Read by"] != "docs/parity.md":
            found.append(f"{row['Class']}: a class the check half reads no rule for")
        elif row["Class"] not in parity_rows:
            found.append(f"{row['Class']}: named as read by the parity table, which has no row for "
                         f"it")
    return found


def rule_gr_reaches_a_route(data):
    found = []
    registered = read.port_routes(data["port_routes"])
    for row in data["matrix"]:
        answer = row["This port answers"]
        if row["Class"] in {"no_route_here", "closed_source"} or answer.startswith("dispatch:"):
            continue
        if answer == "catch-all":
            if "catch-all" not in data["port_routes"]:
                found.append(f"{row['Client']}/{row['Call']}: the port has no catch-all branch")
            continue
        if answer not in registered:
            found.append(f"{row['Client']}/{row['Call']}: the port registers no route for the path "
                         f"the row names")
    return found


def rule_reference_answer(data):
    found = []
    gr, _ = read.reference_sets(data["reference"], "## Google Reader API")
    fever, fever_dispatch = read.reference_sets(data["reference"], "## Fever API")
    for row in data["matrix"]:
        read_by = row["The reference reads"]
        if read_by in {"not read here", "catch-all"}:
            continue
        if read_by.startswith("dispatch:"):
            name = read_by.split("dispatch: ")[1]
            if name != "default" and name not in fever_dispatch:
                found.append(f"{row['Client']}/{row['Call']}: the reference records no case for "
                             f"{name}")
            continue
        if read_by not in gr and read_by not in fever:
            found.append(f"{row['Client']}/{row['Call']}: the reference records no route for "
                         f"{read_by}")
    return found


def rule_fever_names_from_switch(data):
    found = []
    _, dispatch = read.reference_sets(data["reference"], "## Fever API")
    for row in data["matrix"]:
        read_by = row["The reference reads"]
        if not read_by.startswith("dispatch:"):
            continue
        name = read_by.split("dispatch: ")[1]
        if name == "default":
            if "default:" not in data["port_fever"]:
                found.append(f"{row['Client']}/{row['Call']}: the switch has no default branch")
            continue
        if name not in dispatch:
            found.append(f"{row['Client']}/{row['Call']}: the reference records no case for {name}")
        if f'named: "{name.split("=")[0]}"' not in data["port_fever"]:
            found.append(f"{row['Client']}/{row['Call']}: the port's switch has no case for {name}")
    return found


def rule_partial_half(data):
    found = []
    for name, set_data in data["sets"].items():
        partial = [half for half in set_data["halves"] if half["answered_here"] == "no route here"]
        if not partial:
            continue
        if len(set_data["halves"]) < 2:
            found.append(f"{name}: the half that reaches no route is named without the other half")
        if not any(half.get("note") for half in set_data["halves"]):
            found.append(f"{name}: the partial half is named without naming the read it comes from")
    return found


def rule_sequence(data):
    found = []
    for name, set_data in data["sets"].items():
        kind = set_data["sequence_kind"]
        if kind.startswith("not read here"):
            if set_data["calls"] or set_data["source_order"]:
                found.append(f"{name}: the set names the order as not read here and still records "
                             f"one")
            continue
        if kind == "the order the source declares them in" and \
                set_data["declared_order"] != set_data["source_order"]:
            found.append(f"{name}: the recorded order is not the order the source declares")
        if sorted(set_data["source_order"]) != sorted(call["key"] for call in set_data["calls"]):
            found.append(f"{name}: the calls do not cover the order the set records")
    return found


def rule_login_first(data):
    """The login record is first, and the token record comes before every call that carries it as a
    name — which is the half the read reads for that method."""
    found = []
    for name, set_data in data["sets"].items():
        if not set_data["calls"]:
            continue
        order, keys = set_data["source_order"], [call["key"] for call in set_data["calls"]]
        shape = set_data["runtime_shape"]
        if "accounts/ClientLogin" in keys:
            if not shape.get("login_first"):
                found.append(f"{name}: the set records a login and does not name login as first")
            if order[0] != "accounts/ClientLogin":
                found.append(f"{name}: the login is not the first call the set records")
        elif shape.get("login_first"):
            found.append(f"{name}: the set names login as running first and records no login call")
        if "reader/api/0/token" not in keys:
            continue
        token = order.index("reader/api/0/token")
        if not shape.get("token_before_T"):
            found.append(f"{name}: the set records a token call and does not name it as coming "
                         f"before `T`")
        for call in set_data["calls"]:
            if "T" in call.get("names", []) and order.index(call["key"]) < token:
                found.append(f"{name}/{call['key']}: a call that carries `T` comes before the token")
    return found


def rule_token_half(data):
    found = []
    for name, set_data in data["sets"].items():
        for call in set_data["calls"]:
            if call["auth"] == "none":
                continue
            expected = "header" if call["method"] == "GET" else "form"
            if call["auth"] != expected:
                found.append(f"{name}/{call['key']}: the set names the {call['auth']} half for a "
                             f"{call['method']} call, which the read takes from the {expected} side")
    return found


def rule_stream_forms(data):
    found = []
    for name, set_data in data["sets"].items():
        for call in set_data["calls"]:
            for form in call.get("streams", []):
                prefix = next((p for p in PREFIXES if form.startswith(p)), None)
                if prefix is None:
                    found.append(f"{name}/{call['key']}: the branch reads no prefix for {form}")
                elif prefix.endswith("com.google/") and form[len(prefix):] not in SUFFIXES:
                    found.append(f"{name}/{call['key']}: the branch has no case for the suffix the "
                                 f"set records in {form}")
    return found


def rule_counts(data):
    """The columns are counts of records: the calls per client, and the matrix rows that reach each
    answer. The `all clients` row is the sum the per-client rows count, read the same way."""
    found = []
    gr, _ = read.reference_sets(data["reference"], "## Google Reader API")
    _, fever = read.reference_sets(data["reference"], "## Fever API")
    recorded = {set_data["client"]: len(set_data["calls"]) for set_data in data["sets"].values()}
    columns = ("Calls recorded", "Reaches a route or a dispatch case",
               "Reaches the catch-all or the default branch", "Replayed here")

    def counted(rows):
        reaches = sum(1 for r in rows if r["The reference reads"] in gr or
                      r["The reference reads"].split("dispatch: ")[-1] in fever)
        other = sum(1 for r in rows if r["The reference reads"] in
                    {"catch-all", "dispatch: default"})
        replayed = sum(1 for r in rows if r["Replayed here"] == "yes")
        calls = sum(recorded.get(client, 0) for client in {row["Client"] for row in rows})
        return {columns[0]: calls, columns[1]: reaches, columns[2]: other, columns[3]: replayed}

    for row in data["counts"]:
        rows = data["matrix"] if row["Client"] == "all clients" else \
            [r for r in data["matrix"] if r["Client"] == row["Client"]]
        expected = counted(rows)
        for column in columns:
            if int(row[column]) != expected[column]:
                found.append(f"{row['Client']}: the counts table reports {row[column]} for "
                             f"{column}, the rows count {expected[column]}")
    return found


def rule_replayed(data):
    """The replay list names, for each recorded call, the pin that reads it or the reason it cannot
    be replayed here, and the matrix's own column has to agree with the record."""
    found = []
    for record in data["replayed"]:
        if len(record["rest"]) != 1:
            found.append(f"{record['key']}: a replay record with no pin and no reason")
            continue
        row = next((r for r in data["matrix"] if r["Call"] == record["key"].split("/", 1)[1]), None)
        if row is None:
            found.append(f"{record['key']}: the matrix has no row for a replay record")
            continue
        reason = record["rest"][0].startswith("not replayed here")
        if reason != (row["Replayed here"] != "yes"):
            found.append(f"{record['key']}: the record names a {'reason' if reason else 'pin'}, the "
                         f"matrix names it as {row['Replayed here']}")
    return found


def rule_performance(data):
    """The table is read against the run log, and the run log against the fields its sources
    declare: the names the shell's echo lines write, and the name the timed pin's print writes.
    A field no source declares is a finding, which is why the pin is read as data here rather than
    assumed."""
    found = []
    run = {}
    for line in data["run"].splitlines():
        if not line or line.startswith("#"):
            continue
        parts = [part.strip() for part in line.split("|")]
        run.setdefault((parts[0], parts[1], parts[2]), []).append(parts[3])
    declared = set(re.findall(r"(\w+)=", data["perf_script"])) | \
            set(re.findall(r"(\w+)=", data["perf_pin"]))
    used, undeclared = [], set()
    for row in data["perf_table"]:
        if row["Named as"] != "measured here":
            continue
        key = (row["Run"], row["Source"], row["Field"])
        if row["Field"] not in declared and row["Field"] not in undeclared:
            undeclared.add(row["Field"])
            found.append(f"{row['Field']}: a field no source declares")
        if key not in run:
            found.append(f"{row['Run']} {row['Field']}: the table reports it as measured here, the "
                         f"run answered nothing")
            continue
        if row["Value"] not in run[key]:
            found.append(f"{row['Run']} {row['Field']}: the table reports {row['Value']}, the run "
                         f"answered {' or '.join(run[key])}")
            continue
        used.append((key, row["Value"]))
    for key, values in run.items():
        if key[2] in undeclared:
            continue
        if key[2] in SHAPE:
            if values[0] != SHAPE[key[2]]:
                found.append(f"the shape line {key[2]} answers {values[0]}, the document names "
                             f"{SHAPE[key[2]]}")
            continue
        for value in values:
            if (key, value) not in used:
                found.append(f"{key[0]} {key[2]}: the run answered {value}, the table does not read "
                             f"that number")
    return found


def rule_names_every_rule(data):
    found = []
    names = sorted(RULES)
    for name in names:
        if name not in data["rule_names"]:
            found.append(f"{name}: a rule the check half has, the document does not name")
    for name in data["rule_names"]:
        if name not in names:
            found.append(f"{name}: named in the document, the check half has no rule for it")
    for line in data["not_shown"]:
        if line not in NOT_SHOWN:
            found.append(f"the document names `{line}` as not shown, the check half has no fact "
                         f"for it")
    for line in NOT_SHOWN:
        if line not in data["not_shown"]:
            found.append(f"`{line}`: the check half has a fact for it, the document does not name "
                         f"it")
    return found


def rule_acts_on_name(data):
    found = []
    for name, set_data in data["sets"].items():
        header = set_data["runtime_shape"].get("acts_on_header")
        if header and header not in data["port_auth"] and header not in data["port_fever"]:
            found.append(f"{name}: the set names a response name the port does not write")
    return found


RULES = {
    "sets_name_the_source_and_a_set_read_from_docs_records_no_calls": rule_source,
    "sets_are_redacted": rule_redacted,
    "matrix_names_every_call_and_the_classes_agree_with_the_manifest": rule_matrix_and_manifest,
    "matrix_classes_are_read_by_the_matrix_and_parity_classes_have_a_row": rule_classes_read,
    "a_gr_call_reaches_a_route_the_port_registers_or_the_catch_all": rule_gr_reaches_a_route,
    "the_reference_answer_names_a_route_the_reference_registers": rule_reference_answer,
    "the_fever_names_are_read_from_the_dispatch_switch": rule_fever_names_from_switch,
    "the_half_with_no_routes_here_is_named_as_partial": rule_partial_half,
    "the_recorded_sequence_is_the_set_the_source_declares": rule_sequence,
    "the_login_record_is_first_and_the_token_precedes_every_call_that_needs_it": rule_login_first,
    "the_token_half_is_the_half_the_read_reads": rule_token_half,
    "the_stream_forms_are_the_forms_the_reference_reads": rule_stream_forms,
    "counts_match_the_records_they_report": rule_counts,
    "every_recorded_call_is_named_as_replayed_or_with_a_reason": rule_replayed,
    "performance_names_which_numbers_were_measured_here": rule_performance,
    "the_matrix_names_every_rule_and_what_it_cannot_show": rule_names_every_rule,
    "the_name_a_client_acts_on_is_the_name_the_port_writes": rule_acts_on_name,
}


def run(paths):
    data = read.build_matrix(paths)
    findings = []
    for name, rule in RULES.items():
        findings.extend(rule(data))
    return findings


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="Apply the client-matrix rules to the recorded data.")
    for name, path in read.DEFAULTS.items():
        parser.add_argument(f"--{name.replace('_', '-')}", default=path)
    findings = run(vars(parser.parse_args()))
    for line in findings:
        print(line)
    if findings:
        sys.exit(1)
