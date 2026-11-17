# Client matrix

This is the client matrix of stage 7. It records the calling sets of the clients that matter for
acceptance, and what the port answers for each of them.

Every set here is read from a source, not captured. A calling set is one of two things, and the
document names which one it is for every set: a client's own source at a named commit, or the
project's documentation when the client is closed source. No set is a capture, and three clients
have been run against this port here and left a record this half reads as data — NewsFlash, the
Fever client, FeedFlow, the Google Reader client run on a phone, and NetNewsWire, the Google Reader
run on a Mac, all through `Scripts/client-run.sh`, the run half that reads what a real client
actually sent — and the records those runs left behind, `Tools/clients/newsflash.txt`,
`Tools/clients/feedflow.txt` and `Tools/clients/netnewswire.txt`, one file per client named as the
round reads that client, are read as data by the rule that reads them, which reads them under those
names: the performance record that sits in the same directory is read by the rule that reads the
numbers, at its own path, and not as a record for a client the matrix has a row for. A fourth run,
Reeder Classic on the phone, walked the Fever half here, and its record is held as evidence outside
the repository rather than read here, because the set for that client records no calls, so the rule
reads a record file for it as a finding. The manual matrix exit criterion of
`docs/plan/stage-7-acceptance.md` is closed for the three whose records are read as data and for the
halves the walk on Reeder Classic showed, and stays open for lire, the client this machine has no
device to run. The single-client criterion of `docs/plan/stage-5-apis.md`, which names one real
client rather than a client by name, is closed: the Fever run shows the halves its set has, that a
client connects and syncs, and the Google Reader run shows the half that set has no call for, the
call that adds a feed. FeedFlow was run on a phone over the local network, and NetNewsWire on the
Mac on the same network, which is the half the run half reads the host guard for. The checklists
below are the checks to run for a client, and the four for the clients walked here name what each
walk showed.

The halves are separated the way the soak's and the parity harness's are. `Tools/clients/replay.py`
is the check half: it reads the calling sets, the record files, this document, the port's own
source, the pin that pins the response builder's status mapping, and the field the timed pin's print
writes as data, with the parsers it reads them with in `Tools/clients/parsers.py`, and the rule that
reads the halves the sets name in `Tools/clients/halves.py`, because this file is at the size cap,
so the rules stay the readable part of the file. What it reads as data
includes two sentences written for the sets they name: the shape the performance paragraph declares,
and the two sets of endpoints in `docs/reference-notes.md` that the output-check class is read
against. `Tools/clients/probes.py` is the probe half: it crafts one input per rule that violates it
and asserts that the rule reports it alone; the baseline reports nothing, so each probe is single-
firing — 19 rules, 36 crafted inputs and the baseline, so 37 cases: the performance rule has one
for each of the five kinds of finding it reads, the route rule has one for each of its two halves,
because an input that violates one of them still satisfies the other, the rule that reads the half
that reaches no route has one for each of its two halves, because a one-half set has no other half
to name, and the rule that reads the run record has one for each of its eleven halves, which is
twelve crafts: six on the record the
Fever run wrote here, one on the paragraph naming its calls, one on the record the Google Reader
run on the phone wrote here, the order half crafted again on the record the run on the Mac wrote,
one on a record this machine has not written, for a client whose set records no calls, one on the
names the round reads the record files under, which is the half that keeps the performance record,
read by its own rule at its own path, out of the client records; the craft adds a name the round
does not read a client under, so what the round shows is the message on that name, not that the
read leaves the other files out; and one on the status a record line carries, which writes a status
the handler for that path has no branch for. The order half reads a paragraph only when the
document writes it in the form the half names, so the craft on the Mac record works because the
paragraph for that client names the client, as the other two do; the form itself is the second half
named in `Tools/clients/run_record.py` rather than probed, because a craft that took the client name
out of the paragraph leaves this half reading nothing. One of the twelve crafts reaches two parts of
two parts of the data at once, the record line and the paragraph that names the calls this run
showed, because the half reads the record against the paragraph and the Fever run reached no call
outside the recorded set. Two crafts have to name data this rule cannot read, which is why the
redaction craft is on a set for a client this machine has not run and the first craft of the route
rule is on a row no record line reaches: a change to data this rule also reads fires it alongside
the rule the craft names, which is what the round showed here after the third record landed.

The width rule does not reach a table row, a manifest record line or a report item line, which are
each read as one whole string. The record lines and the item lines here are exempt for that reason.

## The run half

