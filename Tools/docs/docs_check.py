#!/usr/bin/env python3
"""The rules the DocC check half reads over the pages the catalog writes and the answer the
tool gave.

This is the DocC slice's check half: `Scripts/docs.sh` is the run half, `Tools/docs/collect.py`
writes the document the run leaves behind, and this file reads that document as data rather than a
build. It is not a test; it is checked by `probes.py`, which crafts at least one input per rule that
violates it and asserts each craft reports its own rule alone or the rules its patch reaches. The
committed document is the run this machine produced, and the baseline case asserts it
reports nothing.

Every rule is a function over the data `parsers.py` builds: the document the run left, or the
document and the committed files the run names. The pages are read as the shapes they write, so a
rule that compares a page with a source reads the source rather than the word the page declared for
it. What the rules cannot read is what `CANNOT_SHOW` names and what `docs/docc.md` writes as the
report: the version line the tool answers for itself, the directive kind and the child directives
the tool requires, the reading time each article names, and the prose of a page, which the rules
read as the shapes it writes and never as the sentence.

Usage, one per line:

docs_check.py --probe # the probe set against the committed document

docs_check.py --document docs.json # apply the rules to one run document
"""

import argparse
import os

import parsers as read

ROOT = read.ROOT

# The parts no rule can read, which the run cannot show either, so they are named here and in
# `docs/docc.md` rather than asserted by a rule. These lines are read as whole strings by the report
# rule, so they are not wrapped.
CANNOT_SHOW = [
    "that the tool answer recorded here is the answer another machine answers, because the run records what this machine's tool answered and the rules read that record",
    "the version of the tool the run names, because the tool answers no version for its own run and the run records the program it invoked",
    "a symbol page for a public declaration, because the rule reads the catalog's files as the shapes they write and the graph the build half copies is read as the path it is at rather than as the pages it writes, so a symbol page is what the archive has and not what the harness shows",
    "that a documentation comment renders as a page, because the rule reads the sources as text and the page it renders into is read by no rule",
    "the prose of a page, which the rules read as the shapes it writes and not as the sentence, so a claim no shape carries is not a finding here",
    "a configuration name a page names in prose rather than sets, because the shape the rule reads is the assignment line a fence writes and not the sentence",
    "the reading time each article names, which the tool reads and no rule reads",
    "the titles, the chapter names and the child directives the tool requires, recorded for the reader and read by no rule",
    "the way a page renders, because the tool writes files and the rules read the shapes the files write",
    "the archive the build half writes, because it lives outside the repository and no rule here reads an archive or the link the build puts on a page it wrote",
    "the site the pages are published on, because the publishing happens outside this repository and no rule here reads what a web server answers",
    "a value a page states for a name the source reads with a trim alone, because no rule reads a value that reads as free text",
    "a stage state past the first part the rule reads, because the plan table writes a state as one long cell",
    "a claim about a test this round cannot run, because the rules read committed files as data and never a test",
    "the run having run at all, because the run half is on demand and the probe round is what CI runs",
    "the pages built on a machine that is not the one that wrote the catalog, because the committed answer is the run this machine ran",
    "the comment of an initializer, because the rule that reads the sources reads the named declaration kinds and an initializer is not one of them",
]

# Which rule reads which shape. The coverage rule reads this bookkeeping as data, so a shape no rule
# reads has to be named in `NOT_READ` rather than be left unread. These lines are the record lines
# the coverage rule reads as whole strings, so they are not wrapped.
READS = {
    "the_document_names_the_run_that_wrote_it": ["document"],
    "the_catalog_names_the_target_the_manifest_writes": ["catalog", "targets", "page.args"],
    "the_table_of_contents_names_every_page_the_catalog_has": ["pages", "page.path", "page.references"],
    "every_asset_the_table_of_contents_names_is_a_file_the_catalog_has": ["assets", "page.images"],
    "the_pages_the_tool_built_are_the_pages_the_catalog_has": ["document", "page.path"],
    "the_tool_answered_no_finding_for_any_page": ["document"],
    "the_pages_call_only_commands_the_dispatch_registers": ["commands", "page.calls"],
    "the_pages_use_only_flags_the_signatures_declare": ["command_flags", "page.flags", "page.calls"],
    "the_pages_set_only_names_the_config_reads": ["names", "page.sets"],
    "the_values_the_pages_write_are_the_values_the_example_writes": ["example", "page.values"],
    "the_values_the_pages_state_are_the_values_the_sources_write": ["page.stated", "integer_minimums",
        "listen_default"],
    "the_reference_version_the_pages_name_is_the_version_the_plan_pins": ["plan_version", "page.version"],
    "the_routes_the_pages_name_are_routes_the_port_registers": ["routes", "page.routes"],
    "the_clients_the_pages_name_are_the_clients_the_matrix_records": ["matrix_clients", "page.clients"],
    "no_page_carries_a_local_only_reference": ["page.repo_paths", "page.links"],
    "no_page_carries_a_todo": ["page.todo"],
    "every_public_declaration_has_a_documentation_comment": ["declarations"],
    "the_readme_names_the_stages_as_the_plan_table_states_them": ["plan_stages", "readme_stages"],
    "the_contents_table_names_every_document_the_docs_directory_has": ["contents", "docs_documents"],
    "report_names_rules_and_gaps": ["report"],
    "the_check_half_reads_every_shape_the_pages_write": ["shapes", "check.reads", "check.not_read"],
}

