#!/usr/bin/env python3
"""The rules the stage-7 parity comparator reads over the data one comparison run leaves behind.

This is the parity harness's check half (`Scripts/parity.sh` is the run half). It is not a test and
it does not run in CI: it reads two live systems — real Miniflux and Rivulet — over the same feed
corpus, so it is run by hand. Every rule here is a function over the data the run gathered, which is
what makes each of them falsifiable: `probes.py` crafts one input per rule that violates it and
asserts that the rule reports it alone.

A rule reports a difference only when nothing covers it. Coverage is the tolerance table in
`docs/parity.md`, read as data: a row marked `accepted` is a deviation the port keeps on purpose, a
row marked `fixed` is a rule the port already keeps so nothing may differ there, and a difference
whose class no row names is a finding. The corpus manifest names, for each input, the classes it can
reach, which is what lets a difference be attributed to a class rather than accepted by the
comparator's own preference. The guard rules report whatever the data says, whatever the table says.

Usage:
    parity_check.py --probe                       # the probe set against the committed data
    parity_check.py --pair PAIR.json              # apply the rules to one pair the run gathered
    parity_check.py --render                      # write the report the run commits

The pair document carries both sides. Each side carries the run it ran, the digest of each input the
manifest names, the rows it stored, the counts it reports, and the requests it answered. A request
carries the key of the corpus input or the request shape it came from, and the two sides are paired
by that key rather than by position, so a run that answered the same requests in a different order
still matches. The row ids of the two databases are never compared as values: they are the map, and
a payload item id is read through it. Order is compared only through the recorded collation row, and
the clock fields are never read at all — the rule that reads the parse results can never fail on a
clock difference, which is what that rule says.
"""

import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULTS = {"pair": os.path.join(HERE, "baseline.json"),
            "table": os.path.join(HERE, "..", "..", "docs", "parity.md"),
            "manifest": os.path.join(HERE, "corpus", "manifest.txt"),
            "report": os.path.join(HERE, "..", "..", "docs", "parity-report.md")}
SECTION = "## Parity harness (stage 7)"
ITEM_PREFIX = "tag:google.com,2005:reader/item/"

PINNED_REFERENCE = "v2.3.3 at c4d54f87"
CANNOT_SHOW = [
    "that the run ran at all, because it is on demand and not in CI",
    "that the two sides read the same bytes over the network, because each fetch is its own hop",
    "the row order a storage read answers for rows sharing one value, which SQL does not fix",
    "the clock fields, which each side wrote at its own write instant",
    "the rules the stage-3 corpora already pin, which the run re-reads rather than pins",
    "the rules that are tautologies on run data because the collector writes both sides from one "
    "source, so they can only be shown on crafted data: the input digests, the flags, the names "
    "the run asked with, and the response name read with the value that response answered, which "
    "are one read on a run",
    "the login half as one rule on both sides, because the reference reads the integration row, "
    "which only its web form writes, and this port has no web form, so the run has no path that "
    "sets that row for both sides",
    "the pinned version on the port side, because the rule that reads it reads only the reference "
    "side, where the run names the pinned version and the port names the build it ran",
    "the guards, which are shown only by declaring a value below what they require, and the seven "
    "that read data rather than a declared value, which fail only on a run",
    "the four classes no corpus input can reach, which are named in the table rather than asserted",
]
RULES = [
    "flags_are_the_same_on_both_sides",
    "run_names_the_pinned_reference_version",
    "inputs_are_the_same_on_both_sides",
    "request_sequence_is_the_same_on_both_sides",
    "recorded_classes_are_exercised_by_the_corpus",
    "entry_set_is_the_feed_and_hash_pair",
    "counts_match_the_rows_they_report",
    "state_and_starred_match_for_matched_entries",
    "parse_results_match_and_clock_values_are_not_compared",
    "payload_ids_read_through_the_map",
    "shape_rules_read_as_the_reference_writes_them",
    "self_is_each_side_own_configured_base_url",
    "statuses_match_except_where_a_recorded_row_covers_them",
    "order_compared_only_through_the_recorded_collation_row",
    "response_headers_read_with_the_first_value_winning",
    "media_proxy_is_none_on_the_reference_side",
    "names_are_ascii_so_the_auth_read_is_one_rule_on_both_sides",
    "report_names_every_rule_and_what_the_run_cannot_show",
]