`Scripts/client-run.sh` is the run half and `Tools/clients/observer.py` is its observing half. The
run half asserts nothing about a record line: the observer writes what each request looked like as
it arrived, and the rule `the_run_record_agrees_with_the_set_and_the_answer_it_names`, named in the
list below, reads the record the run left behind. That is what makes the run falsifiable: the
document the run wrote is the input, and a rule over it can be shown to report a run that did not
agree with the set.

A record line is seven parts split at `|`: the client, the order the request arrived at, the call as
the recorded set names it, the method, the answer the port gave, the key names the answer carried in
the order the answer wrote them, and the field names the request carried, read as the transport
chooses which side it reads, the urlencoded half running only for the methods the reference reads a
body form for, which is the guard `FeverForm.readsBodyHalf` pins. The answer is written as the run
saw it: the name the dispatch case answered on when the port wrote a document of this path, and the
status when it wrote something else. The shape answer is read against the matrix row; the status is
read against the handler the route file gives the path, through the shapes its own branches write
and the status each shape writes, so a record line carrying a status this handler has no branch for
is a finding. The half reads only the paths it can name a handler for: a row whose answer is the
catch-all or a dispatch case has no handler, and the login route writes no handler call, so those
paths read nothing here. A shape that writes no error status, `text` or `json`, has no pair in the
pin, so it adds nothing to the statuses a handler answers, and a record line carrying `status 200`
is read as a finding because no pair names the status the text shape writes. The record carries no
value, so the credential pair appears as the name the redaction names for it.

The order is read as the order column, not as the position of the line, because the line is written
when the response is complete and the client had more than one connection open at once, which the
first pass shows: the order column reads groups, feeds, unread, saved while the lines the observer
wrote came in as groups, unread, saved, feeds. It is read as first appearances, because the client
reached the same call more than once. The call name is read from the path the client sent to, and
the mark branch comes from the merged form, which is where the dispatch takes it.

What the run half reads as guards, and what each guard can fail on, is named in its header. The run
half is not in CI, so it is checked here by `bash -n` and by its guards seen to fail on the value
each names: the record path, by a path outside the record directory the check half reads; the
client, by a name the matrix has no row for; the host, by an address the machine does not answer on,
read against the address the machine's own default route selects; the two ports, by naming the same
port twice, and by a port the machine already holds, seen by holding the observer port with a
listener and then the served port; the base, by the port the observer forwards to instead of its
own, and by a path the set does not name for the client, seen for FeedFlow, whose set reads the
Google Reader path while the base carries the Fever prefix, and by the form the set names for how
this client builds the prefix, seen for the clients whose sets name that they append the prefix
itself, where a base carrying the prefix reaches the port with it twice — which is also what the
default base the run builds did before the read followed that form, so the default now names the
port alone for those clients and the prefix for the client that sends the base as the whole prefix;
for NetNewsWire this half was seen red on the head before its set named the form, on the base its
own source needs, which carries only host and port because every call appends the endpoint path to
the base it is given;
the version, by a version the file the run reads does not write, which is the half that only exists
on this machine; the pair row, by an empty name the command's rule refuses before the storage layer,
seen on both paths through the column each one names; the entry rows, by the value 2 against the one
row the pass wrote, and by a url the run wrote no row for; and the record being empty, by an empty
record. The nine guards are twelve read sites, one failure message each: six of them read one value,
the ports item reads three, the base reads three halves at two sites, and the entry guard reads two
halves at one site. The usage block names thirteen of the fourteen halves the guards read, one line
each; the half it cannot name is the observer port the machine already holds, which is seen by
holding the port with a listener, while the served-port half has a line. The three guards that read
what the run itself wrote — the pair row, the entry rows, and the record being empty — fail only on
a run, and the guards that read the machine fail only on a machine. The guards that read a value the
run declares run before the record is written, so a guard that fires leaves the committed record
alone, which is what kept it byte-identical through the ports demos; the guards that read what the
run wrote run at the end, and their demos were run in a copy of the tree, which is what kept the
committed record byte-identical there too. A stand-in client, not one of the five the matrix names,
was sent to the observer in that copy to show that these halves read a record a run wrote rather
than a record the round crafts: writing its record in the copy's record directory, the rule read it
for the client its lines named and reported nothing where the stand-in agreed with the path and the
names it reads, and reported the answers it did not agree with. The check half then reads the record
the run wrote, not the processes.

The host guard is what the second run reads the machine for: the client was a phone on the local
network, so the run declared the address the machine's own default route selects rather than
loopback, and the phone reached the observer through it. A firewall rule on this machine allows the
local network to the observer port, which is a half no guard reads: a machine that does not answer
on the port the run declares is a guard failure, while a machine that answers on the port and drops
the packets from another device is not something a guard can see. The third run showed the same half
on the port the run serves its feed page on: the record carries no line for a page fetch at all,
because the app's fetch of the page does not pass through the observer, which writes a line for
every request it forwards, so no line can show a packet the firewall dropped. What the record does
show is the add call arriving after the port was opened to the local network, which is the run half
reading the address its own guard names.

