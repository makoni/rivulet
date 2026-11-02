#!/usr/bin/env python3
"""The rules the stage-4 soak checks on each round, and the probes that show each can fail.

This is the stage-4 soak artifact's check half (`Scripts/soak.sh` is the run half). It is not a
test and it does not run in CI: it reads data the shell gathered, so every rule here is a function
over that data rather than a check on a live process. The rules are what the stage's exit criteria
ask the soak to show, plus the shape of the `status --json` contract they read, and each rule can
fail on the rule it names — the probe set at the bottom crafts one input per rule that violates it
and asserts that the rule reports it alone.

What the rules cannot show is stated in `docs/testing.md` under the soak: that the run slept at all,
that the fetcher reached the network, and which round a row was read in. Those are properties of the
run, not of the data a round reports, so the soak names them as observed rather than as pinned. The
run's own numbers — the ≥2h duration and the ≥20 feeds — are guards in `Scripts/soak.sh`, because
the number a run declares is not something a check over a round's data can fail on.

Usage:
    soak_check.py --prev P.json --cur C.json --instant-prev N --instant-cur N \
        --error-limit L --batch-size B --host-limit 0 --min-feeds M --error-feed ID \
        --error-increments K --exit-refresh R --exit-status S --rules names [--db file]
    soak_check.py --probe                 # assert each rule fails on its crafted input

The rules read the two snapshots and the values the run declared; `--db` is only for the rules that
read the database, and the probes pass their inputs as data, so no probe touches a live process.

The snapshot documents are what `rivulet status --json` prints; the rules read them as the contract
documents them, so a round that reports a document the contract does not describe fails.
"""

import argparse
import json
import sys

DOCUMENT_KEYS = {"feeds", "totals"}
ROW_KEYS = {"id", "user_id", "title", "url", "site_url", "enabled", "fetched_at", "next_check_at",
           "parsing_error_count", "parsing_error_message"}
TOTAL_KEYS = {"feeds", "enabled", "disabled", "due", "at_error_limit"}
STAMP_KEYS = {"fetched_at", "next_check_at"}


def pick(rows, now, error_limit, batch_size, host_limit):
    """The rows the batch rules select at `now`, as `FeedRepository+Batch.swift` writes them.

    Strict due-ness, the disabled gate, the two switches that read a zero as off, and the window.
    This port's `due` count is the number the query returns, so the window caps it.
    """
    if host_limit:
        raise ValueError("the pick is only computable with the host limit off, which the soak sets")
    due = [entry for entry in rows
           if entry.get("enabled")
           and entry.get("next_check_at") is not None and entry.get("next_check_at") < now
           and (error_limit == 0 or entry.get("parsing_error_count", 0) < error_limit)]
    return due[:batch_size] if batch_size else due


def rows_by_id(data, side):
    return {entry["id"]: entry for entry in data[side]["feeds"] if "id" in entry}


def ran_ids(data):
    """The rows the round stamped — the ones whose last-fetch value the pass moved."""
    before = rows_by_id(data, "prev")
    moved = [entry["id"] for entry in data["cur"]["feeds"]
             if "id" in entry and entry.get("fetched_at") != before.get(entry["id"], {}).get(
                 "fetched_at")]
    return sorted(moved)


def expected_type(key):
    if key in STAMP_KEYS:
        return (int, type(None))
    if key == "enabled":
        return bool
    return int if key in {"id", "user_id", "parsing_error_count"} else str


def rule_document_shape(data):
    found = []
    for side in ("prev", "cur"):
        document = data[side]
        if set(document) != DOCUMENT_KEYS:
            found.append(f"{side}: document keys {sorted(set(document))}")
        if set(document.get("totals", {})) != TOTAL_KEYS:
            found.append(f"{side}: totals keys {sorted(set(document.get('totals', {})))}")
        for key, value in document.get("totals", {}).items():
            if not isinstance(value, int):
                found.append(f"{side}: totals.{key} reads {value!r}")
        for entry in document.get("feeds", []):
            missing = ROW_KEYS - set(entry)
            if missing:
                found.append(f"{side}: row {entry.get('id')} has no key {sorted(missing)}")
            for key, value in entry.items():
                if not isinstance(value, expected_type(key)):
                    found.append(f"{side}: row {entry.get('id')} reads {key} as {value!r}")
    return found


