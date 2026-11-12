#!/usr/bin/env python3
"""The rule that reads the client run as data, kept in its own file because the check half is at the
size cap.

The run half writes one record line per request the client actually sent, so this rule reads the run
document rather than the app: the order the calls arrived in, the call as the recorded set names it,
the method, the answer the port gave, the key names the answer carried, and the field names the
request carried. Seven halves, each with its own craft: the order the record carries against the
order the document names the calls this run showed, a call the set cannot name against the document
naming it as a call this run showed, the answer for a call the set names against the matrix row, the
answer for a call the reference records no case for against the default branch, the key names read
against the names the response shape writes, the name the redaction names for the credential pair,
and the guarded call against the document naming it as a call this run showed.

The order half reads the order of first appearances, because one run can reach the same call more
than once, and it does not read the run's order against the order the source declares: the document
names the order a client reaches its calls at as shown only for the client run here, so the half
compares the record with the order the same document names the calls this run showed, which is the
half the document can be wrong about. The order column is the order the requests arrived at, read
rather than the position of the line, because the line is written when the response is complete,
which is not the arrival order when the client has more than one connection open at once.

Every half is craftable, because the record is a committed file the round reads as data: a probe
changes the parsed record in memory and the round hashes the file before and after.
"""

import parsers as read

GUARD_CLASS = "client_guard"
PARAGRAPH = "The calls this run showed"


def order_half(record, shown):
    """The order the record carries, read as the order column, against the order the document names
    the calls the two have in common, as the first appearance of each.
    """
    shared = [one for one in shown if one in {line["call"] for line in record}]
    carried = []
    for line in sorted(record, key=lambda one: one["order"]):
        if line["call"] in shown and line["call"] not in carried:
            carried.append(line["call"])
    if carried == shared:
        return []
    return [f"the record carries the calls as {carried}, "
            f"which is not the order the document names the calls this run showed ({shared})"]


def answer_half(data, record, rows, shown):
    """The answer for a call the set names, read against the matrix row; the call the set cannot
    name has to be a call the document names as shown, and its answer has to be the default branch.
    """
    found = []
    for one in record:
        if one["call"] in data["sets"]["newsflash"]["declared_order"]:
            if one["answer"] != rows[one["call"]]["This port answers"]:
                found.append(f"{one['call']}: the record reads {one['answer']}, "
                             f"the matrix row names {rows[one['call']]['This port answers']}")
            continue
        if one["call"] not in shown:
            found.append(f"{one['call']}: a call the record carries that the set does not name "
                         f"and the document does not name as shown by this run")
        if one["answer"] != "dispatch: default":
            found.append(f"{one['call']}: a call the reference records no case for, answered as "
                         f"{one['answer']}, which is the half that has to be the default branch")
    return found


def key_half(record, written):
    """A key name the record carries that the response shape writes nowhere."""
    found = []
    for one in record:
        extra = [key for key in one["keys"] if key not in written]
        if extra:
            found.append(f"{one['call']}: the record names {extra}, "
                         f"which the response shape writes nowhere")
    return found


def token_half(record, token):
    """The name the redaction names for the pair, which has to be on every line the run wrote."""
    found = []
    for one in record:
        if token not in one["fields"]:
            found.append(f"{one['call']}: the record carries no {token}, "
                         f"which is the name the redaction names for the pair the client sends")
    return found


def guard_half(record, guarded, shown):
    """The call whose guard the client applies before it sends.

    Read as the bound the guard is, not as a half no input reaches: the record can carry a line for
    the guarded call when the list the client sent is below the bound, which is what this run
    showed, so the half is that a line for it has to be a call the document names as shown by this
    run. The bound firing is what no line can show, because the record carries names and not
    values, and that is the report item.
    """
    found = []
    for one in record:
        if one["call"] in guarded and one["call"] not in shown:
            found.append(f"{one['call']}: the record carries a line for a call whose guard the "
                         f"client applies before it sends, which the document does not name as a "
                         f"call this run showed")
    return found


def run_reads_the_record(data):
    """The rule over the run document, split into the halves each message names.

    The order half reads the calls the record reached, not the whole set, because a run can reach a
    part of a calling set, and the record is read in the order its order column names the calls.
    """
    record = data["observed"]
    set_data = data["sets"]["newsflash"]
    rows = {row["Call"]: row for row in data["matrix"] if row["Client"] == set_data["client"]}
    shown = read.names_in_order(read.paragraph(data["clients"], PARAGRAPH))
    guarded = {line["key"].split("/", 1)[1] for line in data["manifest"]
               if line["rest"][0] == GUARD_CLASS}
    found = order_half(record, shown)
    found += answer_half(data, record, rows, shown)
    found += key_half(record, data["shape_keys"])
    found += token_half(record, set_data["redaction"]["token"])
    found += guard_half(record, guarded, shown)
    return found


RULES = {"the_run_record_agrees_with_the_set_and_the_answer_it_names": run_reads_the_record}
