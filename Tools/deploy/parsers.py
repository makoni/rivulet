#!/usr/bin/env python3
"""The parsers the deploy check half reads the three deploy artifacts with.

Split from the rules the way `Tools/clients/parsers.py` is split from the client-matrix check half:
this file turns files into values and reports nothing, so the rule list stays the readable part.
Every function here is what one rule reads, so a crafted input in `probes.py` changes the parsed
form and never a file, and the round hashes every file named here before and after.

What the round reads as data: the document `Scripts/deploy.sh` leaves, which carries the two tool
answers the run recorded; the three deploy artifacts, read as the keys they write; the sources the
rules read the names and the shapes against - the config parser, the dispatch, the signal handler,
the hasher and the pin that names the width the token derivation writes; `.gitignore`, which is
where the env file name the run builds is read as data; and the runbook, which names the data path
and the port the run publishes.

Comment lines and empty lines in the artifacts are the part no rule reads. The two unit keys that are
structure rather than a value the port reads are named as not read in `deploy_check.py`, and the
position the unit tool prints for a key finding is recorded here for the reader and read by no rule.
"""

import hashlib
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

DEFAULTS = {
    "document": os.path.join(ROOT, "Tools", "deploy", "deploy.json"),
    "compose": os.path.join(ROOT, "deploy", "compose.yml"),
    "unit": os.path.join(ROOT, "deploy", "rivulet.service"),
    "example": os.path.join(ROOT, ".env.example"),
    "dockerfile": os.path.join(ROOT, "Dockerfile"),
    "gitignore": os.path.join(ROOT, ".gitignore"),
    "runbook": os.path.join(ROOT, "docs", "deploy.md"),
    "config": os.path.join(ROOT, "Sources", "RivuletCore", "Config", "Config.swift"),
    "fetcher": os.path.join(ROOT, "Sources", "RivuletCore", "Config", "FetcherOptions.swift"),
    "cli": os.path.join(ROOT, "Sources", "RivuletApp", "RivuletCLI.swift"),
    "signals": os.path.join(ROOT, "Sources", "RivuletApp", "ServerSignalSource.swift"),
    "hasher": os.path.join(ROOT, "Sources", "RivuletApp", "Hashing", "BcryptHasher.swift"),
    "token_test": os.path.join(ROOT, "Tests", "RivuletCoreTests", "FeverTokenTests.swift"),
}


def text(name):
    """The committed file read as the bytes it has."""
    return open(DEFAULTS[name], encoding="utf-8").read()


def data_lines(name):
    """The lines a file writes as data, which are the lines no comment line is."""
    return [line for line in text(name).splitlines() if line and not line.lstrip().startswith("#")]


def digest(name):
    """The bytes a committed file has, as the run recorded them for its copies."""
    return hashlib.sha256(open(DEFAULTS[name], "rb").read()).hexdigest()


def document():
    """The document the run left behind, read as the JSON it wrote."""
    with open(DEFAULTS["document"], encoding="utf-8") as handle:
        return json.load(handle)


def compose_tree():
    """The compose file read as the key set the tool resolves it as, with no YAML library.

    A line ending in a colon opens a block, and a dash line is an item of the block the line before
    it opened. The indent stack is the nesting, so the keys come out as the paths the tool reads.
    """
    tree, lists = {}, {}
    stack = [(-1, tree, "")]
    for raw in data_lines("compose"):
        indent = len(raw) - len(raw.lstrip(" "))
        while len(stack) > 1 and indent <= stack[-1][0]:
            stack.pop()
        container, path = stack[-1][1], stack[-1][2]
        item = raw.strip()
        if item.startswith("-"):
            lists.setdefault(path, []).append(item[1:].strip().strip('"'))
            continue
        key, _, value = item.partition(":")
        key = key.strip()
        full = key if not path else f"{path}.{key}"
        if value:
            container[key] = value.strip()
        else:
            child = {}
            container[key] = child
            stack.append((indent, child, full))
    for path, items in lists.items():
        node = tree
        for part in path.split(".")[:-1]:
            node = lists.get(part, node[part])
        node[path.rsplit(".", 1)[-1]] = items
    return tree


def unit_sections():
    """The unit read as the sections it puts its keys in, which is what the tool reads it as."""
    sections, current = {}, None
    for raw in data_lines("unit"):
        if raw.startswith("["):
            current = raw.strip("[]")
            sections.setdefault(current, {})
            continue
        key, _, value = raw.partition("=")
        sections[current][key.strip()] = value.strip()
    return sections


def example_values():
    """The committed example read as the names and the values it writes, one pair per line."""
    values = {}
    for raw in data_lines("example"):
        name, _, value = raw.partition("=")
        values[name.strip()] = value.strip()
    return values


def dockerfile_lines():
    """The image file read as the lines it writes: base, the file it copies, the program."""
    out = {}
    for raw in data_lines("dockerfile"):
        keyword, _, value = raw.partition(" ")
        out[keyword] = value.strip()
    return out


def gitignored():
    """The names .gitignore writes, as the lines it writes them at."""
    return [line.strip() for line in data_lines("gitignore")]


def env_file_name():
    """The gitignored name the file a deployment reads has, read as the line .gitignore writes."""
    return next(one for one in gitignored() if one.endswith(".env"))


def runbook_names():
    """The names the runbook sets in its fenced block, read as the data the page writes."""
    block = text("runbook").split("```sh")[1].split("```")[0]
    out = {}
    for raw in block.splitlines():
        if raw.startswith("export "):
            name, _, value = raw[7:].partition("=")
            out[name.strip()] = value.strip()
    return out


def parser_names():
    """The names the config reads, as the sources write them, not as the runbook says them."""
    source = text("config") + text("fetcher")
    return sorted(set(re.findall(r'environment\["([A-Z_0-9]+)"\]', source)))