def rule_id_order(data):
    ids = [entry.get("id") for entry in data["cur"]["feeds"]]
    return [f"cur: rows are not in id order ({ids})"] if ids != sorted(ids) else []


def rule_totals_match_rows(data):
    # `due` is not read here: it is the pick, and `rule_due_matches_pick` reports it.
    rows = data["cur"]["feeds"]
    limit = data["error_limit"]
    read = {
        "feeds": len(rows),
        "enabled": sum(1 for entry in rows if entry.get("enabled")),
        "disabled": sum(1 for entry in rows if not entry.get("enabled")),
        "at_error_limit": 0 if limit == 0 else sum(
            1 for entry in rows if entry.get("parsing_error_count", 0) >= limit),
    }
    return [f"cur: totals.{key} reports {data['cur']['totals'].get(key)}, the rows give {value}"
            for key, value in read.items() if data["cur"]["totals"].get(key) != value]


def rule_due_matches_pick(data):
    # The instant compared here is the one the shell recorded just before the status command read
    # the row, so a row crossing the due boundary between the two reads as a violation. The reported
    # count comes from the query's clock, at or after the recorded instant, so the mismatch can only
    # go one way: this rule can fail falsely, it cannot pass falsely.
    expected = pick(data["cur"]["feeds"], data["instants"]["cur"], data["error_limit"],
                    data["batch_size"], data["host_limit"])
    reported = data["cur"]["totals"].get("due")
    if reported != len(expected):
        return [f"cur: totals.due reports {reported}, the pick is "
                f"{sorted(entry['id'] for entry in expected)}"]
    return []


def rule_pick_ran_exactly(data):
    expected = sorted(entry["id"] for entry in pick(data["prev"]["feeds"], data["instants"]["prev"],
                                                    data["error_limit"], data["batch_size"],
                                                    data["host_limit"]))
    ran = ran_ids(data)
    return [f"the round stamped {ran} but the pick was {expected}"] if ran != expected else []


def rule_fetched_stamp_moves_forward(data):
    before = rows_by_id(data, "prev")
    found = []
    for entry in data["cur"]["feeds"]:
        if entry["id"] not in ran_ids(data):
            continue
        old = before.get(entry["id"], {}).get("fetched_at")
        new = entry.get("fetched_at")
        if old is None or new is None:
            continue
        if new <= old:
            found.append(f"row {entry['id']}: fetched_at {old} -> {new}")
    return [f"fetched_at did not move forward: {found}"] if found else []


def rule_schedule_moved_forward(data):
    before = rows_by_id(data, "prev")
    found = []
    for entry in data["cur"]["feeds"]:
        if entry["id"] not in ran_ids(data):
            continue
        old, new = before.get(entry["id"], {}).get("next_check_at"), entry.get("next_check_at")
        if new is None:
            found.append(f"row {entry['id']}: next_check_at is null after the round")
        elif old is not None and new <= old:
            found.append(f"row {entry['id']}: next_check_at {old} -> {new}")
        elif new <= data["instants"]["cur"]:
            found.append(f"row {entry['id']}: next_check_at {new} is not after the round "
                         f"({data['instants']['cur']})")
    return [f"the schedule did not move forward: {found}"] if found else []


def rule_error_counter(data):
    before = rows_by_id(data, "prev")
    found = []
    for entry in data["cur"]["feeds"]:
        if entry["id"] not in ran_ids(data):
            continue
        old = before.get(entry["id"], {}).get("parsing_error_count", 0)
        new = entry.get("parsing_error_count", 0)
        if new != 0 and new != old + 1:
            found.append(f"row {entry['id']}: parsing_error_count {old} -> {new}")
    return [f"a row that ran was neither reset nor incremented: {found}"] if found else []


def rule_error_path_observed(data):
    if data["error_increments"] < 1:
        return [f"the error feed {data['error_feed_id']} never incremented"]
    return []