# The shapes no rule compares, named here so the coverage rule can read them as the part of the
# pages that is structure rather than a value. `page.fenced` is read through the shapes it builds -
# the calls, the names the page sets and the name-and-value pairs - so no rule compares the fenced
# lines themselves.
NOT_READ = ["page.fenced", "page.kind", "page.children"]


def toc(data):
    """The page the tool reads as the table of contents, which is the site's landing."""
    return next((one for one in data["pages"].values() if one["kind"] == "Tutorials"), None)


def stem(path):
    """The name the tool reads a page file as, which is the file without its extension."""
    return os.path.basename(path).split(".")[0]


def the_document_names_the_run_that_wrote_it(data):
    """The document as the run wrote it: the half the run names itself with, and the answer it got.

    The build is the part the run writes outside the repository, so a document naming a build inside
    the tree is a run that put a generated artifact where the working agreement says none may go. A
    half the document does not carry is read as a finding here rather than as a crash, because the
    writer leaves a document with no answer when the run read nothing, which is the shape the run
    half's guard reads through the data writer.
    """
    halves = {"run": "the half the run writes", "tool": "the half a run that read nothing leaves out"}
    findings, document = [], data["document"]
    for name, phrase in halves.items():
        if document.get(name) is None:
            findings.append(f"the document carries no {name} part, which is {phrase}")
    if findings:
        return findings
    run = document["run"]
    if run["record"] != read.repo_name(read.DEFAULTS["document"]):
        findings.append(f"the document names the record as {run['record']}, not the path the check half reads it at ({read.repo_name(read.DEFAULTS['document'])})")
    if run["catalog"] != read.repo_name(read.DEFAULTS["catalog"]):
        findings.append(f"the run read the catalog at {run['catalog']}, not the path the check half reads it at ({read.repo_name(read.DEFAULTS['catalog'])})")
    if str(run["out"]).startswith(ROOT):
        findings.append(f"the run wrote its build at {run['out']}, which is inside the repository")
    return findings


def the_catalog_names_the_target_the_manifest_writes(data):
    """The catalog as the directory the tool reads it at, against the target the manifest writes."""
    findings = []
    if data["catalog"] not in data["targets"]:
        findings.append(f"the catalog sits under the source directory {data['catalog']}, which is not a target the manifest writes ({data['targets']})")
    contents = toc(data)
    if contents is None:
        return findings + ["the catalog writes no table of contents, so the name the tool reads for the site has nothing to compare"]
    if contents["args"].get("name") != data["catalog"]:
        findings.append(f"the table of contents names the site as {contents['args'].get('name')}, not the target the catalog sits under ({data['catalog']})")
    return findings


def the_table_of_contents_names_every_page_the_catalog_has(data):
    """The pages read on both halves: the list the table of contents writes against the files, and
    the files against the list.
    """
    contents, findings = toc(data), []
    if contents is None:
        return ["the catalog writes no table of contents, so the pages it has are named by no list"]
    named = {stem(path) for path in data["pages"] if path != contents["path"]}
    for name in sorted(named):
        if name not in contents["references"]:
            findings.append(f"the catalog has the page {name}, which the table of contents names no reference for")
    for reference in sorted(contents["references"]):
        if reference not in named:
            findings.append(f"the table of contents names {reference}, which is not a page file the catalog has ({sorted(named)})")
    return findings


