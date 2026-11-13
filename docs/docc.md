# DocC harness (stage 8)

This is the harness that reads the DocC layer as data. The layer itself is
`Sources/RivuletCore/RivuletCore.docc/`: one table-of-contents page, four concept articles, one
tutorial, and the asset the table of contents names. The pages state only what a check here can show
— the commands the dispatch registers, the flags those signatures declare, the names the
configuration reads, the values the sources write, the routes the port registers, the clients the
client matrix records, and the version the plan pins — so a page that names something the sources do
not write is a finding rather than a sentence.

The halves are separated the way the deploy slice's are: `Scripts/docs.sh` is the run half,
`Tools/docs/collect.py` writes the document the run leaves behind, and `Tools/docs/docs_check.py` is
the check half, reading that document as data rather than a build. The reads are in
`Tools/docs/parsers.py` so the rule list stays the readable part, and `Tools/docs/probes.py` crafts
at least one input per rule that violates it: 31 cases — 30 crafts plus the baseline, which is
asserted to report nothing — so each craft reports its own rule alone, with no craft reaching more
than one rule through the patch it names, because every rule here reads the parsed form and never a
file, and the round hashes every file the check half reads before and after. The committed
`Tools/docs/docs.json` is the run this machine produced, and the CI job runs the round rather than
the run half, which needs the tool.

## The rules this check half reads

- every_asset_the_table_of_contents_names_is_a_file_the_catalog_has
- every_public_declaration_has_a_documentation_comment
- no_page_carries_a_local_only_reference
- no_page_carries_a_todo
- report_names_rules_and_gaps
- the_catalog_names_the_target_the_manifest_writes
- the_check_half_reads_every_shape_the_pages_write
- the_clients_the_pages_name_are_the_clients_the_matrix_records
- the_contents_table_names_every_document_the_docs_directory_has
- the_document_names_the_run_that_wrote_it
- the_pages_call_only_commands_the_dispatch_registers
- the_pages_set_only_names_the_config_reads
- the_pages_the_tool_built_are_the_pages_the_catalog_has
- the_pages_use_only_flags_the_signatures_declare
- the_readme_names_the_stages_as_the_plan_table_states_them
- the_reference_version_the_pages_name_is_the_version_the_plan_pins
- the_routes_the_pages_name_are_routes_the_port_registers
- the_table_of_contents_names_every_page_the_catalog_has
- the_tool_answered_no_finding_for_any_page
- the_values_the_pages_state_are_the_values_the_sources_write
- the_values_the_pages_write_are_the_values_the_example_writes

Seven rules read more than one half, so they have one craft for each half: the document rule reads
the value its build path is compared with and the document read as the run wrote nothing; the
catalog rule reads the directory the tool reads the catalog at and the name the table of contents
writes for the site; the table-of-contents rule reads the list against the page files and the page
files against the list; the stated-value rule reads the pragma, the factor, the listener and the
integer minimums, which are four kinds of value; the reference-path rule reads an inline-code path
and a link; the contents-table rule reads the rows against the documents and the documents against
the rows; and the report rule reads the two lists below against what the check half has.

## What this harness cannot show

- that the tool answer recorded here is the answer another machine answers, because the run records what this machine's tool answered and the rules read that record
- the version of the tool the run names, because the tool answers no version for its own run and the run records the program it invoked
- a symbol page for a public declaration, because the rule reads the catalog's files as the shapes they write and the graph the build half copies is read as the path it is at rather than as the pages it writes, so a symbol page is what the archive has and not what the harness shows
- that a documentation comment renders as a page, because the rule reads the sources as text and the page it renders into is read by no rule
- the prose of a page, which the rules read as the shapes it writes and not as the sentence, so a claim no shape carries is not a finding here
- a configuration name a page names in prose rather than sets, because the shape the rule reads is the assignment line a fence writes and not the sentence
- the reading time each article names, which the tool reads and no rule reads
- the titles, the chapter names and the child directives the tool requires, recorded for the reader and read by no rule
- the way a page renders, because the tool writes files and the rules read the shapes the files write
- the archive the build half writes, because it lives outside the repository and no rule here reads an archive or the link the build puts on a page it wrote
- the site the pages are published on, because the publishing happens outside this repository and no rule here reads what a web server answers
- a value a page states for a name the source reads with a trim alone, because no rule reads a value that reads as free text
- a stage state past the first part the rule reads, because the plan table writes a state as one long cell
- a claim about a test this round cannot run, because the rules read committed files as data and never a test
- the run having run at all, because the run half is on demand and the probe round is what CI runs
- the pages built on a machine that is not the one that wrote the catalog, because the committed answer is the run this machine ran
- the comment of an initializer, because the rule that reads the sources reads the named declaration kinds and an initializer is not one of them

