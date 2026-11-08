#!/usr/bin/env python3
"""The run half's data reader: one live comparison read as the pair document the rules apply to.

This is not a check and it asserts nothing: it only runs when the machine gives the two things the
shell guards, the daemon for the reference side and a Postgres server the reference needs because
its `go.mod` has no SQLite driver. What it writes is the pair document `parity_check.py` reads: per
side, the run it ran, the digest of each input the manifest names, the rows it stored, the counts it
reports, and the requests it answered. It was run here for the first time, and the login answers it
recorded were the unauthorized answers, because neither side had the values the read compares: the
integration row is there for every user on the reference side, but its enabled flag is set only by
its web form, and on this side the credential pair sits on the account row, which the run had not
set either.

Eight things a live run has to arrange, and the shapes below are what the rules read them as.

The login: `POST /accounts/ClientLogin`, read with the form names the reference reads, and recorded
as
the first request, because a pair document carrying requests before the login answer is a run that
never authenticated. The token is then sent as the `Authorization` name the auth read reads —
`GoogleLogin auth=<token>`, split as `strings.Fields` splits it — not as a name of its own.

The unauthenticated half: the no-slash path is asked before the login, because the reference writes
its
redirect before the auth middleware, so an answer after the login is a different request than the
one
the row names.

The header case: the stub writes one name twice, so a name is kept as the list in the order the
values
arrive, which is what `Header.Get` reads through. `acted_on` is the value that response answered,
not
what the stub wrote.

The status: it is taken from the failed response, which is the only way the statuses the status rule
compares can be the reference's 404 and 405 rather than an exception. A non-JSON answer is recorded
as
the text it is, because the redirect body is text.

The name of an input: neither storage has a column that holds the manifest key, and the stored title
is
the parsed feed title, so `file` is the name the run added the feed under, resolved through the feed
url
the run gave. The row id is the run's own, so the two sides carry different ones and nothing here
normalises them.

The subscription shapes: the three endpoints this path implements are recorded as the answers
they give, asked with the names each handler reads — `output` for the listing, `s` and `ac` for
the edit, `output` and `quickadd` for the discovery. Nothing here compares what those names
carried, so the two shapes that answer the same document reach no class the table names, and the
discovery shape can only show its difference as the key set its answer carries.

What is normalised is the dialect, not the value: Postgres answers `t` for a boolean where SQLite
answers `1`, so the boolean is read as the same value on both sides. The date is not normalised: the
reference keeps the sub-second part on its date column and this port's column holds whole seconds,
which
is the difference the row names, so the value is read as each side answers it.

The connection: libpq reads its own environment names, not the url the reference's config reads, so
the
reference side's read is given `PGDATABASE` and its companions by the shell.

Usage: run through `Scripts/parity.sh`, which sets the environment this reads.
"""

import hashlib
import json
import os
import urllib.error
import urllib.parse
import urllib.request

CORPUS = os.environ["PARITY_CORPUS"]
MANIFEST = os.environ["PARITY_MANIFEST"]
OUT = os.environ["PARITY_PAIR"]
USER = os.environ["PARITY_USER"]
PASSWORD = os.environ["PARITY_PASSWORD"]
PORT = os.environ["PARITY_PORT"]
FLAGS = dict(part.split("=", 1) for part in os.environ["PARITY_FLAGS"].split())
ENGINES = {"reference": "postgres", "port": "sqlite"}
BASES = {"reference": os.environ["PARITY_REFERENCE_BASE"], "port": os.environ["PARITY_BASE"]}
PINS = {"reference": "v2.3.3 at " + os.environ["MINIFLUX_REF"], "port": "rivulet at " +
os.environ["HEAD"]}
SELECT = ("select feeds.url, entries.hash, entries.id, entries.title, entries.content, "
          "entries.published_at, entries.status, entries.starred from entries "
          "join feeds on feeds.id = entries.feed_id order by entries.id")
REQUESTS = [
    ("request/repeated_header", "POST", "/accounts/ClientLogin", "login"),
    ("request/no_trailing_slash", "GET", "/reader/api/0", "unauthenticated"),
    ("corpus/tag_order.xml", "GET", "/reader/api/0/tag/list", "token"),
    ("request/stream_items_ids", "GET", "/reader/api/0/stream/items/ids", "token"),
    ("request/stream_items_contents", "POST", "/reader/api/0/stream/items/contents", "token"),
    ("request/method_mismatch", "POST", "/reader/api/0/edit-tag", "token"),
    ("request/subscription_list", "GET", "/reader/api/0/subscription/list", "token"),
    ("request/subscription_edit", "POST", "/reader/api/0/subscription/edit", "token"),
    ("request/subscription_quickadd", "POST", "/reader/api/0/subscription/quickadd", "token"),
]
STREAM = "user/-/state/com.google/reading-list"


def keys():
    return [line.split("|")[0].strip() for line in open(MANIFEST) if line and not
line.startswith("#")]

# The document the discovery shape is asked with is the first corpus input the manifest names.
SCAN_INPUT = next(key for key in keys() if key.startswith("corpus/"))


