# Deploy runbook (stage 8)

One static binary and one SQLite file. The machine needs no toolchain, no interpreter and no service
beyond what this page names: the artifact is the static musl build `Scripts/build-release.sh`
leaves, and the data is the file `DATABASE_URL` names.

## The environment the runs read

Only `DATABASE_URL` is required; the rest read as their defaults. Every name below is a name the
config parser reads, and a name it does not reads as nothing — so a typo here is not an error the
run reports. `LISTEN_ADDR` is read as `host:port`, so the port comes from the value as well and the
default is the loopback listener `127.0.0.1:8080`; a value with no port is reported as an invalid
value, not read as the default.

```sh
export DATABASE_URL=/var/lib/rivulet/rivulet.db
export LISTEN_ADDR=0.0.0.0:8080
export BASE_URL=https://reader.example.com
export RUN_MIGRATIONS=1
export POLLING_FREQUENCY=60
export POLLING_PARSING_ERROR_LIMIT=3
export LOG_LEVEL=info
export LOG_FORMAT=text
export FETCHER_ALLOW_PRIVATE_NETWORKS=0
```

The last name is the address policy: on a host that can reach the machine's own addresses it stays
off, and the fetcher refuses a target in a class the policy names. A feed that lives on the host's
own network needs it on, and that is a decision the operator makes for one run rather than a
default.

## Zero to running

```sh
mkdir -p /var/lib/rivulet
rivulet migrate
rivulet create-admin
rivulet integration-credentials
rivulet add https://example.com/feed.xml --user alice
rivulet status --json
rivulet serve
```

`create-admin` and `integration-credentials` read their prompts from the terminal, so this part of
the runbook runs on a console, not from a unit or a pipe: the secure read the dependency uses takes
its values from the terminal device, and on a pipe it answered nothing, which is what the parity run
showed — this port has no terminal guard of its own, so that is what the read does rather than a
rule the port reads. The credential pair the clients log in with is the one
`integration-credentials` writes; `create-admin` writes the account hash alone, so the login answers
401 until the second command has run.

`add` writes the row and fetches nothing, so the first round is the cadence loop's own: the serve
run waits the interval it was built with, reads the batch, and writes the entries. `status --json`
is the minimal contract the reader reads, and the counts it reports are read over every row whatever
its state.

`serve` is the run that keeps running; a deployment names it in a service unit, which is committed
at `deploy/rivulet.service`, and the signal the unit names is the signal the handler has a case for,
which is the clean stop path, answering 0. The port the run answers on is the one the value names,
and the program the unit names is the file the image writes.

## Backups

```sh
rivulet backup /var/backups/rivulet.db
rivulet backup --verify /var/backups/rivulet.db
rivulet vacuum
```

The copy is `VACUUM INTO`: the snapshot at the moment of the run, written as a file of its own that
does not change with the source afterwards. Before the write the run reads the room at the directory
the destination is in, and asks for the bytes the source holds as the filesystem reads them, plus
the bytes the WAL holds, times the factor it uses (2). A destination the run did not create is
reported, not built, and a destination that exists is reported rather than overwritten unless
`--force` names it; the flag does not skip the room read.

`--verify` opens the copy the run wrote through its own connection and reports the problems it
finds, leaving the copy as written. `vacuum` rebuilds the file it already holds, so it reads no
room.

## Restore

There is no restore command: the recipe is the file swap, and it is the reason the backup is a plain
file rather than a database the run can open.

1. Stop the serve run, so nothing writes while the file is replaced.
2. Copy the copy back to the path `DATABASE_URL` names.
3. Run `rivulet migrate`, which answers the migration the schema file declares and writes nothing
when
   the schema is already there.
4. Read the counts back with `rivulet status --json` and compare them with the counts recorded
before
   the swap.

## Durability

The storage wrapper sets synchronous to `NORMAL`, which is the durability this page claims:
committed writes are in the operating system's cache rather than forced to the device per row, so a
device crash can lose the writes of the round that was running. The recovery point is therefore one
round, not one entry, and the round is the batch the tick takes. A host that needs a smaller
recovery point needs a different pragma, which this port does not read from the environment.

WAL is on, and one write transaction is taken per feed refresh. The checkpoint that empties the WAL
runs best-effort at the end of a run, so the bytes a run leaves in the WAL are the interrupted
round's when a stop lands mid-round.

## Time

The schedule is read as whole Unix seconds, and the cadence as minutes. A clock that steps backwards
or forwards by more than the interval moves the schedule for every row: a row whose `next_check_at`
lies in the past is due at the next read, and a row scheduled by a clock that ran ahead is not read
until the clock reaches it. Run the time adjustment incrementally (`chrony`, or `systemd-timesyncd`
with a step threshold below the cadence), and read the clock after the first round rather than
before it.

