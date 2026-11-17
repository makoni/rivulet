#!/usr/bin/env python3
"""The probe set: one input per rule that violates it, and the assertion that the rule reports it.
This is the falsifiability half of the client matrix. The rules in `replay.py` are functions over
the committed data, so a probe is a crafted input: the same data with one thing changed, and the
assertion is that the rule the change names reports it and no other rule reports anything. The
baseline is the committed data itself, asserted to report nothing, which is what makes each probe
single-firing: 19 rules, 35 crafted inputs and the baseline, so 36 cases — the performance rule
has one craft for each of the five kinds of finding it reads, the route rule has one for each of
its two halves, because an input that violates one half of a rule still satisfies the other, and the
rule that reads the run record has one for each of its eleven halves, twelve crafts in all: six on
the record the Fever run wrote here, one on the paragraph naming its calls, one on the record the
Google Reader run on the phone wrote here, one on the record the run on the Mac wrote, one on a
record this machine has not written, for a client whose set records no calls, one on the names the
round reads the record files under, which is the half that keeps the performance record, read by its
own rule at its own path, out of the client records, and one on the status a record line carries for
an error answer. One of those twelve reaches two parts of the data at once, the record line and the
paragraph that names the calls this run showed, because the half reads the record against the
paragraph and the Fever run reached no call outside the recorded set; that craft is named with the
rule in `docs/clients.md`.
The crafts change the data in memory, never the files. The round hashes every file the check half
reads before and after, so a craft that reached a file is reported. The crafts that would have to
change a client's own source — the bound the guard applies before the request is sent, and the
values the records carry, which are placeholders — are what this half cannot show, so they are
named in `docs/clients.md` rather than asserted here. Run it with `python3
Tools/clients/probes.py`, or through the check half with `--probe`."""

import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import parsers as read
import replay as check

# The three names the base document writes, read through the same read the rule uses, so a craft
# that adds a record line writes names the shape writes rather than restating them.
BASE_KEYS = read.base_shape_keys(read.DEFAULTS["port_shape"])
NEWSFLASH = "NewsFlash"


def set_of(data, client):
    return data["sets"][read.set_file_name(client)]


def call_of(data, client, key):
    return next(call for call in set_of(data, client)["calls"] if call["key"] == key)


def row_of(data, client, call):
    return next(row for row in data["matrix"] if row["Client"] == client and row["Call"] == call)


def lines_of(data, client):
    """The parsed record lines for the record the run wrote for one client. A client this machine
    has not run has no record, so the round reads an empty record for it, which is the half the
    craft adds a line to.
    """
    return data["observed"].setdefault(client, [])


def line_of(data, client, call):
    """The parsed record line for one call, as the run wrote it, read as the craft changes it. The
    record is the document the run left behind, so a craft changes the parsed line rather than
    the file, which is what the round hashes before and after.
    """
    return next(line for line in lines_of(data, client) if line["call"] == call)


def add_line(data, client, call, answer, keys, fields):
    """A record line the run did not write, added as the data the rule reads. The order is the next
    free one, so the added line cannot move the order the half reads. The rule reads a record for
    the client its lines name, so the client named here is the half this craft reaches, and the
    record it is added to is the record the round reads for that client.
    """
    order = max((line["order"] for line in lines_of(data, client)), default=0) + 1
    lines_of(data, client).append({"client": client, "order": order, "call": call, "method": "POST",
                                   "answer": answer, "keys": keys, "fields": fields})


def swap_order(data, first, second, client=NEWSFLASH):
    """Swap the order two calls carry, which is what a run that reached them the other way wrote."""
    a, b = line_of(data, client, first), line_of(data, client, second)
    a["order"], b["order"] = b["order"], a["order"]


def rename_in_record_and_paragraph(data, call, name):
    """Rename one call in the record and the same name in the paragraph that names the calls this
    run showed, because the half reads the record against the paragraph naming the call. The
    craft has to reach both: the run here reached no call outside the recorded set, so a craft
    that changed only the record would also be a finding for the half that reads a call the set
    cannot name.
    """
    line_of(data, NEWSFLASH, call)["call"] = name
    data.__setitem__("clients", data["clients"].replace(f"`{call}`", f"`{name}`"))


def hash_of():
    """Every file the check half reads, hashed as the bytes the round started with. `sets` is a
    directory, so its entries are hashed as the files inside it rather than as the directory
    itself, which is the one thing here that cannot be hashed as bytes. The record directory is
    hashed for the record files the rule reads, not for the files that sit beside them.
    """
    out = {}
    for name in sorted(read.DEFAULTS):
        path = read.DEFAULTS[name]
        if os.path.isdir(path):
            for entry in sorted(os.listdir(path)):
                full = os.path.join(path, entry)
                if os.path.isdir(full):
                    continue
                if name == "record_dir" and not entry.endswith(".txt"):
                    continue
                out[f"{name}/{entry}"] = hashlib.sha256(open(full, "rb").read()).hexdigest()
        else:
            out[name] = hashlib.sha256(open(path, "rb").read()).hexdigest()
    return out