The entry guard is what the second run showed as a rule over what a run wrote rather than over
what the run half itself wrote: the run left the feed row to the call the set names, so the row
the guard reads was written by the client's own add call, and the entry rows the guard read can
only have come from the pass the cadence loop makes during the window, the run half writing none
itself. For a client whose set names no call that can write a row, the run half writes the row
itself, which is the half the run half names. On the Reeder Classic walk the row the guard reads
is the run's own: the walk database puts it before the first request arrived, so the walk cannot
show which write made it. The same
rule is what the pin in `ServeProcessTests` reads as the request the child makes for the feed it
seeds, and the seed that pin writes is a command that fetches nothing.

## The rules the comparator reads

- `sets_name_the_source_and_a_set_read_from_docs_records_no_calls`
- `sets_are_redacted`
- `matrix_names_every_call_and_the_classes_agree_with_the_manifest`
- `matrix_classes_are_read_by_the_matrix_and_parity_classes_have_a_row`
- `the_output_check_class_names_an_endpoint_the_reference_applies_the_check_on`
- `a_gr_call_reaches_a_route_the_port_registers_or_the_catch_all`
- `the_reference_answer_names_a_route_the_reference_registers`
- `the_fever_names_are_read_from_the_dispatch_switch`
- `the_half_with_no_routes_here_is_named_as_partial`
- `the_recorded_sequence_is_the_set_the_source_declares`
- `the_login_record_is_first_and_the_token_precedes_every_call_that_needs_it`
- `the_token_half_is_the_half_the_read_reads`
- `the_stream_forms_are_the_forms_the_reference_reads`
- `counts_match_the_records_they_report`
- `every_recorded_call_is_named_as_replayed_or_with_a_reason`
- `performance_names_which_numbers_were_measured_here`
- `the_matrix_names_every_rule_and_what_it_cannot_show`
- `the_name_a_client_acts_on_is_the_name_the_builder_writes`
- `the_run_record_agrees_with_the_set_and_the_answer_it_names`

The record files are read as data, not as prose: each line is a record with the parts `replay.py`
splits at `|`. For the rule that reads the replay records as its input, a file with no record lines
reports nothing, and the rule that looks a recorded call up in the manifest cannot read an empty
one, so no probe is an emptied file: each probe changes the parsed data in memory, and the round
hashes every file the check half reads before and after, so a craft that reached a file is reported.

## The classes this matrix reads

A class is the rule the comparator reads for a row, and the `Read by` column names which half reads
it: a class marked `docs/parity.md` is read against the tolerance table there, so a difference in it
is covered by a row that already exists; a class marked `client matrix` is read only by the rule
this document names, and that rule reports what the data says rather than what the table expects.

| Class | Read by | State |
| --- | --- | --- |
| login_shape | client matrix | matrix rule |
| token_transport | client matrix | matrix rule |
| output_check | client matrix | matrix rule |
| merged_form_read | client matrix | matrix rule |
| guard_wording | client matrix | matrix rule |
| error_wording | client matrix | matrix rule |
| unauthenticated_shape | client matrix | matrix rule |
| item_id_forms | client matrix | matrix rule |
| stream_forms | client matrix | matrix rule |
| dispatch_names | client matrix | matrix rule |
| subpath_answer | client matrix | matrix rule |
| minimal_scan | client matrix | matrix rule |
| no_route_here | client matrix | matrix rule |
| client_guard | client matrix | matrix rule |
| closed_source | client matrix | matrix rule |
| page_size | client matrix | matrix rule |
| empty_lists | docs/parity.md | accepted |

## The matrix

