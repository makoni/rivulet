#!/usr/bin/env python3
"""The probe round the deploy check half is checked with, one crafted input per rule.

Every craft changes the parsed form and never a file, so the round hashes every file the check half
reads before and after and reports a craft that reached a file. The committed document is the run
this
machine produced, and the baseline case asserts it reports nothing, which is what makes each craft
single-firing: a craft that reached a second rule is reported as reaching it, and `REACHES` names
the
crafts that reach more than one rule through the same patch.

Crafts that change one side of a tool-versus-file read mirror the change on the other side, the way
the smoke probe round does: `mirror` keeps the tool answer for a key equal to what the file side now
writes, `mirror_file` keeps the file side equal to what the tool side now writes, `mirror_env` keeps
the values the tool resolved equal to the values the example now writes, `mirror_pairs` keeps a pair
list equal on both sides, `keep_program_line` keeps the tool line for the unit equal to what the
unit
side now writes, and `keep_covered` keeps the bookkeeping equal to the keys the artifacts write
after
the craft.

Two crafts reach the rule that reads the compose as the tool resolved it as well as their own,
because
that rule reads the same key each of them changes: the restart policy and the container subcommand.
They are named in `REACHES`, which is the reach `docs/testing.md` records rather than asserts.

Run it through `deploy_check.py --probe`.
"""

import copy
import hashlib

import parsers as read
import deploy_check as check

# The crafts that reach more than one rule through one patch, named as the rules they reach.
REACHES = {
    "the_two_files_name_one_restart_policy": sorted(["the_two_files_name_one_restart_policy",
                                                     "compose_reads_as_the_tool_read_it"]),
    "the_container_starts_a_command_the_dispatch_registers": sorted(["the_container_starts_a_command_the_dispatch_registers",
                                                                     "compose_reads_as_the_tool_read_it"]),
}


def hash_of():
    return {name: read.digest(name) for name in read.DEFAULTS}


def file_side(data):
    return data["compose"]["services"][next(iter(data["compose"]["services"]))]


def tool_side(data):
    tool = data["document"]["compose"]
    return tool["services"][next(iter(tool["services"]))]


def mirror(data, key, value):
    """Keep the tool answer for one key equal to what the file side now writes."""
    tool_side(data)[key] = value
    return value


def mirror_file(data, key, value):
    """Keep the file side for one key equal to what the tool side now writes."""
    file_side(data)[key] = value
    return value


def mirror_env(data, name, value):
    """Keep the value the tool resolved equal to the value the example now writes."""
    tool_side(data)["environment"][name] = value
    return value


def mirror_pairs(data, key, pair, entry):
    """Keep a pair list equal on both sides of the read, which is what a pair craft needs."""
    file_side(data)[key] = [pair]
    tool_side(data)[key] = [entry]
    return pair, entry


def keep_program_line(data, program):
    """Keep the tool line for the unit equal to what the unit side now writes."""
    for entry in data["analyze"]:
        if entry["kind"] == "program":
            entry["program"] = program
    return program


def keep_covered(data):
    """Keep the bookkeeping equal to the keys the artifacts write after the craft."""
    check.COVERED = copy.deepcopy(check.READS)
    for rule, keys in check.COVERED.items():
        for key in read.key_paths(data):
            if key not in keys:
                keys.append(key)


def compose_tool_answer_values(data):
    # The values the tool resolved from the env file, read against the committed example, which is
    # the half of this rule no other rule reads, so the craft reports this rule alone.
    tool_side(data)["environment"]["LOG_FORMAT"] = "json"


def compose_volume_pair(data):
    # A volume pair as the tool resolved it, against the pair the file writes, plus the volume name
    # as the tool resolved it with the project the run declared. The bookkeeping is kept equal, so
    # the coverage rule does not read the renamed key as a gap.
    mirror_pairs(data, "volumes", "reader-data:/var/lib/rivulet",
                 {"type": "volume", "source": "reader-data", "target": "/var/lib/rivulet", "volume": {}})
    data["compose"]["volumes"] = {"reader-data": {}}
    data["document"]["compose"]["volumes"] = {"reader-data": {"name": "reader_reader-data",
                                                               "delivered": False}}
    for entry in check.COVERED.values():
        for key in read.key_paths(data):
            if key.replace("reader-data", "rivulet-data") in entry:
                entry.append(key)


