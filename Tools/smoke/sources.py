#!/usr/bin/env python3
"""The committed files the smoke rules read as data: the Dockerfile, the manifest, the sources.

It parses nothing but what the files write, so a rule that compares the document with a name a
source declares reads the source rather than the run's word for it. It is kept apart from the rules
the way `Tools/clients/parsers.py` is kept apart from the client-matrix check half, so the rule list
stays the readable part of the check half.

The files it reads: the Dockerfile the base and the file set are read against; the corpus manifest
and the corpus files the digests are read against; the schema file the migration answer is read
against; the sources the answers are read against — the health route, the user-info shape, the
login handler's bound field names, the route group and the registered path, the header name the
auth read takes the token from, the first word of the value it compares, the sentence the account
command writes, the line the serve run writes for its integrity rule; the release script the
artifact path is read from; the fetcher file that names the policy variable and the default its
own defaults carry, and the config file for the value forms the boolean read switches on; the
policy file for the address classes it refuses; the batch file for the order clause the pick order
is read against; the storage wrapper for the pragma the runbook's durability sentence is read
against and the free-space check for the factor its room sentence is read against; and the runbook
the stage has now written, read as the commands its fenced lines call.

Usage: read by `smoke_check.py`, which names the files it needs.
"""

import hashlib
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")

DEFAULTS = {"document": os.path.join(HERE, "run.json"),
            "dockerfile": os.path.join(ROOT, "Dockerfile"),
            "manifest": os.path.join(HERE, "corpus", "manifest.txt"),
            "schema": os.path.join(ROOT, "Sources", "RivuletCore", "Storage", "Migrations",
                                   "SchemaV1.swift"),
            "health_route": os.path.join(ROOT, "Sources", "RivuletApp", "Routes",
                                         "HealthRoutes.swift"),
            "shape": os.path.join(ROOT, "Sources", "RivuletApp", "Routes",
                                  "GoogleReaderShape.swift"),
            "serve": os.path.join(ROOT, "Sources", "RivuletApp", "Commands", "Serve.swift"),
            "backup": os.path.join(ROOT, "Sources", "RivuletApp", "Commands", "Backup.swift"),
            "create_admin": os.path.join(ROOT, "Sources", "RivuletApp", "Commands",
                                         "CreateAdmin.swift"),
            # Read as one literal, because the guard reads this entry with the name the run
            # declares, and a path split over segments is not one literal the shell can read.
            "integration_credentials": os.path.join(ROOT, "Sources/RivuletApp/Commands/IntegrationCredentials.swift"),
            "cli": os.path.join(ROOT, "Sources", "RivuletApp", "RivuletCLI.swift"),
            "auth": os.path.join(ROOT, "Sources", "RivuletApp", "Routes",
                                 "GoogleReaderAuth.swift"),
            "routes": os.path.join(ROOT, "Sources", "RivuletApp", "Routes",
                                   "GoogleReaderRoutes.swift"),
            "config": os.path.join(ROOT, "Sources", "RivuletCore", "Config", "Config.swift"),
            "fetcher": os.path.join(ROOT, "Sources", "RivuletCore", "Config",
                                    "FetcherOptions.swift"),
            "policy": os.path.join(ROOT, "Sources", "RivuletCore", "Reader",
                                   "NetworkAddressPolicy.swift"),
            "batch": os.path.join(ROOT, "Sources", "RivuletCore", "Storage", "Repositories",
                                  "FeedRepository+Batch.swift"),
            "storage": os.path.join(ROOT, "Sources", "RivuletCore", "Storage", "SQLiteStorage.swift"),
            "free_space": os.path.join(ROOT, "Sources", "RivuletCore", "Storage",
                                       "FreeSpaceCheck.swift"),
            "release": os.path.join(ROOT, "Scripts", "build-release.sh"),
            "runbook": os.path.join(ROOT, "docs", "deploy.md")}


def read(name):
    with open(DEFAULTS[name], encoding="utf-8") as handle:
        return handle.read()


def corpus_path(name):
    return os.path.join(HERE, "corpus", os.path.basename(name))


def docker_lines(prefix):
    return [line.strip() for line in read("dockerfile").splitlines()
            if line.strip().startswith(prefix)]


def manifest_rows():
    rows = []
    for line in read("manifest").splitlines():
        if line.startswith("#") or not line.strip():
            continue
        parts = [part.strip() for part in line.split("|")]
        rows.append({"name": parts[0], "title": parts[1], "note": parts[2]})
    return rows


def digest(path):
    with open(path, "rb") as handle:
        return "sha256:" + hashlib.sha256(handle.read()).hexdigest()


def first_line(name, marker):
    return next(one for one in read(name).splitlines() if marker in one)


def quoted_values(line):
    """The string literals one line carries, in the order the file writes them."""
    parts = line.split('"')
    return [parts[i] for i in range(1, len(parts), 2)]


