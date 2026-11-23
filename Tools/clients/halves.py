#!/usr/bin/env python3
"""The rule that reads the halves the calling sets name, kept in its own file because the check
half is at the size cap. It reads three halves. The half a set names as answered here has to be a
prefix the port registers a route on, read from the files that register them, which is the half
that reads the third path as data. For a set that names more than one half, the shape the set names
for its halves has to agree with the halves it names, and a half whose calls are not read as data
has to name the read it comes from. All three halves are read as data, so a patch that took the
registration out of the third file reports, and so does a set that names the shape as one while
naming two halves, and a set that names a half whose calls are not read as data without naming the
read it comes from. Each half is crafted on its own input, and all three inputs are the one set
that names more than one half, so each craft reports the half its own input violates alone. The
rule is registered in the dict `Tools/clients/probes.py` reads, which is the dict in
`Tools/clients/replay.py`; this file holds the rule and no register of its own.
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
        if not any(half.get("note") for half in halves if half["calls_read"] != "read here"):
            found.append(f"{name}: the half whose calls are not read as data is named without "
                         f"naming the read it comes from")
    return found
