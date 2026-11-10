#!/usr/bin/env python3
"""The probe set: one input per rule that violates it, and the assertion that the rule reports it.

This is the falsifiability half of the client matrix. The rules in `replay.py` are functions over
the committed data, so a probe is a crafted input: the same data with one thing changed, and the
assertion is that the rule the change names reports it and no other rule reports anything. The
baseline is the committed data itself, asserted to report nothing, which is what makes each probe
single-firing: 17 rules, 18 crafted inputs and the baseline, so 19 cases — the performance rule
has two, because a value the table reports differently still matches a field a source
declares, so its two branches cannot be shown by one input. The crafts change the data
in memory, never the files. The round hashes every file the check half reads before and after, so a
craft that reached a file is reported.

The crafts that would have to change a client's own source — the guard that fires before the request
is sent, and the values the records carry, which are placeholders — are what this half cannot show,
so they are named in `docs/clients.md` rather than asserted here.

Run it with `python3 Tools/clients/probes.py`, or through the check half with `--probe`.
"""

import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import parsers as read
import replay as check


def set_of(data, client):
    return data["sets"][client.lower().replace(" ", "-")]


def call_of(data, client, key):
    return next(call for call in set_of(data, client)["calls"] if call["key"] == key)


def row_of(data, client, call):
    return next(row for row in data["matrix"] if row["Client"] == client and row["Call"] == call)


def hash_of():
    """Every file the check half reads, hashed as the bytes the round started with.

    `sets` is a directory, so its entries are hashed as the files inside it rather than as the
    directory itself, which is the one thing here that cannot be hashed as bytes."""
    out = {}
    for name in sorted(read.DEFAULTS):
        path = read.DEFAULTS[name]
        if os.path.isdir(path):
            for entry in sorted(os.listdir(path)):
                out[f"{name}/{entry}"] = hashlib.sha256(
                    open(os.path.join(path, entry), "rb").read()).hexdigest()
        else:
            out[name] = hashlib.sha256(open(path, "rb").read()).hexdigest()
    return out


