#!/usr/bin/env python3
"""The rules the stage-8 smoke job reads over the document one clean-container run leaves behind.
This is the smoke job's check half (`Scripts/smoke.sh` is the run half). It is not a test and it
does not run in CI: it reads a container the machine may not have, so the run is on demand, and the
check half is checked by `probes.py`, which crafts one input per rule that violates it and asserts
that the rule reports it alone. The committed document is the run this machine produced, and the
baseline case asserts it reports nothing. Every rule is a function over the document, or over the
document and a committed file the run names, and the file readers are in `sources.py` so the rule
list stays the readable part. A rule that compares two values the run recorded at two moments is a
rule rather than a restatement, and the rules that compare the document with a count the document
itself declares are only falsifiable through a crafted document, which is what the probe round does.
What the rules cannot read is what `CANNOT_SHOW` names and `docs/testing.md` writes as the report.

Usage, one per line:
smoke_check.py --probe # the probe set against the committed document
smoke_check.py --document run.json # apply the rules to one run document
"""

import argparse
import json
import os

import sources

HERE = os.path.dirname(os.path.abspath(__file__))

#  The contract the soak documents, read as the key names the source declares. The smoke reads the
# same two snapshots through these names, so a document carrying a key the contract does not
# describe fails here as it fails in the soak.
DOCUMENT_KEYS = {"feeds", "totals"}
ROW_KEYS = {"id", "user_id", "title", "url", "site_url", "enabled", "fetched_at", "next_check_at",
           "parsing_error_count", "parsing_error_message"}
TOTAL_KEYS = {"feeds", "enabled", "disabled", "due", "at_error_limit"}

#  The row fields the stop does not write, which are the ones a stop is not allowed to change. The
# fields a fetch does write are read by the scheduling rule, because the round is allowed to move
# them; the two parsing-error fields are read here as unchanged because the job the stop interrupted
# never reached its write, which is the last step of a job — the reason the second snapshot is taken
# after the stamp lands.
UNCHANGED_FIELDS = ("url", "enabled", "parsing_error_count", "parsing_error_message")

CANNOT_SHOW = [
    "that the run ran at all, because it is on demand and not in CI",
    "that the fetch was still in flight when the stop signal landed, which only the run knows",
    "that the container held no toolchain beyond the file the Dockerfile writes, because a scratch base has no shell to list it with, so the run records the base and the file set",
    "the wording of the lines the binary printed, which are the port's own",
    "which device the console read took its values from, because the container has no terminal and the run gives it one through `Tools/smoke/console_feed.py`",
    "the exit code the stop signal left, because a signal that never lands hangs the run rather than reporting a code",
    "the WAL bytes the run recorded at the stop, because the checkpoint the process harness reads as empty is blocked by the write transaction the stop interrupted, so those bytes are the interrupted round's and no rule reads them as the harness reads them",
    "that the copy the backup wrote is a plain file rather than a database the run can open, beyond the listing the run read at the moment it looked",
    "that the two machine reads came from the same machine, because the run reads the machine twice with the same call, so the rule reads two lists rather than one list read twice",
    "that the run created the containers the machine reads name, because the rule reads the names, not the calls that created them, so no run can report a container it did not start",
    "that a run which left a container behind would have read it in the second pass, because the run lists only what it started, so the rule reports a document that names a container the run did not create rather than one the run left",
    "that the fetch read the same bytes as the corpus file holds, because the run reads the record the stub wrote and the digest of the file, so no rule reads the bytes a hop answered with",
    "the decision the address policy answered on the round, because the rule reads the flag the run declares against the class the policy names, so the decision itself is not read here",
    "the value the config read answered with for the policy flag, because the run records the value it declared, not the value the read normalized it to",
    "the order the round's jobs ran in, because the fetcher dispatches the picked rows through the worker pool, which fixes no order, so the record shows the arrivals and not the order the clause names; the rule reads the order the values the `add` calls wrote put the rows in",
    "the runbook's commands, because `docs/deploy.md` does not exist yet, so the rule that would read it reports that it cannot",
    "the titles the corpus documents declare, because the fetch writes no title and neither does the reference's refresh path, so the rows carry the empty value the create defaults write and the titles are read as declared data rather than as stored values",
    "the whole set the export lists, because the base the run declares puts names of its own in it at build time and a scratch base has no shell to list them with, so only the file the run put there is read",
    "which prompt of the credentials run produced which value, because the run writes the values through the terminal it gives the container and records only the order the file declares the prompts in, never the order they were answered in",
]