## Upgrade

Replace the binary with the artifact the release build leaves, then run `rivulet migrate`. Until the
first release the schema is edited in place, so an upgrade that changes the schema is not something
the run can apply to an existing database; take a backup before it, and treat the database as the
unit that changes with the binary.

## Optional external streaming

[Litestream](https://litestream.io) can stream the file to another device. It is named here as a
tool outside this port: no command of the port runs it, and nothing here reads what a stream of it
would contain. The port's own half is the copy `backup` writes, which is a snapshot at a moment
rather than a stream.

## The three artifacts read as data

`deploy/compose.yml`, `deploy/rivulet.service` and `.env.example` are the three artifacts read as
data by `Tools/deploy/deploy_check.py`, which reads the document `Scripts/deploy.sh` leaves behind
rather than a container or a service, and the run's fourth file is `Dockerfile`, read as the line
that names the file the program has to be. The compose file is read as the key set the tool resolves
it as, with each pair read as the tool took it, and the env file read as the values the tool
resolved into the service environment rather than as a key of its own. The unit is read as the
sections it puts its keys in, which is what the tool reads it as, and the example as one
name-and-value pair per line. Comment lines and empty lines are the part no rule reads.

Sixteen rules, read over the document the run left and the committed files it names: the compose as
the tool read it, key by key and pair by pair; the copies the run wrote against the bytes the
committed files have; the subcommand the tool resolves against the names the dispatch registers; the
published port against the port the address the tool resolved names; every name the three files
write against the names the config sources read; each value as the kind of value the source reads
that name as; no value in the example reading as the shape a credential has, read as the marker the
hasher writes and the width the pin names for the hex form the token derivation writes; the data
path as the three files name it; the unit subcommand against the names the dispatch registers; the
program the unit names against the file the image copy line writes; the tool's own lines as data,
the file each names read in the shape the tool prints it in for the kind of finding the line is, and
the key each names in the section the tool read it in; the restart policy the two files name as one
value; the signal the unit names against the signals the handler has a case for; the project name as
the tool resolved it against the name the run declared; the keys the three artifacts write against
the bookkeeping the check half keeps; and the two lists the document carries against what the check
half has. The position the tool prints for a key finding is recorded in the document for the reader
and read by no rule.

Twenty-two cases: 21 crafts plus the baseline, the baseline asserted to report nothing, which is
what makes each craft single-firing. Four rules have more than one craft, because each reads more
than one half: the compose rule has one craft for the key it resolves and one for the pair it takes,
the credential rule one for the marker and one for the width, the tool-lines rule one for the file
shape, one for the section and one for the program, and the report rule one for each of the two
lists it reads. Two crafts reach more than one rule through one patch, which
`Tools/deploy/probes.py` names as `REACHES`: the restart policy and the container subcommand,
because the rule that reads the compose as the tool read it reads the same key each of those crafts
changes. Those two are recorded as the reach rather than asserted as single-firing, and the round
asserts each other craft reports its own rule alone. Two halves of the tool-lines rule are read but
not probed alone, which the header of `probes.py` names: the shape the tool prints for a key
finding, because the committed answer carries only the line about the program.

What the harness cannot show, which the check half names as its report items:

that the run ran at all, because it is on demand and not in CI
the image being built or started, because the run reads the compose as the tool resolves it and never builds
the artifact the Dockerfile names being in the build context, because the run does not build and the tool resolves the name without reading the file
the unit installed and run on a machine, because the tool reads the file as a parse and the only finding it answers is the program path not being on this machine
the signal a stop delivers, because the tool reads the signal the unit names as text, and which signal a stop sends is what the unit answers on a machine that runs it
the values an operator fills in, because the committed example carries placeholders and the file a deployment reads is the gitignored name
the credential pair, which lands through the command the runbook names, not through a name the config reads
the published port being free on the machine, because this run half reads no machine and the rule reads the pair as a value the file writes
the wording of the lines the tools printed, which the rule reads as the file and the value each line names, not as the sentence
the version of each tool the run names, because the run records the line each tool answered for itself and no rule reads it
the runbook executed on a machine that is not the one that wrote it, because the stage criterion is a fresh VPS and this run ran on the machine that built the artifact
a value an operator changes after the run, because the rules read the files as they are committed, so a change to the file a deployment reads is not read here

## What this runbook cannot show

That its steps were executed on a machine that is not the one that wrote this page: the clean-
container run reads the commands it names against the command surface the dispatch registers,
against the flags each command's signature declares, against the names the config parser reads,
against the pragma and the factor the checks use, and against the steps that run recorded — but it
ran on the machine that built the artifact, and the stage's criterion is a fresh VPS.