def rule_no_crash(data):
    return [f"{name} exited {code}" for name, code in data["exit_codes"].items() if code != 0]


def rule_entries_have_no_duplicate_pair(data):
    return [f"(feed_id, hash) duplicated: {pair}" for pair in data["duplicate_pairs"]]


def rule_every_enabled_row_was_fetched(data):
    # The row already at the limit can never be picked, so the rule reads only the rows the pick
    # could reach: enabled and under the limit.
    limit = data["error_limit"]
    never = [entry["id"] for entry in data["cur"]["feeds"] if entry.get("enabled")
            and (limit == 0 or entry.get("parsing_error_count", 0) < limit)
            and entry.get("fetched_at") is None]
    return [f"enabled rows the pick could reach, never fetched: {never}"] if never else []


def rule_integrity_is_ok(data):
    return [] if data["integrity"] == "ok" else [f"integrity_check answered {data['integrity']!r}"]


def rule_row_count_matches_the_declaration(data):
    if len(data["cur"]["feeds"]) < data["min_feeds"]:
        return [f"the snapshot has {len(data['cur']['feeds'])} rows, the run declared "
                f"{data['min_feeds']}"]
    return []


RULES = {
    "document_shape": rule_document_shape,
    "id_order": rule_id_order,
    "totals_match_rows": rule_totals_match_rows,
    "due_matches_pick": rule_due_matches_pick,
    "pick_ran_exactly": rule_pick_ran_exactly,
    "fetched_stamp_moves_forward": rule_fetched_stamp_moves_forward,
    "schedule_moved_forward": rule_schedule_moved_forward,
    "error_counter": rule_error_counter,
    "error_path_observed": rule_error_path_observed,
    "no_crash": rule_no_crash,
    "entries_have_no_duplicate_pair": rule_entries_have_no_duplicate_pair,
    "every_enabled_row_was_fetched": rule_every_enabled_row_was_fetched,
    "integrity_is_ok": rule_integrity_is_ok,
    "row_count_matches_the_declaration": rule_row_count_matches_the_declaration,
}


def apply_rules(data):
    return [name for name in data["rules"] if RULES[name](data)]


def row(id, user_id, title, url, site_url, enabled, fetched_at, next_check_at,
        parsing_error_count, parsing_error_message):
    return {"id": id, "user_id": user_id, "title": title, "url": url, "site_url": site_url,
            "enabled": enabled, "fetched_at": fetched_at, "next_check_at": next_check_at,
            "parsing_error_count": parsing_error_count, "parsing_error_message": parsing_error_message}


def totals(feeds, enabled, disabled, due, at_error_limit):
    return {"feeds": feeds, "enabled": enabled, "disabled": disabled, "due": due,
            "at_error_limit": at_error_limit}


def recompute(data):
    """The totals as the current rows give them, so a probe changes one rule and not another."""
    rows = data["cur"]["feeds"]
    limit = data["error_limit"]
    data["cur"]["totals"] = {
        "feeds": len(rows),
        "enabled": sum(1 for entry in rows if entry.get("enabled")),
        "disabled": sum(1 for entry in rows if not entry.get("enabled")),
        "due": len(pick(rows, data["instants"]["cur"], limit, data["batch_size"],
                        data["host_limit"])),
        "at_error_limit": 0 if limit == 0 else sum(
            1 for entry in rows if entry.get("parsing_error_count", 0) >= limit),
    }
    return data


def row_of(data, id):
    return next(entry for entry in data["cur"]["feeds"] if entry["id"] == id)