def load_document(name):
    with open(name, encoding="utf-8") as handle:
        return json.load(handle)


def snapshot_rows(data, side):
    return {row["id"]: row for row in data["snapshots"][side]["document"]["feeds"]}


def pick(rows, now, error_limit, batch_size):
    """The rows the batch rules select at `now`, as `FeedRepository+Batch.swift` writes them.

    Strict due-ness, the disabled gate, the switch that reads a zero as off, and the window, read as
    a set rather than as an order, because SQL fixes no order between rows sharing one value. The
    per-host filter is not read here: the document declares no value for it, so the rule reads only
    the default the file declares, which is off, and for this run the two sets are the same.
    """
    due = [row for row in rows if row.get("enabled")
           and row.get("next_check_at") is not None and row.get("next_check_at") < now
           and (error_limit == 0 or row.get("parsing_error_count", 0) < error_limit)]
    return due[:batch_size] if batch_size else due


def image_base(data):
    lines = sources.docker_lines("FROM")
    if len(lines) != 1:
        return [f"the Dockerfile writes {len(lines)} base lines, so there is no single base to read"]
    declared = lines[0].split()[-1]
    if data["run"]["base"] != declared:
        return [f"the run recorded base {data['run']['base']}, not the {declared} the Dockerfile "
                "writes"]
    return []


def image_content(data):
    """The file the Dockerfile's `COPY` line names, read as being in the export. The whole set the
    export lists is not read here: the base puts names of its own in it at build time, which a
    scratch base has no shell to list, so only the file the run put there is read.
    """
    want = [line.split()[-1].lstrip("/") for line in sources.docker_lines("COPY")]
    got = sorted(data["image_content"])
    for name in want:
        if name not in got:
            return [f"the export lists {got}, which does not carry {name}, the file the COPY line "
                    "names"]
    return []


def artifact_identity(data):
    findings = []
    run = data["run"]
    if run["artifact_digest"] != run["image_copy_digest"]:
        findings.append(f"the build context holds {run['image_copy_digest']}, not the artifact the run built ({run['artifact_digest']})")
    shape = sources.read("release").split("out/Products/")[1].split("/")[0].split("$")[0]
    product = shape + run["triple"].split("-")[0]
    named = run["artifact_path"].rsplit("/out/Products/", 1)
    if len(named) < 2 or named[1] != f"{product}/rivulet":
        findings.append(f"the run reads the artifact at {run['artifact_path']}, not the product path the release script names for {product}")
    return findings


def corpus_matches_manifest(data):
    findings = []
    rows = sources.manifest_rows()
    declared = data["run"]["declared_feeds"]
    if len(rows) != declared:
        findings.append(f"the run declares {declared} feeds, while the manifest holds {len(rows)}")
    for row in rows:
        path = sources.corpus_path(row["name"])
        if not os.path.isfile(path):
            findings.append(f"the manifest names {row['name']}, which is not there")
            continue
        recorded = next((entry for entry in data["manifest"] if entry["name"] == row["name"]), None)
        if recorded is None:
            findings.append(f"the document carries no record for {row['name']}")
        elif recorded["digest"] != sources.digest(path):
            findings.append(f"the document records {row['name']} as {recorded['digest']}, not the bytes the file holds ({sources.digest(path)})")
    return findings


def account_created(data):
    quoted = sources.literal("create_admin", "Created admin user")
    prefix, rest = quoted.split("\\(")
    answer = data["answers"]["account"]
    expected = prefix + answer["declared"] + rest.split(")")[-1]
    if answer["line"] != expected:
        return [f"the console answered {answer['line']}, not the sentence the command writes for "
                f"{answer['declared']} ({expected})"]
    return []


