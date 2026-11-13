#!/usr/bin/env python3
"""The DocC run's data reader: the catalog read as the tool read it.

The run half is `Scripts/docs.sh`, which copies the catalog into the directory it ran in, runs the
tool there, and calls this file. Nothing here asserts anything: the rules are in `docs_check.py`,
which reads the document this file writes, so a run that read a different answer is falsifiable
through the same round as every other rule.

The document records the tool's own answer as the tool answered it: the pages it wrote, the findings
it printed, and the code it answered with. The tool answers no version for its own run, so the
document records the program the run invoked, which is read by no rule.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import parsers as read


def built_pages(out):
    """The pages the tool wrote, as the paths it wrote them at, relative to the build."""
    found = []
    for path, _, names in os.walk(out):
        for name in names:
            if name.endswith(".html"):
                found.append(os.path.relpath(os.path.join(path, name), out))
    return sorted(found)


def document(out, tool, answer):
    """The run's own values and the tool's answer, with nothing read off the machine.

    The record and catalog paths are recorded as the repository root names them, so the document
    says the same thing on the machine that ran the run as on the machine that reads it; the build
    path is recorded as the run wrote it, because the run writes it outside the repository.
    """
    return {
        "run": {"record": read.repo_name(os.environ["docs_record"]),
                "catalog": read.repo_name(read.DEFAULTS["catalog"]), "out": out, "tool": tool},
        "tool": {"pages": built_pages(out),
                 "findings": [line for line in answer.splitlines() if line]},
    }


def main():
    out = os.environ["docs_out"]
    tool = os.environ["docs_tool"]
    record = os.environ["docs_record"]
    answer = open(os.path.join(os.environ["docs_work"], "answer.txt"), encoding="utf-8").read()

    with open(record, "w", encoding="utf-8") as handle:
        if os.environ.get("docs_empty") == "1":
            # The half the guard reads: a run that wrote no answer for the tool.
            handle.write("{}\n")
        else:
            json.dump(document(out, tool, answer), handle, indent=2, sort_keys=True)
            handle.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
