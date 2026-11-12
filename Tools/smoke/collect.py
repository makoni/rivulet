#!/usr/bin/env python3
"""The smoke run's data reader: one clean-container run read as the document the rules apply to.

It asserts nothing. It only runs when the machine gives what the shell guards: Docker, an artifact
at the path the release script names, the corpus the manifest declares, both ports free, and an
address policy declared as the value the run needs, because the corpus target is the loopback
address the policy refuses by default. What it writes is the document `smoke_check.py` reads: the
run it ran, the state of the machine read twice, the file set the image carries, the digests of
the inputs the manifest names, the answers the binary gave inside the container, the events the stub
recorded for the round, the two snapshots of the rows taken around the stop, and the copy the backup
wrote. Every value in the document is a read: the file set comes from `docker export`, because a
scratch base has no shell to list it with, and the container list comes from the machine's own list.

Four shapes are what the rules read them as. The snapshots are the `status --json` contract, so the
rows are read as the contract documents them. The first snapshot is taken at the point the round was
mid-way: the stub had recorded the answers for the files it answers at once and not the answer
for the file it holds, so the row for that file was unstamped at the read — which is what makes the
round mid-way, and which the document cannot show beyond the read itself. The second snapshot is the
round after the restart, read once the pipeline had written the row for the job the stop
interrupted: the row is written at the end of a job, and the stub holds every hop for the held file,
so the write lands after the job's last hop, and a read taken before it reads a job that had not
written its row. The integrity line is read from that second boot, because the rule names the second
boot.

The health answer is read once the boot answers on the port the run declares, because a read taken
before the server listens answers nothing, which is the machine's startup and not the answer the
route writes. The WAL bytes are recorded as the file held them at the moment the run looked, and no
rule reads them as the empty WAL the process harness reads: the checkpoint that rule reads is
blocked by the write transaction the stop interrupted, so the bytes the run recorded are the
round's.

The names the run asks with are read from the sources the rules read them from, so the run cannot
pass a rule by naming a path, a field or a header on its own: it asks with what the port reads. The
instants the run records keep the sub-second part, because the order the rules read is an order of
events that can fall inside one second, while the stamps the contract reports are whole seconds. The
copy is read as the binary's answer against the file it wrote, and the listing beside it is read
before that answer, so the run does not report a WAL the read itself created. The machine is read
once before the run created anything and once after the run removed what it created, which is what
lets the state rule compare two reads of the same machine. The `add` calls run in the order the
manifest declares the records in, and the run leaves a gap between them so each row's schedule value
lands in a second of its own, which is the only case where the order clause fixes an order at all.
The value each call wrote is read back through the contract, so the order the rule reads is the
order the clause names; the order the jobs of the round ran in is the pool's choice and is not read.

The run removes the containers it started before it reads the machine the second time, because the
state rule compares two reads, and it removes what it copied and what the binary wrote after it has
written the document, because the document is what the rules read and the work dir is the run's own
scratch.

Run it through `Scripts/smoke.sh`, which sets the environment this reads.
"""

import io
import json
import os
import shutil
import subprocess
import tarfile
import time

import smoke_check
import sources

HERE = os.path.dirname(os.path.abspath(__file__))

WORK = os.environ["SMOKE_WORK"]
VOLUME = os.path.join(WORK, "volume")
IMAGE = os.environ["SMOKE_IMAGE"]
PORT = int(os.environ["SMOKE_PORT"])
STUB_PORT = int(os.environ["SMOKE_STUB_PORT"])
TARGET = os.environ["SMOKE_TARGET"]
POLICY_NAME = os.environ["SMOKE_POLICY_NAME"]
POLICY_VALUE = os.environ["SMOKE_ALLOW_PRIVATE"]
RECORD = os.environ["SMOKE_RECORD"]
EVENTS = os.environ["SMOKE_EVENTS"]
CORPUS = os.environ["SMOKE_CORPUS"]
DOCKERFILE = os.environ["SMOKE_DOCKERFILE"]
HELD = os.path.basename(os.environ["SMOKE_HELD_FILE"])
ARTIFACT = os.environ["SMOKE_ARTIFACT"]
GRACE = int(os.environ["SMOKE_STOP_GRACE"])
ERROR_LIMIT = int(os.environ["SMOKE_ERROR_LIMIT"])
BATCH_SIZE = int(os.environ["SMOKE_BATCH_SIZE"])
WAIT = int(os.environ["SMOKE_WAIT_SECONDS"])
GAP = int(os.environ["SMOKE_ADD_GAP"])
STEPS = []
USER = os.environ["SMOKE_USER"]
PASSWORD = os.environ["SMOKE_PASSWORD"]
DB = "/data/smoke.db"
COPY_DB = "/data/smoke-copy.db"
TAG = os.path.basename(WORK)
# The label the run writes on every container it starts, so the machine read lists the run's own
# containers and not the machine's whole state, and a run cannot read what another run created.
LABEL = f"smoke-run-{TAG}"
COPY_WAL = os.path.join(VOLUME, "smoke-copy.db-wal")
# The names the run asks with, read from the sources the rules read them from: the health path and
# the body the route writes, the pair the login handler binds, the path the route group and the
# registration build, the header name and the first word of the value the auth read compares.
HEALTH_VALUES = sources.quoted_values(sources.first_line("health_route", '"healthz"'))
HEALTH_PATH, HEALTH_BODY = "/" + HEALTH_VALUES[0], HEALTH_VALUES[1]
LOGIN_PATH = "/accounts/ClientLogin"
LOGIN_FIELDS = sources.literals_in("routes", "static func clientLogin", "    }", 'value(named: "',
                                   "let ")