def migration_answer(data):
    name = sources.word_at("schema", "Schema")
    answer = data["answers"]["migrate"]
    if not name:
        return ["the schema file names no migration"]
    if name not in answer:
        return [f"the run recorded {answer}, which does not name the migration {name} the schema "
                "file declares"]
    return []


def health_answer(data):
    line = sources.first_line("health_route", '"healthz"')
    values = sources.quoted_values(line)
    answer, findings = data["answers"]["health"], []
    if answer["path"].lstrip("/") != values[0]:
        findings.append(f"the run asked {answer['path']}, which is not the path the route registers")
    if answer["status"] != 200:
        findings.append(f"the health answer is {answer['status']}, not the 200 the route answers")
    if answer["body"] != values[1]:
        findings.append(f"the health answer carries {answer['body']}, not the body the route writes")
    return findings


def login_answer(data):
    names = sources.literals_in("routes", "static func clientLogin", "    }", 'value(named: "', "let ")
    answer = data["answers"]["login"]
    findings = []
    if sorted(answer["fields"]) != sorted(names):
        findings.append(f"the run asked with {sorted(answer['fields'])}, not the names the handler " f"reads ({sorted(names)})")
    declared = sources.prompts("integration_credentials")
    if answer["prompts"] != declared:
        findings.append(f"the run listed the credentials prompts as {answer['prompts']}, not in the " f"order the command declares them ({declared})")
    command = sources.literal("cli", "IntegrationCredentials(environment")
    if answer["written_through"] != command:
        findings.append(f"the pair the login compares was written through {answer['written_through']}, not as the name the group registers it ({command})")
    if answer["status"] != 200:
        findings.append(f"the login answered {answer['status']}, so the reader answer was built " "without the row the auth read looks for")
    if answer["token"] != data["answers"]["reader"]["carried_with"]:
        findings.append("the reader answer was carried by a token the login did not answer")
    return findings


def reader_answer(data):
    keys = sources.literals_in("shape", "func userInfoResponse", "    }", '(key: "')
    header = sources.literal("auth", 'name: "')
    first = sources.literal("auth", "fields.first == ")
    group = sources.quoted_values(sources.first_line("routes", "application.grouped("))
    endpoint = "/" + "/".join(group + [sources.literal("routes", 'protected.get("user-info"')])
    answer = data["answers"]["reader"]
    findings = []
    if answer["half"] != "header":
        findings.append(f"the answer was carried by {answer['half']}, not by the header the auth read " "takes the token from for a GET")
    if answer["name"] != header:
        findings.append(f"the run sent the token as {answer['name']}, not as the name the auth read " f"reads it from ({header})")
    if answer["field"] != first:
        findings.append(f"the value the run sent began with {answer['field']}, not with the word the " f"auth read compares ({first})")
    if answer["status"] != 200:
        findings.append(f"the reader answer is {answer['status']}, not the 200 a row the auth read " "found answers")
    if answer["endpoint"] != endpoint:
        findings.append(f"the run asked {answer['endpoint']}, not the path the group and the " f"registration build ({endpoint})")
    if sorted(answer["keys"]) != sorted(keys):
        findings.append(f"the answer carries {sorted(answer['keys'])}, not the keys the shape writes " f"({sorted(keys)})")
    return findings


def policy_admits_the_target(data):
    run, findings = data["run"], []
    name = sources.literal("fetcher", 'variable: "FETCHER_ALLOW_PRIVATE_NETWORKS"')
    if run["policy"]["name"] != name:
        findings.append(f"the run set {run['policy']['name']}, which is not the name the config read " f"takes the flag by ({name})")
    on, off = sources.switch_values("config", 'case "1"'), sources.switch_values("config", 'case "0"')
    value = run["policy"]["value"]
    default = sources.value_in_block("fetcher", "public static let defaults", "allowPrivateNetworks:")
    read_as = value if value in on + off else default
    octet = run["target"].split(".")[0]
    refused = sources.single_cases("policy", "isPrivateV4")
    if octet in refused:
        if read_as not in on:
            findings.append(f"the policy as the run declares it reads as {read_as}, which refuses {run['target']} (a class the policy names), so no round happened")
    elif read_as in on:
        findings.append(f"the run declares the escape hatch for {run['target']}, which the policy admits without it")
    return findings