def build_reads_the_files_the_run_copied(data):
    # The copy as the bytes the run wrote it with, against the bytes the committed file has.
    data["document"]["run"]["copy_digests"]["unit"] = "0" * 64
    keep_covered(data)


def the_container_starts_a_command_the_dispatch_registers(data):
    tool_side(data)["command"] = ["reader-extra"]
    keep_covered(data)


def the_published_port_is_the_port_the_address_names(data):
    entry = tool_side(data)["ports"][0]
    entry["published"], entry["target"] = "8081", 8080
    mirror_file(data, "ports", ["8081:8080"])
    keep_covered(data)


def every_name_the_deploy_set_writes_is_a_config_read(data):
    data["example"]["DATABASE_FILENAME"] = "rivulet.db"
    mirror_env(data, "DATABASE_FILENAME", "rivulet.db")
    for entry in check.COVERED.values():
        if "example.DATABASE_FILENAME" in entry:
            entry.append("example.DATABASE_FILENAME")
            break
    keep_covered(data)


def the_values_read_as_the_parser_reads_them(data):
    data["example"]["LOG_LEVEL"] = "verbose"
    mirror_env(data, "LOG_LEVEL", "verbose")
    keep_covered(data)


def credential_shape(data):
    # A value that reads as the hex width the pin names for the token derivation, written on a name
    # the URL read takes, so the shape half of the read stays satisfied.
    data["example"]["BASE_URL"] = "https://" + "a" * 32
    mirror_env(data, "BASE_URL", data["example"]["BASE_URL"])
    keep_covered(data)


def credential_file_name(data):
    # The file the run built, read as the name half alone. The compose item that names the file is
    # kept equal to the path the craft writes, so the rule that reads the copies reports nothing.
    copy_of = data["document"]["run"]["copies"]["example"].replace(".env", ".data")
    data["document"]["run"]["copies"]["example"] = copy_of
    file_side(data)["env_file"] = [one.replace(".env", ".data") for one in file_side(data)["env_file"]]
    keep_covered(data)


def the_three_files_name_one_data_path(data):
    data["unit"]["Service"]["StateDirectory"] = "reader"
    keep_covered(data)


def the_unit_runs_a_command_the_dispatch_registers(data):
    data["unit"]["Service"]["ExecStart"] = "/usr/local/bin/rivulet vacuums"
    keep_program_line(data, "/usr/local/bin/rivulet")
    keep_covered(data)


def the_unit_names_the_binary_the_dockerfile_writes(data):
    data["unit"]["Service"]["ExecStart"] = "/usr/local/bin/reader serve"
    keep_program_line(data, "/usr/local/bin/reader serve")
    keep_covered(data)


def the_tool_read_the_unit_as_the_file_the_run_named(data):
    for entry in data["analyze"]:
        entry["file"] = "reader.service"
    keep_covered(data)


def tool_line_wrong_section(data):
    # A key the tool read in a section the unit does not put it in. The key is read in the section
    # the tool names, so the unit side keeps the key where the file writes it and the program line
    # is left as the tool printed it, which is what keeps the other two halves from reporting.
    data["analyze"].append({"file": data["document"]["run"]["unit_named"], "kind": "key",
                            "key": "Restart", "section": "Install", "program": None,
                            "passed": data["document"]["run"]["unit_named"]})
    keep_covered(data)


def tool_line_program_claim(data):
    data["document"]["run"]["program_on_this_machine"] = True
    keep_covered(data)


def the_two_files_name_one_restart_policy(data):
    file_side(data)["restart"] = "unless-stopped"
    keep_covered(data)


def the_unit_names_only_signals_the_port_has_a_handler_for(data):
    data["unit"]["Service"]["KillSignal"] = "SIGHUP"
    keep_covered(data)


def the_project_the_tool_resolved_is_the_name_the_run_declares(data):
    data["document"]["compose"]["name"] = "reader"
    keep_covered(data)