def every_asset_the_table_of_contents_names_is_a_file_the_catalog_has(data):
    """The image the tool reads, against the files the catalog has, which is the half a page
    cannot write.

    The tool resolves the name `@Image` writes against the catalog's resources directory, so the
    name is read as the file the directory has, one entry per file, and the shape the rule compares
    is the name against the file's own name rather than against the path.
    """
    contents, findings = toc(data), []
    if contents is None:
        return findings
    names = {os.path.basename(asset) for asset in data["assets"]}
    for image in sorted(contents["images"]):
        if image not in names:
            findings.append(f"the table of contents names the asset {image}, which is not a file the catalog has ({sorted(names)})")
    for name in sorted(names):
        if name not in contents["images"]:
            findings.append(f"the catalog has the asset {name}, which the table of contents names no image for")
    return findings


def tool_answer(data):
    """The answer the tool gave, read as the document's tool half.

    A run that read nothing writes no answer, so the absence of this half is read by the rule that
    reads the document as the run wrote it. The rules that read the answer read an answer that is
    not there as nothing to read, which is what keeps a craft that takes the document away from the
    run half single-firing.
    """
    return data["document"].get("tool") or {}


def built_names(data):
    """The pages as the tool wrote them, read as the name each built path carries.

    The tool writes one page per page file at the name it reads the file as, lowercased, and one
    landing for the site at the root, which is the one built item that names no page file. The name
    a path carries is the segment before `index.html`, so the rule compares names rather than the
    layout the tool chose for the site.
    """
    out = []
    for path in tool_answer(data).get("pages", []):
        parts = path.split("/")
        out.append(parts[-2] if len(parts) > 1 and parts[-1] == "index.html" else path)
    return sorted(out)


def the_pages_the_tool_built_are_the_pages_the_catalog_has(data):
    """The pages as the tool wrote them, read against the page files the catalog has.

    Both halves are read: the names the tool built against the page files, and the page files
    against those names, so a built name no page file writes and a page file the tool built no page
    for are both findings. The landing is read as the one built item that names no page file, which
    is the half no page file can write. A document with no tool part reports nothing here, because
    the half that is not there is read by the rule that reads the document as the run wrote it.
    """
    contents, answer, findings = toc(data), tool_answer(data), []
    if contents is None or not answer:
        return findings
    landing = "index.html"
    names = sorted(stem(path).lower() for path in data["pages"] if path != contents["path"])
    names.append(stem(contents["path"]).lower())
    if landing not in answer.get("pages", []):
        findings.append("the tool wrote no landing for the site, which is the built item that names no page file")
    built = [one for one in built_names(data) if one != landing]
    if sorted(built) != names:
        findings.append(f"the tool built {sorted(built)}, which is not the set the catalog writes ({names})")
    return findings


def the_tool_answered_no_finding_for_any_page(data):
    """The findings as the tool answered them, which is the half a page cannot pass by wording."""
    findings = tool_answer(data).get("findings", [])
    if findings:
        return [f"the tool answered {len(findings)} finding(s) for the run: {findings}"]
    return []


def the_pages_call_only_commands_the_dispatch_registers(data):
    """The commands the pages call, against the names the dispatch registers."""
    findings = []
    for path, one in sorted(data["pages"].items()):
        for call in one["calls"]:
            command = call.split()[1] if len(call.split()) > 1 else ""
            if command not in data["commands"]:
                findings.append(f"the page {path} calls {call}, which the dispatch registers no case for ({data['commands']})")
    return findings


def the_pages_use_only_flags_the_signatures_declare(data):
    """The flags each call carries, against the flags that command's signature declares."""
    findings = []
    for path, one in sorted(data["pages"].items()):
        for call, used in sorted(one["flags"].items()):
            command = call.split()[1]
            for flag in used:
                declared = data["command_flags"].get(command, [])
                if flag not in declared:
                    findings.append(f"the page {path} uses --{flag} with {command}, which its signature does not declare ({declared})")
    return findings


def the_pages_set_only_names_the_config_reads(data):
    """The names the pages set, against the names the config sources read."""
    findings = []
    for path, one in sorted(data["pages"].items()):
        for name in one["sets"]:
            if name not in data["names"]:
                findings.append(f"the page {path} sets {name}, which no config read takes")
    return findings


def the_values_the_pages_write_are_the_values_the_example_writes(data):
    """The name-and-value pairs the fenced lines write, against the committed example."""
    findings = []
    for path, one in sorted(data["pages"].items()):
        for name, value in sorted(one["values"].items()):
            if data["example"].get(name) != value:
                findings.append(f"the page {path} writes {name} as {value}, not the {data['example'].get(name)} the committed example writes")
    return findings


