#!/usr/bin/env python3
"""The probe set: one input per rule that violates it, and the assertion that the rule reports it.

This is the falsifiability half of the client matrix. The rules in `replay.py` are functions over
the committed data, so a probe is a crafted input: the same data with one thing changed, and the
assertion is that the rule the change names reports it and no other rule reports anything. The
baseline is the committed data itself, asserted to report nothing, which is what makes each probe
single-firing: 19 rules, 30 crafted inputs and the baseline, so 31 cases — the performance rule has
one craft for each of the five kinds of finding it reads, the route rule has one for each of its two
halves, because an input that violates one half of a rule still satisfies the other, and the rule
that reads the run record has one for each of its seven halves, on the record the run wrote here.
One of those seven reaches two parts of the data at once, the record line and the paragraph that
names the calls this run showed, because the half reads the record against the paragraph and this
run reached no call outside the recorded set; that craft is named with the rule in
`docs/clients.md`. The crafts change the data in memory, never the files. The round hashes every
file the check half reads before and after, so a craft that reached a file is reported.

The crafts that would have to change a client's own source — the bound the guard applies before the
request is sent, and the values the records carry, which are placeholders — are what this half
cannot show, so they are named in `docs/clients.md` rather than asserted here.

Run it with `python3 Tools/clients/probes.py`, or through the check half with `--probe`.
"""

import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import parsers as read
import replay as check

# The three names the base document writes, read through the same read the rule uses, so a craft
# that adds a record line writes names the shape writes rather than restating them.
BASE_KEYS = read.base_shape_keys(read.DEFAULTS["port_shape"])


def set_of(data, client):
    return data["sets"][client.lower().replace(" ", "-")]


def call_of(data, client, key):
    return next(call for call in set_of(data, client)["calls"] if call["key"] == key)


def row_of(data, client, call):
    return next(row for row in data["matrix"] if row["Client"] == client and row["Call"] == call)


def line_of(data, call):
    """The parsed record line for one call, as the run wrote it, read as the craft changes it.

    The record is the document the run left behind, so a craft changes the parsed line rather than
    the file, which is what the round hashes before and after.
    """
    return next(line for line in data["observed"] if line["call"] == call)


def add_line(data, call, answer, keys, fields):
    """A record line the run did not write, added as the data the rule reads.

    The order is the next free one, so the added line cannot move the order the half reads.
    """
    order = max(line["order"] for line in data["observed"]) + 1
    data["observed"].append({"client": "NewsFlash", "order": order, "call": call, "method": "POST",
                             "answer": answer, "keys": keys, "fields": fields})


def swap_order(data, first, second):
    """Swap the order two calls carry, which is what a run that reached them the other way wrote."""
    a, b = line_of(data, first), line_of(data, second)
    a["order"], b["order"] = b["order"], a["order"]


def rename_in_record_and_paragraph(data, call, name):
    """Rename one call in the record and the same name in the paragraph that names the calls this
    run showed, because the half reads the record against the paragraph naming the call.

    The craft has to reach both: the run here reached no call outside the recorded set, so a craft
    that changed only the record would also be a finding for the half that reads a call the set
    cannot name.
    """
    line_of(data, call)["call"] = name
    data.__setitem__("clients", data["clients"].replace(f"`{call}`", f"`{name}`"))


