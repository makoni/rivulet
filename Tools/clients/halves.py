#!/usr/bin/env python3
"""The rule that reads the halves the calling sets name, kept in its own file because the check
half is at the size cap. It reads four halves. The half a set names as answered here has to be a
prefix the port registers a route on, read from the files that register them, which is the half that
reads the third path as data. For a set that names more than one half, the shape the set names for
its halves has to agree with the halves it names, and a half whose calls are read through the
tolerance table has to name the table it reads them through. The side the run answered on is read as
data for the half read through the tolerance table, and it has to be the side the table reads the
difference on, which is the other side: the run that left the record for this client answered on the
reference, so the answer its lines carry is read against the reference's answer for the path rather
than against this port's, and the half has to name the section of the note the read takes the
chain's answer from. All four halves are read as data, so a patch that took the registration out of
the third file reports, and so does a set that names the shape as one while naming two halves, and
a set that names a half read through the tolerance table without naming the table, and a half that
names this port as the side the table reads the difference on. Each half that can be shown alone is
crafted on its own input: three on the one set that names more than one half, and the fourth half
read as data without a craft of its own, because the third route file registers one route and the
matrix has a row that names it as its answer, so a patch that took the registration out fires the
route rule as well. The rule is registered in the dict `Tools/clients/probes.py` reads, which is the
dict in `Tools/clients/replay.py`; this file holds the rule and no register of its own.
"""

import parsers as read


def rule_shape_note_and_registrations(data):
    found = []
    registered = (read.port_routes(data["port_routes"])
                  | read.port_routes(data["port_rest_routes"])
                  | read.fever_routes(data["port_fever_routes"]))
    for name, set_data in data["sets"].items():
        halves = set_data["halves"]
        for half in halves:
            if half["answered_here"].startswith("served here") and not any(
                    one.split(" ")[1].startswith(half["prefix"]) for one in registered):
                found.append(f"{name}: the half names {half['prefix']} as answered here, which the "
                             f"port registers no route on")
        if len(halves) < 2:
            continue
        if set_data["runtime_shape"].get("uses_two_halves") is not True:
            found.append(f"{name}: the shape is named as one half, while the set names "
                         f"{len(halves)}")
        if not any(half.get("note") for half in halves
                   if half["calls_read"] == read.TOLERANCE_READ):
            found.append(f"{name}: the half whose calls are read through the tolerance table is "
                         f"named without naming the table it reads them through")
        for half in halves:
            if half["calls_read"] != read.TOLERANCE_READ:
                continue
            if half.get("run_answered_on") != read.REFERENCE_SIDE:
                found.append(f"{name}: the half whose calls are read through the tolerance table "
                             f"names {half.get('run_answered_on')} as the side the run answered on, "
                             f"which is not the side the table reads the difference on")
            if not half.get("chain_answer"):
                found.append(f"{name}: the half read through the tolerance table names no section "
                             f"of the note the read takes the chain's answer from")
            elif half["chain_answer"] not in data["reference"]:
                found.append(f"{name}: the half read through the tolerance table names "
                             f"{half['chain_answer']} as the section the read takes the chain's "
                             f"answer from, which the note has no heading for")
    return found
