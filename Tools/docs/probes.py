#!/usr/bin/env python3
"""The probe round the DocC check half is checked with, at least one crafted input per rule.

Every craft changes the parsed form and never a file, so the round hashes every file the check half
reads before and after and reports a craft that reached a file. The committed document is the run
this machine produced, and the baseline case asserts it reports nothing, which is what makes each
craft single-firing: a craft that reached a second rule is reported as reaching it. No craft here
reaches more than one rule, so `REACHES` names nothing; it is the place a craft that reached two
rules through one patch would be named, which is what keeps the assertion honest when a craft is
added. Seven rules have more than one craft, because each of those rules reads more than one half:
the document rule one for the value its build path is compared with and one for the document read as
the run wrote nothing, the catalog rule has one for the directory the tool reads it as and one for
the name the table of contents writes, the table-of-contents rule one for each half of its read, the
stated-value rule one for each of the four kinds of value it reads, the reference-path rule one for
each of its two halves, the contents-table rule one for each half, and the report rule one for each
of the two lists it reads.

The shapes the coverage rule reads are the shapes the parser produces, so a craft that adds a shape
to the parsed set is the only craft that can move that rule, and no other craft reaches it.

31 cases: 30 crafted inputs plus the baseline.

Run it through `docs_check.py --probe`.
"""

import hashlib
import os

import parsers as read
import docs_check as check

ROOT = read.ROOT

# The crafts that reach more than one rule through one patch, named as the rules they reach.
REACHES = {}


def hash_of():
    """The bytes every committed file the check half reads has, before and after the round."""
    out = {}
    for name in read.DEFAULTS:
        path = read.DEFAULTS[name]
        if os.path.isdir(path):
            for root, _, names in os.walk(path):
                for file in sorted(names):
                    out[os.path.relpath(os.path.join(root, file), ROOT)] = hashlib.sha256(
                        open(os.path.join(root, file), "rb").read()).hexdigest()
        else:
            out[name] = hashlib.sha256(open(path, "rb").read()).hexdigest()
    return out


def one_page(data):
    """One page as the rules read it, which is the shape a craft moves without moving a file."""
    return next(page for page in sorted(data["pages"]))


def the_document_names_the_run_that_wrote_it(data):
    # The build as the run wrote it, read against the repository the check half reads.
    data["document"]["run"]["out"] = os.path.join(os.path.dirname(read.DEFAULTS["document"]), "site")


def catalog_directory(data):
    # The directory the tool read the catalog at, read as a name the manifest writes no target for. The
    # table of contents keeps the name it writes equal to the catalog, so the second half reports
    # nothing, which is what keeps this craft single-firing.
    data["catalog"] = "Extra"
    toc = check.toc(data)
    toc["args"]["name"] = "Extra"


def catalog_name(data):
    # The name the table of contents writes for the site, read against the target the catalog sits
    # under. The first craft keeps the two equal and moves only the directory, so this one moves
    # only the name.
    check.toc(data)["args"]["name"] = "RivuletCorePage"


def table_missing_reference(data):
    check.toc(data)["references"] = [one for one in check.toc(data)["references"]
                                     if one != "Setup"]


def table_reference_without_file(data):
    check.toc(data)["references"] = sorted(set(check.toc(data)["references"]) | {"Extra"})


def asset_without_file(data):
    check.toc(data)["images"] = sorted(set(check.toc(data)["images"]) | {"missing.svg"})


def tool_built_an_extra_page(data):
    data["document"]["tool"]["pages"] = sorted(set(data["document"]["tool"]["pages"])
                                               | {"tutorials/rivuletcore/extra/index.html"})


def tool_answered_a_finding(data):
    data["document"]["tool"]["findings"] = ["warning: `Article` should name a page the catalog has"]


def page_calls_an_unregistered_command(data):
    # Only the shape the rule reads is changed: the call, not the fenced line it came from, so
    # no other
    # rule reads this craft. The command is one the port has no run for, which the runbook names as the
    # recipe rather than as a command.
    page = data["pages"][one_page(data)]
    page["calls"] = sorted(set(page["calls"]) | {"rivulet restore /var/backups/rivulet.db"})


