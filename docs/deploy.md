# Deploy runbook

One static binary and one SQLite file. The server needs no Swift toolchain, no interpreter and no
other service. The binary is the static musl build `Scripts/build-release.sh` produces; the data is
the file `DATABASE_URL` names.

## Configuration

Only `DATABASE_URL` is required; everything else has a default. The README lists every variable.
A variable Rivulet does not read is silently ignored, so check the spelling.

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

`LISTEN_ADDR` must be `host:port` (default `127.0.0.1:8080`); a value without a port is an error.
`FETCHER_ALLOW_PRIVATE_NETWORKS` stays off unless you subscribe to feeds on your own network: with it
off, the fetcher refuses loopback and private addresses.

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

`create-admin` and `integration-credentials` prompt for passwords on the terminal, so run them in an
interactive shell, not from a unit or a pipe. Clients log in with the pairs `integration-credentials`
stores (Google Reader and Fever); until it has run, client logins answer 401. Clients that use the
Miniflux REST API log in with the account password or a key from `rivulet create-api-key`.

`add` stores the subscription without fetching it; `serve` fetches it on its first scheduler pass.
Run `rivulet refresh` to fetch due feeds immediately.

## Running as a service

`deploy/rivulet.service` is an example systemd unit. Put the configuration in an environment file,
reference it from the unit, and adjust the binary path:

```ini
[Service]
ExecStart=/usr/local/bin/rivulet serve
EnvironmentFile=/etc/rivulet/rivulet.env
```

`serve` stops cleanly on SIGTERM (and SIGINT): it finishes, checkpoints the WAL and exits 0.

`deploy/compose.yml` with the `Dockerfile` is the container alternative: copy the static binary into
the build context as `rivulet`, put the configuration in `.env` (see `.env.example`), and the compose
file mounts a volume for the database.

## Backups

```sh
rivulet backup /var/backups/rivulet.db
rivulet backup --verify /var/backups/rivulet.db
rivulet vacuum
```

`backup` writes a consistent snapshot with `VACUUM INTO`. It first checks there is room for about
twice the database plus its WAL in the destination directory. It refuses to overwrite an existing
file unless `--force` is given. `--verify` opens the copy and runs an integrity check on it.
`vacuum` rebuilds the live database to release free pages. More detail is in `docs/backup-restore.md`.

## Restore

There is no restore command; restoring is a file swap.

1. Stop `serve`.
2. Copy the backup to the path `DATABASE_URL` names.
3. Run `rivulet migrate` (it does nothing when the schema is current).
4. Check the counts with `rivulet status --json` against what you expect.

## Durability

SQLite runs with `synchronous=NORMAL` and WAL: commits reach the OS cache, not the disk, on every
write, so a power loss can lose the refresh round that was running. Each feed refresh is one write
transaction. The WAL is checkpointed when `serve` stops.

## Time

Schedules are stored as Unix seconds. A large clock step moves every feed's schedule: feeds whose
next check is now in the past are fetched at the next pass. Keep the clock synchronised gradually
(`chrony`, or `systemd-timesyncd`).

## Upgrade

Replace the binary, then run `rivulet migrate`. Until the first release the schema is still edited
in place, so take a backup before upgrading and treat the database and the binary as one unit.

## Optional: continuous replication

[Litestream](https://litestream.io) can stream the database file to other storage. Rivulet does not
run or configure it; `rivulet backup` is the built-in, point-in-time alternative.