GROUP = sources.quoted_values(sources.first_line("routes", "application.grouped("))
READER_PATH = "/" + "/".join(GROUP + [sources.literal("routes", 'protected.get("user-info"')])
READER_HEADER = sources.literal("auth", 'name: "')
READER_WORD = sources.literal("auth", "fields.first == ")
DATABASE_NAME = "DATABASE_URL"


def size(path):
    return os.path.getsize(path) if os.path.isfile(path) else 0


def env_args(database=DB):
    """The values the run declares, passed under the names the config reads them by.

    `docker run` does not inherit the caller's environment, so the run names each value with `-e`,
    and the policy value goes under the name the config read takes the flag by, which is the same
    name the check half reads.
    """
    return ["-e", f"{DATABASE_NAME}={database}", "-e", f"BATCH_SIZE={BATCH_SIZE}",
            "-e", f"POLLING_PARSING_ERROR_LIMIT={ERROR_LIMIT}",
            "-e", f"POLLING_FREQUENCY={os.environ['SMOKE_POLLING_FREQUENCY']}",
            "-e", f"{POLICY_NAME}={POLICY_VALUE}"]


def call(args, database=DB, feed=False, feed_values=None):
    """One run of the binary inside the image, answered as the container reported it.

    `feed_values` is the values the terminal half writes for this call, which are the values the run
    declares for the command that reads the prompts. The terminal half reads one set of values, so
    the run names the set for the call rather than making the half know which command it runs.

    Every call is recorded as a step, because the rule that reads the runbook compares the order the
    page names its steps in with the order the run ran them in, which is something only the run can
    record.
    """
    STEPS.append(args[0])
    argv = ["docker", "run", "--rm", "--network", "host", "-v", f"{VOLUME}:/data"]
    if feed:
        argv += ["-i", "-t"]
    argv += env_args(database) + [IMAGE] + args
    env = dict(os.environ)
    if feed_values:
        env["SMOKE_FEED"] = "\n".join(feed_values)
    runner = subprocess.run([os.path.join(HERE, "console_feed.py")] + argv if feed else argv,
                            capture_output=True, text=True, env=env)
    return runner.stdout.strip()


def answer_line(output):
    """The answer itself, not the log lines the run wrote beside it."""
    return next((line for line in output.splitlines() if line.startswith("{")), "")


def line_after_prefix(output):
    """The sentence the command printed, read as the source writes it, without the log prefix.

    A run that reports a failure prints the reported failure rather than the sentence, so the value
    the rule compares is the one the file writes for the case the run reached.
    """
    return output.splitlines()[-1].rsplit("] ", 1)[-1].strip()


def image_files():
    """The file set the image carries, read from the export, not from the Dockerfile's word."""
    created = subprocess.run(["docker", "create", IMAGE], capture_output=True,
                             text=True).stdout.strip()
    listing = subprocess.run(["docker", "export", created], capture_output=True)
    subprocess.run(["docker", "rm", created], capture_output=True)
    with tarfile.open(fileobj=io.BytesIO(listing.stdout)) as archive:
        return sorted(name.split("/")[-1] for name in archive.getnames())