SWITCH = ['case "1", "yes", "true", "on":', 'case "0", "no", "false", "off":']


def shapes():
    """For each name the config reads, what kind of value the read takes it as.

    The integer reads carry their own minimum, the choice reads carry the case set the enum
    declares, the boolean read carries the forms the switch has, and the three reads that take a
    value as a shape of their own are named by the function that reads them. A name the source
    reads with a trim alone is read as free text.
    """
    source = text("config")
    out = {}
    pattern = r'parseInteger\(variable: "([A-Z_0-9]+)",[^)]*?minimum: (\d+)\)'
    for name, minimum in re.findall(pattern, source + text("fetcher")):
        out[name] = {"kind": "integer", "minimum": int(minimum)}
    enums = {name: [one.strip() for one in cases.split(",")]
             for name, cases in re.findall(r"enum (\w+): String.*?\n\s*case ([a-z, ]+)", source)}
    choice = r'parseEnum\(\s*(\w+)\.self,\s*variable: "([A-Z_0-9]+)"'
    for type_name, variable in re.findall(choice, source):
        out[variable] = {"kind": "choice", "cases": enums[type_name]}
    forms = [one for one in source.splitlines() if one.strip() in SWITCH]
    boolean_read = r'parseBoolean\(\s*variable: "([A-Z_0-9]+)"'
    for variable in re.findall(boolean_read, source + text("fetcher")):
        out[variable] = {"kind": "boolean", "forms": re.findall(r'"([0-9a-z]+)"', "\n".join(forms))}
    for name, kind in (("DATABASE_URL", "path"), ("BASE_URL", "url"), ("LISTEN_ADDR", "host port")):
        out[name] = {"kind": kind}
    for name in parser_names():
        out.setdefault(name, {"kind": "text"})
    return out


def listen_default():
    """The listener the read answers for a value it does not read, read as the source writes it."""
    line = next(one for one in text("config").splitlines() if "ListenAddress(host:" in one)
    host = re.search(r'"([\d.]+)"', line).group(1)
    return {"host": host, "port": int(re.search(r"port: (\d+)", line).group(1))}


def value_shapes():
    """The shapes the reads take a value as, read from the guards the source writes."""
    path_line = next(one for one in text("config").splitlines() if 'range(of: "^[' in one)
    scheme_line = next(one for one in text("config").splitlines() if 'scheme == "http"' in one)
    return {"path_scheme": re.search(r'"(\^\[.*?://)"', path_line).group(1),
            "schemes": sorted(re.findall(r'"(https?)"', scheme_line))}


def dispatch_commands():
    """The commands the dispatch registers, as the names its lines write."""
    return sorted(set(re.findall(r'as: "([a-z-]+)"', text("cli"))))


def handler_signals():
    """The signals the process handler has a case for, as the source names them."""
    return sorted(set(re.findall(r"\bSIG[A-Z]+\b", text("signals"))))


def credential_shapes():
    """The two value shapes the credential paths write, read from the sources that write them."""
    marker = re.search(r"this port writes (`\$2[ab]\$`)", text("hasher")).group(1).strip("`")
    width = int(re.search(r"token\.count == (\d+)", text("token_test")).group(1))
    return {"marker": marker, "hex_width": width}


def analyze_lines(raw_lines, passed):
    """The lines the unit tool printed, read as the file, the position and the value each names.

    The tool names the file two ways: as the path it resolved the unit at with the position the key
    sits at for a key finding, and as the name the run passed it with no position for the finding
    about the program, so the rule that reads the tool as data reads the file in the shape the tool
    printed it. The position is recorded for the reader and read by no rule. A line can name a key
    the unit writes in a section the unit does not put it in, which is what the tool reads as an
    unknown key, or the program the command names, which is the finding the run declares as not
    being on this machine.
    """
    out = []
    for raw in raw_lines:
        head, _, rest = raw.partition(":")
        position = re.match(r"^(\d+):", rest)
        if position:
            rest = rest[position.end():]
        entry = {"file": head, "position": position.group(1) if position else None,
                 "kind": "other", "key": None, "section": None, "program": None, "passed": passed}
        key = re.search(r"Unknown key '([A-Za-z]+)' in section \[(\w+)\]", rest)
        if key:
            entry.update({"kind": "key", "key": key.group(1), "section": key.group(2)})
        program = re.search(r"Command (\S+) is not executable", rest)
        if program:
            entry.update({"kind": "program", "program": program.group(1)})
        out.append(entry)
    return out


def key_paths(data):
    """Every key the three artifacts write, as the path the check half reads it at."""
    out = []

    def walk(node, path):
        for key, value in sorted(node.items()):
            full = f"{path}.{key}" if path else key
            out.append(full)
            if isinstance(value, dict):
                walk(value, full)

    walk(data["compose"], "compose")
    for section, keys in sorted(data["unit"].items()):
        for key in sorted(keys):
            out.append(f"unit.{section}.{key}")
    for name in sorted(data["example"]):
        out.append(f"example.{name}")
    return sorted(out)


def build():
    """The data the rules read: the document the run left, and the files it names."""
    data = {"document": document(), "compose": compose_tree(), "unit": unit_sections(),
            "example": example_values(), "dockerfile": dockerfile_lines(),
            "gitignore": gitignored(), "runbook": runbook_names(), "shapes": shapes(),
            "names": parser_names(), "commands": dispatch_commands(),
            "signals": handler_signals(), "credential": credential_shapes(),
            "listen_default": listen_default(), "value_shapes": value_shapes(),
            "env_file_name": env_file_name()}
    data["analyze"] = analyze_lines(data["document"]["analyze"]["lines"],
                                    data["document"]["run"]["unit_named"])
    return data