| Client | Call | Method | The reference reads | This port answers | Replayed here | Class |
| --- | --- | --- | --- | --- | --- | --- |
| NetNewsWire | accounts/ClientLogin | POST | POST /accounts/ClientLogin | POST /accounts/ClientLogin | yes | login_shape |
| NetNewsWire | reader/api/0/token | GET | GET /reader/api/0/token | GET /reader/api/0/token | yes | token_transport |
| NetNewsWire | reader/api/0/tag/list | GET | GET /reader/api/0/tag/list | GET /reader/api/0/tag/list | yes | output_check |
| NetNewsWire | reader/api/0/rename-tag | POST | POST /reader/api/0/rename-tag | POST /reader/api/0/rename-tag | yes | error_wording |
| NetNewsWire | reader/api/0/disable-tag | POST | POST /reader/api/0/disable-tag | POST /reader/api/0/disable-tag | yes | merged_form_read |
| NetNewsWire | reader/api/0/subscription/list | GET | GET /reader/api/0/subscription/list | GET /reader/api/0/subscription/list | yes | none |
| NetNewsWire | reader/api/0/subscription/edit | POST | POST /reader/api/0/subscription/edit | POST /reader/api/0/subscription/edit | yes | stream_forms |
| NetNewsWire | reader/api/0/subscription/quickadd | POST | POST /reader/api/0/subscription/quickadd | POST /reader/api/0/subscription/quickadd | yes | minimal_scan |
| NetNewsWire | reader/api/0/stream/items/contents | POST | POST /reader/api/0/stream/items/contents | POST /reader/api/0/stream/items/contents | yes | item_id_forms |
| NetNewsWire | reader/api/0/stream/items/ids | GET | GET /reader/api/0/stream/items/ids | GET /reader/api/0/stream/items/ids | yes | page_size |
| NetNewsWire | reader/api/0/edit-tag | POST | POST /reader/api/0/edit-tag | POST /reader/api/0/edit-tag | yes | item_id_forms |
| FeedFlow | accounts/ClientLogin | POST | POST /accounts/ClientLogin | POST /accounts/ClientLogin | yes | login_shape |
| FeedFlow | reader/api/0/subscription/list | GET | GET /reader/api/0/subscription/list | GET /reader/api/0/subscription/list | yes | none |
| FeedFlow | reader/api/0/stream/items/ids | GET | GET /reader/api/0/stream/items/ids | GET /reader/api/0/stream/items/ids | yes | page_size |
| FeedFlow | reader/api/0/stream/contents | GET | catch-all | catch-all | yes | subpath_answer |
| FeedFlow | reader/api/0/token | GET | GET /reader/api/0/token | GET /reader/api/0/token | yes | token_transport |
| FeedFlow | reader/api/0/stream/items/contents | POST | POST /reader/api/0/stream/items/contents | POST /reader/api/0/stream/items/contents | yes | none |
| FeedFlow | reader/api/0/edit-tag | POST | POST /reader/api/0/edit-tag | POST /reader/api/0/edit-tag | yes | merged_form_read |
| FeedFlow | reader/api/0/rename-tag | POST | POST /reader/api/0/rename-tag | POST /reader/api/0/rename-tag | yes | error_wording |
| FeedFlow | reader/api/0/edit-tag#disable-tag | POST | POST /reader/api/0/edit-tag | POST /reader/api/0/edit-tag | yes | guard_wording |
| FeedFlow | reader/api/0/subscription/edit | POST | POST /reader/api/0/subscription/edit | POST /reader/api/0/subscription/edit | yes | merged_form_read |
| FeedFlow | reader/api/0/subscription/quickadd | POST | POST /reader/api/0/subscription/quickadd | POST /reader/api/0/subscription/quickadd | yes | minimal_scan |
| NewsFlash | fever/?api | POST | dispatch: default | dispatch: default | yes | unauthenticated_shape |
| NewsFlash | fever/groups | POST | dispatch: groups | dispatch: groups | yes | empty_lists |
| NewsFlash | fever/feeds | POST | dispatch: feeds | dispatch: feeds | yes | none |
| NewsFlash | fever/favicons | POST | dispatch: favicons | dispatch: favicons | yes | none |
| NewsFlash | fever/items | POST | dispatch: items | dispatch: items | yes | page_size |
| NewsFlash | fever/items/since_id | POST | dispatch: items | dispatch: items | yes | dispatch_names |
| NewsFlash | fever/items/max_id | POST | dispatch: items | dispatch: items | yes | dispatch_names |
| NewsFlash | fever/items/with_ids | POST | dispatch: items | dispatch: items | no: the guard is this client's own bound on the list size, which this run reached below | client_guard |
| NewsFlash | fever/links | POST | dispatch: default | dispatch: default | yes | dispatch_names |
| NewsFlash | fever/unread_item_ids | POST | dispatch: unread_item_ids | dispatch: unread_item_ids | yes | none |
| NewsFlash | fever/saved_item_ids | POST | dispatch: saved_item_ids | dispatch: saved_item_ids | yes | none |
| NewsFlash | fever/mark/item | POST | dispatch: mark=item | dispatch: mark=item | yes | merged_form_read |
| NewsFlash | fever/mark/feed | POST | dispatch: mark=feed | dispatch: mark=feed | yes | merged_form_read |
| NewsFlash | fever/mark/group | POST | dispatch: mark=group | dispatch: mark=group | yes | merged_form_read |
| lire | no-call-recorded | — | not read here | no route here | no: no call recorded for a closed-source client | no_route_here |
| Capy Reader | no-call-recorded | — | not read here | no route here | no: no call recorded for the path this half reads no rules for | no_route_here |
| Reeder Classic | no-call-recorded | — | not read here | no route here | no: no call recorded for a closed-source client | closed_source |