def read_containers():
    """The machine's own list, read through the label the run writes on every container it
    starts."""
    out = subprocess.run(["docker", "ps", "-a", "--format", "{{.Names}} {{.State}}"],
                         capture_output=True, text=True).stdout
    entries = [{"name": part.split(" ", 1)[0], "running": part.split(" ", 1)[1] == "running"}
               for part in out.splitlines() if part.startswith(LABEL)]
    return {"instant": time.time(), "entries": sorted(entries, key=lambda one: one["name"])}


def event_records():
    """The stub's own record, read as it stands, which is the data the round rules read.

    The name is read as the text between the action and the held mark, which is empty for a hop the
    fetcher made for the site root rather than for a corpus file, because the icon finder takes that
    hop before the file it is given. A reader that split the line into fields would read such a line
    as having no name and stop, so the shape here is the one the file writes.
    """
    if not os.path.isfile(EVENTS):
        return []
    with open(EVENTS, encoding="utf-8") as handle:
        rows = [line.rstrip("\n") for line in handle if line.strip()]
    out = []
    for row in rows:
        instant, action, rest = row.split(" ", 2)
        name, _, mark = rest.partition(" held")
        out.append({"instant": float(instant), "action": action, "name": name.strip(),
                    "held": bool(mark)})
    return sorted(out, key=lambda one: (one["instant"], one["action"]))


def start(number):
    """The serve run, recorded as the step the runbook names, because the run starts it as a container."""
    STEPS.append("serve")
    subprocess.run(["docker", "run", "-d", "--name", f"{LABEL}-{number}", "--network", "host",
                    "-v", f"{VOLUME}:/data"] + env_args()
                   + ["-e", f"LISTEN_ADDR={TARGET}:{PORT}", IMAGE, "serve"], check=True,
                   capture_output=True, text=True)


def stop(number):
    subprocess.run(["docker", "stop", "-t", str(GRACE), f"{LABEL}-{number}"], check=True,
                   capture_output=True)


def integrity_line(number):
    """The line the boot answered for the run's own integrity rule, read from that boot's log."""
    logs = subprocess.run(["docker", "logs", f"{LABEL}-{number}"], check=True, capture_output=True,
                          text=True)
    line = next((one for one in f"{logs.stdout}{logs.stderr}".splitlines()
                 if "integrity check passed" in one), "")
    # The line the boot wrote carries the log prefix; the rule reads the sentence the source writes,
    # so the part after the prefix is what the run records, not the whole line.
    return line.rsplit("] ", 1)[-1].strip()


def wait_for(action, name, seconds, since):
    """The event file, polled: the run knows a round is mid-way only through what the stub recorded.

    `since` is the instant the run started its own serve container, so an event the stub wrote for
    another round, or for the `add` calls that wrote the rows before it, is not read as this
    round's.
    """
    deadline = time.time() + seconds
    while time.time() < deadline:
        for row in event_records():
            if row["action"] == action and row["name"] == name and row["instant"] > since:
                return row["instant"]
        time.sleep(0.25)
    raise SystemExit(f"the run never saw a {action} for {name} after {since}, so it cannot say a "
                     "round was mid-way")


def snapshot(read_by, instant):
    document = json.loads(answer_line(call(["status", "--json"])))
    return {"read_by": read_by, "instant": instant, "document": document}


def http_read(path, headers=None, form=None):
    """One read: the status the answer carries and the body it wrote, from the same call."""
    argv = ["curl", "-s", "-w", "\n%{http_code}", f"http://{TARGET}:{PORT}{path}"]
    if form:
        argv += ["-X", "POST", "--data", form]
    for name, value in (headers or {}).items():
        argv += ["-H", f"{name}: {value}"]
    body, code = subprocess.run(argv, capture_output=True, text=True).stdout.rsplit("\n", 1)
    return int(code), body


def health_answer_read():
    """The health answer, read once the boot answers on the port the run declared.

    A read taken before the server listens answers nothing, which is the machine's startup rather
    than the answer the route writes, so the run waits for an answer before it records one. The rule
    still reads the status and the body as the route writes them.
    """
    deadline = time.time() + WAIT
    while time.time() < deadline:
        code, body = http_read(HEALTH_PATH)
        if code:
            return {"status": code, "body": body, "path": HEALTH_PATH}
        time.sleep(0.25)
    raise SystemExit(f"the boot answered nothing on {TARGET}:{PORT} after {WAIT}, so the run has no "
                     "health answer to record")


