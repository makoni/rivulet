#!/usr/bin/env python3
"""The rule that reads the halves the calling sets name, kept in its own file because the check half
is at the size cap. The half that reaches no route is read as partial only against another half, so
the shape a set names for its halves has to agree with the halves it names: a set that names one
half names that half as the whole half. The shape is read as data, so a set that names two halves
while naming the half as the whole half reports, and so does a one-half set named as partial. Each
half of this rule is crafted on its own input, and both inputs are the one set with a half that
reaches no route here.
"""


def rule_partial_half(data):
    found = []
    for name, set_data in data["sets"].items():
        if not any(half["answered_here"] == "no route here" for half in set_data["halves"]):
            continue
        named_as_partial = set_data["runtime_shape"].get("uses_two_halves")
        names_two = len(set_data["halves"]) > 1
        if named_as_partial != names_two:
            found.append(f"{name}: the half that reaches no route is named as "
                         f"{'partial' if named_as_partial else 'the whole half'}, while the "
                         f"set names {'two halves' if names_two else 'one half'}")
        if not any(half.get("note") for half in set_data["halves"]):
            found.append(f"{name}: the half that reaches no route is named without naming the "
                         f"read it comes from")
    return found


RULES = {"the_half_with_no_routes_here_is_named_as_partial": rule_partial_half}