## The counts the matrix reports

| Client | Calls recorded | Reaches a route or a dispatch case | Reaches the catch-all or the default branch | Replayed here |
| --- | --- | --- | --- | --- |
| NetNewsWire | 11 | 11 | 0 | 11 |
| FeedFlow | 11 | 10 | 1 | 11 |
| NewsFlash | 14 | 12 | 2 | 13 |
| lire | 0 | 0 | 0 | 0 |
| Capy Reader | 0 | 0 | 0 | 0 |
| Reeder Classic | 0 | 0 | 0 | 0 |
| all clients | 36 | 33 | 3 | 35 |

## What this matrix cannot show

Each line below is one report item line, read as one whole string by the check half, so it is exempt
from the width rule.

- the clients that have not been run against this port here, which is the half the manual matrix keeps open for them
- the record a walk for a client whose set records no calls leaves, which the check half reads as a finding, so that walk is evidence outside the repository rather than data it reads
- the calling set of a client whose source cannot be read, which is named per client as read from its documentation
- the calls of a client on the path this port registers no route for, which this half records no calls for, because the rules that read calls read the two paths that are registered here
- the order a client reaches its calls at, which the run record carries for the three clients whose records the check half reads as data and the source declares for the others
- the values the calls carry, which are redacted, so no row can show a value
- the app-level choice of which calls a library-based client makes, which is read at the library boundary for the clients that have not been run here
- the guard a client applies before it sends, read as the bound on the list size, which no record line can show firing
- the side of the bound the guard applies, which the record carries as names and not as values
- the answer a record line can carry for a call whose guard the client applies before it sends, read as the status the handler answers for the path rather than as the guard's answer, which no record line can show firing
- the number this read names for each status name, which the pin asserts as a name and no test asserts as a number, so the pair (shape, status) is data while the number is the read's own vocabulary
- the part of a calling set a run did not reach, which the record carries no line for and the paragraph for that client names as the halves this run did not walk
- the token half of a client that sends the stored value as the token, which the read compares as a token
- the numbers of another machine, which the performance half records as measurements taken here or names as not measured here
- the query latency at the 100k corpus, which is gated
- the version of a client run on a device, which this machine has no app metadata to read the value against

## Client by client

### NetNewsWire — Google Reader API

Read from `Account/Sources/Account/ReaderAPI/ReaderAPICaller.swift` at
`ab5421f533a60b9d2f8efe6254cafda46016d41a`. 11 calls; the two endpoints the reference registers that
this client's source does not send are `user-info` and `mark-all-as-read`. It sends the login
without `output`, so the answer it parses is the plain-text one; the write half carries `T` in the
body and the read half carries the token in the header. The item ids it sends are two different
forms: the contents call writes the hex without padding and the state call writes it padded. The
`%016x` scan is what the read for `stream/items/contents` runs, so the unpadded form is reported
there and the padded form reaches the write on `edit-tag` as the field-width rule reads it.

Setup: Settings → Accounts → add an account of type Self-hosted → FreshRSS — the UI has no "Reader
API compatible" type, and FreshRSS is the type whose variant shares the base handling the checklist
reads — with the Google Reader integration credentials, not the account password. The value this
client puts in the header is the answer the login gave, so the credentials are the integration pair.
The address the app is given carries only host and port, because its own source builds the prefix by
appending the endpoint path to the base it is given, which is the form the set names for it.

Manual checklist, walked here by the run on the Mac: log in; list the subscriptions; list the tags;
add a feed from the client; rename a folder; delete a folder; sync a page of item ids and their
contents; mark one item read and un-read; star and un-star; rename a subscription; remove a
subscription. Every call the set names arrived, and the walk reached one add and one remove: the
record carries the add action on one state-write line and the removed name on the other, so which of
the two state items each write carried is a half the record cannot show.

The calls this run showed for NetNewsWire, in the order the record says they arrived:
`accounts/ClientLogin`, `reader/api/0/tag/list`, `reader/api/0/subscription/list`,
`reader/api/0/stream/items/ids`, `reader/api/0/token`, `reader/api/0/subscription/quickadd`,
`reader/api/0/subscription/edit`, `reader/api/0/stream/items/contents`,
`reader/api/0/rename-tag`, `reader/api/0/disable-tag`, `reader/api/0/edit-tag`.