def login_read(credentials):
    """The login as the run reached it: the names the run asked with, and the answer it wrote."""
    form = "&".join(f"{name}={value}" for name, value in zip(LOGIN_FIELDS, (USER, PASSWORD)))
    code, body = http_read(LOGIN_PATH, form=form)
    token = next((line.split("Auth=")[1].strip() for line in body.splitlines() if "Auth=" in line),
                 "")
    return {"fields": list(LOGIN_FIELDS), "status": code, "token": token,
            "prompts": credentials["prompts"], "written_through": credentials["command"]}


def reader_answer(login):
    value = f"{READER_WORD} auth={login['token']}"
    code, body = http_read(READER_PATH, {READER_HEADER: value})
    keys = sorted(json.loads(body).keys()) if body.startswith("{") else []
    return {"endpoint": READER_PATH, "status": code, "keys": keys, "half": "header",
            "name": READER_HEADER, "field": value.split(" ")[0], "carried_with": login["token"]}


def read_answers():
    """The answers the binary gives before any round runs: the migration answer and the rows.

    The migration answer is read on a database the run builds for itself, before the account run
    runs the migrations the command gates, so the answer is the one the schema file names. The
    `add` calls write rows and fetch nothing, so the stamps the round is read for are the round's
    own, and the gap between them puts each row's schedule value in a second of its own, which is
    the only case where the batch's order clause fixes an order at all. The value each call wrote is
    read back through the contract, because the order the jobs of the round ran in is the pool's
    choice and the record cannot show it.
    """
    answers = {"migrate": call(["migrate"])}
    answers["account"] = {"declared": USER, "line": line_after_prefix(call(["create-admin"], feed=True))}
    answers["credentials"] = {
        "prompts": sources.prompts("integration_credentials"),
        "command": sources.literal("cli", "IntegrationCredentials(environment")}
    call([sources.literal("cli", "IntegrationCredentials(environment")], feed=True,
         feed_values=os.environ["SMOKE_CRED_FEED"].split("\n"))
    written = []
    for number, row in enumerate(sources.manifest_rows()):
        if number:
            time.sleep(GAP)
        name = os.path.basename(row["name"])
        call(["add", f"http://{TARGET}:{STUB_PORT}/{name}"])
        document = json.loads(answer_line(call(["status", "--json"])))
        listed = next((one for one in document["feeds"] if one["url"].endswith("/" + name)), None)
        if listed is None:
            raise SystemExit(f"the listing read after the add for {name} holds no row, so the value "
                             "the call wrote cannot be read")
        written.append({"name": name, "value": listed["next_check_at"]})
    answers["add_values"] = written
    return answers


def first_round(answers, started):
    """The round the run stops while it is still reading, and the rows read at that point.

    The read is taken at the point the stub has recorded the answers for the inputs the round read
    before the held one and the request for the held one without its answer, which is what makes the
    round mid-way: the row for that file is unstamped at the read. A read taken later is a read of a
    round that had already finished, which the run says rather than writing a document the round
    rule would report.
    """
    answers["health"] = health_answer_read()
    answers["login"] = login_read(answers["credentials"])
    answers["reader"] = reader_answer(answers["login"])

    for row in sources.manifest_rows():
        name = os.path.basename(row["name"])
        if name != HELD:
            wait_for("answered", name, WAIT, started)
    wait_for("request", HELD, WAIT, started)
    if any(one["action"] == "answered" and one["name"] == HELD for one in event_records()):
        raise SystemExit(f"the stub answered {HELD} before the run read, so the run cannot say the "
                         "round it reports was mid-way at the read")
    before = snapshot("mid-round", time.time())
    stop_instant = time.time()
    stop(1)
    wal = os.path.join(VOLUME, "smoke.db-wal")
    return before, {"in_flight": HELD, "instant": stop_instant, "wal_bytes": size(wal)}


def wait_for_stamp(name, seconds, since):
    """The rows, polled until the pipeline wrote the row for the job the stop interrupted.

    The stamp is the value the scheduling rule reads, so the run waits on the answer the binary gave
    rather than on a hop count: the row is written at the end of the job, and for the file the stub
    holds every hop of the job is held, so the write lands after the job's last hop, which for these
    inputs is the icon read that asks the feed url again.
    """
    deadline = time.time() + seconds
    while time.time() < deadline:
        document = json.loads(answer_line(call(["status", "--json"])))
        row = next((one for one in document["feeds"] if one["url"].endswith("/" + name)), None)
        if row and row["fetched_at"]:
            return row["fetched_at"]
        time.sleep(0.25)
    raise SystemExit(f"the pipeline wrote no stamp for {name} after {since}, so the run cannot say "
                     "the round after the restart finished the job the stop interrupted")