def page_uses_an_undeclared_flag(data):
    page = data["pages"][one_page(data)]
    page["flags"] = {"rivulet status --count 3": ["count"]}


def page_sets_a_name_no_read_takes(data):
    page = data["pages"][one_page(data)]
    page["sets"] = sorted(set(page["sets"]) | {"DATABASE_FILENAME"})


def page_writes_a_value_the_example_does_not(data):
    page = data["pages"][one_page(data)]
    page["values"] = {"LOG_LEVEL": "verbose"}


def page_states_a_pragma_the_source_does_not(data):
    page = data["pages"][one_page(data)]
    page["stated"] = {"pragma": "FULL", "factor": 2, "listener": "127.0.0.1:8080"}


def page_states_a_factor_the_check_does_not(data):
    page = data["pages"][one_page(data)]
    page["stated"] = {"pragma": "NORMAL", "factor": 3, "listener": "127.0.0.1:8080"}


def page_states_a_listener_the_read_does_not(data):
    page = data["pages"][one_page(data)]
    page["stated"] = {"pragma": "NORMAL", "factor": 2, "listener": "0.0.0.0:8080"}


def page_states_a_minimum_the_read_does_not(data):
    page = data["pages"][one_page(data)]
    stated = dict(page["stated"])
    stated.update({name: value for name, value in data["integer_minimums"].items()})
    stated["POLLING_FREQUENCY"] = 2
    page["stated"] = stated


def page_names_another_version(data):
    data["pages"][one_page(data)]["version"] = "v2.3.4"


def page_names_an_unregistered_route(data):
    page = data["pages"][one_page(data)]
    page["routes"] = sorted(set(page["routes"]) | {"GET /reader/api/0/extra"})


def page_names_a_client_the_matrix_does_not(data):
    page = data["pages"][one_page(data)]
    page["clients"] = sorted(set(page["clients"]) | {"Fever Client"})


def page_names_a_repository_path(data):
    page = data["pages"][one_page(data)]
    page["repo_paths"] = sorted(set(page["repo_paths"]) | {"docs/deploy.md"})


def page_links_inside_the_repository(data):
    page = data["pages"][one_page(data)]
    page["links"] = sorted(set(page["links"]) | {"../reference-notes.md"})


def page_carries_a_todo(data):
    page = data["pages"][one_page(data)]
    page["todo"] = ["TODO: name the rule this sentence claims"]


def declaration_without_a_comment(data):
    data["declarations"] = [dict(one, has_comment=(index != 0)) for index, one in
                            enumerate(data["declarations"])]


def readme_states_a_stage_the_plan_does_not(data):
    data["readme_stages"] = [dict(one, state="done") if one["stage"] == "9" else one
                             for one in data["readme_stages"]]


def contents_names_a_document_the_directory_does_not_have(data):
    data["contents"] = data["contents"] + [{"document": "[Extra](extra.md)", "path": "extra.md",
                                            "description": "a document the directory has no file for"}]


def contents_names_no_document_the_directory_has(data):
    data["contents"] = [row for row in data["contents"] if row["path"] != "testing.md"]


def coverage_reads_no_shape(data):
    data["shapes"] = sorted(set(data["shapes"]) | {"page.caption"})


def report_names_rules(data):
    rules, gaps = read.report_lists(data["report"])
    data["report"] = data["report"].replace("\n".join("- " + one for one in rules), "")


def report_names_gaps(data):
    rules, gaps = read.report_lists(data["report"])
    data["report"] = data["report"].replace("\n".join("- " + one for one in gaps), "")


def document_with_no_answer(data):
    # The document read as the run wrote nothing, which the rule reports as a finding for each of the
    # two halves instead of crashing. The rules that read the tool's answer have no answer to read
    # here, so this craft fires the rule that reads the document alone, and it is the same shape the
    # run half's guard reads through the data writer.
    data["document"] = {}