The record carries 56 lines for this run: the login, five tag lists, seven subscription lists,
twenty-five stream pages, the token, two adds, seven subscription edits, two item-content reads, two
folder renames, two folder deletes, and two state writes. Creating a folder sends nothing: the
delegate makes the folder in its own state, so the folder exists on the port only through the
subscription edit that put the feed in it, which is the half the record reads as the destination,
the action and the stream together.

The two folder-delete lines read as the two halves of the same guard: the input that left a row
answered the status the handler writes for the branch that keeps rows, which the record carries as
the route name and which the pin asserts as `.ok`, the `OK` body being asserted for another input on
the same path, and the input that left nothing answered the status the handler gives for that rule,
500, carried through the shape the error answer writes. This is the case the write-handler pin
asserts for the wording, and here it arrived from the app's own delete-folder step, which named the
folder that was the only category row for the pair.

The remove-subscription half deletes the row the entry guard reads, so the walk had to add the feed
again after it: the row the guard read was the one the second add call wrote, and the entry row the
one the pass the cadence loop made after it wrote.

The version the run declared is a report item, not a value. The device's app reports 7.2.1, and the
run here declares the placeholder, because this machine has no app metadata for a client run on a
device; the half reads neither, so both are named rather than compared.

### FeedFlow — Google Reader API

Read from
`feedSync/greader/src/commonMain/kotlin/com/prof18/feedflow/feedsync/greader/data/GReaderClient.kt`
at `75d1c0eea22aac271948b66e8c543287ea1bd4aa`. 11 calls. Three facts come from its own source rather
than from a run: the header is built from the stored value the user typed, not from the login
answer; the folder delete sends to `edit-tag` with `s` and `T` and no add or remove pair, so it
reaches the guard's wording, and the path its own resource table declares for that call is not the
path its own call uses; and the item read sends to `reader/api/0/stream/contents`, which the
reference has no route for, so the answer is the catch-all on both sides — this client's own decoder
takes `[]` as the empty item list, so it reads nothing rather than failing. It acts on the response
name `X-Reader-Google-Bad-Token`, which is the name the port writes for an unauthenticated request
on this path, and it re-fetches the token when that name is true. `n` is 15000, which is above the
clamp this port reads.

Setup: Settings → Feeds & accounts → Accounts → the sync account for Miniflux. The password field is
the value this client sends as the token, so for this port it has to hold the token the login answer
carries, not the integration password — unless the login runs first, which is what this run showed:
the field held the integration pair, the login ran when the account was connected, and the login
path writes its answer into the stored value the header is built from, so after that the header
carries the token.

Manual checklist, walked here by the run on a phone: log in; list subscriptions and categories; read
one stream page and the item contents the ids that page gave were read for; add a feed, and the
category write the add made on the same call the move half uses; open an item, which is the call the
walk reached by bookmarking it; mark items read; rename a category through the drawer's rename,
which is the call the set names for it. It did not walk delete a category, so the half that row
names is not shown by this run.

The calls this run showed for FeedFlow, in the order the record says they arrived:
`accounts/ClientLogin`, `reader/api/0/subscription/list`, `reader/api/0/stream/items/ids`,
`reader/api/0/token`, `reader/api/0/subscription/quickadd`, `reader/api/0/subscription/edit`,
`reader/api/0/stream/items/contents`, `reader/api/0/edit-tag`, `reader/api/0/rename-tag`.

The record carries 25 lines for this run: the login, four subscription lists, twelve stream pages,
the token, the add, the category write, the item-content read, three `edit-tag` lines, and the
rename. The login is a record line here, which the Fever run could not show: this client sends the
login when the account is connected, so it arrived while the observer was recording. It is the only
line that carries the pair, as the two field names the login reads, and every line after it carries
the token field name the redaction writes as `T`. The add is the half the Fever set has no call for,
and the feed row the entry guard reads was written by the client's own add call rather than by this
port's command; the row the entry guard read was the one the pass the cadence loop made during the
window wrote. The version the run declared is a report item, not a value: for a client run on a
device this machine has no app metadata to read the version against, so the run declares what the
app reports for itself rather than a value a read here answered. The device's own package manager
answers 1.20.0 for the app, while the run declared 6.0.2, which is the version the source the set
is read from carries; the half reads neither, so both are named rather than compared.

Two of the three `edit-tag` lines carry the answer the matrix row names, with an empty key column,
which is the shape this handler writes for a write that reads nothing; the third carries a status,
with the field names `a` and `output` and no `i`, so the read the handler makes for `i` failed and
the handler answered it with 400, which is the status the status half reads this path as answering a
read error with. The app action that sent that request was the mark-items-read step of the
checklist, which the record shows only as the field names the request carried. The item-content read
is the read this client makes for the ids a page gives it, and it arrived as the sync the app made
after the pass had written the entry row. The rename is the call the set names for
`reader/api/0/rename-tag`, and it arrived from the drawer's rename, which is the half the first run
on this device did not walk.

