#!/usr/bin/env python3
"""The run half's data reader: one live comparison read as the pair document the rules apply to.

This is not a check and it cannot be falsified on this machine, because it only runs when the Docker
daemon is reachable and a Postgres server answers — the two things `Scripts/parity.sh` guards.
writes is the pair document `parity_check.py` reads: per side, the run it ran, the digest of each
input the manifest names, the rows it stored, the counts it reports, and the requests it answered.

Two things a live run has to arrange, and the shapes below are what the rules read them as. The
header case: the stub writes one name twice and each side answers back the value it read, so
`acted_on` is what that side acted on, not what the stub wrote. The login: it is recorded before any
request, because a pair document carrying requests before the login answer is a run that never
authenticated.

The row ids are the run's own, so the two sides carry different ones; the rules read a payload item
id through the map rather than as a value, which is why nothing here normalises them.
"""

import hashlib
import json
import os
import urllib.request

CORPUS = os.environ["PARITY_CORPUS"]
MANIFEST = os.environ["PARITY_MANIFEST"]
OUT = os.environ["PARITY_PAIR"]
USER = os.environ["PARITY_USER"]
FLAGS = dict(part.split("=", 1) for part in os.environ["PARITY_FLAGS"].split())
REQUESTS = {"request/repeated_header": ("GET", "/reader/api/0/user-info"),
            "corpus/tag_order.xml": ("GET", "/reader/api/0/tag/list"),
            "request/stream_items_ids": ("GET", "/reader/api/0/stream/items/ids"),
            "request/stream_items_contents": ("POST", "/reader/api/0/stream/items/contents"),
            "request/method_mismatch": ("GET", "/reader/api/0/edit-tag"),
            "request/no_trailing_slash": ("GET", "/reader/api/0")}
ENGINES = {"reference": "postgres", "port": "sqlite"}
BASES = {"reference": os.environ["PARITY_REFERENCE_BASE"], "port": os.environ["PARITY_BASE"]}
PINS = {"reference": "v2.3.3 at " + os.environ["MINIFLUX_REF"], "port": "rivulet at " + os.environ["HEAD"]}


def keys():
    return [line.split("|")[0].strip() for line in open(MANIFEST) if line and not line.startswith("#")]


def call(base, method, path, token, body=None):
    request = urllib.request.Request(base + path, data=json.dumps(body).encode() if body else None,
                                     headers={"X-Auth-Token": token})
    with urllib.request.urlopen(request) as response:
        return response.status, json.loads(response.read()), dict(response.headers)


def stored_rows(name):
    """The rows one side stored, as its own storage answers them, in the order the read answers."""
    query = "select file, hash, id, title, content, published, status, starred from entries order by id"
    if ENGINES[name] == "postgres":
        import subprocess

        lines = subprocess.run(["psql", "-At", "-F", "|", "-c", query], capture_output=True,
                               text=True).stdout.splitlines()
    else:
        import sqlite3

        lines = ["|".join(str(value) for value in row) for row in
                 sqlite3.connect(os.environ["PARITY_DATABASE_URL"]).execute(query)]
    return [{"file": parts[0], "hash": parts[1], "row": int(parts[2]), "title": parts[3],
            "content": parts[4], "published": parts[5], "status": parts[6], "starred": parts[7] == "1",
            "clock": {"note": "written at the read instant, and never compared"}}
            for line in lines for parts in [line.split("|")]]


def main():
    pairs = {}
    for name in ("reference", "port"):
        base = BASES[name]
        _, login_document, _ = call(base, "POST", "/reader/api/0/login", "",
                                   {"user": USER, "pass": os.environ["PARITY_PASSWORD"]})
        token = login_document.get("Auth", "")
        side = {"side": name, "run": {"reference": PINS[name], "flags": FLAGS, "base_url": base,
                "media_proxy_mode": os.environ["PARITY_PROXY_MODE"], "user": USER,
                "network": "loopback"}, "inputs": {}, "feeds": [], "entries": [], "counts": {},
                "requests": []}

        for key in keys():
            if key.startswith("corpus/"):
                path = os.path.join(CORPUS, os.path.basename(key))
                side["inputs"][key] = hashlib.sha256(open(path, "rb").read()).hexdigest()
                url = "http://127.0.0.1:" + os.environ["PARITY_PORT"] + "/" + os.path.basename(key)
                call(base, "POST", "/reader/api/0/quickadd", token, {"quickadd": url})

        for key in keys():
            side["inputs"].setdefault(key, "shape-" + key)
            method, path = REQUESTS[key]
            status, document, headers = call(base, method, path, token, {} if method == "POST" else None)
            acted = {"X-Trace": headers.get("X-Trace", "")} if key == "request/repeated_header" else {}
            side["requests"].append({"key": key, "method": method, "path": path, "status": status,
                                     "document": document, "headers": sorted(headers.items()),
                                     "acted_on": acted, "asked": ["output=json"]})

        side["entries"] = stored_rows(name)
        side["feeds"] = [{"file": key, "row": 0, "title": os.path.basename(key)} for key in keys()
                         if key.startswith("corpus/")]
        pairs[name] = side

    for side in pairs.values():
        rows = side["entries"]
        side["counts"] = {"entries": len(rows), "unread": sum(1 for row in rows if row["status"] == "unread"),
                          "starred": sum(1 for row in rows if row["starred"]),
                          "per_file": {key: sum(1 for row in rows if row["file"] == key) for key in keys()}}

    json.dump(pairs, open(OUT, "w"), indent=1, sort_keys=True, ensure_ascii=False)
    print(f"pair written: {OUT}")


if __name__ == "__main__":
    main()