def hash_of():
    """Every file the check half reads, hashed as the bytes the round started with.

    `sets` is a directory, so its entries are hashed as the files inside it rather than as the
    directory itself, which is the one thing here that cannot be hashed as bytes.
    """
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

    # A row names an answer the port registers no route for. The second craft takes away the
    # registration line the catch-all half reads, which is the other half of the same rule.
    "a_gr_call_reaches_a_route_the_port_registers_or_the_catch_all": [
        lambda data: row_of(data, "NetNewsWire", "reader/api/0/token").__setitem__(
            "This port answers", "GET /reader/api/0/token-read"),
        lambda data: data.__setitem__("port_routes", data["port_routes"].replace(
            'on(.GET, "**"', 'on(.GET, "**-not-registered"')),
    ],

    # A row reads as the output check for an endpoint the reference applies the check on nowhere:
    # the craft moves one endpoint from the applied set to the refused set in the reference's note.
    "the_output_check_class_names_an_endpoint_the_reference_applies_the_check_on":
        lambda data: data.__setitem__("reference", data["reference"].replace(
            "that apply it are `tag/list`", "that apply it are `stream/items/ids`")),

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

    # The five kinds the performance rule reads, each with its own craft: a claim the log does not
    # carry, a field no source declares, a record line the document does not name, a shape the
    # document names differently than the run answered it, and the value the table reports against
    # the value the log carries.
    "performance_names_which_numbers_were_measured_here": [
        lambda data: data["perf_table"].append({"Run": "run 5", "Source": "Scripts/perf.sh",
                                               "Field": "pass_wall_ms", "Value": "2200",
                                               "Named as": "measured here"}),
        # A field the table reads as measured here, which no source declares: the timed pin's own
        # print names a different field, so the run log line for it has no declared field.
        lambda data: data.__setitem__("perf_pin", data["perf_pin"].replace(
            "read_path=", "read_path_is_named_here=")),
        lambda data: data["perf_table"].pop(0),
        lambda data: data["shape"].__setitem__("feeds", "90"),
        lambda data: data["perf_table"][0].__setitem__("Value", "2147"),
    ],

    # A fact the check half has no item for, named by the document as not shown.
    "the_matrix_names_every_rule_and_what_it_cannot_show":
        lambda data: data["not_shown"].append("the number of the run that answered it"),

    # The name a client acts on, which the response builder does not write: the craft renames the
    # name in the file that writes it, which is the input this rule reads.
    "the_name_a_client_acts_on_is_the_name_the_builder_writes":
        lambda data: data.__setitem__("port_response", data["port_response"].replace(
            'name: "X-Reader-Google-Bad-Token"', 'name: "X-Reader-Local-Bad-Token"')),

    # The seven halves of the rule that reads the run record, one craft each, on the record the run
    # wrote here.
    "the_run_record_agrees_with_the_set_and_the_answer_it_names": [
        # The order the record carries, read as the order column, against the order the paragraph
        # names the calls the two have in common: the two names swap in the column.
        lambda data: swap_order(data, "fever/groups", "fever/mark/feed"),

        # A call the set cannot name, read against the paragraph naming the calls this run showed.
        # The line keeps the default answer, so the answer half is satisfied by the same input.
        lambda data: add_line(data, "fever/folders", "dispatch: default", BASE_KEYS, ["api_key"]),

        # The answer for a call the set names, read against the matrix row for that call.
        lambda data: line_of(data, "fever/groups").__setitem__("answer", "dispatch: feeds"),

        # The answer for a call the reference records no case for, which has to be the default
        # branch. This craft renames the call in the record and the same name in the paragraph,
        # because the run here reached no call outside the recorded set.
        lambda data: rename_in_record_and_paragraph(data, "fever/mark/item", "fever/folders"),

        # A key name the record carries that the response shape writes nowhere.
        lambda data: line_of(data, "fever/items").__setitem__("keys", ["folders"]),

        # The name the redaction names for the pair, taken off one line's fields.
        lambda data: line_of(data, "fever/mark/feed").__setitem__("fields", ["as", "before", "id",
                                                                            "mark"]),

        # The guarded call the record carries while the paragraph names another call as shown, which
        # is the half the guard covers: the bound, not the call that reached the port under it.
        lambda data: data.__setitem__("clients", data["clients"].replace(
            "`fever/items/with_ids`", "`fever/links`")),
    ],
}


def cases():
    """The committed data as the baseline, and one crafted input per rule, in the order the
    document names the rules, which is the order the round reads them in. Three rules have more
    than one craft, because their branches cannot be shown by one input: the performance rule
    reports five kinds of finding, the route rule reads two halves, and the rule that reads the run
    record reads seven.
    """
    out = [("baseline", None)]
    for name in read.build_matrix(read.DEFAULTS)["rule_names"]:
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
    print(f"{len(cases())} cases over {len(check.RULES)} rules — {len(cases()) - 1} crafted "
          f"inputs plus the baseline: each rule reports its own input alone, and the baseline "
          f"reports nothing; every file the round read is byte-identical to what it started with")
    return 0


if __name__ == "__main__":
    raise SystemExit(assert_each())
