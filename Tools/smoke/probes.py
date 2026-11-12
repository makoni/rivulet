#!/usr/bin/env python3
"""The probe set: one document per rule that violates it, and the assertion it reports alone.

This is the falsifiability half of the smoke check. It is not a check on a live process: the rules
in `smoke_check.py` are functions over the document a run left behind, so a probe is a crafted copy
of that document. Each input is the committed run document — the run this machine produced, which
every rule reports nothing on — with one thing changed, and the assertion is that the rule the
change names reports it and no other rule does. The baseline case is that same document asserted to
report nothing, which is what makes each probe single-firing. The set is 59 crafts plus the baseline
over 19 rules: four rules have one craft and fifteen read more than one half.

Six halves cannot be fired by a crafted document alone: the corpus rule's missing-file half fires
only by taking that file away, which the shell guard shows; the runbook half fires only when
`docs/deploy.md` exists, which is the stage's open criterion; the order rule's clause half is read
from the batch file, so the crafts for that rule reach the values the run recorded and not the
clause; the corruption rule has no WAL half to craft, because the checkpoint the process harness
reads as an empty WAL is blocked by the write transaction the stop interrupted, so the bytes the run
recorded are the interrupted round's; and two halves of the machine rule are craftable only as the
labels the run declares: nothing can show that the containers the reads name are the ones the run
created, or that a run which left a container behind would have read it in the second pass, because
the run lists only what it started. Two more halves are craftable only through a value a committed
file declares, so the craft cannot set the value it compares: the policy rule's default half reads
the default the file declares, so a craft reaches it only with a value the switch reads as neither
on nor off, and the reader rule's endpoint half reads the route registration, so a craft reaches it
only by changing the run's word for the endpoint. The order rule reads the values the `add` calls
wrote: one craft puts them out of the declared order and another makes two of them one value. The
order the jobs of the round ran in is not craftable, because the pool dispatch fixes none, so that
half is named as a gap rather than asserted.

Four helpers keep other rules out of the crafts that reach them. `keep_copy_equal` reads the copy as
the rows the second snapshot holds, so a craft that changes that snapshot does not also change what
the copy rule reads; `set_due` keeps the mid-round count equal to the pick, so a craft that changes
the pick does not also report the count; and `others` takes a row the scheduling rule does not read
as the one in flight, so a craft on a field the stop does not write stays on the rule it names;
`change_url` writes a url change to both reads, so a craft that changes the row set does not also
reach the corruption rule, which compares that field between the two reads. The craft for the row-
set half takes the row out of the first read rather than the second, because the url and the counts
the row rule reads are read from the second, so such a craft reaches one rule.

Run it with `python3 Tools/smoke/probes.py`, or through the check half with `--probe`."""

import copy
import os

import smoke_check as check
import sources

BASELINE = check.load_document(sources.DEFAULTS["document"])


def craft(change):
    """The committed document with one thing changed, so only that rule can report it."""
    data = copy.deepcopy(BASELINE)
    change(data)
    return data


def held(data, side):
    """The row the run names as in flight, by the url naming the file the stub holds."""
    name = os.path.basename(data["stop"]["in_flight"])
    return next(row for row in data["snapshots"][side]["document"]["feeds"]
                if row["url"].endswith("/" + name))


def others(data, side):
    """A row the scheduling rule does not read as the one in flight."""
    name = os.path.basename(data["stop"]["in_flight"])
    return [row for row in data["snapshots"][side]["document"]["feeds"]
            if not row["url"].endswith("/" + name)]


def keep_copy_equal(data):
    """Read the copy as the rows the second snapshot holds, so the copy rule is not reached."""
    data["copy"]["rows"] = copy.deepcopy(data["snapshots"]["after_stop"]["document"]["feeds"])
    data["copy"]["counts"] = copy.deepcopy(data["snapshots"]["after_stop"]["document"]["totals"])


def set_due(data):
    """Read the round's due count as the pick the rules make, so the pick half alone fires."""
    before = data["snapshots"]["before_stop"]
    totals = before["document"]["totals"]
    totals["due"] = len(check.pick(before["document"]["feeds"], before["instant"],
                                   data["run"]["error_limit"], data["run"]["batch_size"]))


def base_is_not_the_dockerfile(data):
    data["run"]["base"] = "alpine"


def export_without_the_file_the_dockerfile_names(data):
    named = sources.docker_lines("COPY")[0].split()[-1].lstrip("/")
    data["image_content"] = [one for one in data["image_content"] if one != named]