## The shapes the rules read

A page is read as the shapes it writes, one entry per file the catalog has: the top directive's kind
and its arguments, the child directives, the references the table of contents names, the assets it
names, the fenced lines, the commands the page calls, the flags each call carries, the names the
page sets, the name-and-value pairs the fenced lines write, the stated values, the routes, the
clients, the links, the repository paths, the version, the TODO lines and the path itself. The
document is read as the run's record path, catalog path and build path, and as the tool's answer:
the pages it wrote and the findings it printed. The sources the rules read against are the manifest,
the dispatch, the config parser and the fetcher options, the two route files, the storage wrapper,
the free-space check, the committed example, the client matrix, the plan table, the root README, the
contents table, the documents the docs directory has, the Swift sources and this document.

The coverage rule reads the bookkeeping of which rule reads which shape, so a shape no rule compares
has to be named there as not read rather than be left unread: the directive kind, the child
directives, and the fenced lines, which are read through the shapes they build — the calls, the
names the page sets and the name-and-value pairs — rather than compared as lines. Every other shape
the pages and the document write is read by a rule.

## The run half

`Scripts/docs.sh` copies the catalog keeping the name the tool reads it as, writes its build outside
the repository, runs the tool, and hands the answer to `Tools/docs/collect.py`. The run asserts
nothing about what the tool answers for the pages it builds; the rules read the answer as data. The
shell is checked by `bash -n` and by its eight guards, thirteen read sites, each seen to fail here
on the value the usage line names: the record path, the catalog path, the tool, the seven copies,
the asset, the build path, the page set, and the document.

## The build half

`Scripts/build-docs.sh` is the build half: it reads the catalog at the path the check half reads it
at, takes the symbol graph from SwiftPM's own subcommand — the tool has no plugin for the graph here
— copies the one file for the target the manifest writes, because a single build answers for one
module while the graph dir holds every module the manifest resolves, and writes the archive a site
is built from, outside the repository, with a markdown link on every page the build wrote. The
routes the build has a markdown file for are the pages the graph writes as well as the tutorial, so
the page the site opens first keeps the link hidden rather than pointing at a file the build never
wrote. The script is checked by `bash -n` and by its nine guards, thirteen read sites, each seen to
fail here on the value the usage lines name: the archive path, the catalog path, the tool, SwiftPM,
the base read as the tool writes it, the names the markdown manifest carries, the copy against the
file SwiftPM wrote, the module the copy names against the target the manifest writes, and the link
on each page the committed document names. No rule here reads an archive, so this half is what a
person runs before publishing, and publishing is outside this repository. The four comment
references the tool reported as findings for a build that reads the graph are fixed at the sites
they name, and the tool answered nothing for the build run here.

## Running it

```sh
Scripts/docs.sh                                  # the run, then the guards
python3 Tools/docs/docs_check.py                 # the committed document as data
python3 Tools/docs/docs_check.py --probe         # the probe round
Scripts/build-docs.sh                            # the build half, then the guards
```

Publishing the pages as a site happens outside this repository, so no CI job here publishes them and
no rule here reads what a web server answers. The round is what CI runs for this harness, because
the run half and the build half both need the tool. The run half writes its copy and its build in a
temporary directory outside the repository; the build half writes the archive outside the repository
as well, at the path its guard reads against the tree, which is what keeps the archive
out of a commit.