The two calls the set names that this run did not reach are `reader/api/0/stream/contents` and the
folder-delete half the set names as `reader/api/0/edit-tag#disable-tag`. The record carries no line
for either: the first is the path this client's own item read sends to, which the reference has no
route for, so the catch-all answer that row reports is not a half this run showed; the second is the
call whose guard the client applies before it sends, which no record line can show firing.
The run cannot show the page-size half the row names either, because the record carries names and
not values: the 15000 the set names is read from the client's source, and no record line carries a
page size.

### NewsFlash — Fever API

Read from `news-flash/fever_api` `src/lib.rs` at `0.6.0`, the client library the app depends on:
the set is the library's own, and the app's choice of which of these calls it makes is read at the
library boundary for the clients this half reads no record data for. 14 calls. Every name the
switch has a case for is called, and two answers come from the branch it has no case for: the base
document the request with no name gets, and `links`, which is a name the switch does not have. The
key reaches the merged form as a multipart part, which is the read PR #61 pins. The item page is
the fixed 50, and the `with_ids` guard is the bound on the list size the client applies before it
sends: the record carries a line for the call, which is the half the bound does not cover, and
both the bound firing and the size the client sent are report items. The `HEAD` reachability check
PR #61 sized to is not attributed to this client here: the library's own source sends POST only.

Setup: Settings → Sync → the Fever service, with the integration name and password; the key is the
digest the library builds from the pair. The app sends to the base as it is typed, so the base has
to name the path this port registers, which is what the run showed at login: a base without the path
reached the root and answered the 404 Vapor writes for a path it does not register.

Manual checklist, walked here by the run: log in; read the base document; read groups, feeds,
favicons, unread and saved ids; read a page of items and the next page through `since_id`; mark one
item read, un-read and saved; mark a feed read before a time; mark a group read; check the value for
`id = 0` on the group branch, which is the user-wide half.

The calls this run showed for NewsFlash, in the order the record says they arrived: `fever/groups`,
`fever/feeds`, `fever/unread_item_ids`, `fever/saved_item_ids`, `fever/items`,
`fever/items/with_ids`, `fever/mark/item`, `fever/mark/feed`.

The record carries four lines for `fever/mark/item` and one for `fever/mark/feed`, which are the
mark calls this run showed. It carries names and not values, so the four marks cannot be told apart
as read, un-read or saved, and the item they were for is not shown either: those are halves a person
walked, not halves a record line can show. The feed mark line is the one mark line with a name a
value reaches as, `before` being the name the time the app sent arrives as. The record has no line
for `fever/favicons`, `fever/links`, `fever/items/since_id`, `fever/items/max_id` or
`fever/mark/group`, which are the checklist halves this run did not walk. The login is not a record
line: it happened before the run started, when the app saved the account, and the first line the
record carries is the first call of the first sync pass. The record carries 26 lines over four sync
passes, which is the document the rule reads as data.

### lire — the Fever API and the Miniflux REST API

Read from the project's documentation, because the app is closed source: it uses both the Fever
integration and the Miniflux REST API with an API key. The calling set cannot be read here, so no
call is recorded for it. What the matrix can state is the half: the Fever half reaches this port,
and the REST half does not — this port registers no route for `/v1` at all, so the sync the
documentation describes is partial here, and the pin that shows it reads Vapor's 404 for that
prefix.

Setup: Settings → Integrations → the Fever pair, and an API key; in the app, the URL without `/v1`
or `/fever`. Manual checklist, not executed here: the Fever half as above, and the REST half
recorded as not served here. The client is paid, so this machine has no run for it; the free client
below is the one this half can walk for the same half.

### Capy Reader — the Miniflux REST API

Read from the project's documentation, which names Miniflux as the sync service this app uses. Its
source is open, so the endpoints could be read from it, and they are not recorded here: the rules
that read calls read the two paths this port registers, and this half is the third, so no rule here
has anything to read a call on it against. The half is named as the whole half rather than as
partial, which is what the rule that reads the shape the set names for its halves checks: the set
names one half, so it names the shape as one.

Setup: the app's account screen asks for the URL and for the API key, or for the pair, and the base
the run prints carries the prefix, because the half names no form, so the run half reads the base as
the whole prefix. Manual checklist, not executed here: log in, read the feeds and the entries, mark
one item read and un-read, star one item, save one item, and add a feed through the call the app
makes for it.