def prompts(name):
    """The prompt names a command declares, in the order the file writes them.

    Read as the order the file declares, not as the order the run answered them in: the run writes
    values through a terminal and records only the printed answer, so no document can say which
    prompt produced which value.
    """
    return [quoted_values(line)[0] for line in read(name).splitlines() if 'prompt: "' in line]


def literal(name, marker):
    """The first string literal on the line the marker names, as the file writes it."""
    return quoted_values(first_line(name, marker))[0]


def word_at(name, marker):
    """The name a declaration writes, read from the marker to the end of the name.

    Read as far as the name goes, because a declaration such as `struct SchemaV1: AsyncMigration`
    ends the name at the colon.
    """
    line = first_line(name, marker)
    name_read = ""
    for char in line[line.index(marker):]:
        if not char.isalnum():
            break
        name_read += char
    return name_read


def value_in_block(name, block, marker):
    """The value one line of a block carries after a marker, read as the block writes it.

    Read inside the block, because the same name also appears as a field declaration, and the rule
    reads the value the block puts with it.
    """
    body = read(name).split(block)[1]
    line = next(one for one in body.splitlines() if marker in one)
    return line.split(marker)[1].strip()


def switch_values(name, marker):
    """The values one switch line names, read as the file writes them."""
    return quoted_values(first_line(name, marker))


def single_cases(name, marker):
    """The single values a switch's cases name, read as the file writes them.

    Read from the function the marker names, not from the first place the name appears, because the
    same name appears in the comment above it. Only the cases naming one value are read, because a
    case naming a range or a guard on a second byte is not the same shape and would be read as text.
    """
    body = read(name).split("func " + marker)[1].split("\n    }")[0]
    return [line.split("case ")[1].split(":")[0].strip() for line in body.splitlines()
            if line.strip().startswith("case ") and "where" not in line and "..." not in line]


def literals_in(name, start, stops_at, item_marker, line_prefix=""):
    """The literals a function body carries, read until the body ends.

    `line_prefix` names which lines of the body are read, because the same read shape appears on the
    guard lines too, and a rule that reads the values a function binds is not a rule that reads the
    values it guards on.
    """
    found, inside = [], False
    for line in read(name).splitlines():
        if start in line:
            inside = True
        elif inside and line.startswith(stops_at):
            break
        elif inside and item_marker in line and line.strip().startswith(line_prefix):
            found.append(quoted_values(line)[0])
    return found


def fenced(name):
    """The lines the runbook writes inside its fenced blocks, which are the commands it calls.

    Read inside the fences, because the same command name also appears in the prose, and the prose
    says what a run does while a fenced line is the line a person runs.
    """
    found, inside = [], False
    for line in read(name).splitlines():
        if line.startswith("```"):
            inside = not inside
        elif inside:
            found.append(line.strip())
    return found


def runbook_calls(name):
    """The command and the flags each `rivulet` line calls, as the page writes them."""
    return [(line.split()[1], sorted(one[2:] for one in line.split() if one.startswith("--")))
            for line in fenced(name) if line.startswith("rivulet ")]


def runbook_names(name):
    """The environment names the runbook assigns, read from the fenced lines that assign them."""
    return [line.split("=", 1)[0].split()[-1] for line in fenced(name) if "=" in line
            and line.split("=", 1)[0].split()[-1].isupper()]


def spelled(name, marker):
    """The inline-code value the runbook writes after a marker, as the page writes it."""
    return first_line(name, marker).split(marker, 1)[1].split("`")[1]


def number_after(name, marker):
    """The number the runbook states after a marker, read inside its parentheses."""
    return int(first_line(name, marker).split("(", 1)[1].split(")", 1)[0])


def code_value(name, marker):
    """The value a source writes for a marker on the line that assigns it, as the file writes it.

    Read on the assigning line, because the same name appears in the comment above it, and a rule
    that reads the value the code assigns is not a rule that reads the value the comment mentions.
    """
    line = next(one for one in read(name).splitlines() if marker in one and "=" in one)
    return line.split("=", 1)[1].strip().rstrip(",").strip('"')


def flags_for(command):
    """The flags one command's signature declares, read from the file its dispatch line names.

    Read per command, because a flag one command declares and another uses is not the same shape,
    and a runbook line that pairs them is a line the parser would reject.
    """
    line = next(one for one in read("cli").splitlines() if f'as: "{command}"' in one)
    path = os.path.join(ROOT, "Sources", "RivuletApp", "Commands",
                        line.split("commands.use(")[1].split("(")[0] + ".swift")
    with open(path, encoding="utf-8") as handle:
        body = handle.read()
    return [quoted_values(one)[0] for one in body.splitlines()
            if "@Option(name:" in one or "@Flag(name:" in one]


def parser_names():
    """The environment names the config reads, as the files that read them name them."""
    found = []
    for name in ("config", "fetcher"):
        found += [quoted_values(line)[0] for line in read(name).splitlines() if 'environment["' in line]
    return found
