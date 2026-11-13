#!/usr/bin/env python3
"""The rules the deploy check half reads over the document the deploy run leaves behind.

This is the deploy slice check half (`Scripts/deploy.sh` is the run half, `collect.py` writes the
document). It is not a test and it does not run in CI: the CI container has neither Docker nor
systemd, so the run is on demand, and the check half is checked by `probes.py`, which crafts one
input per rule that violates it and asserts the rule reports it alone. The committed document is the
run this machine produced, and the baseline case asserts it reports nothing.

Every rule is a function over the data `parsers.py` builds: the document the run left, or the
document and a committed file the run names. The parsers read the three artifacts as the keys they
write, so a rule that compares a tool answer with a key the file writes reads the file rather than
the word the run declared for it. What the rules cannot read is what `CANNOT_SHOW` names and what
`docs/testing.md` writes as the report. The coverage rule reads the keys the three artifacts write
against `READS`, the bookkeeping of which rule reads which key, plus `NOT_READ`, the two unit keys
that are structure rather than a value the port reads.

Usage, one per line:
deploy_check.py --probe # the probe set against the committed document
deploy_check.py --document deploy.json # apply the rules to one run document
"""

import argparse
import os
import re

import parsers as read

# The parts no rule can read, which the run cannot show either, so they are named here and in
# `docs/testing.md` rather than asserted by a rule. These lines are read as whole strings by the
# report rule, so they are not wrapped.
CANNOT_SHOW = [
    "that the run ran at all, because it is on demand and not in CI",
    "the image being built or started, because the run reads the compose as the tool resolves it and never builds",
    "the unit installed and run on a machine, because the tool reads the file as a parse and the only finding it answers is the program path not being on this machine",
    "the signal a stop delivers, because the tool reads the signal the unit names as text, and which signal a stop sends is what the unit answers on a machine that runs it",
    "the values an operator fills in, because the committed example carries placeholders and the file a deployment reads is the gitignored name",
    "the credential pair, which lands through the command the runbook names, not through a name the config reads",
    "the published port being free on the machine, because the guard reads the machine before the run and the rule reads the pair the compose writes",
    "the artifact the Dockerfile names being in the build context, because the run does not build and the tool resolves the name without reading the file",
    "the wording of the lines the tools printed, which the rule reads as the file and the value each line names, not as the sentence",
    "the version of each tool the run names, because the run records the line each tool answered for itself and no rule reads it",
    "the runbook executed on a machine that is not the one that wrote it, because the stage criterion is a fresh VPS and this run ran on the machine that built the artifact",
    "a value an operator changes after the run, because the rules read the files as they are committed, so a change to the file a deployment reads is not read here",
]

# Which rule reads which key the three artifacts write. The coverage rule reads this bookkeeping as
# data, so a key no rule reads has to be named in `NOT_READ` rather than be left unread. These lines
# are the record lines the coverage rule reads as whole strings, so they are not wrapped.
READS = {
    "compose_reads_as_the_tool_read_it": ["compose", "compose.services", "compose.services.rivulet",
        "compose.services.rivulet.build", "compose.services.rivulet.build.context",
        "compose.services.rivulet.build.dockerfile", "compose.services.rivulet.image",
        "compose.services.rivulet.command", "compose.services.rivulet.restart",
        "compose.services.rivulet.ports", "compose.services.rivulet.env_file",
        "compose.services.rivulet.volumes", "compose.volumes", "compose.volumes.rivulet-data"],
    "build_reads_the_files_the_run_copied": ["compose.services.rivulet.build.context",
        "compose.services.rivulet.build.dockerfile", "compose.services.rivulet.env_file",
        "compose.services.rivulet.env_file.env_file"],
    "the_container_starts_a_command_the_dispatch_registers": ["compose.services.rivulet.command"],
    "the_published_port_is_the_port_the_address_names": ["compose.services.rivulet.ports"],
    "every_name_the_deploy_set_writes_is_a_config_read": [f"example.{name}" for name in sorted(read.example_values())],
    "the_values_read_as_the_parser_reads_them": [f"example.{name}" for name in sorted(read.example_values())],
    "no_value_in_the_example_reads_as_a_credential": [f"example.{name}" for name in sorted(read.example_values())],
    "the_three_files_name_one_data_path": ["compose.services.rivulet.volumes",
        "unit.Service.StateDirectory", "example.DATABASE_URL"],
    "the_unit_runs_a_command_the_dispatch_registers": ["unit.Service.ExecStart"],
    "the_unit_names_the_binary_the_dockerfile_writes": ["unit.Service.ExecStart"],
    "the_tool_read_the_unit_as_the_file_the_run_named": [f"unit.{section}.{key}" for section, keys in sorted(read.unit_sections().items()) for key in sorted(keys)],
    "the_two_files_name_one_restart_policy": ["compose.services.rivulet.restart", "unit.Service.Restart"],
    "the_unit_names_only_signals_the_port_has_a_handler_for": ["unit.Service.KillSignal"],
    "the_project_the_tool_resolved_is_the_name_the_run_declares": [],
    "the_check_half_reads_every_key_the_deploy_set_writes": [],
    "report_names_rules_and_gaps": [],
}