def baseline():
    """One round where exactly the pick ran: one success, one error, three rows that stayed put.

    The round instant is 1100, the error limit is 2 and the window is larger than the rows, so the
    pick is the set of rows the rules select. Row 1 is due and ran, row 5 is due and ran and failed,
    row 2 is not due, row 3 is disabled and row 4 is at the limit — the two gates and the strict
    comparison each have a row of their own, which is what makes the probes separable.
    """
    prev = {"feeds": [
        row(1, 1, "one", "http://h/1.xml", "http://h/", True, 900, 1000, 0, ""),
        row(2, 1, "two", "http://h/2.xml", "http://h/", True, 950, 2000, 0, ""),
        row(3, 1, "three", "http://h/3.xml", "http://h/", False, 900, 1000, 0, ""),
        row(4, 1, "four", "http://h/4.xml", "http://h/", True, 900, 1000, 2, "parse failed"),
        row(5, 1, "five", "http://h/5.xml", "http://h/", True, 900, 1000, 1, "parse failed"),
    ], "totals": totals(5, 4, 1, 0, 2)}

    cur = {"feeds": [dict(entry) for entry in prev["feeds"]], "totals": dict(prev["totals"])}
    for entry in cur["feeds"]:
        if entry["id"] in (1, 5):
            entry["fetched_at"] = 1100
            entry["next_check_at"] = 4700
    next(entry for entry in cur["feeds"] if entry["id"] == 5)["parsing_error_count"] = 2

    return {"rules": list(RULES),
            "instants": {"prev": 1100, "cur": 1100},
            "error_limit": 2, "batch_size": 100, "host_limit": 0, "min_feeds": 5,
            "exit_codes": {"refresh": 0, "status": 0},
            "prev": prev, "cur": cur,
            "duplicate_pairs": [], "integrity": "ok",
            "error_feed_id": 5, "error_increments": 1}


def craft(change, keep_totals=True):
    """The baseline with one thing changed, so only the rule that change names can report it.

    `keep_totals` is off for the two probes whose target is a count: the rows are read first and
    the count is then broken on purpose, so the rule that reads the count is the only one that can
    report the change.
    """
    data = baseline()
    if keep_totals:
        change(data)
        recompute(data)
    else:
        recompute(data)
        change(data)
    return data


def probes():
    """One input per rule, crafted so that only the rule it names can report it."""
    cases = [("baseline passes all rules", baseline(), [])]

    def drop_title(data):
        row_of(data, 3).pop("title")
    cases.append(("document_shape", craft(drop_title), ["document_shape"]))

    def reorder(data):
        data["cur"]["feeds"] = list(reversed(data["cur"]["feeds"]))
    cases.append(("id_order", craft(reorder), ["id_order"]))

    def wrong_count(data):
        data["cur"]["totals"]["feeds"] = 6
    cases.append(("totals_match_rows", craft(wrong_count, keep_totals=False),
                  ["totals_match_rows"]))

    def due_counted_the_disabled_row(data):
        data["cur"]["totals"]["due"] = 1
    cases.append(("due_matches_pick", craft(due_counted_the_disabled_row, keep_totals=False),
                  ["due_matches_pick"]))

    def ran_a_row_that_was_not_due(data):
        row_of(data, 2).update({"fetched_at": 1100, "next_check_at": 4700})
    cases.append(("pick_ran_exactly", craft(ran_a_row_that_was_not_due), ["pick_ran_exactly"]))

    def ran_a_due_row_that_was_not_run(data):
        row_of(data, 1).update({"fetched_at": 900, "next_check_at": 1000})
    cases.append(("pick_ran_exactly", craft(ran_a_due_row_that_was_not_run), ["pick_ran_exactly"]))

    def stamp_went_backwards(data):
        data["prev"]["feeds"][0]["fetched_at"] = 1200
    cases.append(("fetched_stamp_moves_forward", craft(stamp_went_backwards),
                  ["fetched_stamp_moves_forward"]))

    def schedule_stayed(data):
        row_of(data, 1)["next_check_at"] = 1000
    cases.append(("schedule_moved_forward", craft(schedule_stayed), ["schedule_moved_forward"]))

    def schedule_landed_at_the_round_instant(data):
        row_of(data, 1)["next_check_at"] = 1100
    cases.append(("schedule_moved_forward", craft(schedule_landed_at_the_round_instant),
                  ["schedule_moved_forward"]))

    def error_row_ran_without_incrementing(data):
        row_of(data, 5)["parsing_error_count"] = 1
    cases.append(("error_counter", craft(error_row_ran_without_incrementing), ["error_counter"]))

    def error_path_never_ran(data):
        data["error_increments"] = 0
    cases.append(("error_path_observed", craft(error_path_never_ran), ["error_path_observed"]))

    def refresh_crashed(data):
        data["exit_codes"]["refresh"] = 1
    cases.append(("no_crash", craft(refresh_crashed), ["no_crash"]))

    def duplicate_pair(data):
        data["duplicate_pairs"] = [[1, "hash"]]
    cases.append(("entries_have_no_duplicate_pair", craft(duplicate_pair),
                  ["entries_have_no_duplicate_pair"]))

    def row_never_fetched(data):
        row_of(data, 2)["fetched_at"] = None
        data["prev"]["feeds"][1]["fetched_at"] = None
    cases.append(("every_enabled_row_was_fetched", craft(row_never_fetched),
                  ["every_enabled_row_was_fetched"]))

    def integrity_reported_a_problem(data):
        data["integrity"] = "ok\nextra"
    cases.append(("integrity_is_ok", craft(integrity_reported_a_problem), ["integrity_is_ok"]))

    def fewer_rows_than_the_run_declared(data):
        data["min_feeds"] = 20
    cases.append(("row_count_matches_the_declaration", craft(fewer_rows_than_the_run_declared),
                  ["row_count_matches_the_declaration"]))

    return cases