def round_reached_the_stub(data):
    events, rounds = data["events"], data["rounds"]
    read_instant = data["snapshots"]["before_stop"]["instant"]
    held = os.path.basename(data["stop"]["in_flight"])
    findings = []

    def seen(action, name):
        return [one for one in events if one["action"] == action and one["name"] == name]

    for row in sources.manifest_rows():
        name = os.path.basename(row["name"])
        arrived = seen("request", name)
        if not arrived:
            findings.append(f"the stub recorded no request for {name}, so the run read no round for it")
            continue
        if arrived[0]["instant"] <= rounds["started"]:
            findings.append(f"the request for {name} is dated {arrived[0]['instant']}, not after the boot the run started for the round at {rounds['started']}")

    for row in sources.manifest_rows():
        name = os.path.basename(row["name"])
        answered = seen("answered", name)
        if not answered:
            findings.append(f"the stub recorded no answer for {name}")
        elif name == held:
            if answered[0]["instant"] <= read_instant:
                findings.append(f"the held file was answered at {answered[0]['instant']}, not after the read at {read_instant}, so the round was not mid-way")
            if answered[0]["instant"] <= rounds["restarted"]:
                findings.append(f"the held file was answered before the round after the restart at " f"{rounds['restarted']}")
        elif answered[0]["instant"] > read_instant:
            findings.append(f"{name} was answered at {answered[0]['instant']}, after the read at {read_instant}, so the read was not at the point the four were answered")
    if data["stop"]["instant"] <= read_instant:
        findings.append(f"the read is dated {read_instant}, not before the stop at {data['stop']['instant']}, so the stop did not land during the round")
    return findings


def pick_order_follows_declared_order(data):
    """The order the tick's pick takes the rows in, read as the values each `add` call wrote.

    The clause orders the rows by the column the committed file names, and the run leaves a gap
    between the `add` calls so no two rows carry one value, because the clause fixes no order
    between equal values. The order the jobs ran in is not read here: the pool dispatch fixes none.
    """
    column = sources.first_line("batch", "ORDER BY").split("ORDER BY")[1].split()[0]
    order = [os.path.basename(row["name"]) for row in sources.manifest_rows()]
    written = data["answers"]["add_values"]
    values = [one["value"] for one in written]
    findings = []
    if len(set(values)) != len(values):
        findings.append(f"{len(values)} values recorded for {len(set(values))} distinct ones, so the clause fixes no order between rows sharing one value")
    read_order = [one["name"] for one in sorted(written, key=lambda one: one["value"])]
    if read_order != order:
        findings.append(f"the values the add calls wrote put the rows in {read_order}, not the declared order ({order}) the clause names by {column}")
    return findings


def snapshot_contract(data):
    findings = []
    for side, snapshot in data["snapshots"].items():
        document = snapshot["document"]
        if set(document) != DOCUMENT_KEYS:
            findings.append(f"the {side} snapshot is not the contract document: it carries " f"{sorted(set(document))}")
        if set(document["totals"]) != TOTAL_KEYS:
            findings.append(f"the {side} totals carry {sorted(set(document['totals']))}, not the five " f"the contract names ({sorted(TOTAL_KEYS)})")
        for row in document["feeds"]:
            if set(row) != ROW_KEYS:
                findings.append(f"the {side} snapshot has a row carrying {sorted(set(row))}, not the " "contract's row shape")
                break
    return findings