def document_half_cases():
    """The crafts that move the document the run left, or the catalog shape it is read against."""
    return [
        ("the_document_names_the_run_that_wrote_it", the_document_names_the_run_that_wrote_it),
        ("the_document_names_the_run_that_wrote_it", document_with_no_answer),
        ("the_catalog_names_the_target_the_manifest_writes", catalog_directory),
        ("the_catalog_names_the_target_the_manifest_writes", catalog_name),
        ("the_table_of_contents_names_every_page_the_catalog_has", table_missing_reference),
        ("the_table_of_contents_names_every_page_the_catalog_has", table_reference_without_file),
        ("every_asset_the_table_of_contents_names_is_a_file_the_catalog_has", asset_without_file),
        ("the_pages_the_tool_built_are_the_pages_the_catalog_has", tool_built_an_extra_page),
        ("the_tool_answered_no_finding_for_any_page", tool_answered_a_finding),
    ]


def page_half_cases():
    """The crafts that move one page as the rules read it, one per rule the page half fires."""
    return [
        ("the_pages_call_only_commands_the_dispatch_registers", page_calls_an_unregistered_command),
        ("the_pages_use_only_flags_the_signatures_declare", page_uses_an_undeclared_flag),
        ("the_pages_set_only_names_the_config_reads", page_sets_a_name_no_read_takes),
        ("the_values_the_pages_write_are_the_values_the_example_writes",
         page_writes_a_value_the_example_does_not),
        ("the_values_the_pages_state_are_the_values_the_sources_write",
         page_states_a_pragma_the_source_does_not),
        ("the_values_the_pages_state_are_the_values_the_sources_write",
         page_states_a_factor_the_check_does_not),
        ("the_values_the_pages_state_are_the_values_the_sources_write",
         page_states_a_listener_the_read_does_not),
        ("the_values_the_pages_state_are_the_values_the_sources_write",
         page_states_a_minimum_the_read_does_not),
        ("the_reference_version_the_pages_name_is_the_version_the_plan_pins",
         page_names_another_version),
        ("the_routes_the_pages_name_are_routes_the_port_registers",
         page_names_an_unregistered_route),
        ("the_clients_the_pages_name_are_the_clients_the_matrix_records",
         page_names_a_client_the_matrix_does_not),
        ("no_page_carries_a_local_only_reference", page_names_a_repository_path),
        ("no_page_carries_a_local_only_reference", page_links_inside_the_repository),
        ("no_page_carries_a_todo", page_carries_a_todo),
    ]


def sources_half_cases():
    """The crafts that move the committed sources the rules read the pages against."""
    return [
        ("every_public_declaration_has_a_documentation_comment", declaration_without_a_comment),
        ("the_readme_names_the_stages_as_the_plan_table_states_them",
         readme_states_a_stage_the_plan_does_not),
        ("the_contents_table_names_every_document_the_docs_directory_has",
         contents_names_a_document_the_directory_does_not_have),
        ("the_contents_table_names_every_document_the_docs_directory_has",
         contents_names_no_document_the_directory_has),
        ("the_check_half_reads_every_shape_the_pages_write", coverage_reads_no_shape),
        ("report_names_rules_and_gaps", report_names_rules),
        ("report_names_rules_and_gaps", report_names_gaps),
    ]


def cases():
    """The round, grouped by the half each craft moves: the baseline, then one craft per rule.

    The grouping is what the docstring above calls the halves, so the list stays the readable part:
    the document half is the run's own answer, the page half is one page read as the shapes it
    writes, and the sources half is the committed files the pages are compared with.
    """
    return ([("baseline", lambda data: None)] + document_half_cases() + page_half_cases()
            + sources_half_cases())


def assert_each():
    started = hash_of()
    failed = []
    baseline = check.apply_rules(read.build())
    if baseline:
        failed.append(f"baseline: reports {baseline}")
    for rule, change in cases()[1:]:
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