CASES = {
    # A set read from documentation cannot have a calling set, so a docs set with a call reports.
    "sets_name_the_source_and_a_set_read_from_docs_records_no_calls":
        lambda data: set_of(data, "NetNewsWire")["source"].__setitem__("kind", "docs"),

    # A value that reads as a captured response, not as the placeholder the half reads.
    "sets_are_redacted":
        lambda data: set_of(data, "NetNewsWire")["redaction"].__setitem__("token", "9f2c1a7b3e"),

    # A matrix row names a class the manifest line for the same call does not.
    "matrix_names_every_call_and_the_classes_agree_with_the_manifest":
        lambda data: row_of(data, "NetNewsWire", "reader/api/0/token").__setitem__(
            "Class", "subpath_answer"),

    # A class the matrix reads is named as read by the parity table, which has no row for it.
    "matrix_classes_are_read_by_the_matrix_and_parity_classes_have_a_row":
        lambda data: data["classes"][0].__setitem__("Read by", "docs/parity.md"),

    # A row names an answer the port registers no route for.
    "a_gr_call_reaches_a_route_the_port_registers_or_the_catch_all":
        lambda data: row_of(data, "NetNewsWire", "reader/api/0/token").__setitem__(
            "This port answers", "GET /reader/api/0/token-read"),

    # A row names a route the reference records nothing for. It has to be a row the counts rule
    # counts as reaching nothing, otherwise the same change is a finding for the counts rule too.
    "the_reference_answer_names_a_route_the_reference_registers":
        lambda data: row_of(data, "Reeder Classic", "no-call-recorded").__setitem__(
            "The reference reads", "GET /reader/api/0/not-a-route"),

    # A name the switch has a case for is written in the port's own switch as another name.
    "the_fever_names_are_read_from_the_dispatch_switch":
        lambda data: data.__setitem__("port_fever", data["port_fever"].replace(
            'named: "groups"', 'named: "groupz"')),

    # The half that reaches no route is named without the read it comes from.
    "the_half_with_no_routes_here_is_named_as_partial":
        lambda data: set_of(data, "lire")["halves"][1].pop("note"),

    # The recorded order is not the order the source declares.
    "the_recorded_sequence_is_the_set_the_source_declares":
        lambda data: set_of(data, "NetNewsWire")["source_order"].__setitem__(
            slice(2, 4), [set_of(data, "NetNewsWire")["source_order"][3],
                          set_of(data, "NetNewsWire")["source_order"][2]]),

    # A call that carries `T` reaches the read before the token is read.
    "the_login_record_is_first_and_the_token_precedes_every_call_that_needs_it":
        lambda data: set_of(data, "FeedFlow")["source_order"].__setitem__(
            slice(4, 7), [set_of(data, "FeedFlow")["source_order"][6],
                          *set_of(data, "FeedFlow")["source_order"][4:6]]),

    # The half the record names for one call is not the half the read takes for that method.
    "the_token_half_is_the_half_the_read_reads":
        lambda data: call_of(data, "NetNewsWire", "reader/api/0/token").__setitem__("auth", "form"),

    # A stream form with a suffix the branch has no case for.
    "the_stream_forms_are_the_forms_the_reference_reads":
        lambda data: call_of(data, "FeedFlow", "reader/api/0/rename-tag")["streams"].__setitem__(
            0, "user/-/state/com.google/unknown-thing"),

    # The counts table reports a count the records do not.
    "counts_match_the_records_they_report":
        lambda data: data["counts"][1].__setitem__("Calls recorded", "10"),

    # A call the matrix names as replayed here, whose record names a reason instead of a pin.
    "every_recorded_call_is_named_as_replayed_or_with_a_reason":
        lambda data: data["replayed"][0]["rest"].__setitem__(
            0, "not replayed here: the login half has no pin for it"),

    # A number the performance table claims was measured here, which the run did not answer.
    "performance_names_which_numbers_were_measured_here": [
        lambda data: data["perf_table"][0].__setitem__("Value", "2147"),
        # A field the table reads as measured here, which no source declares: the timed pin's own
        # print names a different field, so the run log line for it has no declared field.
        lambda data: data.__setitem__("perf_pin", data["perf_pin"].replace(
            "read_path=", "read_path_is_named_here=")),
    ],

    # A fact the check half has no item for, named by the document as not shown.
    "the_matrix_names_every_rule_and_what_it_cannot_show":
        lambda data: data["not_shown"].append("the number of the run that answered it"),

    # The name a client acts on, which the port does not write.
    "the_name_a_client_acts_on_is_the_name_the_port_writes":
        lambda data: set_of(data, "FeedFlow")["runtime_shape"].__setitem__(
            "acts_on_header", "X-Reader-Google-Wrong-Token"),
}

def cases():
    """The committed data as the baseline, and one crafted input per rule, in the order the rules
    are named in `docs/clients.md`, which is the order the round reads them in. The performance rule
    has two: its claim branch and its declared-field branch cannot both be shown by one input,
    because a value the table reports differently still matches a field the source declares."""
    out = [("baseline", None)]
    for name in sorted(check.RULES):
        craft = CASES[name]
        for change in (craft if isinstance(craft, list) else [craft]):
            out.append((name, change))
    return out


def assert_each():
    started = hash_of()
    failed = []
    baseline = check.run(read.DEFAULTS)
    if baseline:
        failed.append(f"baseline: reports {baseline}")
    for name, change in cases()[1:]:
        data = read.build_matrix(read.DEFAULTS)
        change(data)
        found = {rule_name: issues for rule_name, issues in
                 ((rule_name, rule(data)) for rule_name, rule in check.RULES.items()) if issues}
        if list(found) != [name]:
            failed.append(f"{name}: reports {sorted(found)}, expected this rule alone")
    ended = hash_of()
    for name in sorted(started):
        if started[name] != ended[name]:
            failed.append(f"{name}: the round changed a file it reads, so nothing was reverted")
    for line in failed:
        print(f"PROBE FAIL: {line}")
    if failed:
        return 1
    print(f"{len(cases())} probes: each rule reports its own input, and the baseline reports "
          f"nothing; every file the round read is byte-identical to what it started with")
    return 0


if __name__ == "__main__":
    raise SystemExit(assert_each())
