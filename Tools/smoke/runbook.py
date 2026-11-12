#!/usr/bin/env python3
"""The rule that reads the runbook, kept in its own file because the check half is at the size cap.

The rule reads the page as data: the commands its fenced lines call against the command surface the
dispatch registers, the flags those lines use against the signature each command declares, the
environment names against the names the config reads, the durability value against the pragma the
storage wrapper runs, the room number against the factor the free-space check uses, and the
order the page names its steps in against the order the run recorded running them in.

Five of those six halves read a committed file, so a crafted document cannot move them: they are
seen to fail by patching the page itself, which the header of `probes.py` names. The sixth reads the
document, so it is the half the probe round crafts.
"""

import sources


def runbook_reads_the_command_surface(data):
    """The rule over the page, split into the halves each message names."""
    calls, findings = sources.runbook_calls("runbook"), []
    declared = sources.literals_in("cli", "static func makeCommandGroup", "    }", 'as: "',
                                   "commands.use(")
    for command, used in calls:
        if command not in declared:
            findings.append(f"the runbook calls {command}, which the dispatch registers no case for")
        for flag in used:
            if flag not in sources.flags_for(command):
                findings.append(f"the runbook uses --{flag} with {command}, which its signature does not declare")
    for name in sorted(set(sources.runbook_names("runbook"))):
        if name not in sources.parser_names():
            findings.append(f"the runbook sets {name}, which no config read takes")
    if sources.spelled("runbook", "synchronous") != sources.code_value("storage", "synchronous"):
        findings.append(f"the runbook states synchronous as {sources.spelled('runbook', 'synchronous')}, not the {sources.code_value('storage', 'synchronous')} the storage wrapper runs")
    if sources.number_after("runbook", "factor") != int(sources.code_value("free_space", "factor")):
        findings.append(f"the runbook states the room with the factor {sources.number_after('runbook', 'factor')}, not the {sources.code_value('free_space', 'factor')} the check uses")
    named = [command for command, _ in calls]
    ran = [one for one in dict.fromkeys(data["run"]["steps"]) if one in named]
    if ran != list(dict.fromkeys(named)):
        findings.append(f"the run ran the steps the page names as {ran}, not in the order it gives them ({list(dict.fromkeys(named))})")
    return findings


RULES = {"runbook_reads_the_command_surface": runbook_reads_the_command_surface}