def table(pair):
    return {row["class"]: row for row in pair["recorded"]}


def manifest(pair):
    return {entry["key"]: entry for entry in pair["manifest"]}


def sides(pair):
    return pair["reference"], pair["port"]


def input_keys(pair):
    return sorted(manifest(pair))


def classes_of(pair, key):
    return manifest(pair).get(key, {}).get("classes", [])


def covered(pair, key):
    """A difference from `key` is accepted when a recorded row names one of its classes."""
    return any(table(pair).get(name, {}).get("state") == "accepted" for name in classes_of(pair, key))


def request_pairs(pair):
    """Each request as the pair it is: the same request answered by both sides, matched by key."""
    right = {one["key"]: one for one in pair["port"]["requests"]}
    return [(left, right[left["key"]]) for left in pair["reference"]["requests"] if left["key"] in right]


def entry_map(pair):
    """The entries matched by the feed-and-hash pair, which is the reference's own dedupe key."""
    found = {}
    for side in sides(pair):
        for row in side["entries"]:
            found.setdefault((row["file"], row["hash"]), {})[side["side"]] = row
    return found


def counted(side, pair):
    rows = side["entries"]
    counts = {"entries": len(rows), "unread": sum(1 for row in rows if row["status"] == "unread"),
             "starred": sum(1 for row in rows if row["starred"])}
    counts["per_file"] = {key: sum(1 for row in rows if row["file"] == key) for key in input_keys(pair)}
    return counts


def feed_row(side, row):
    """The feed row the entry came from, or nothing when no recorded feed names that file."""
    return next((feed["row"] for feed in side["feeds"] if feed["file"] == row["file"]), None)


def item_hex(value):
    """The hex field the reference's item read takes, read as `fmt.Sscanf` with `%016x` reads it.

    The prefix decides which form it is: with the prefix the field is the value after it, and without
    the prefix the whole value is the field, which is the form the clients that do not follow the
    reference's own write send. Nothing here normalises the padding, because the scan keeps what it
    read rather than the whole value.
    """
    return value.split("reader/item/")[-1]


def rule_flags_are_the_same_on_both_sides(pair):
    ref, port = sides(pair)
    names = sorted(set(ref["run"]["flags"]) | set(port["run"]["flags"]))
    return [f"{name}: {ref['run']['flags'].get(name)!r} against {port['run']['flags'].get(name)!r}"
            for name in names if ref["run"]["flags"].get(name) != port["run"]["flags"].get(name)]


def rule_run_names_the_pinned_reference_version(pair):
    """Only the reference side can name the pinned version: the port side names the build it ran."""
    side = pair["reference"]
    if side["run"]["reference"] == PINNED_REFERENCE:
        return []
    return [f"the run read the reference as {side['run']['reference']!r}, not the pinned "
            f"{PINNED_REFERENCE!r}"]


def rule_inputs_are_the_same_on_both_sides(pair):
    ref, port = sides(pair)
    found = [f"{key}: {ref['inputs'].get(key)!r} against {port['inputs'].get(key)!r}"
            for key in input_keys(pair) if ref["inputs"].get(key) != port["inputs"].get(key)]
    for side in sides(pair):
        found += [f"{side['side']}: the row {row['hash']} came from {row['file']!r}, which the "
                  f"manifest does not name" for row in side["entries"] if row["file"] not in manifest(pair)]
    return found


def rule_request_sequence_is_the_same_on_both_sides(pair):
    def shape(side):
        return [(one["method"], one["path"], tuple(one["asked"])) for one in side["requests"]]

    ref, port = sides(pair)
    if shape(ref) == shape(port):
        return []
    return [f"the sequence is {shape(ref)} against {shape(port)}"]


def rule_recorded_classes_are_exercised_by_the_corpus(pair):
    """Each recorded row names an input that reaches it. The other half is not read here: a class
    the manifest reaches but no row names is a difference nothing covers, so the difference rules
    read it, and the probe that drops a row shows that half through them."""
    found = []
    for row in pair["recorded"]:
        key = row["exercised_by"]
        if key == "not reachable here":
            continue
        entry = manifest(pair).get(key)
        if entry is None:
            found.append(f"{row['class']}: the table claims {key!r} reaches it and the manifest names "
                         f"no such input")
        elif row["class"] not in entry["classes"]:
            found.append(f"{row['class']}: {key!r} names {entry['classes']}, not this class")
    return found