def rows_match_manifest(data):
    """The rows as the run wrote them, read as one row per record the manifest declares.

    The titles the documents declare are not read here: the fetch writes no title, and neither does
    the reference's refresh path, so the rows carry the empty value the create defaults write. The
    rule reads each row as naming the record it declares through the url the run asked with.
    """
    rows = sources.manifest_rows()
    by_name = {}
    findings = []
    for row in snapshot_rows(data, "after_stop").values():
        name = row["url"].rsplit("/", 1)[-1]
        if name in by_name:
            findings.append(f"{by_name[name]} and {row['id']} both name {name}, so a record is read " "as two rows")
        by_name[name] = row["id"]
    for row in rows:
        name = os.path.basename(row["name"])
        if name not in by_name:
            findings.append(f"no row names {name}, the record the manifest declares")
    for name in sorted(by_name):
        if name not in {os.path.basename(row["name"]) for row in rows}:
            findings.append(f"the rows carry {name}, which no record the manifest declares names")
    for side in sorted(data["snapshots"]):
        counts = data["snapshots"][side]["document"]["totals"]
        if counts["feeds"] != len(rows):
            findings.append(f"the {side} totals report {counts['feeds']} feeds, while the manifest " f"holds {len(rows)}")
    return findings


def stop_left_no_corruption(data):
    """The rows as the stop left them, and the sentence the second boot answered for the integrity
    rule. The WAL bytes are not read here: the checkpoint the process harness reads as an empty WAL
    is blocked by the write transaction the stop interrupted, so those bytes are the round's.
    """
    integrity = sources.literal("serve", "integrity check passed")
    stop = data["stop"]
    findings = []
    if stop["integrity_line"] != integrity:
        findings.append(f"the second boot answered {stop['integrity_line']}, not the {integrity} the " "run's own integrity rule writes")
    before, after = snapshot_rows(data, "before_stop"), snapshot_rows(data, "after_stop")
    if sorted(before) != sorted(after):
        findings.append(f"the rows before the stop are {sorted(before)}, the rows after are " f"{sorted(after)}")
    for key in sorted(set(before) & set(after)):
        for field in UNCHANGED_FIELDS:
            if before[key][field] != after[key][field]:
                findings.append(f"row {key} carries {field} {after[key][field]}, not the " f"{before[key][field]} it held before the stop")
                break
    return findings


def scheduling_resumed(data):
    findings = []
    run, stop = data["run"], data["stop"]
    before, after = snapshot_rows(data, "before_stop"), snapshot_rows(data, "after_stop")
    instant = data["snapshots"]["before_stop"]["instant"]
    held = next((row for row in before.values() if row["url"].endswith("/" + os.path.basename(
        stop["in_flight"]))), None)
    if held is None:
        return [f"the run names {stop['in_flight']} as the file the round was reading, and no row "
                "carries a url naming it"]
    took = [row["id"] for row in pick(list(before.values()), instant, run["error_limit"],
                                      run["batch_size"])]
    moved = [key for key in sorted(before) if after[key]["fetched_at"] != before[key]["fetched_at"]]
    if sorted(moved) != sorted(took):
        findings.append(f"the round after the restart moved {sorted(moved)}, not the pick the rules " f"take at the read ({sorted(took)})")
    if held["id"] not in took:
        findings.append(f"the pick at the read did not take the row the run names as the one in flight " f"({held['id']})")
    if before[held["id"]]["fetched_at"] is not None:
        findings.append(f"the row the run names as in flight was stamped {before[held['id']]['fetched_at']} at the read, so the round was not mid-way")
    totals = data["snapshots"]["before_stop"]["document"]["totals"]
    if totals["due"] != len(took):
        findings.append(f"the mid-round totals report due as {totals['due']}, not the pick the rules " f"take at that read ({len(took)})")
    later = after[held["id"]]
    if later["fetched_at"] is None:
        findings.append("the row the round was reading is not stamped at the second read, so the job the stop interrupted had not finished")
    else:
        if later["fetched_at"] < stop["instant"]:
            findings.append(f"the row the round was reading is stamped {later['fetched_at']}, which " f"is not after the stop at {stop['instant']}")
        if not later["next_check_at"] or later["next_check_at"] <= later["fetched_at"]:
            findings.append("the schedule did not land after the round for the row the stop caught")
    return findings