# The two unit keys that are structure rather than a value the port reads, named here so the
# coverage rule can read them as the part of the artifacts no rule reads.
COVERED = READS

NOT_READ = ["unit.Unit.Description", "unit.Install.WantedBy"]


def as_list(value):
    """A scalar the tool answers as one item of its own, which is how it reads a list block."""
    return [value] if isinstance(value, str) else value


def run(data):
    return data["document"]["run"]


def tool(data):
    return data["document"]["compose"]


def pair(data):
    """The service block on both sides of the read: the key the file writes, the tool answer."""
    services = data["compose"]["services"]
    return services[next(iter(services))], answer(data)


def answer(data):
    services = tool(data)["services"]
    return services[next(iter(services))]


def compose_reads_as_the_tool_read_it(data):
    """The compose as the tool read it, key by key, plus the values read from the env file.

    The tool resolves a pair into its two numbers and the protocol it reads for it, a volume pair
    into the source and the target, and the volume name with the project the run declared. The env
    file is not a key in the tool answer, because the tool puts the values it read from that file
    into the service environment, so the rule reads those values against the committed example.
    """
    file_block, resolved = pair(data)
    findings = []
    for key, value in sorted(file_block.items()):
        got = resolved.get(key)
        if key == "ports":
            findings += read_pairs(value, got, "published")
        elif key == "volumes":
            findings += read_pairs(value, got, "source")
        elif key == "build":
            if got["dockerfile"] != value["dockerfile"]:
                findings.append(f"the tool names the dockerfile as {got['dockerfile']}, not the {value['dockerfile']} the file writes")
        elif key == "env_file":
            # The tool answers no key for the env file: it puts the values it read from that file
            # into the service environment, so the env file is read by the rule that reads copies.
            continue
        elif value != got and as_list(value) != got:
            findings.append(f"the tool answers {key} as {got}, not the {value} the file writes")
    for name in sorted(data["compose"]["volumes"]):
        resolved_name = f"{run(data)['project']}_{name}"
        recorded = tool(data)["volumes"][name]["name"]
        if recorded != resolved_name:
            findings.append(f"the tool resolves the volume {name} as {recorded}, not as {resolved_name}, which the project the run declared builds")
    environment = resolved["environment"]
    for name, value in sorted(data["example"].items()):
        if environment.get(name) != value:
            findings.append(f"the tool resolved {name} as {environment.get(name)}, not the {value} the committed example writes")
    return findings


def read_pairs(pairs, entries, first):
    """One port or volume pair, read as the tool took it, against the pair the file writes.
    
    `first` names the half of the pair that differs between the two kinds: the published number for
    a port, the source name for a volume. The other half is read as the target either way. A port
    pair the file writes with no protocol is read as the protocol the tool answers for it by
    default.
    """
    findings = []
    for written, entry in zip(pairs, entries):
        left, right = written.split(":")
        right_value = int(right) if first == "published" else right
        if str(entry[first]) != left or entry["target"] != right_value:
            findings.append(f"the tool reads the pair {written} as {entry[first]} to {entry['target']}, which is not what the file writes")
        if first == "published" and entry["protocol"] != "tcp":
            findings.append(f"the pair writes no protocol, so the tool reads it as tcp, not {entry['protocol']}")
    return findings