def the_values_the_pages_state_are_the_values_the_sources_write(data):
    """Each value a page states, against the value the source that writes it carries.

    The three markers are read as the sources write them: the pragma the storage wrapper runs, the
    factor the free-space check uses, and the listener the read answers for a value it does not
    read. The integer minimums are read as the reads carry them, so a page that states a number a
    read does not carry is a finding, and a name the source reads with a trim alone is not
    read here.
    """
    sources = {"pragma": read.code_value("storage", "synchronous"),
               "factor": read.code_value("free_space", "factor"), "listener": data["listen_default"]}
    findings = []
    for path, one in sorted(data["pages"].items()):
        for marker, value in sorted(one["stated"].items()):
            if value is None:
                continue
            if marker in sources:
                if str(value) != str(sources[marker]):
                    findings.append(f"the page {path} states {marker} as {value}, not the {sources[marker]} the source writes")
            elif int(value) != data["integer_minimums"].get(marker):
                findings.append(f"the page {path} states {marker} as {value}, not the {data['integer_minimums'].get(marker)} the integer read carries")
    return findings


def the_reference_version_the_pages_name_is_the_version_the_plan_pins(data):
    """The version the pages name, against the version the plan pins as the behavioral reference."""
    findings = []
    for path, one in sorted(data["pages"].items()):
        if one["version"] and one["version"] != data["plan_version"]:
            findings.append(f"the page {path} names {one['version']}, not the {data['plan_version']} the plan pins")
    return findings


def the_routes_the_pages_name_are_routes_the_port_registers(data):
    """The routes the pages name, against the registrations the route files write."""
    findings = []
    for path, one in sorted(data["pages"].items()):
        for route in one["routes"]:
            if route not in data["routes"]:
                findings.append(f"the page {path} names {route}, which the port registers no route for ({sorted(data['routes'])})")
    return findings


def the_clients_the_pages_name_are_the_clients_the_matrix_records(data):
    """The clients the pages name, against the names the client matrix records."""
    findings = []
    for path, one in sorted(data["pages"].items()):
        for client in one["clients"]:
            if client not in data["matrix_clients"]:
                findings.append(f"the page {path} names {client}, which the client matrix records no row for ({sorted(data['matrix_clients'])})")
    return findings


def no_page_carries_a_local_only_reference(data):
    """The pages as they can be published: a reference that resolves only in this repository is
    a finding.

    The first half reads an inline-code path inside the repository, which a published page cannot
    resolve. The second reads a link that is not an absolute URL, which is the shape the tool writes
    as a reference into the site rather than as a link out of it.
    """
    findings = []
    for path, one in sorted(data["pages"].items()):
        for name in one["repo_paths"]:
            findings.append(f"the page {path} names {name}, which is a path inside this repository and resolves nowhere a published page can go")
        for link in one["links"]:
            if not link.startswith("https://"):
                findings.append(f"the page {path} links to {link}, which is not an absolute URL the published site can resolve")
    return findings


def no_page_carries_a_todo(data):
    """The pages as the working agreement writes them: no TODO in prose."""
    return [f"the page {path} carries a TODO line, which the working agreement does not allow in prose"
            for path, one in sorted(data["pages"].items()) if one["todo"]]


def every_public_declaration_has_a_documentation_comment(data):
    """The public declarations, read as the sources write them, against the comment each one has."""
    missing = [one for one in data["declarations"] if not one["has_comment"]]
    if missing:
        return [f"{len(missing)} public declaration(s) have no documentation comment: " +
                "; ".join(f"{one['file']}:{one['line']}" for one in missing)]
    return []


def the_readme_names_the_stages_as_the_plan_table_states_them(data):
    """The stage states the root README names, against the states the plan table writes."""
    findings = []
    if not data["readme_stages"]:
        return ["the root README names no stage state, so the plan table is read against nothing"]
    for row in data["plan_stages"]:
        named = next((one for one in data["readme_stages"] if one["stage"] == row["stage"]), None)
        if named is None:
            findings.append(f"the plan table names stage {row['stage']}, which the root README names no state for")
            continue
        if named["title"] != row["title"]:
            findings.append(f"the root README names stage {row['stage']} as {named['title']}, not the {row['title']} the plan table writes")
        if named["state"] != row["state"]:
            findings.append(f"the root README states stage {row['stage']} as {named['state']}, not the {row['state']} the plan table states")
    return findings