def image_carries_other_bytes(data):
    data["run"]["image_copy_digest"] = "sha256:" + "0" * 64


def artifact_from_another_triple(data):
    data["run"]["triple"] = "aarch64-swift-linux-musl"


def more_feeds_than_the_manifest_holds(data):
    data["run"]["declared_feeds"] = 6


def record_for_bytes_the_file_does_not_hold(data):
    data["manifest"][0]["digest"] = "sha256:" + "1" * 64


def document_missing_a_record(data):
    data["manifest"] = data["manifest"][1:]


def console_answered_the_min_length_rule(data):
    data["answers"]["account"]["line"] = "Error: The password must be at least 6 bytes."


def migration_answered_another_migration(data):
    data["answers"]["migrate"] = "Applied 2 migration(s): SchemaV2."


def health_answered_another_status(data):
    data["answers"]["health"]["status"] = 503


def health_answered_another_body(data):
    data["answers"]["health"]["body"] = "ok"


def health_asked_another_path(data):
    data["answers"]["health"]["path"] = "/livez"


def login_answered_the_guard(data):
    data["answers"]["login"]["status"] = 403


def login_asked_other_field_names(data):
    data["answers"]["login"]["fields"] = ["Passwd", "username"]


def credentials_prompts_in_another_order(data):
    prompts = data["answers"]["login"]["prompts"]
    prompts[0], prompts[1] = prompts[1], prompts[0]


def pair_written_through_another_command(data):
    data["answers"]["login"]["written_through"] = "create-admin"


def reader_carried_another_token(data):
    data["answers"]["reader"]["carried_with"] = "token-from-an-earlier-login"


def reader_answered_without_finding_the_row(data):
    data["answers"]["reader"]["status"] = 401


def reader_answered_one_key_fewer(data):
    data["answers"]["reader"]["keys"] = [key for key in data["answers"]["reader"]["keys"]
                                         if key != "userEmail"]


def reader_answered_through_the_query(data):
    data["answers"]["reader"]["half"] = "query"


def reader_sent_another_header_name(data):
    data["answers"]["reader"]["name"] = "X-Auth"


def reader_value_began_with_another_word(data):
    data["answers"]["reader"]["field"] = "Auth"


def reader_asked_another_endpoint(data):
    data["answers"]["reader"]["endpoint"] = "/reader/api/0/tag/list"


def policy_set_another_name(data):
    data["run"]["policy"]["name"] = "FETCHER_ALLOW_PRIVATE"


def policy_read_as_off_on_a_refused_target(data):
    data["run"]["policy"]["value"] = "0"


def policy_value_reads_as_the_default(data):
    data["run"]["policy"]["value"] = ""


def target_is_a_class_the_policy_admits(data):
    data["run"]["target"] = "93.184.216.34"


def stub_recorded_no_request_for_one_input(data):
    name = os.path.basename(sources.manifest_rows()[0]["name"])
    data["events"] = [one for one in data["events"]
                      if not (one["action"] == "request" and one["name"] == name)]


def request_dated_before_the_round_started(data):
    first = next(one for one in data["events"] if one["action"] == "request")
    first["instant"] = data["rounds"]["started"] - 30


def an_input_answered_after_the_read(data):
    name = os.path.basename(sources.manifest_rows()[0]["name"])
    read_instant = data["snapshots"]["before_stop"]["instant"]
    for one in data["events"]:
        if one["action"] == "answered" and one["name"] == name:
            one["instant"] = read_instant + 20


def held_name(data):
    """The record the run names as the one in flight at the read."""
    return os.path.basename(data["stop"]["in_flight"])


def held_file_answered_before_the_read(data):
    read_instant = data["snapshots"]["before_stop"]["instant"]
    for one in data["events"]:
        if one["action"] == "answered" and one["name"] == held_name(data):
            one["instant"] = read_instant - 10


def held_answered_before_the_restart(data):
    read_instant = data["snapshots"]["before_stop"]["instant"]
    restarted = data["rounds"]["restarted"]
    for one in data["events"]:
        if one["action"] == "answered" and one["name"] == held_name(data):
            one["instant"] = read_instant + (restarted - read_instant) / 2


def read_taken_after_the_stop(data):
    data["snapshots"]["before_stop"]["instant"] = data["stop"]["instant"] + 20


def add_values_put_the_rows_in_another_order(data):
    values = data["answers"]["add_values"]
    values[0]["value"], values[1]["value"] = values[1]["value"], values[0]["value"]


