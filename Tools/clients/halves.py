#!/usr/bin/env python3
"""The rule that reads the halves the calling sets name, kept in its own file because the check half
is at the size cap. The half that reaches no route is read in two halves: the shape the set names
for its halves has to agree with the halves it names, and the note has to name the read that half
comes from. Both are read as data, so a set that names the shape as two halves while naming one half
reports, and so does a set that names the shape as one while naming two. Each half of this rule is
crafted on its own input, and both inputs are the one set with a half that reaches no route here, so
each craft reports the half its own input violates alone. The rule is registered in the dict
`Tools/clients/probes.py` reads, which is `Tools/clients/replay.py`; this file holds the rule, not a
register of its own.
"""


def rule_shape_and_note(data):
    found = []
    for name, set_data in data["sets"].items():
        if not any(half["answered_here"] == "no route here" for half in set_data["halves"]):
            continue
        shape_names_two = set_data["runtime_shape"].get("uses_two_halves")
        names_two = len(set_data["halves"]) > 1
        if shape_names_two != names_two:
            found.append(f"{name}: the shape is named as "
                         f"{'two halves' if shape_names_two else 'one half'}, while the "
                         f"set names {'two halves' if names_two else 'one half'}")
        if not any(half.get("note") for half in set_data["halves"]):
            found.append(f"{name}: the half that reaches no route is named without naming the "
                         f"read it comes from")
    return found