def call(base, method, path, token, form=None):
    """One request, answered as the side answers it: the failed response's status is included."""
    body = urllib.parse.urlencode(form).encode() if form else None
    headers = {"Authorization": "GoogleLogin auth=" + token} if token else {}
    request = urllib.request.Request(base + path, data=body, headers=headers)
    try:
        with urllib.request.urlopen(request) as response:
            status, text, answer = response.status, response.read().decode(), response.headers
    except urllib.error.HTTPError as error:
        status, text, answer = error.code, error.read().decode(), error.headers
    is_json = answer.get("Content-Type", "").startswith("application/json")
    document = json.loads(text) if is_json else {"body": text}
    values = {}
    for name in answer.keys():
        values[name] = list(answer.get_all(name) or [])
    return status, document, values


def read(name, query):
    """The fields one side's storage answers, in the order it reads them.

    The content field can hold the character a delimited read uses to split, and a newline inside
    it, so the reference side is read as CSV over the whole text rather than line by line: a field
    with a newline in it is one row, not two. This port's driver answers rows as fields, which
    needs no delimiter at all. A value the storage cannot read is nothing on both sides, so the
    field is the empty string rather than the name of nothing.
    """
    import csv

    if ENGINES[name] == "postgres":
        import io
        import subprocess

        out = subprocess.run(["psql", "-At", "-c", f"COPY ({query}) TO STDOUT WITH (FORMAT csv)"],
                             capture_output=True, text=True).stdout
        return [row for row in csv.reader(io.StringIO(out)) if row]

    import sqlite3

    return [[("" if value is None else str(value)) for value in row] for row in
            sqlite3.connect(os.environ["PARITY_DATABASE_URL"]).execute(query)]

def key_for(url):
    """The manifest key the run added this feed under, which is the name the rules read the row
by."""
    return next((key for key in keys() if url.endswith("/" + os.path.basename(key))), "")


def main():
    pairs = {}
    for name in ("reference", "port"):
        side = {"side": name, "run": {"reference": PINS[name], "flags": FLAGS, "base_url":
BASES[name],
                "media_proxy_mode": os.environ["PARITY_PROXY_MODE"], "user": USER,
                "network": "loopback"}, "inputs": {}, "feeds": [], "entries": [], "counts": {},
                "requests": []}

        for key in keys():
            if key.startswith("corpus/"):
                path = os.path.join(CORPUS, os.path.basename(key))
                side["inputs"][key] = hashlib.sha256(open(path, "rb").read()).hexdigest()
            else:
                side["inputs"][key] = "shape-" + key

        token = ""
        for key, method, path, when in REQUESTS:
            if when == "login":
                form = {"Email": USER, "Passwd": PASSWORD, "output": "json"}
            elif key == "request/subscription_edit":
                # The names this handler reads, with no title, so the branch writes nothing and
                # answers the plain-text `OK` on both sides.
                form = {"output": "json", "s": STREAM, "ac": "edit"}
            elif key == "request/subscription_quickadd":
                # The discovery answers on the document the corpus serves, so the shape is asked
                # with a corpus input. The two sides answer with a different key set when the
                # discovery differs, which is the half the table cannot cover.
                form = {"output": "json",
                        "quickadd": "http://127.0.0.1:" + PORT + "/" + os.path.basename(SCAN_INPUT)}
            elif method == "POST":
                form = {"output": "json", "s": STREAM, "a": STREAM}
            else:
                form = {"output": "json"}
            status, document, headers = call(BASES[name], method, path, token if when == "token"
else None, form)
            if when == "login":
                token = document.get("Auth", "")
            acted = {name: values[0] for name, values in headers.items() if len(values) > 1}
            side["requests"].append({"key": key, "method": method, "path": path, "status": status,
                                     "document": document, "headers": headers, "acted_on": acted,
                                     "asked": sorted(form)})

        for key in keys():
            if key.startswith("corpus/"):
                url = "http://127.0.0.1:" + PORT + "/" + os.path.basename(key)
                call(BASES[name], "POST", "/reader/api/0/subscription/quickadd", token,
                     {"quickadd": url, "output": "json"})

        side["entries"] = [{"file": key_for(parts[0]), "hash": parts[1], "row": int(parts[2]),
                            "title": parts[3], "content": parts[4], "published": parts[5],
                            "status": parts[6], "starred": parts[7] in ("1", "t"),
                            "clock": {"note": "written at the read instant, and never compared"}}
                           for parts in read(name, SELECT)]
        side["feeds"] = [{"file": key_for(parts[0]), "row": int(parts[1]), "title": parts[2]}
                         for parts in read(name, "select url, id, title from feeds order by id")]
        pairs[name] = side

    for side in pairs.values():
        stored = side["entries"]
        side["counts"] = {"entries": len(stored),
                          "unread": sum(1 for row in stored if row["status"] == "unread"),
                          "starred": sum(1 for row in stored if row["starred"]),
                          "per_file": {key: sum(1 for row in stored if row["file"] == key) for key
in keys()}}

    json.dump(pairs, open(OUT, "w"), indent=1, sort_keys=True, ensure_ascii=False)
    print(f"pair written: {OUT}")


if __name__ == "__main__":
    main()