def the_check_half_reads_every_key_the_deploy_set_writes(data):
    # A key the artifacts write that no rule reads, which this rule reports as a gap: both sides of
    # the tool read are kept equal, so the rule that reads the compose reports nothing.
    key = "stop_grace_period"
    file_side(data)[key] = "30s"
    tool_side(data)[key] = "30s"
    check.COVERED = copy.deepcopy(check.READS)


def report_names_rules(data):
    data["document"]["rules"] = sorted(check.RULES)[:5]
    keep_covered(data)


def report_names_gaps(data):
    data["document"]["cannot_show"] = sorted(check.CANNOT_SHOW)[:4]
    keep_covered(data)


def cases():
    return [
        ("baseline", lambda data: None),
        ("compose_reads_as_the_tool_read_it", compose_tool_answer_values),
        ("compose_reads_as_the_tool_read_it", compose_volume_pair),
        ("build_reads_the_files_the_run_copied", build_reads_the_files_the_run_copied),
        ("the_container_starts_a_command_the_dispatch_registers", the_container_starts_a_command_the_dispatch_registers),
        ("the_published_port_is_the_port_the_address_names", the_published_port_is_the_port_the_address_names),
        ("every_name_the_deploy_set_writes_is_a_config_read", every_name_the_deploy_set_writes_is_a_config_read),
        ("the_values_read_as_the_parser_reads_them", the_values_read_as_the_parser_reads_them),
        ("no_value_in_the_example_reads_as_a_credential", credential_shape),
        ("no_value_in_the_example_reads_as_a_credential", credential_file_name),
        ("the_three_files_name_one_data_path", the_three_files_name_one_data_path),
        ("the_unit_runs_a_command_the_dispatch_registers", the_unit_runs_a_command_the_dispatch_registers),
        ("the_unit_names_the_binary_the_dockerfile_writes", the_unit_names_the_binary_the_dockerfile_writes),
        ("the_tool_read_the_unit_as_the_file_the_run_named", the_tool_read_the_unit_as_the_file_the_run_named),
        ("the_tool_read_the_unit_as_the_file_the_run_named", tool_line_wrong_section),
        ("the_tool_read_the_unit_as_the_file_the_run_named", tool_line_program_claim),
        ("the_two_files_name_one_restart_policy", the_two_files_name_one_restart_policy),
        ("the_unit_names_only_signals_the_port_has_a_handler_for", the_unit_names_only_signals_the_port_has_a_handler_for),
        ("the_project_the_tool_resolved_is_the_name_the_run_declares", the_project_the_tool_resolved_is_the_name_the_run_declares),
        ("the_check_half_reads_every_key_the_deploy_set_writes", the_check_half_reads_every_key_the_deploy_set_writes),
        ("report_names_rules_and_gaps", report_names_rules),
        ("report_names_rules_and_gaps", report_names_gaps),
    ]


def assert_each():
    started = hash_of()
    failed = []
    check.COVERED = copy.deepcopy(check.READS)
    baseline = check.apply_rules(read.build())
    if baseline:
        failed.append(f"baseline: reports {baseline}")
    for rule, change in cases()[1:]:
        check.COVERED = copy.deepcopy(check.READS)
        data = read.build()
        change(data)
        found = [name for name in sorted(check.RULES) if check.RULES[name](data)]
        expected = REACHES.get(change.__name__, [rule])
        if found != expected:
            failed.append(f"{rule} ({change.__name__}): reports {found}, expected {expected}")
    ended = hash_of()
    for name in sorted(started):
        if started[name] != ended[name]:
            failed.append(f"{name}: the round changed a file it reads, so nothing was reverted")
    for line in failed:
        print(f"PROBE FAIL: {line}")
    if failed:
        return 1
    print(f"{len(cases())} cases over {len(check.RULES)} rules — {len(cases()) - 1} crafted inputs "
          f"plus the baseline: each craft reports its own rule alone or the rules its patch reaches, "
          f"the baseline reports nothing, and every file the round read is byte-identical to what it "
          f"started with")
    return 0


if __name__ == "__main__":
    raise SystemExit(assert_each())