def build_reads_the_files_the_run_copied(data):
    """The build and the env file as the run built them, read as copies of the committed files.

    The run copies the committed files into the directory it ran in, because the tool reads its
    context and its env file as paths relative to the file it reads. The rule reads the tool answer
    for the context against that directory, and each copy against the bytes the committed file has,
    which the run recorded as two digests. The artifact the Dockerfile names is not read here,
    because the run does not build.
    """
    work, findings = run(data)["work"], []
    build = answer(data)["build"]
    compose_copy = run(data)["copies"]["compose"]
    if build["context"] != work or os.path.dirname(compose_copy) != os.path.join(work, "deploy"):
        findings.append(f"the tool resolved the context as {build['context']}, not the directory the run ran in ({work}) with the compose file it read")
    for name in ("compose", "unit", "example", "dockerfile"):
        copy = run(data)["copies"][name]
        if os.path.dirname(copy) not in (work, os.path.join(work, "deploy")):
            findings.append(f"the run wrote {copy}, which is not in the directory it ran in ({work})")
        digests = (run(data)["digests"][name], run(data)["copy_digests"][name])
        if digests[0] != digests[1]:
            findings.append(f"the run wrote {copy} as {digests[1]}, not the bytes the committed {name} has ({digests[0]})")
    read_path = os.path.join(work, os.path.basename(run(data)["copies"]["example"]))
    if as_list(pair(data)[0]["env_file"]) != [os.path.relpath(read_path, os.path.dirname(compose_copy))]:
        findings.append(f"the file the run built is {read_path}, not the {pair(data)[0]['env_file']} the compose resolves from the copy it read")
    return findings


def the_container_starts_a_command_the_dispatch_registers(data):
    """The subcommand the tool resolves for the container, against the names the dispatch registers.
    
    The entrypoint the Dockerfile writes names the program alone, so the subcommand the tool answers
    comes from the line the compose writes, and the program in the entrypoint is read as the file
    the
    image copy line writes.
    """
    _, resolved = pair(data)
    words = resolved["command"]
    findings = []
    if len(words) != 1 or words[0] not in data["commands"]:
        findings.append(f"the container starts {words}, which is not one command the dispatch registers ({data['commands']})")
    if resolved["entrypoint"] is not None:
        findings.append(f"the tool answers the entrypoint as {resolved['entrypoint']}, while the Dockerfile writes no subcommand for it")
    entry = re.search(r'"([^"]+)"', data["dockerfile"]["ENTRYPOINT"]).group(1)
    copied = data["dockerfile"]["COPY"].rsplit("/", 1)[-1]
    if entry.rsplit("/", 1)[-1] != copied:
        findings.append(f"the ENTRYPOINT runs {entry}, which is not the file the COPY line writes ({data['dockerfile']['COPY']})")
    return findings


def the_published_port_is_the_port_the_address_names(data):
    """The port the tool publishes, against the port the address value it resolved names.

    The pair the compose writes is read as one port on both halves, and the address value the tool
    resolved from the env file is read against the port the runbook names. A value that is the
    listener the read answers for a value it does not read is read as the default rather than as a
    value the example writes, which is what the second half reports.
    """
    _, resolved = pair(data)
    entry, findings = resolved["ports"][0], []
    address = resolved["environment"]["LISTEN_ADDR"]
    port = address.rsplit(":", 1)[-1]
    if entry["published"] != port:
        findings.append(f"the tool publishes {entry['published']}, not the port the address it resolved names ({port})")
    if entry["target"] != int(entry["published"]):
        findings.append(f"the tool reads the pair as {entry['published']} to {entry['target']}, which is not one port")
    runbook_port = data["runbook"]["LISTEN_ADDR"].rsplit(":", 1)[-1]
    if port != runbook_port:
        findings.append(f"the address the tool resolved names port {port}, not the {runbook_port} the runbook names")
    default = f"{data['listen_default']['host']}:{data['listen_default']['port']}"
    if address == default:
        findings.append(f"the address the tool resolved is the listener the read answers for a value it does not read, so the port here is the default and not a value the example writes")
    return findings