def the_contents_table_names_every_document_the_docs_directory_has(data):
    """The contents table against the documents, read on both halves.

    The paths the table writes are read relative to the page that writes them, which is the
    directory the table names, so a row pointing at a stage file or at the working agreement is read
    as the path that page resolves.
    """
    findings = []
    for row in data["contents"]:
        path = row["path"]
        target = os.path.join(read.DEFAULTS["docs_dir"], path)
        if not os.path.exists(target):
            findings.append(f"the contents table names {row['document']} at {path}, which is not a file the repository has")
        if os.path.dirname(target) == read.DEFAULTS["docs_dir"] and os.path.basename(target) not in data["docs_documents"]:
            findings.append(f"the contents table names {path}, which is not a document the docs directory has")
    for name in data["docs_documents"]:
        if name not in {row["path"] for row in data["contents"]}:
            findings.append(f"the docs directory has {name}, which the contents table names no row for")
    return findings


def the_check_half_reads_every_shape_the_pages_write(data):
    """The shapes the pages and the document write, against the bookkeeping the check half keeps."""
    covered = set(sum(READS.values(), [])) | set(NOT_READ)
    missing = [shape for shape in data["shapes"] if shape not in covered]
    if missing:
        return [f"no rule reads {sorted(missing)}, which the pages write and the report names nothing for"]
    return []


def report_names_rules_and_gaps(data):
    """The two lists the report document carries, read against what the check half has."""
    rules, gaps = read.report_lists(data["report"])
    findings = []
    if sorted(rules) != sorted(RULES):
        findings.append(f"the report names {sorted(rules)}, not every rule the check half has ({sorted(RULES)})")
    if sorted(gaps) != sorted(CANNOT_SHOW):
        findings.append(f"the report names {sorted(gaps)}, not what the run cannot show ({sorted(CANNOT_SHOW)})")
    return findings


RULES = {
    "the_document_names_the_run_that_wrote_it": the_document_names_the_run_that_wrote_it,
    "the_catalog_names_the_target_the_manifest_writes": the_catalog_names_the_target_the_manifest_writes,
    "the_table_of_contents_names_every_page_the_catalog_has": the_table_of_contents_names_every_page_the_catalog_has,
    "every_asset_the_table_of_contents_names_is_a_file_the_catalog_has": every_asset_the_table_of_contents_names_is_a_file_the_catalog_has,
    "the_pages_the_tool_built_are_the_pages_the_catalog_has": the_pages_the_tool_built_are_the_pages_the_catalog_has,
    "the_tool_answered_no_finding_for_any_page": the_tool_answered_no_finding_for_any_page,
    "the_pages_call_only_commands_the_dispatch_registers": the_pages_call_only_commands_the_dispatch_registers,
    "the_pages_use_only_flags_the_signatures_declare": the_pages_use_only_flags_the_signatures_declare,
    "the_pages_set_only_names_the_config_reads": the_pages_set_only_names_the_config_reads,
    "the_values_the_pages_write_are_the_values_the_example_writes": the_values_the_pages_write_are_the_values_the_example_writes,
    "the_values_the_pages_state_are_the_values_the_sources_write": the_values_the_pages_state_are_the_values_the_sources_write,
    "the_reference_version_the_pages_name_is_the_version_the_plan_pins": the_reference_version_the_pages_name_is_the_version_the_plan_pins,
    "the_routes_the_pages_name_are_routes_the_port_registers": the_routes_the_pages_name_are_routes_the_port_registers,
    "the_clients_the_pages_name_are_the_clients_the_matrix_records": the_clients_the_pages_name_are_the_clients_the_matrix_records,
    "no_page_carries_a_local_only_reference": no_page_carries_a_local_only_reference,
    "no_page_carries_a_todo": no_page_carries_a_todo,
    "every_public_declaration_has_a_documentation_comment": every_public_declaration_has_a_documentation_comment,
    "the_readme_names_the_stages_as_the_plan_table_states_them": the_readme_names_the_stages_as_the_plan_table_states_them,
    "the_contents_table_names_every_document_the_docs_directory_has": the_contents_table_names_every_document_the_docs_directory_has,
    "report_names_rules_and_gaps": report_names_rules_and_gaps,
    "the_check_half_reads_every_shape_the_pages_write": the_check_half_reads_every_shape_the_pages_write,
}


def apply_rules(data):
    return [name for name, rule in sorted(RULES.items()) if rule(data)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--probe", action="store_true")
    parser.add_argument("--document", help="apply the rules to one run document instead of the committed one")
    args = parser.parse_args()

    if args.probe:
        import probes
        return probes.assert_each()

    if args.document:
        read.DEFAULTS["document"] = args.document

    data = read.build()
    fired = apply_rules(data)
    for name in fired:
        print(f"RULE FAIL: {name}: " + "; ".join(RULES[name](data)))
    return 1 if fired else 0


if __name__ == "__main__":
    raise SystemExit(main())
