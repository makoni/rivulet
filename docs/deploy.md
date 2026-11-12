# Deploy runbook (stage 8)

One static binary and one SQLite file. The machine needs no toolchain, no interpreter and no service
beyond what this page names: the artifact is the static musl build `Scripts/build-release.sh`
leaves, and the data is the file `DATABASE_URL` names.

## The environment the runs read

Only `DATABASE_URL` is required; the rest read as their defaults. Every name below is a name the
config parser reads, and a name it does not reads as nothing — so a typo here is not an error the
run reports.

```sh
export DATABASE_URL=/var/lib/rivulet/rivulet.db
export LISTEN_ADDR=0.0.0.0
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
the runbook runs on a console, not from a unit or a pipe: a secure read answers nothing when its
input is not a terminal, and the run then writes nothing. The credential pair the clients log in
with is the one `integration-credentials` writes; `create-admin` writes the account hash alone, so
the login answers 401 until the second command has run.

`add` writes the row and fetches nothing, so the first round is the cadence loop's own: the serve
run waits the interval it was built with, reads the batch, and writes the entries. `status --json`
is the minimal contract the reader reads, and the counts it reports are read over every row whatever
its state.

`serve` is the run that keeps running; the unit names it, and the signal it reads is the clean stop
path, which exits with 0. The port the run answers on is the one `LISTEN_ADDR` names.

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

## What this runbook cannot show

That its steps were executed on a machine that is not the one that wrote this page: the clean-
container run reads the commands it names against the command surface the dispatch registers,
against the flags each command's signature declares, against the names the config parser reads,
against the pragma and the factor the checks use, and against the steps that run recorded — but it
ran on the machine that built the artifact, and the stage's criterion is a fresh VPS.