def rule_entry_set_is_the_feed_and_hash_pair(pair):
    ref, port = sides(pair)
    found = []
    for key in input_keys(pair):
        left = {row["hash"] for row in ref["entries"] if row["file"] == key}
        right = {row["hash"] for row in port["entries"] if row["file"] == key}
        if left != right and not covered(pair, key):
            found.append(f"{key}: {sorted(left)} against {sorted(right)}")
    return found


def rule_counts_match_the_rows_they_report(pair):
    found = []
    for side in sides(pair):
        for name, value in counted(side, pair).items():
            if side["counts"].get(name) != value:
                found.append(f"{side['side']}: counts.{name} reports {side['counts'].get(name)!r}, "
                             f"the rows give {value}")
    return found


def rule_state_and_starred_match_for_matched_entries(pair):
    found = []
    for key, row in sorted(entry_map(pair).items()):
        if len(row) < 2:
            continue
        found += [f"{key[1]}: {name} is {row['reference'][name]!r} against {row['port'][name]!r}"
                  for name in ("status", "starred") if row["reference"][name] != row["port"][name]]
    return found


def rule_parse_results_match_and_clock_values_are_not_compared(pair):
    """Reads title, content and published. The clock fields are not read, whatever they hold."""
    found = []
    for key, row in sorted(entry_map(pair).items()):
        if len(row) < 2 or covered(pair, key[0]):
            continue
        for name in ("title", "content", "published"):
            if row["reference"][name] != row["port"][name]:
                found.append(f"{key[0]}: {name} is {row['reference'][name]!r} against "
                             f"{row['port'][name]!r}")
    return found


def rule_payload_ids_read_through_the_map(pair):
    found = []
    for side in sides(pair):
        rows = {row["row"]: row for row in side["entries"]}
        for one in side["requests"]:
            for item in one["document"].get("items", []):
                row = rows.get(int(item_hex(item["id"]), 16))
                if row is None:
                    found.append(f"{side['side']}: item id {item['id']} is not the form of a row this "
                                 f"side has")
                    continue
                feed = feed_row(side, row)
                if feed is None:
                    continue
                stream = item["origin"]["streamId"].rsplit("/", 1)[-1]
                if stream != str(feed):
                    found.append(f"{side['side']}: item {item['id']} names the stream {stream}, not "
                                 f"its own feed row {feed}")
    return found


def rule_shape_rules_read_as_the_reference_writes_them(pair):
    found = []
    for left, right in request_pairs(pair):
        if set(left["document"]) != set(right["document"]):
            found.append(f"{left['key']}: the keys are {sorted(left['document'])} against "
                         f"{sorted(right['document'])}")
        for name in sorted(set(left["document"]) & set(right["document"])):
            first, other = left["document"][name], right["document"][name]
            if type(first) is not type(other):
                found.append(f"{left['key']}: {name} is written as {type(first).__name__} against "
                             f"{type(other).__name__}")
            if name == "continuation" and not isinstance(first, str):
                found.append(f"{left['key']}: continuation is written as {first!r}, not as a string")
    return found


def rule_self_is_each_side_own_configured_base_url(pair):
    found = []
    for side in sides(pair):
        base = side["run"]["base_url"]
        for one in side["requests"]:
            for href in one["document"].get("self", []):
                if href["href"] != base + one["path"]:
                    found.append(f"{side['side']}: self is {href['href']!r}, not the configured base "
                                 f"{base!r} plus the request path")
    return found


def rule_statuses_match_except_where_a_recorded_row_covers_them(pair):
    return [f"{left['key']}: {left['status']} against {right['status']}"
            for left, right in request_pairs(pair)
            if left["status"] != right["status"] and not covered(pair, left["key"])]


def rule_order_compared_only_through_the_recorded_collation_row(pair):
    found = []
    for left, right in request_pairs(pair):
        order = [tag["label"] for tag in left["document"].get("tags", [])]
        other = [tag["label"] for tag in right["document"].get("tags", [])]
        if order != other and not covered(pair, left["key"]):
            found.append(f"{left['key']}: {order} against {other}")
    return found


