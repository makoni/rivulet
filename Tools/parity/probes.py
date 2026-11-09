#!/usr/bin/env python3
"""The probe set: one input per rule that violates it, and the assertion that the rule reports it.

This is the falsifiability half of the parity comparator. It is not a check on a live process: the
rules in `parity_check.py` are functions over the data a run left behind, so a probe is a crafted
piece of that data. Each input is the baseline pair — the run where every difference is covered —
with one thing changed, and the assertion is that the rule the change names reports it and no other
rule does. The
baseline is asserted to report nothing, which is what makes each probe single-firing.

Run it with `python3 Tools/parity/probes.py`, or through the comparator with `--probe`.

What the probe set cannot show is named in `docs/testing.md` under the harness: that the run ran at
all, and the half of the parse rule that reads no clock field, which no input can make report.
"""

import parity_check as check


def craft(change):
    """The baseline with one thing changed, so only the rule that change names can report it."""
    data = check.build_pair(check.DEFAULTS)
    change(data)
    return data


def drop_row(pair, class_name):
    """The same difference, with the covering row removed, so the rule that reads it reports it."""
    pair["recorded"] = [row for row in pair["recorded"] if row["class"] != class_name]


def request(side, key):
    return next(one for one in side["requests"] if one["key"] == key)


def flags_differ(data):
    data["port"]["run"]["flags"]["BATCH_SIZE"] = "50"


def other_reference(data):
    data["reference"]["run"]["reference"] = "v2.4.0 at 00000000"


def digest_differs(data):
    data["port"]["inputs"]["corpus/zone_pst.xml"] = "sha-other"


def row_from_a_file_the_manifest_does_not_name(data):
    data["port"]["entries"].append({"file": "corpus/extra.xml", "hash": "h7", "row": 67,
                                    "title": "extra", "content": "x", "published": 1719792000,
                                    "status": "unread", "starred": False, "clock": {}})
    data["port"]["counts"] = check.counted(data["port"], data)


def reordered(data):
    data["port"]["requests"] = list(reversed(data["port"]["requests"]))


def class_not_reached(data):
    row = next(row for row in data["recorded"] if row["class"] == "zone_offset")
    row["exercised_by"] = "corpus/tag_order.xml"


def entry_only_on_one_side(data):
    drop_row(data, "name_classes")


def count_broken(data):
    data["port"]["counts"]["starred"] = 1


def starred_on_one_side_only(data):
    row = next(row for row in data["reference"]["entries"] if row["file"] == "corpus/tag_order.xml")
    row["starred"] = True
    data["reference"]["counts"] = check.counted(data["reference"], data)


def content_not_covered(data):
    drop_row(data, "foster_parenting")


def id_from_the_other_side(data):
    item = request(data["port"], "request/stream_items_contents")["document"]["items"][0]
    item["id"] = check.ITEM_PREFIX + "%016x" % data["reference"]["entries"][0]["row"]


def empty_list_absent(data):
    request(data["port"], "request/stream_items_ids")["document"] = {}


def continuation_as_a_number(data):
    for side in check.sides(data):
        one = request(side, "request/stream_items_ids")
        value = 7 if side is data["port"] else "7"
        one["document"] = dict(one["document"], continuation=value)


def self_read_as_the_base_without_the_path(data):
    one = request(data["port"], "request/stream_items_contents")
    one["document"]["self"] = [{"href": data["port"]["run"]["base_url"]}]


def status_not_covered(data):
    drop_row(data, "method_mismatch")


def order_not_covered(data):
    drop_row(data, "collation_order")


def header_kept_the_second_value(data):
    request(data["port"], "request/repeated_header")["acted_on"] = {"X-Trace": "two"}


def proxy_on(data):
    data["reference"]["run"]["media_proxy_mode"] = "http-only"


def non_ascii_name(data):
    data["port"]["run"]["user"] = "p\u00e2rity"


def token_from_the_other_pair(data):
    one = request(data["port"], check.LOGIN)
    one["document"] = dict(one["document"], Auth="sid-from-the-other-pair")


def report_missing_a_rule(data):
    data["report"] = data["report"].replace("payload_ids_read_through_the_map", "")


CRAFTS = [
    ("flags_are_the_same_on_both_sides", flags_differ),
    ("run_names_the_pinned_reference_version", other_reference),
    ("inputs_are_the_same_on_both_sides", digest_differs),
    ("inputs_are_the_same_on_both_sides", row_from_a_file_the_manifest_does_not_name),
    ("request_sequence_is_the_same_on_both_sides", reordered),
    ("recorded_classes_are_exercised_by_the_corpus", class_not_reached),
    ("entry_set_is_the_feed_and_hash_pair", entry_only_on_one_side),
    ("counts_match_the_rows_they_report", count_broken),
    ("state_and_starred_match_for_matched_entries", starred_on_one_side_only),
    ("parse_results_match_and_clock_values_are_not_compared", content_not_covered),
    ("payload_ids_read_through_the_map", id_from_the_other_side),
    ("shape_rules_read_as_the_reference_writes_them", empty_list_absent),
    ("shape_rules_read_as_the_reference_writes_them", continuation_as_a_number),
    ("self_is_each_side_own_configured_base_url", self_read_as_the_base_without_the_path),
    ("statuses_match_except_where_a_recorded_row_covers_them", status_not_covered),
    ("order_compared_only_through_the_recorded_collation_row", order_not_covered),
    ("response_headers_read_with_the_first_value_winning", header_kept_the_second_value),
    ("media_proxy_is_none_on_the_reference_side", proxy_on),
    ("names_are_ascii_so_the_auth_read_is_one_rule_on_both_sides", non_ascii_name),
    ("login_half_answers_the_same_token_on_both_sides", token_from_the_other_pair),
    ("report_names_every_rule_and_what_the_run_cannot_show", report_missing_a_rule),
]


def cases():
    """The baseline, where every difference is covered, plus one input per rule that violates it."""
    out = [("baseline passes every rule", check.build_pair(check.DEFAULTS), [])]
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
