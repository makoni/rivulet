# Client matrix

This is the client matrix of stage 7. It records the calling sets of the clients that matter for
acceptance, and what the port answers for each of them.

Every set here is read from a source, not captured. A calling set is one of two things, and the
document names which one it is for every set: a client's own source at a named commit, or the
project's documentation when the client is closed source. No set is a capture: **no client has been
run against this port here**, because this machine has no device to run one on. The manual matrix
exit criterion of `docs/plan/stage-7-acceptance.md` is therefore still open, and the checklists
below are the checks to run when a client can be run.

The halves are separated the way the soak's and the parity harness's are. `Tools/clients/replay.py`
is the check half: it reads the calling sets, the record files, this document, the port's own source
and the field the timed pin's print writes as data, with the parsers it reads them with in
`Tools/clients/parsers.py` so the rules stay the readable part of the file. `Tools/clients/probes.py` is the probe half: it crafts one input per
rule that violates it and asserts that the rule reports it alone; the baseline reports nothing, so
each probe is single-firing — 17 rules, 18 crafted inputs and the baseline, so 19 cases, the
performance rule having one for each of the two branches it reads.

The width rule does not reach a table row, a manifest record line or a report item line, which are
each read as one whole string. The record lines and the item lines here are exempt for that reason.

## The rules the comparator reads

- `sets_name_the_source_and_a_set_read_from_docs_records_no_calls`
- `sets_are_redacted`
- `matrix_names_every_call_and_the_classes_agree_with_the_manifest`
- `matrix_classes_are_read_by_the_matrix_and_parity_classes_have_a_row`
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
- `the_name_a_client_acts_on_is_the_name_the_port_writes`

The record files are read as data, not as prose: each line is a record with the parts `replay.py`
splits at `|`. For the rule that reads the replay records as its input, a file with no record lines
reports nothing, and the rule that looks a recorded call up in the manifest cannot read an empty
one, so no probe is an emptied file: each probe changes the parsed data in memory, and the round
hashes every file the check half reads before and after, so a craft that reached a file is reported.

## The classes this matrix reads

A class is a rule the comparator reads. A class marked `docs/parity.md` is read against the
tolerance table, so a difference in it is covered by a row that already exists; a class marked
`client matrix` is read only here, and the rule that reads it reports whatever the data says.

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
| FeedFlow | reader/api/0/edit-tag | POST | POST /reader/api/0/edit-tag | POST /reader/api/0/edit-tag | yes | output_check |
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
| NewsFlash | fever/items/with_ids | POST | dispatch: items | dispatch: items | no: the guard is this client's own, applied before the request is sent | client_guard |
| NewsFlash | fever/links | POST | dispatch: default | dispatch: default | yes | dispatch_names |
| NewsFlash | fever/unread_item_ids | POST | dispatch: unread_item_ids | dispatch: unread_item_ids | yes | none |
| NewsFlash | fever/saved_item_ids | POST | dispatch: saved_item_ids | dispatch: saved_item_ids | yes | none |
| NewsFlash | fever/mark/item | POST | dispatch: mark=item | dispatch: mark=item | yes | merged_form_read |
| NewsFlash | fever/mark/feed | POST | dispatch: mark=feed | dispatch: mark=feed | yes | merged_form_read |
| NewsFlash | fever/mark/group | POST | dispatch: mark=group | dispatch: mark=group | yes | merged_form_read |
| lire | no-call-recorded | — | not read here | no route here | no: no call recorded for a closed-source client | no_route_here |
| Reeder Classic | no-call-recorded | — | not read here | no route here | no: no call recorded for a closed-source client | closed_source |

## The counts the matrix reports

| Client | Calls recorded | Reaches a route or a dispatch case | Reaches the catch-all or the default branch | Replayed here |
| --- | --- | --- | --- | --- |
| NetNewsWire | 11 | 11 | 0 | 11 |
| FeedFlow | 11 | 10 | 1 | 11 |
| NewsFlash | 14 | 12 | 2 | 13 |
| lire | 0 | 0 | 0 | 0 |
| Reeder Classic | 0 | 0 | 0 | 0 |
| all clients | 36 | 33 | 3 | 35 |