def copy_equals_the_source(data):
    """The copy as the run wrote it, read as the answer the command gave for the destination.

    The room check runs before anything is written, so a run that cannot hold the copy reports the
    refusal and writes nothing; the copy the run read is the file it wrote, read through the same
    contract the snapshots are read as.
    """
    findings = []
    copy = data["copy"]
    source = data["snapshots"]["after_stop"]["document"]
    quoted = sources.literal("backup", "Backup written")
    prefix, rest = quoted.split("\\(")
    expected = prefix + copy["path"] + rest.split(")")[-1]
    if copy["printed"] != expected:
        findings.append(f"the run reported {copy['printed']}, not the sentence the command writes " f"for {copy['path']} ({expected})")
    if copy["wal_beside"]:
        findings.append("the copy has a `-wal` beside it, which the stage-1 rule says a copy does not")
    if copy["rows"] != source["feeds"]:
        findings.append("the rows read from the copy are not the rows the source held")
    if copy["counts"] != source["totals"]:
        findings.append(f"the counts read from the copy are {sorted(copy['counts'].items())}, not the " f"source's {sorted(source['totals'].items())}")
    return findings


def machine_left_as_found(data):
    findings = []
    work = data["machine"]["work"]
    for moment in sorted(("before", "left")):
        for entry in data["machine"][moment]["entries"]:
            if not entry["name"].endswith(work):
                findings.append(f"the {moment} read names {entry['name']}, which is not a container " f"this run created ({work})")
            if entry["running"]:
                findings.append(f"the {moment} read finds {entry['name']} running, so the run did " "not stop what it started")
    if data["machine"]["left"]["entries"]:
        names = sorted(entry["name"] for entry in data["machine"]["left"]["entries"])
        findings.append(f"the second read names {names}, which is what the run left behind")
    if not (data["machine"]["before"]["instant"] < data["machine"]["left"]["instant"]
           < data["copy"]["instant"]):
        findings.append(f"the copy read is dated {data['copy']['instant']}, not after the second machine read at {data['machine']['left']['instant']}, so the listing read is not the one read before the copy")
    return findings


def report_names_rules_and_gaps(data):
    findings = []
    if sorted(data["rules"]) != sorted(RULES):
        findings.append(f"the report names {sorted(data['rules'])}, not every rule the check half has " f"({sorted(RULES)})")
    if sorted(data["cannot_show"]) != sorted(CANNOT_SHOW):
        findings.append(f"the report names {sorted(data['cannot_show'])}, not what the run cannot " f"show ({sorted(CANNOT_SHOW)})")
    if os.path.isfile(sources.DEFAULTS["runbook"]):
        findings.append(f"the runbook rule is named as not read, but {sources.DEFAULTS['runbook']} exists, so the run has commands to execute from it")
    return findings


RULES = {"image_base": image_base, "image_content": image_content, "artifact_identity":
         artifact_identity, "corpus_matches_manifest": corpus_matches_manifest,
         "account_created": account_created, "migration_answer": migration_answer,
         "health_answer": health_answer, "login_answer": login_answer, "reader_answer": reader_answer,
         "policy_admits_the_target": policy_admits_the_target, "round_reached_the_stub":
         round_reached_the_stub, "pick_order_follows_declared_order":
         pick_order_follows_declared_order, "snapshot_contract": snapshot_contract,
         "rows_match_manifest": rows_match_manifest, "stop_left_no_corruption":
         stop_left_no_corruption, "scheduling_resumed": scheduling_resumed,
         "copy_equals_the_source": copy_equals_the_source, "machine_left_as_found":
         machine_left_as_found, "report_names_rules_and_gaps": report_names_rules_and_gaps}


def apply_rules(data):
    return [name for name, rule in sorted(RULES.items()) if rule(data)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--document", default=sources.DEFAULTS["document"])
    parser.add_argument("--probe", action="store_true")
    args = parser.parse_args()

    if args.probe:
        import probes
        return probes.assert_each()

    data = load_document(args.document)
    fired = apply_rules(data)
    for name in fired:
        print(f"RULE FAIL: {name}: " + "; ".join(RULES[name](data)))
    return 1 if fired else 0


if __name__ == "__main__":
    raise SystemExit(main())
