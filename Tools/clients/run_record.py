#!/usr/bin/env python3
"""The rule that reads the client run as data, kept in its own file because the check half is at the
size cap. The run half writes one record line per request the client actually sent, so this rule
reads the run document rather than the app: the client the record names, the order the calls
arrived in, the call as the recorded set names it, the method, the answer the port gave, the key
names the answer carried, and the field names the request carried. Eleven halves, each with its own
craft: the client the record names against the set that client's row records; the order the
record carries against the order the document names the calls this run showed; a call the set
cannot name against the document naming it as shown; the answer for a call the set names against
the matrix row; the answer for a call the reference records no case for against the default
branch, which is the dispatch word for the path that dispatches and the catch-all word for the
path that answers on a route; the status a record line carries when the port wrote something other
than an answer of this path, read as the status the handler the route file gives this path answers,
through the shapes its own branches write and the status each shape writes; the call name against
the branch the merged form gives, read through the mark the set names that branch with; the key
names read against the names the file writes for the path this client uses; the name the redaction
names for the pair; the guarded call against the document naming it as shown by this run; and the
record files the round reads, read as the names it reads them under, which is the half that keeps
the file another rule reads at its own path out of the client records. The order half reads the
order of first appearances, because one run can reach the same call more than once, and it does not
read the run's order against the order the source declares: the document names the order a client
reaches its calls at as shown only for the client run here, so the half compares the record with the
order the same document names the calls this run showed, which is the half the document can be
wrong about. The order column is the order the requests arrived at, read rather than the position
of the line, because the line is written when the response is complete, which is not the arrival
order when the client has more than one connection open at once. The paragraph is read for the
client the record names, so a run this machine has not written a record for has no paragraph to
read an order against, and the half reads nothing for it rather than reading the order of another
client's run. Each half the round crafts is single-firing, because the record is a committed file
the round reads as data: a craft changes the parsed record in memory and the round hashes the
file before and after. One branch has no craft and is named here rather than probed: the one that
reports a record naming a client the check half has no set for, which no committed record can put
in place. The number written for each status name is this read's vocabulary, because the pin asserts
the status name and no test asserts the number: the pair (shape, status) is read as data, the number
is named here, and that is the half the report item names.
"""

import parsers as read

GUARD_CLASS = "client_guard"
PARAGRAPH = "The calls this run showed for"
# The word the default half reads for a call the reference records no case for, per path: the name
# the dispatch switch has for the path that dispatches, and the catch-all as the matrix names it for
# the path that answers on a route.
DEFAULT_ANSWER = {"fever": "dispatch: default", "google-reader": "catch-all"}
# The field the merged form gives the branch with, and the mark the set uses to name that branch as
# the row has it.
BRANCH_FIELD = "s"
BRANCH_MARK = "#"
# The word the record writes for an answer that is not an answer of this path, and the number this
# read names for each status name the response builder writes. The pin pairs the shape with the
# status name as data; the number is named here because no test asserts it, and that is the half the
# report item names.
STATUS_PREFIX = "status "
STATUS_NUMBER = {"badRequest": 400, "internalServerError": 500, "notFound": 404}


def set_key(client):
    """The name the set files are read under for a client, read through the same reader the run half
    uses for the record file it names."""
    return read.set_file_name(client)


def shown_for(data, client):
    """The calls the document names as shown by the run for this client, in the order it names them.
    """
    first = f"{PARAGRAPH} {client}"
    if first not in data["clients"]:
        return []
    return read.names_in_order(read.paragraph(data["clients"], first))


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


def call_half(record, calls, shown):
    """A call the record carries that the set does not name, which has to be a call the document
    names as shown by this run.
    """
    found = []
    for one in record:
        if one["call"] not in calls and one["call"] not in shown:
            found.append(f"{one['call']}: a call the record carries that the set does not name "
                         f"and the document does not name as shown by this run")
    return found


def answer_half(record, rows):
    """The answer the record carries for a call the set names, read against the matrix row. A line
    whose answer is a status is not read here: the row names the answer for the path, while the
    status is the answer the handler wrote for the read that failed, which the status half reads.
    """
    found = []
    for one in record:
        if one["answer"].startswith(STATUS_PREFIX):
            continue
        if one["call"] in rows and one["answer"] != rows[one["call"]]["This port answers"]:
            found.append(f"{one['call']}: the record reads {one['answer']}, "
                         f"the matrix row names {rows[one['call']]['This port answers']}")
    return found


def default_half(record, calls, default):
    """The answer for a call the set cannot name, which has to be the branch the read answers on for
    this path.
    """
    found = []
    for one in record:
        if one["call"] in calls or one["answer"] == default:
            continue
        found.append(f"{one['call']}: a call the reference records no case for, answered as "
                     f"{one['answer']}, which is not the {default} half")
    return found