def second_round(restarted):
    """The round after the restart, read once the job the stop interrupted had finished."""
    start(2)
    wait_for("answered", HELD, WAIT, restarted)
    wait_for_stamp(HELD, WAIT, restarted)
    after = snapshot("after-restart", time.time())
    stop(2)
    return after, integrity_line(2)


def read_copy():
    """The copy as the binary answered it, with the listing beside it read before the answer."""
    printed = call(["backup", COPY_DB])
    beside, instant = size(COPY_WAL) > 0, time.time()
    document = json.loads(answer_line(call(["status", "--json"], COPY_DB)))
    return {"path": COPY_DB, "printed": line_after_prefix(printed), "wal_beside": beside,
            "instant": instant, "rows": document["feeds"], "counts": document["totals"]}


def build_document(machine, files, answers, before, after, stop_record, copy, rounds):
    return {
        "run": {"base": os.environ["SMOKE_BASE"], "triple": os.environ["SMOKE_TRIPLE"],
                "artifact_path": ARTIFACT, "artifact_digest": sources.digest(ARTIFACT),
                "image_copy_digest": sources.digest(os.path.join(WORK, "rivulet")),
                "record": "Tools/smoke/run.json", "target": TARGET, "feed_base": f"http://{TARGET}:{STUB_PORT}",
                "policy": {"name": POLICY_NAME, "value": POLICY_VALUE},
                "declared_feeds": len(sources.manifest_rows()), "error_limit": ERROR_LIMIT,
                "batch_size": BATCH_SIZE, "steps": STEPS},
        "machine": machine,
        "image_content": files,
        "manifest": [{"name": row["name"], "title": row["title"],
                      "digest": sources.digest(sources.corpus_path(row["name"]))}
                     for row in sources.manifest_rows()],
        "answers": answers,
        "rounds": rounds,
        "events": event_records(),
        "snapshots": {"before_stop": before, "after_stop": after},
        "stop": stop_record,
        "copy": copy,
        "rules": sorted(smoke_check.RULES),
        "cannot_show": sorted(smoke_check.CANNOT_SHOW),
    }


def remove(number):
    subprocess.run(["docker", "rm", "-f", f"{LABEL}-{number}"], check=True, capture_output=True)


def release(server):
    """Give the machine back: the containers the run created, the port the stub holds, the run's own
    work directory."""
    for number in (1, 2):
        subprocess.run(["docker", "rm", "-f", f"{LABEL}-{number}"], capture_output=True)
    # A server inside `serve_forever` does not read the signal, so the run gives the port back by
    # closing the socket it holds, which is what the guard that reads the port would otherwise fail
    # on for the next run.
    server.kill()
    server.wait(timeout=5)
    shutil.rmtree(VOLUME, ignore_errors=True)
    if os.path.isfile(os.path.join(WORK, "rivulet")):
        os.remove(os.path.join(WORK, "rivulet"))


def main():
    os.makedirs(VOLUME, exist_ok=True)
    subprocess.run(["docker", "build", "-q", "-t", IMAGE, "-f", DOCKERFILE, WORK], check=True,
                   capture_output=True)
    files = image_files()
    answers = read_answers()

    server = subprocess.Popen([os.path.join(HERE, "stub_server.py")])
    try:
        machine = {"work": TAG, "before": read_containers()}
        started = time.time()
        start(1)
        before, stop_record = first_round(answers, started)
        remove(1)
        restarted = time.time()
        after, integrity = second_round(restarted)
        stop_record["integrity_line"] = integrity
        remove(2)
        # The second read is taken after the run has removed what it created, which is the half the
        # state rule compares: the rule reads two reads of the same machine, so the run cannot
        # report a state it did not read after its own containers were gone.
        machine["left"] = read_containers()
        copy = read_copy()
        # The page's last step runs here as well, so the rule that reads the runbook sees the run as
        # having executed every command the page names, not only the ones the rules happen to need.
        answers["vacuum"] = call(["vacuum"])
        rounds = {"started": started, "restarted": restarted}

        document = build_document(machine, files, answers, before, after, stop_record, copy, rounds)
        with open(RECORD, "w", encoding="utf-8") as handle:
            json.dump(document, handle, indent=1, sort_keys=True)
            handle.write("\n")
        print(f"wrote {RECORD}")
    finally:
        release(server)


if __name__ == "__main__":
    raise SystemExit(main())