def two_add_calls_wrote_one_value(data):
    values = data["answers"]["add_values"]
    values[1]["value"] = values[0]["value"]


def snapshot_carries_a_key_the_contract_does_not(data):
    data["snapshots"]["before_stop"]["document"]["clock"] = {}


def totals_carried_a_sixth_field(data):
    data["snapshots"]["before_stop"]["document"]["totals"]["last_round"] = 0


def row_carried_one_field_fewer(data):
    data["snapshots"]["before_stop"]["document"]["feeds"][0].pop("site_url")


def change_url(data, row, url):
    """Set one row's url in both reads, so the corruption rule sees the pair unchanged.

    The url is one of the fields a fetch does not write, so a craft that changed it in one read
    would also reach the corruption rule. The craft for the row set reads the second read only, so
    the change is written to both.
    """
    before = next(one for one in data["snapshots"]["before_stop"]["document"]["feeds"]
                  if one["id"] == row["id"])
    before["url"] = url
    row["url"] = url


def row_named_a_record_the_manifest_does_not_declare(data):
    row = others(data, "after_stop")[0]
    change_url(data, row, data["run"]["feed_base"] + "/smoke_zeta.xml")
    keep_copy_equal(data)


def two_rows_named_one_record(data):
    rows = others(data, "after_stop")
    change_url(data, rows[1], rows[0]["url"])
    keep_copy_equal(data)


def counts_do_not_match_the_rows(data):
    data["snapshots"]["after_stop"]["document"]["totals"]["feeds"] = 4
    keep_copy_equal(data)


def second_boot_answered_another_integrity_line(data):
    data["stop"]["integrity_line"] = "Database integrity check passed for the source only"


def stop_lost_a_row(data):
    feeds = data["snapshots"]["before_stop"]["document"]["feeds"]
    data["snapshots"]["before_stop"]["document"]["feeds"] = feeds[1:]


def stop_changed_a_field_it_does_not_write(data):
    others(data, "after_stop")[0]["enabled"] = False
    keep_copy_equal(data)


def pick_at_the_read_was_not_the_round_that_stopped(data):
    row = others(data, "before_stop")[0]
    row["next_check_at"] = data["snapshots"]["before_stop"]["instant"] - 10
    set_due(data)


def the_row_the_run_named_was_already_stamped(data):
    held(data, "before_stop")["fetched_at"] = data["snapshots"]["before_stop"]["instant"] - 60


def the_stamp_landed_before_the_stop(data):
    held(data, "after_stop")["fetched_at"] = data["stop"]["instant"] - 10
    keep_copy_equal(data)


def schedule_did_not_land_after_the_round(data):
    row = held(data, "after_stop")
    row["next_check_at"] = row["fetched_at"]
    keep_copy_equal(data)


def mid_round_due_is_not_the_pick(data):
    data["snapshots"]["before_stop"]["document"]["totals"]["due"] = 2


def copy_reported_another_line(data):
    data["copy"]["printed"] = "Backup verified: " + data["copy"]["path"]


def copy_has_a_wal_beside_it(data):
    data["copy"]["wal_beside"] = True


def copy_rows_are_not_the_source_rows(data):
    data["copy"]["rows"] = data["copy"]["rows"][:-1]


def copy_counts_are_not_the_source_counts(data):
    data["copy"]["counts"]["due"] = 3


def the_second_read_named_a_container_the_run_left(data):
    data["machine"]["left"]["entries"] = [{"name": f"smoke-run-2-{data['machine']['work']}",
                                           "running": False}]


def machine_read_named_a_container_the_run_did_not_create(data):
    data["machine"]["before"]["entries"] = [{"name": "smoke-run-1-from-an-earlier-run",
                                             "running": False}]


def machine_read_found_a_container_running(data):
    data["machine"]["before"]["entries"] = [{"name": f"smoke-run-1-{data['machine']['work']}",
                                             "running": True}]


def copy_read_before_the_machine_read(data):
    data["copy"]["instant"] = data["machine"]["left"]["instant"] - 30


def report_missing_a_rule(data):
    data["rules"] = [name for name in data["rules"] if name != "image_content"]


def report_missing_a_gap(data):
    data["cannot_show"] = data["cannot_show"][1:]