def status_half(record, rows, handlers, shapes, statuses):
    """The status a record line carries when the port wrote something other than an answer of this
    path. Read as the status the handler the route file gives this path answers, through the shapes
    its own branches write and the status each shape writes: a status this handler has no branch for
    is a finding, which is what the craft for this half shows.
    """
    found = []
    for one in record:
        if not one["answer"].startswith(STATUS_PREFIX):
            continue
        answer = rows[one["call"]]["This port answers"]
        handler = handlers.get(answer)
        if handler is None:
            continue
        answered = {STATUS_NUMBER[statuses[shape]] for shape in shapes.get(handler, [])
                    if shape in statuses and statuses[shape] in STATUS_NUMBER}
        if int(one["answer"][len(STATUS_PREFIX):]) not in answered:
            found.append(f"{one['call']}: the record reads {one['answer']}, which is not a status "
                         f"the handler {handler} answers ({sorted(answered)})")
    return found


def branch_half(record, calls):
    """For a call the set names, the call name has to carry the branch the merged form gives. The
    record carries names and not values, so the branch is read as the field the switch takes it
    from: `s` is the name the merged form gives the branch this path's row has, and the set names
    the call with that branch. The Fever path has no equivalent half, because its branch is the
    part of the name the record already carries. The bound the client applies before it sends is
    the half no line can show, which is the report item.
    """
    found = []
    for one in record:
        if one["call"] not in calls or BRANCH_FIELD not in one["fields"]:
            continue
        named = next((call for call in calls if BRANCH_MARK in call
                      and call.split(BRANCH_MARK)[0] == one["call"]), None)
        if named is not None and named != one["call"]:
            found.append(f"{one['call']}: the merged form gives this call the branch {named}, which is "
                         f"the name the set has for it, and the record names the call without it")
    return found


def key_half(record, written):
    """A key name the record carries that the file writes nowhere for this path."""
    found = []
    for one in record:
        extra = [key for key in one["keys"] if key not in written]
        if extra:
            found.append(f"{one['call']}: the record names {extra}, "
                         f"which the response shape writes nowhere")
    return found


def token_half(record, token, login):
    """The name the redaction names for the pair, which has to be on every line the run wrote for a
    call that carries the pair. The login is the call that reads it, so the line for it carries
    the pair as the redaction names the fields, not as the name it reads the token with.
    """
    found = []
    for one in record:
        if one["call"] == login or token in one["fields"]:
            continue
        found.append(f"{one['call']}: the record carries no {token}, "
                     f"which is the name the redaction names for the pair the client sends")
    return found


def guard_half(record, guarded, shown):
    """The call whose guard the client applies before it sends. Read as the bound the guard is, not
    as a half no input reaches: the record can carry a line for the guarded call when the list
    the client sent is below the bound, which is what this run showed, so the half is that a line
    for it has to be a call the document names as shown by this run. The bound firing is what no
    line can show, because the record carries names and not values, and that is the report item.
    """
    found = []
    for one in record:
        if one["call"] in guarded and one["call"] not in shown:
            found.append(f"{one['call']}: the record carries a line for a call whose guard the "
                         f"client applies before it sends, which the document does not name as a "
                         f"call this run showed")
    return found


def record_halves(data, client, record):
    """The halves this rule reads for one record, as the data names the client that run wrote it
    for.
    """
    set_data = data["sets"].get(set_key(client))
    if set_data is None:
        return [f"the record names {client}, which the check half reads no set for"]
    if not set_data["calls"]:
        return [f"the record names {client}, whose set records no calls, so its lines cannot be read "
                f"against a set"]
    calls = {call["key"] for call in set_data["calls"]}
    login = next((call["key"] for call in set_data["calls"] if call["auth"] == "none"), None)
    rows = {row["Call"]: row for row in data["matrix"] if row["Client"] == client}
    guarded = {line["key"].split("/", 1)[1] for line in data["manifest"]
               if line["rest"][0] == GUARD_CLASS}
    shown = shown_for(data, client)
    found = order_half(record, shown)
    found += call_half(record, calls, shown)
    found += answer_half(record, rows)
    found += default_half(record, calls, DEFAULT_ANSWER[set_data["api"]])
    found += status_half(record, rows, data["route_handlers"], data["handler_shapes"],
                         read.status_names(data["status_pin"]))
    found += branch_half(record, calls)
    found += key_half(record, data["shape_keys"][set_data["api"]])
    found += token_half(record, set_data["redaction"]["token"], login)
    found += guard_half(record, guarded, shown)
    return found


def record_name_half(data, named):
    """The record files the round reads as client records, read as the names the round reads them
    under. A file in the record directory that is not named as the record for a client the matrix
    has a row for is read by another rule at its own path, which is what the performance record is,
    so a half that read the directory as whatever sits in it would put that file in front of the
    halves that read a client's run.
    """
    found = []
    for entry in data["record_files"]:
        if entry not in named:
            found.append(f"{entry}: a file in the record directory read as a client record, which is "
                         f"not the name the round reads a client the matrix has a row under")
    return found


def run_reads_the_record(data):
    """The rule over the run document, split into the halves each message names. The order half
    reads the calls the record reached, not the whole set, because a run can reach a part of a
    calling set, and the record is read in the order its order column names the calls.
    """
    named = {set_key(row["Client"]) + ".txt" for row in data["matrix"]}
    found = record_name_half(data, named)
    for client in sorted(data["observed"]):
        found += record_halves(data, client, data["observed"][client])
    return found


RULES = {"the_run_record_agrees_with_the_set_and_the_answer_it_names": run_reads_the_record}