def every_name_the_deploy_set_writes_is_a_config_read(data):
    """The names the three files write, against the names the config sources read.

    The unit has no key of its own for an environment value, so a unit key of that shape is read as
    a name the artifacts write that no rule reads as data and no config read takes.
    """
    _, resolved = pair(data)
    findings = []
    for name in sorted(data["example"]):
        if name not in data["names"]:
            findings.append(f"the example writes {name}, which no config read takes")
    for name in sorted(resolved["environment"]):
        if name not in data["names"]:
            findings.append(f"the tool resolved {name}, which no config read takes")
    for section, keys in sorted(data["unit"].items()):
        for key in sorted(keys):
            if key in ("Environment", "EnvironmentFile"):
                findings.append(f"the unit writes {key} in [{section}], which no rule reads as data and no config read takes")
    return findings


def the_values_read_as_the_parser_reads_them(data):
    """Each value as the kind of value the source reads that name as.

    The kinds come from the sources: the integer reads with their minimum, the choice reads with the
    case set the enum declares, the boolean read with the forms the switch has, and the three reads
    that take a value as a shape of their own. A name the source reads with a trim alone is not read
    here, because no rule can show a value that reads as free text.
    """
    findings = []
    for name, value in sorted(data["example"].items()):
        shape = data["shapes"].get(name)
        if shape is None:
            continue
        kind = shape["kind"]
        host = value.split("//")[-1].split("/")[0] if "//" in value else value
        if kind == "integer" and (not value.isdigit() or int(value) < shape["minimum"]):
            findings.append(f"{name} reads as {value}, which is not an integer at least the {shape['minimum']} the read requires")
        elif kind == "choice" and value not in shape["cases"]:
            findings.append(f"{name} reads as {value}, not one of the cases the enum declares ({shape['cases']})")
        elif kind == "boolean" and value not in shape["forms"]:
            findings.append(f"{name} reads as {value}, not one of the forms the switch has ({shape['forms']})")
        elif kind == "path" and re.match(data["value_shapes"]["path_scheme"], value):
            findings.append(f"{name} reads as {value}, which the path read reports as a value carrying a scheme")
        elif kind == "url" and ("//" not in value or value.split("://")[0] not in data["value_shapes"]["schemes"]):
            findings.append(f"{name} reads as {value}, which is not an absolute URL with one of the schemes ({data['value_shapes']['schemes']})")
        elif kind == "host port" and (":" not in value or not value.rsplit(":", 1)[-1].isdigit()):
            findings.append(f"{name} reads as {value}, which the address read does not read as a host with a port")
    return findings


def no_value_in_the_example_reads_as_a_credential(data):
    """The values as placeholders, read against the two shapes the credential paths write.
    
    The shapes are read from the sources: the marker the hasher writes and the width the pin names
    for the hex form the token derivation writes. The second half reads the file the run built as
    the
    gitignored name, so a committed file that is the file a deployment reads is a finding, not a
    template.
    """
    marker, width, findings = data["credential"]["marker"], data["credential"]["hex_width"], []
    for name, value in sorted(data["example"].items()):
        host = value.split("//")[-1].split("/")[0] if "//" in value else value
        if host.startswith(marker) or (len(host) == width and re.fullmatch(r"[0-9a-f]+", host)):
            findings.append(f"{name} carries {value}, which reads as the shape a credential has ({marker}, or {width} hex digits)")
    built = run(data)["copies"]["example"]
    if os.path.basename(built) != data["env_file_name"]:
        name = data["env_file_name"]
        findings.append(f"the run built {built}, whose name is not the gitignored name the file a deployment reads has ({name})")
    if os.path.basename(built) == os.path.basename(read.DEFAULTS["example"]):
        findings.append("the committed example is the file the run reads, so nothing here is read as a template")
    return findings


