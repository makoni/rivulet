#!/usr/bin/env python3
"""The deploy run's data reader: the three artifacts read as the two tools read them.

The run half is `Scripts/deploy.sh`, which builds the copies the tools read, runs the two tools, and
calls this file. Nothing here asserts anything: the rules are in `deploy_check.py`, which reads the
document this file writes, so a run that read a different answer is falsifiable through the same
round as every other rule.

The run copies the committed files into the directory it ran in, because the compose reads its build
context and its env file as paths relative to the file it reads, and because the file a deployment
reads is the gitignored name rather than the committed example. The document records each copy as
the path the run wrote it at and as the pair of digests, the committed file and the copy, so a run
that changed a copy is a finding for the rule that reads that pair.

The two tool answers are recorded as the tools answered them: the compose tool's resolution as the
JSON it printed, and the unit tool's lines as the lines it printed with the code it answered. The
version line each tool answered for itself is recorded for the reader and read by no rule.
"""

import hashlib
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import deploy_check as check
import parsers as read

COPY_NAMES = {"compose": "deploy_copy_compose", "unit": "deploy_copy_unit",
             "example": "deploy_copy_example", "dockerfile": "deploy_copy_dockerfile"}


def sha256(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def answer(tool, arguments, cwd):
    process = subprocess.run([tool] + arguments, cwd=cwd, capture_output=True, text=True)
    return process.stdout, process.stderr, process.returncode


def read_copies():
    """The four copies, with the committed bytes and the bytes the run wrote as the two digests."""
    paths = {key: os.environ[value] for key, value in COPY_NAMES.items()}
    committed = {key: read.digest(key) for key in COPY_NAMES}
    written = {key: sha256(paths[key]) for key in COPY_NAMES}
    return paths, committed, written


def document(work, project, compose_tool, analyze_tool, build):
    """The run's own values, the two tool answers, and the two lists the rules keep."""
    paths, committed, written = read_copies()
    unit_name = os.path.basename(read.DEFAULTS["unit"])
    compose_out, _, compose_code = answer(compose_tool, ["compose", "-p", project, "config",
                                                         "--format", "json"], build)
    # The unit tool prints its findings on the error stream, so the document keeps the lines as the
    # tool printed them rather than as the stream they landed on.
    _, analyze_out, analyze_code = answer(analyze_tool, ["verify", unit_name], build)
    return {
        "run": {
            "compose_tool": answer(compose_tool, ["compose", "version"], build)[0].strip(),
            "analyze_tool": answer(analyze_tool, ["--version"], build)[0].splitlines()[0],
            "project": project,
            "work": work,
            "unit_named": unit_name,
            "copies": paths,
            "digests": committed,
            "copy_digests": written,
            "program_on_this_machine": False,
        },
        "compose": json.loads(compose_out),
        "analyze": {"exit": analyze_code, "lines": [line for line in analyze_out.splitlines() if line]},
        "rules": sorted(check.RULES),
        "cannot_show": sorted(check.CANNOT_SHOW),
    }


def main():
    work = os.environ["deploy_work"]
    record = os.environ["deploy_record"]
    project = os.environ["deploy_project"]
    compose_tool = os.environ["deploy_compose_tool"]
    analyze_tool = os.environ["deploy_analyze_tool"]
    data = document(work, project, compose_tool, analyze_tool, os.path.join(work, "deploy"))

    with open(record, "w", encoding="utf-8") as handle:
        if os.environ.get("deploy_empty") == "1":
            # The half the guard reads: a run that wrote no answer for either tool.
            handle.write("{}\n")
        else:
            json.dump(data, handle, indent=2, sort_keys=True)
            handle.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