CRAFTS = [
    ("image_base", base_is_not_the_dockerfile),
    ("image_content", export_without_the_file_the_dockerfile_names),
    ("artifact_identity", image_carries_other_bytes),
    ("artifact_identity", artifact_from_another_triple),
    ("corpus_matches_manifest", more_feeds_than_the_manifest_holds),
    ("corpus_matches_manifest", record_for_bytes_the_file_does_not_hold),
    ("corpus_matches_manifest", document_missing_a_record),
    ("account_created", console_answered_the_min_length_rule),
    ("migration_answer", migration_answered_another_migration),
    ("health_answer", health_answered_another_status),
    ("health_answer", health_answered_another_body),
    ("health_answer", health_asked_another_path),
    ("login_answer", login_answered_the_guard),
    ("login_answer", login_asked_other_field_names),
    ("login_answer", credentials_prompts_in_another_order),
    ("login_answer", pair_written_through_another_command),
    ("login_answer", reader_carried_another_token),
    ("reader_answer", reader_answered_without_finding_the_row),
    ("reader_answer", reader_answered_one_key_fewer),
    ("reader_answer", reader_answered_through_the_query),
    ("reader_answer", reader_sent_another_header_name),
    ("reader_answer", reader_value_began_with_another_word),
    ("reader_answer", reader_asked_another_endpoint),
    ("policy_admits_the_target", policy_set_another_name),
    ("policy_admits_the_target", policy_read_as_off_on_a_refused_target),
    ("policy_admits_the_target", policy_value_reads_as_the_default),
    ("policy_admits_the_target", target_is_a_class_the_policy_admits),
    ("round_reached_the_stub", stub_recorded_no_request_for_one_input),
    ("round_reached_the_stub", request_dated_before_the_round_started),
    ("round_reached_the_stub", an_input_answered_after_the_read),
    ("round_reached_the_stub", held_file_answered_before_the_read),
    ("round_reached_the_stub", held_answered_before_the_restart),
    ("round_reached_the_stub", read_taken_after_the_stop),
    ("pick_order_follows_declared_order", add_values_put_the_rows_in_another_order),
    ("pick_order_follows_declared_order", two_add_calls_wrote_one_value),
    ("snapshot_contract", snapshot_carries_a_key_the_contract_does_not),
    ("snapshot_contract", totals_carried_a_sixth_field),
    ("snapshot_contract", row_carried_one_field_fewer),
    ("rows_match_manifest", row_named_a_record_the_manifest_does_not_declare),
    ("rows_match_manifest", two_rows_named_one_record),
    ("rows_match_manifest", counts_do_not_match_the_rows),
    ("stop_left_no_corruption", second_boot_answered_another_integrity_line),
    ("stop_left_no_corruption", stop_lost_a_row),
    ("stop_left_no_corruption", stop_changed_a_field_it_does_not_write),
    ("scheduling_resumed", pick_at_the_read_was_not_the_round_that_stopped),
    ("scheduling_resumed", the_row_the_run_named_was_already_stamped),
    ("scheduling_resumed", the_stamp_landed_before_the_stop),
    ("scheduling_resumed", schedule_did_not_land_after_the_round),
    ("scheduling_resumed", mid_round_due_is_not_the_pick),
    ("copy_equals_the_source", copy_reported_another_line),
    ("copy_equals_the_source", copy_has_a_wal_beside_it),
    ("copy_equals_the_source", copy_rows_are_not_the_source_rows),
    ("copy_equals_the_source", copy_counts_are_not_the_source_counts),
    ("machine_left_as_found", the_second_read_named_a_container_the_run_left),
    ("machine_left_as_found", machine_read_named_a_container_the_run_did_not_create),
    ("machine_left_as_found", machine_read_found_a_container_running),
    ("machine_left_as_found", copy_read_before_the_machine_read),
    ("report_names_rules_and_gaps", report_missing_a_rule),
    ("report_names_rules_and_gaps", report_missing_a_gap),
]


def cases():
    """The committed run document, plus one crafted document per rule that violates it."""
    out = [("baseline reports nothing", BASELINE, [])]
    out += [(f"{rule}: {change.__name__}", craft(change), [rule]) for rule, change in CRAFTS]
    return out


def assert_each():
    failed = []
    for name, data, expected in cases():
        fired = check.apply_rules(data)
        if fired != expected:
            failed.append(f"{name}: reported {fired or ['nothing']}, expected {expected}")
    for line in failed:
        print(f"PROBE FAIL: {line}")
    if failed:
        return 1
    print(f"{len(cases())} probes: each rule reports its own input, and the baseline reports nothing")
    return 0


if __name__ == "__main__":
    raise SystemExit(assert_each())