Nothing is committed for this client beyond the set: the set records no calls, so a record file for
it is a finding rather than data, and a walk here leaves its record as evidence outside the
repository, as the walk on Reeder Classic did. The Android phone in the same network is the device
this client can be walked on.

### Reeder Classic — Fever API

Read from the project's documentation, which names it as Fever-compatible; the client is closed
source, so this is the whole fact the matrix can state for it. The Fever half of the checklist was
walked here on the phone through the run half, with the pair the run declares; the window and the
cadence are values the person gave the run, not values the record can show. The record that walk
wrote is held outside the repository as evidence, not committed as data: the set for this client
records no calls, so the check half reads a record file for it as a finding, and the round read it
as one while the file sat in the record directory.

Setup: the app's Fever form asks for the address and for the pair, and the base the run prints
names the prefix the set names for this client, which is what the guard on the base reads. What the
record names as the path is the name the observer's read gives it, not the path as it arrived: the
base document reads as `fever/?api` because the read has no name for the query key that arrived,
and the log shows those requests arriving as `GET /fever/?refresh`; the mark lines read as
`fever/mark/item` from the branch the merged form gives, and the log shows them arriving as `POST
/fever/?api` with the branch name in the body.

Manual checklist, walked here on the device: log in; read the base document; read groups, feeds,
unread and saved ids; read a page of items and the next page through `since_id`; mark one item
read, un-read and saved. Not walked here: `fever/favicons`, `fever/links`, marking a feed read
before a time, and marking a group read, which this walk did not reach: the person walking saw
only the folder named All holding the one feed, which is the default category the port writes for
a new account, and the record has no line for the group call. The value for `id = 0` on that
branch is a value, so no line can show it either.

What the walk showed, as its lines name it, in the order they arrived: line 1 is POST with the key
as the name the field carries, answered by the default branch, and it is the first request that
reached the observer; the pair row was written by the run's own commands before the observer
started, so this line names the app's first request rather than a login the app made before it.
Four sync passes carried the base document, `fever/feeds`, `fever/groups`, `fever/unread_item_ids`
and `fever/saved_item_ids`; `fever/items` arrived on the first pass, `fever/items/since_id` on
each of the four, and `fever/items/with_ids` on the last two. The log names five passes, so the
record stops before the last one, and it names three `with_ids` requests, all arriving with an
empty list, where the record carries two lines. Seven `fever/mark/item` lines arrived; the
checklist names three steps, read, un-read and saved, so three of the seven are the steps the walk
named and four are left by them, with nothing in either file showing which side sent them; the
states are values, so the seven lines cannot be told apart, and no line names the item they were
for. The evidence holds 35 record lines against 42 requests the log names, so seven forwarded
requests have no line, which the two files cannot explain: the rule that would show it is the
observer's own, one line per request it forwards.

The order named in this section is the order the record carries, and the order half reads records
for the three clients whose records it reads as data, so the order here is what the walk left
rather than what the rule can read for this client.

The feed the run wrote carries an empty title, which is what the person walking saw as an empty
name in the app: the write that creates the row writes an empty title, and the write that records
a successful fetch leaves the title as the row held it, so the fetch that ran here, which
succeeded, did not fill it. The comment on the row names the title as empty until the first
successful fetch fills it, which is the half this walk contradicts. A record line carries names
and not values, so an app display is not something a line can show, and the same empty name on the
NewsFlash walk is what the person who walked it reports rather than what that record shows.

The two end halves of the run were not printed: the window's process ended before its window
closed, so nothing after the sleep ran. Read against the walk's own leftovers, the record is non-
empty, and the walk's database holds the one entry row the run declares for the feed the run
wrote, which the run's own pass wrote before the first request arrived.

## What the replay half shows

`Tests/RivuletIntegrationTests/ClientSequenceReplayTests` replays the recorded calls against the
served app over a real socket, and reads the calling sets as data rather than restating them. 9 pins
and 10 probes: the recorded order for each set, which recorded call reaches a registered route and
which reaches the catch-all answer, the two forms of the same item id the same client sends, the
page size above the clamp against the page size below it, the token half per method, the guard the
merged form answers for the call with no add and no remove pair, the name the dispatch switch has no
case for, and the prefix this port registers no route for. What no patch can show is named in the
suite header rather than asserted: the `>50` guard, which is the client's own and fires before the
request is sent, and the values the records carry, which are placeholders.

The two halves read the same copy of the data: the pins read the calling sets through
`Bundle.module`, and the check half reads the same files from disk, so a pin that reads the recorded
order and the check half that reads the same order cannot disagree by restating it twice. That is
why the sets live inside the integration test target.
