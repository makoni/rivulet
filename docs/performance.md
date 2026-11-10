# Performance notes (stage 7)

The numbers this stage records are measurements taken on this machine, not bounds. A bound is a rule
a pin asserts; a measurement is what a run answered here, and the two are kept apart because only
the first can fail on a patch. The run half is `Scripts/perf.sh`, the check half is
`Tools/clients/replay.py`, and the recorded numbers are `Tools/clients/perf-run.txt` — the output
the run printed here, kept as data so the rule that reads the document's claims can match each claim
to the line that produced it. It is not a test and it is not in CI.

The shape every run here had: 100 feeds, 3 items per feed, the local stub server, a debug build, and
the flag `FETCHER_ALLOW_PRIVATE_NETWORKS=true`, because the stub server is a private-network host.
The rows are stamped before the run instant, because the due rule is strictly less than the instant
it reads, so a row stamped at the run instant is not due at that instant.

## The numbers measured here

| Run | Source | Field | Value | Named as |
| --- | --- | --- | --- | --- |
| run 1 | Scripts/perf.sh | pass_wall_ms | 2146 | measured here |
| run 1 | Scripts/perf.sh | second_pass_wall_ms | 31 | measured here |
| run 1 | Scripts/perf.sh | entries_written | 300 | measured here |
| run 1 | LargeFeedTests | read_path | 0.001171302 | measured here |
| run 1 | LargeFeedTests | read_path | 0.001538876 | measured here |
| run 2 | Scripts/perf.sh | pass_wall_ms | 2171 | measured here |
| run 2 | Scripts/perf.sh | second_pass_wall_ms | 32 | measured here |
| run 2 | Scripts/perf.sh | entries_written | 300 | measured here |
| run 2 | LargeFeedTests | read_path | 0.001126036 | measured here |
| run 2 | LargeFeedTests | read_path | 0.001150914 | measured here |
| run 3 | Scripts/perf.sh | pass_wall_ms | 2169 | measured here |
| run 3 | Scripts/perf.sh | second_pass_wall_ms | 31 | measured here |
| run 3 | Scripts/perf.sh | entries_written | 300 | measured here |
| run 3 | LargeFeedTests | read_path | 0.001165026 | measured here |
| run 3 | LargeFeedTests | read_path | 0.001448212 | measured here |
| run 4 | Scripts/perf.sh | pass_wall_ms | 2112 | measured here |
| run 4 | Scripts/perf.sh | second_pass_wall_ms | 31 | measured here |
| run 4 | Scripts/perf.sh | entries_written | 300 | measured here |
| run 4 | LargeFeedTests | read_path | 0.001149871 | measured here |
| run 4 | LargeFeedTests | read_path | 0.001200647 | measured here |
| 100k corpus | LargeFeedTests | read_path | — | not measured here |

The first four columns are what the run half and the pin printed; the last is what the rule reads,
so a number the document claims was measured here has to be carried by a record line with the same
run, source and field, and every record line has to be named here.

What the rows are: the wall time of one refresh pass over 100 local stub feeds — which is the whole
run, from the process start to its exit, so it includes the process startup and the single-threaded
stub server, not only the fetch and the write; 300 entries were written on each of the four passes.
The second pass, taken right after the first, is the shape: nothing was due, because each job had
already stamped the policy interval, so the pass read an empty batch. The read-path numbers are the
elapsed the timed pin itself measured at the reduced corpus of 10k entries, printed by the pin, and
the bound that pin asserts (250 ms) is the check half, not a measurement.

## What the numbers cannot show

- the query latency at the 100k corpus, which is gated, so no number for it is recorded here
- the numbers of another machine: these are this machine's, and the rule that reads them reads which
  numbers were measured here, not what another machine answered
- a release build, because every number here is from a debug build
- the wall time as the fetch or the write alone, because a wall number includes the process startup
  and the single-threaded stub server that answered the feeds
- the memory budget, which no pin reads, so it is documented as the plan states it and not measured
- the plan the planner chooses for a corpus of a different size, which the pins read only at the
  reduced corpus
- which rows the pass read, because the run reads the rows through the due rule and the record line
  names only the count the pass reported
- that the run ran at all, because it is on demand and not in CI, so the recorded log is the only
  record of it and the check half reads the log rather than the run

## The client matrix's read of this document

The performance half of the matrix is the rule `performance_names_which_numbers_were_measured_here`:
it reads this document's table against the recorded run log, and the run log against the fields the
sources declare: the names `Scripts/perf.sh` writes, and the name the timed pin's print writes, so
the pin is read as data here rather than assumed. It reports five kinds of finding, each with its
own craft: a claim the log does not carry, a field no source declares, a record line this document
does not name, a shape this document names differently than the run answered it, and the value the
table reports against the value the log carries — which is what makes the rule falsifiable rather
than a restatement of the numbers, and what makes the shape read as data rather than as a constant
in the check half.