def the_three_files_name_one_data_path(data):
    """The data path as the three files name it: the example, the mount, the state directory.

    The mount target is read as the tool resolved it, the state directory as the unit writes it and
    as systemd reads a name of that shape, and the runbook as the page writes its fenced block.
    """
    _, resolved = pair(data)
    directory = os.path.dirname(data["example"]["DATABASE_URL"])
    target = resolved["volumes"][0]["target"]
    findings = []
    if directory != target:
        findings.append(f"the example names the data in {directory}, while the compose mounts {target}")
    name = data["unit"]["Service"]["StateDirectory"]
    if f"/var/lib/{name}" != target:
        findings.append(f"the unit names StateDirectory as {name}, which reads as /var/lib/{name}, not the {target} the compose mounts")
    runbook_directory = os.path.dirname(data["runbook"]["DATABASE_URL"])
    if runbook_directory != directory:
        findings.append(f"the runbook names the data in {runbook_directory}, not the {directory} the example names")
    return findings


def the_unit_runs_a_command_the_dispatch_registers(data):
    """The subcommand the unit program line carries, against the names the dispatch registers."""
    line = data["unit"]["Service"]["ExecStart"]
    words = line.split()
    if len(words) < 2 or words[1] not in data["commands"]:
        return [f"the unit runs {line}, whose subcommand is not one the dispatch registers ({data['commands']})"]
    return []


def the_unit_names_the_binary_the_dockerfile_writes(data):
    """The program the unit names, against the file the image copy line writes, and the tool line.

    The tool line naming a program is the finding the run declares as not being on this machine, so
    the rule reads the program the tool printed as the same program the unit writes, and the read
    has nothing to compare when the tool answered no line of that shape.
    """
    program = data["unit"]["Service"]["ExecStart"].split()[0]
    findings = []
    copied = data["dockerfile"]["COPY"].rsplit("/", 1)[-1]
    if program.rsplit("/", 1)[-1] != copied:
        findings.append(f"the unit names {program}, whose file is {copied} as the Dockerfile writes it")
    entry = next((one for one in data["analyze"] if one["kind"] == "program"), None)
    if entry is None:
        return findings + ["the tool answered no line naming a program, so the read has nothing to compare"]
    if entry["program"] != program:
        findings.append(f"the tool names {entry['program']}, not the program the unit writes ({program})")
    return findings


def the_tool_read_the_unit_as_the_file_the_run_named(data):
    """The tool lines as data: the file each names, and the key each names in its section.

    The tool reads the unit as a parse, so the lines it printed are the whole of what the run saw of
    the unit. A line naming a key in a section the unit does not put that key in is a reading the
    file does not support, and the finding about the program is read as the run declaring the path
    as being on this machine, which the line reports it is not.
    """
    passed, findings = run(data)["unit_named"], []
    for entry in data["analyze"]:
        if entry["file"] != passed:
            findings.append(f"the line names {entry['file']}, not the file the run passed ({passed})")
        if entry["kind"] == "key" and entry["key"] not in data["unit"].get(entry["section"], {}):
            findings.append(f"the tool read {entry['key']} as a key in [{entry['section']}], where the unit writes no such key")
        if entry["kind"] == "program" and run(data)["program_on_this_machine"]:
            findings.append(f"the run declares {entry['program']} as being on this machine, which is what the line reports it is not")
    if not data["analyze"]:
        findings.append("the tool answered nothing for the run, so no line names the file the run passed")
    return findings


def the_two_files_name_one_restart_policy(data):
    """The policy the two files name, read as one value rather than as two wordings."""
    file_block, _ = pair(data)
    compose_value, unit_value = file_block["restart"], data["unit"]["Service"]["Restart"]
    if compose_value != unit_value:
        return [f"the compose names the policy as {compose_value} and the unit as {unit_value}, which is not one policy"]
    return []