def read_db(data, path):
    """The two rules that read the database, gathered from the file the run used."""
    import sqlite3

    connection = sqlite3.connect(path)
    pairs = [list(row) for row in connection.execute(
        "SELECT feed_id, hash FROM entries GROUP BY feed_id, hash HAVING count(*) > 1")]
    integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
    connection.close()
    data["duplicate_pairs"] = pairs
    data["integrity"] = integrity
    return data


def main(argv):
    if "--probe" in argv:
        failed = []
        for name, data, expected in probes():
            fired = apply_rules(data)
            if fired != expected:
                failed.append(f"{name}: reported {fired or ['nothing']}, expected {expected}")
        for line in failed:
            print(f"PROBE FAIL: {line}")
        if failed:
            return 1
        print(f"{len(probes())} probes: each rule reports its own crafted input and the baseline "
              f"reports nothing")
        return 0

    args = argparse.ArgumentParser(description="Apply the soak rules to one round")
    args.add_argument("--prev", required=True, help="the snapshot taken before the round")
    args.add_argument("--cur", required=True, help="the snapshot the round wrote")
    args.add_argument("--instant-prev", type=int, required=True)
    args.add_argument("--instant-cur", type=int, required=True)
    args.add_argument("--error-limit", type=int, required=True)
    args.add_argument("--batch-size", type=int, required=True)
    args.add_argument("--host-limit", type=int, required=True)
    args.add_argument("--min-feeds", type=int, required=True)
    args.add_argument("--error-feed", type=int, required=True)
    args.add_argument("--error-increments", type=int, required=True)
    args.add_argument("--exit-refresh", type=int, required=True)
    args.add_argument("--exit-status", type=int, required=True)
    args.add_argument("--rules", required=True, help="comma-separated rule names to apply")
    args.add_argument("--db", help="the run's database file, for the rules that read it")
    opts = vars(args.parse_args(argv))

    data = {"rules": opts["rules"].split(","),
            "instants": {"prev": opts["instant_prev"], "cur": opts["instant_cur"]},
            "error_limit": opts["error_limit"], "batch_size": opts["batch_size"],
            "host_limit": opts["host_limit"], "min_feeds": opts["min_feeds"],
            "exit_codes": {"refresh": opts["exit_refresh"], "status": opts["exit_status"]},
            "prev": json.load(open(opts["prev"])), "cur": json.load(open(opts["cur"])),
            "duplicate_pairs": [], "integrity": "ok",
            "error_feed_id": opts["error_feed"], "error_increments": opts["error_increments"]}
    if opts["db"]:
        read_db(data, opts["db"])

    violations = apply_rules(data)
    for name in violations:
        print(f"VIOLATION: {name}")
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