## What this matrix cannot show

Each line below is one report item line, read as one whole string by the check half, so it is exempt
from the width rule.

- that no client has been run against this port here, which is the half the manual matrix keeps open
- the calling set of a client whose source cannot be read, which is named per client as read from its documentation
- the order a client reaches its calls at on a device, which this matrix reads from the source rather than from a run
- the values the calls carry, which are redacted, so no row can show a value
- the app-level choice of which calls a library-based client makes, which is read at the library boundary
- the guard a client applies before it sends, which no input reaches
- the token half of a client that sends the stored value as the token, which the read compares as a token
- the numbers of another machine, which the performance half records as measurements taken here or names as not measured here
- the query latency at the 100k corpus, which is gated

## Client by client

### NetNewsWire — Google Reader API

Read from `Account/Sources/Account/ReaderAPI/ReaderAPICaller.swift` at
`ab5421f533a60b9d2f8efe6254cafda46016d41a`. 11 calls; the two endpoints the reference registers that
this client's source does not send are `user-info` and `mark-all-as-read`. It sends the login
without `output`, so the answer it parses is the plain-text one; the write half carries `T` in the
body and the read half carries the token in the header. The item ids it sends are two different
forms: the contents call writes the hex without padding and the state call writes it padded, and the
read keeps what it read.

Setup: Settings → Accounts → add an account of type "Reader API compatible", with the Google Reader
integration credentials, not the account password. The value this client puts in the header is the
answer the login gave, so the credentials are the integration pair.

Manual checklist, not executed here: log in; list the subscriptions; list the tags; add a feed from
the client; rename a folder; delete a folder; sync a page of item ids and their contents; mark one
item read and un-read; star and un-star; rename a subscription; remove a subscription.

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
carries, not the integration password.

Manual checklist, not executed here: log in; list subscriptions and categories; read one stream
page; add a feed; move a feed between categories; rename a category; delete a category; mark items
read; star an item. Record what the item list shows: on this port the item read answers the
catch-all, so the list is empty by the reference's own rule.

### NewsFlash — Fever API

Read from `news-flash/fever_api` `src/lib.rs` at `0.6.0`, the client library the app depends on: the
set is the library's own, and the app's choice of which of these calls it makes is not read here. 14
calls. Every name the switch has a case for is called, and two answers come from the branch it has
no case for: the base document the request with no name gets, and `links`, which is a name the
switch does not have. The key reaches the merged form as a multipart part, which is the read PR #61
pins. The item page is the fixed 50, and the `with_ids` guard — a list above 50 refused before the
request is sent — is the client's own, so no input reaches it. The `HEAD` reachability check PR #61
sized to is not attributed to this client here: the library's own source sends POST only.

Setup: Settings → Sync → the Fever service, with the integration name and password; the key is the
digest the library builds from the pair, and the app takes the base URL without `/fever`.

Manual checklist, not executed here: log in; read the base document; read groups, feeds, favicons,
unread and saved ids; read a page of items and the next page through `since_id`; mark one item read,
un-read and saved; mark a feed read before a time; mark a group read; check the value for `id = 0`
on the group branch, which is the user-wide half.

### lire — the Fever API and the Miniflux REST API

Read from the project's documentation, because the app is closed source: it uses both the Fever
integration and the Miniflux REST API with an API key. The calling set cannot be read here, so no
call is recorded for it. What the matrix can state is the half: the Fever half reaches this port,
and the REST half does not — this port registers no route for `/v1` at all, so the sync the
documentation describes is partial here, and the pin that shows it reads Vapor's 404 for that
prefix.

Setup: Settings → Integrations → the Fever pair, and an API key; in the app, the URL without `/v1`
or `/fever`. Manual checklist, not executed here: the Fever half as above, and the REST half
recorded as not served here.

### Reeder Classic — Fever API

Read from the project's documentation, which names it as Fever-compatible; the client is closed
source, so this is the whole fact the matrix can state for it. Manual checklist, not executed here:
the Fever half as above.

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