CASES = {
    # A set read from documentation cannot have a calling set, so a docs set with a call reports.
    "sets_name_the_source_and_a_set_read_from_docs_records_no_calls":
        lambda data: set_of(data, "NetNewsWire")["source"].__setitem__("kind", "docs"),

    # A value that reads as a captured response, not as the placeholder the half reads. The set has
    # to be one this machine has not run: a change to the redaction of a client whose run wrote a
    # record is a finding for the rule that reads that record too, which is what the round showed
    # when the third record landed.
    "sets_are_redacted":
        lambda data: set_of(data, "lire")["redaction"].__setitem__("token", "9f2c1a7b3e"),

    # A matrix row names a class the manifest line for the same call does not.
    "matrix_names_every_call_and_the_classes_agree_with_the_manifest":
        lambda data: row_of(data, "NetNewsWire", "reader/api/0/token").__setitem__(
            "Class", "subpath_answer"),

    # A class the matrix reads is named as read by the parity table, which has no row for it.
    "matrix_classes_are_read_by_the_matrix_and_parity_classes_have_a_row":
        lambda data: data["classes"][0].__setitem__("Read by", "docs/parity.md"),

    # A row names an answer the port registers no route for. The row has to be one the record for
    # its client carries no line for — the same change on a row a record line reads is a finding for
    # the rule that reads the record as well. The second craft takes away the registration line the
    # catch-all half reads, which is the other half of the same rule.
    "a_gr_call_reaches_a_route_the_port_registers_or_the_catch_all": [
        lambda data: row_of(data, "FeedFlow", "reader/api/0/stream/contents").__setitem__(
            "This port answers", "POST /reader/api/0/stream/contents-not-registered"),
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

    # Two crafts for this rule, because its two halves cannot be shown by one input: a one-half
    # set has no other half to name, so the shape half is crafted on the set that names one half,
    # and the note half on the set that names two.
    "the_half_with_no_routes_here_is_named_as_partial": [
        lambda data: set_of(data, "lire")["halves"][1].pop("note"),
        lambda data: set_of(data, "Capy Reader")["runtime_shape"].__setitem__(
            "uses_two_halves", True),
    ],

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

    # The eleven halves of the rule that reads the run record, one craft each: six on the record the
    # Fever run wrote here, one on the paragraph that names its calls, one on the record the Google
    # Reader run wrote here, one on a record this machine has not written, which is the craft that
    # adds a line for a client whose set records no calls, one on the names the round reads the
    # record files under, and one on the status a record line carries for an error answer.
    "the_run_record_agrees_with_the_set_and_the_answer_it_names": [
        # The order the record carries, read as the order column, against the order the paragraph
        # names the calls the two have in common: the two names swap in the column.
        lambda data: swap_order(data, "fever/groups", "fever/mark/feed"),

        # The same half on the record the run on the Mac wrote, which is read because the paragraph
        # for that client is written in the form this half names. The two names swap in the column.
        lambda data: swap_order(data, "reader/api/0/rename-tag", "reader/api/0/disable-tag",
                                "NetNewsWire"),

        # A call the set cannot name, read against the paragraph naming the calls this run showed.
        # The line keeps the default answer, so the answer half is satisfied by the same input.
        lambda data: add_line(data, NEWSFLASH, "fever/folders", "dispatch: default", BASE_KEYS,
                              ["api_key"]),

        # The answer for a call the set names, read against the matrix row for that call.
        lambda data: line_of(data, NEWSFLASH, "fever/groups").__setitem__(
            "answer", "dispatch: feeds"),

        # The answer for a call the reference records no case for, which has to be the default
        # branch. This craft renames the call in the record and the same name in the paragraph,
        # because the run here reached no call outside the recorded set.
        lambda data: rename_in_record_and_paragraph(data, "fever/mark/item", "fever/folders"),

        # The client the record names, read against the set that client's row records: a client
        # whose set records no calls has no half to read its lines against.
        lambda data: add_line(data, "lire", "no-call-recorded", "no route here", [], ["T"]),

        # The branch the merged form gives, read through the mark the set names it with. The answer,
        # the key name and the redaction name on this line are the values the other halves read, so
        # the craft reaches the branch half alone.
        lambda data: add_line(data, "FeedFlow", "reader/api/0/edit-tag", "POST /reader/api/0/edit-tag",
                              ["itemRefs"], ["T", "s"]),

        # A key name the record carries that the file writes nowhere for this path.
        lambda data: line_of(data, NEWSFLASH, "fever/items").__setitem__("keys", ["folders"]),

        # The name the redaction names for the pair, taken off one line's fields.
        lambda data: line_of(data, NEWSFLASH, "fever/mark/feed").__setitem__("fields", ["as", "before",
                                                                                        "id", "mark"]),

        # The guarded call the record carries while the paragraph names another call as shown, which
        # is the half the guard covers: the bound, not the call that reached the port under it.
        lambda data: data.__setitem__("clients", data["clients"].replace(
            "`fever/items/with_ids`", "`fever/links`")),

        # A file in the record directory that the round does not name as a record for a client the
        # matrix has a row under. The performance record is read by its own rule at its own path, so
        # a half that read the directory as whatever sits in it would put that file in front of this
        # half, which is what it did before the read named the files.
        lambda data: data.__setitem__("record_files", sorted(data["record_files"] + ["stand-in.txt"])),

        # The status a record line carries for an error answer, read against the statuses the
        # handler the route file gives this path answers. The handler for `edit-tag` answers its
        # read errors as 400 and 500, so 404 is the shape it has no branch for: the craft moves the
        # status on the line the run wrote as a status answer for that call.
        lambda data: next(line for line in lines_of(data, "FeedFlow")
                          if line["answer"].startswith("status ")).__setitem__(
            "answer", "status 404"),
    ],
}


def cases():
    """The committed data as the baseline, and one crafted input per rule, in the order the document
    names the rules, which is the order the round reads them in. Four rules have more than one
    craft, because their branches cannot be shown by one input: the performance rule reports five
    kinds of finding, the route rule reads two halves, the rule that reads the run record reads
    eleven, and the rule that reads the half that reaches no route reads two, because a one-half set
    has no other half to name.
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