def rule_response_headers_read_with_the_first_value_winning(pair):
    ref, port = sides(pair)
    found = []
    for left, right in request_pairs(pair):
        repeated = sorted(name for name, values in left["headers"].items() if len(values) > 1)
        for name in repeated:
            first = left["headers"][name][0]
            for side, one in ((ref, left), (port, right)):
                if name in one["acted_on"] and one["acted_on"][name] != first:
                    found.append(f"{side['side']}: {name} appears twice and that response answered "
                                 f"{one['acted_on'][name]!r}, not the first value {first!r}")
    return found


def rule_media_proxy_is_none_on_the_reference_side(pair):
    mode = pair["reference"]["run"]["media_proxy_mode"]
    if mode == "none":
        return []
    return [f"the reference ran with the proxy mode {mode!r}, so the content values are its rewrite "
            f"rather than the stored bytes"]


def rule_names_are_ascii_so_the_auth_read_is_one_rule_on_both_sides(pair):
    return [f"{side['side']}: the name {side['run']['user']!r} is not ASCII, and this port's LOWER "
            f"folds ASCII only" for side in sides(pair)
            if any(char > "\u007f" for char in side["run"]["user"])]


def rule_report_names_every_rule_and_what_the_run_cannot_show(pair):
    text = pair["report"]
    found = [f"the report does not name the rule {name}" for name in pair["rules"] if name not in text]
    found += [f"the report does not name the class {row['class']}" for row in pair["recorded"]
              if row["class"] not in text]
    found += [f"the report does not name what the run cannot show: {item}" for item in CANNOT_SHOW
              if item not in text]
    return found


def findings(pair):
    return {name: globals()["rule_" + name](pair) for name in pair["rules"]}


def apply_rules(pair):
    return [name for name in pair["rules"] if findings(pair)[name]]


def render(pair):
    """The report the run writes: every rule applied, every class read, what it cannot show."""
    lines = ["# Parity harness report", "", "Rules the run applied:"]
    lines += [f"- {name}" for name in pair["rules"]]
    lines += ["", "Classes the run read:"]
    lines += [f"- {row['class']}: {row['state']}" for row in pair["recorded"]]
    lines += ["", "What the run cannot show:", *[f"- {item}" for item in CANNOT_SHOW]]
    return "\n".join(lines)


def parse_table(text):
    rows = []
    for line in text[text.index(SECTION):].splitlines()[2:]:
        if line.startswith("## "):
            break
        if not line.startswith("|") or line.count("|") < 5:
            continue
        cells = [cell.strip() for cell in line.strip("|").split("|")]
        if cells[0] in ("Class", "---") or cells[1] == "---":
            continue
        rows.append({"class": cells[0], "row": cells[1], "state": cells[2], "exercised_by": cells[3]})
    return rows


def parse_manifest(text):
    entries = []
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        parts = [part.strip() for part in line.split("|")]
        entries.append({"key": parts[0], "classes": parts[1].split(","), "cannot": parts[2]})
    return entries


def build_pair(paths, report=None):
    document = json.load(open(paths["pair"]))
    return {"rules": list(RULES), "recorded": parse_table(open(paths["table"]).read()),
            "manifest": parse_manifest(open(paths["manifest"]).read()),
            "report": report if report is not None else open(paths["report"]).read(),
            "reference": document["reference"], "port": document["port"]}


def main(argv):
    paths = dict(DEFAULTS)
    args = argparse.ArgumentParser(description="Apply the parity rules to one comparison pair")
    args.add_argument("--pair", help="the pair document: the run's, or baseline.json for the probes")
    args.add_argument("--recorded", help="the tolerance table, read from docs/parity.md")
    args.add_argument("--manifest", help="the corpus manifest")
    args.add_argument("--report", help="the committed report: read in pair mode, written in render")
    args.add_argument("--probe", action="store_true", help="assert each rule reports its own input")
    args.add_argument("--render", action="store_true", help="write the report instead of applying")
    opts = vars(args.parse_args(argv))
    for name in ("pair", "recorded", "manifest", "report"):
        if opts[name]:
            paths[name] = opts[name]

    if opts["probe"]:
        sys.path.insert(0, HERE)
        import probes
        return probes.assert_each()

    pair = build_pair(paths, "" if opts["render"] else None)
    if opts["render"]:
        open(paths["report"], "w").write(render(pair) + "\n")
        print(f"wrote {paths['report']}")
        return 0

    violations = apply_rules(pair)
    for name in violations:
        print(f"VIOLATION: {name}")
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