def the_unit_names_only_signals_the_port_has_a_handler_for(data):
    """The signal the unit names, against the signals the process handler has a case for."""
    named = data["unit"]["Service"]["KillSignal"]
    if named not in data["signals"]:
        return [f"the unit names {named}, which the handler has no case for ({data['signals']})"]
    return []


def the_project_the_tool_resolved_is_the_name_the_run_declares(data):
    """The project name as the tool answered it, against the name the run declared.

    A compose file that declares its own project makes the tool read the name from the file, so the
    second half reads the file as not writing one, which is what lets the name the run declared be
    the whole of what the tool resolved.
    """
    if tool(data)["name"] != run(data)["project"]:
        recorded, declared = tool(data)["name"], run(data)["project"]
        return [f"the tool resolved the project as {recorded}, not the name the run declared ({declared})"]
    if "name" in data["compose"]:
        return [f"the compose declares its own project as {data['compose']['name']}, so the tool read the name from the file and not from the run"]
    return []


def the_check_half_reads_every_key_the_deploy_set_writes(data):
    """The keys the three artifacts write, against the bookkeeping the check half keeps."""
    keys = read.key_paths(data)
    covered = set(sum(COVERED.values(), [])) | set(NOT_READ)
    missing = [key for key in keys if key not in covered]
    if missing:
        return [f"no rule reads {missing}, which the artifacts write and the report names nothing for"]
    return []


def report_names_rules_and_gaps(data):
    """The two lists the document carries, read against what the check half has."""
    if sorted(data["document"]["rules"]) != sorted(RULES):
        named = sorted(data["document"]["rules"])
        return [f"the report names {named}, not every rule the check half has ({sorted(RULES)})"]
    if sorted(data["document"]["cannot_show"]) != sorted(CANNOT_SHOW):
        named = sorted(data["document"]["cannot_show"])
        return [f"the report names {named}, not what the run cannot show ({sorted(CANNOT_SHOW)})"]
    return []


RULES = {
    "compose_reads_as_the_tool_read_it": compose_reads_as_the_tool_read_it,
    "build_reads_the_files_the_run_copied": build_reads_the_files_the_run_copied,
    "the_container_starts_a_command_the_dispatch_registers": the_container_starts_a_command_the_dispatch_registers,
    "the_published_port_is_the_port_the_address_names": the_published_port_is_the_port_the_address_names,
    "every_name_the_deploy_set_writes_is_a_config_read": every_name_the_deploy_set_writes_is_a_config_read,
    "the_values_read_as_the_parser_reads_them": the_values_read_as_the_parser_reads_them,
    "no_value_in_the_example_reads_as_a_credential": no_value_in_the_example_reads_as_a_credential,
    "the_three_files_name_one_data_path": the_three_files_name_one_data_path,
    "the_unit_runs_a_command_the_dispatch_registers": the_unit_runs_a_command_the_dispatch_registers,
    "the_unit_names_the_binary_the_dockerfile_writes": the_unit_names_the_binary_the_dockerfile_writes,
    "the_tool_read_the_unit_as_the_file_the_run_named": the_tool_read_the_unit_as_the_file_the_run_named,
    "the_two_files_name_one_restart_policy": the_two_files_name_one_restart_policy,
    "the_unit_names_only_signals_the_port_has_a_handler_for": the_unit_names_only_signals_the_port_has_a_handler_for,
    "the_project_the_tool_resolved_is_the_name_the_run_declares": the_project_the_tool_resolved_is_the_name_the_run_declares,
    "the_check_half_reads_every_key_the_deploy_set_writes": the_check_half_reads_every_key_the_deploy_set_writes,
    "report_names_rules_and_gaps": report_names_rules_and_gaps,
}


def apply_rules(data):
    return [name for name, rule in sorted(RULES.items()) if rule(data)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--probe", action="store_true")
    args = parser.parse_args()

    if args.probe:
        import probes
        return probes.assert_each()

    data = read.build()
    fired = apply_rules(data)
    for name in fired:
        print(f"RULE FAIL: {name}: " + "; ".join(RULES[name](data)))
    return 1 if fired else 0


if __name__ == "__main__":
    raise SystemExit(main())
