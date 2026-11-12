#!/usr/bin/env python3
"""The run's observing half for the client run: it writes one record line per request it forwarded.

It asserts nothing. It listens on the port the run declares, forwards every request to the port the
run names, and writes what each request looked like as it arrived: the order it arrived in, the path
the client sent to, the call as the recorded set names it, the method, the answer the port gave, the
key names the answer carried, and the field names the request carried. The answer is written as the
run saw it — the name the dispatch case answered on when the port wrote a document of this path, and
the status when it wrote something else — so the record says what happened rather than what the
matrix expected to see, which is what lets the check half read the record against the matrix and
report a run that answered differently.

The order column is the order the requests arrived at, counted per request rather than per
connection, because a client that keeps its connections open sends several requests on one
connection. The name order is part of what the record says: the key names are the names the answer
carried, in the order the answer wrote them, and the call name is read from the path the client
used, not from a prefix this half assumes, because a client can send to a path this port registers
no route for.

The record carries no value. The values the client sends are the credential pair the app reads from
its own settings, so the record names the field the pair reaches as the redaction names it. The part
names are read as the port's own merged read takes them, quoted or unquoted, which is the read PR
#61 pins. A record line is exempt from the width rule because it is one record.

Usage: CLIENT_RECORD=<the file the run writes> CLIENT_OBSERVE_PORT=<the port the client is pointed
at> CLIENT_TARGET_PORT=<the port the run serves on> python3 Tools/clients/observer.py

Read `docs/clients.md` first: the rule in `Tools/clients/run_record.py` reads the record as data.
"""

import http.client
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import parsers as read

RECORD = os.environ["CLIENT_RECORD"]
OBSERVE_PORT = int(os.environ["CLIENT_OBSERVE_PORT"])
TARGET_PORT = int(os.environ["CLIENT_TARGET_PORT"])
CLIENT = os.environ.get("CLIENT_NAME", "NewsFlash")
QUOTE = chr(34)

# The names the dispatch switch reads, the item parameter names the items read takes, and the three
# words the mark switch reads. Read as the set names them so the record and the matrix row use one
# word for the call.
KEYS = ["groups", "feeds", "favicons", "unread_item_ids", "saved_item_ids", "items", "links",
        "folders", "mark"]
ITEM_PARAMS = ["since_id", "max_id", "with_ids"]
MARK_BRANCHES = ["item", "feed", "group"]
# The names that belong to the hop, not to the request: this half writes its own framing, so copying
# the answer's framing is what a client reads as an incomplete message.
HOP_BY_HOP = {"transfer-encoding", "connection", "content-length"}

# The three names the base document writes before every document of this path, read through the same
# read the check half uses, so the answer the record writes and the answer the rule reads come from
# one read of the same file.
BASE = read.base_shape_keys(read.DEFAULTS["port_shape"])


def read_pairs(source):
    """The names a request carries as pairs, and the bare names, kept apart as the dispatch
    reads them.
    """
    names, pairs = [], []
    for one in source.split("&"):
        if not one:
            continue
        if "=" in one:
            pairs.append(one.split("=", 1)[0])
        else:
            names.append(one)
    return names, pairs


def part_names(body):
    """The part names the merged form gives, read as the port's multipart read reads the name
    parameter, quoted or unquoted — the value is not read here, only the name.
    """
    out = []
    for line in body.splitlines():
        if "form-data; name" not in line:
            continue
        value = line.split("name", 1)[1].lstrip("=")
        if value.startswith(QUOTE):
            value = value[1:]
            end = value.find(QUOTE)
            value = value[:end] if end >= 0 else value
        out.append(value.split(";")[0])
    return out


def pair_value(source, name):
    """The value one pair carries, read only when it is one of the words the switch reads."""
    for one in source.split("&"):
        if one.split("=", 1)[0] == name:
            value = one.split("=", 1)[1]
            return value if value in MARK_BRANCHES else ""
    return ""


def keys_in_answer(payload):
    """The key names the answer carried, in the order the answer wrote them, not filtered by the
    shape. A name the shape writes nowhere is the half the rule reports, so the record has to carry
    it rather than leave it out.
    """
    try:
        document = json.loads(payload)
    except ValueError:
        return []
    return list(document) if isinstance(document, dict) else []


def answer_of(status, keys, mark):
    """The answer the run saw: the name the dispatch case answered on, or the status when the port
    wrote something other than a document of this path.
    """
    if status != 200 or not keys or keys[0] not in BASE:
        return "status " + str(status)
    if mark:
        return "dispatch: mark=" + mark
    named = [key for key in keys if key not in BASE]
    return "dispatch: " + named[0] if named else "dispatch: default"


def call_of(path, names, pairs, mark):
    """The call as the set names it, read from the path the client sent to, with the branch it
    takes.

    The head name is read from the merged form, not from the bare query names, because the dispatch
    takes `mark` from the merged read: the run sent `?api&&mark=item&as=read&id=1`, where `mark` is
    a pair, so the call the record names for that line is the branch the switch ran on.
    """
    head = next((one for one in names + pairs if one in KEYS), None)
    base = path.split("?")[0].strip("/") or "the root"
    if head is None:
        return base + "/?api"
    if head == "mark":
        return base + "/mark/" + mark if mark else base + "/mark"
    item = next((one for one in pairs if one in ITEM_PARAMS), None)
    return base + "/" + head + "/" + item if item else base + "/" + head


def main():
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
    import threading

    # Counted per request, not per connection, because a client that keeps its connections open
    # sends several requests on one connection, and the record says the order the requests arrived
    # at. The lock keeps the lines in that order when two connections are open at once.
    lock = threading.Lock()
    seen = [0]

    class Observer(BaseHTTPRequestHandler):
        # Written as HTTP/1.1 with the length stated by this half, because the headers copied from
        # the answer can carry the framing the answer used, which is what makes a client see an
        # incomplete message: the hop-by-hop names are not forwarded.
        protocol_version = "HTTP/1.1"

        def do_POST(self):
            self.forward("POST")

        def do_GET(self):
            self.forward("GET")

        def forward(self, method):
            with lock:
                seen[0] += 1
                order = seen[0]
            query = self.path.split("?", 1)[1] if "?" in self.path else ""
            body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode("utf-8",
                                                                                       "replace")
            names, pairs = read_pairs(query)
            pairs = pairs + part_names(body)
            connection = http.client.HTTPConnection("127.0.0.1", TARGET_PORT)
            connection.request(method, self.path, body.encode("utf-8"), dict(self.headers))
            response = connection.getresponse()
            payload = response.read()
            self.send_response(response.status)
            for name, value in response.getheaders():
                if name.lower() in HOP_BY_HOP:
                    continue
                self.send_header(name, value)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

            mark = pair_value(query, "mark") or pair_value(body, "mark")
            carried = keys_in_answer(payload.decode("utf-8", "replace"))
            line = " | ".join((CLIENT, str(order), call_of(self.path, names, pairs, mark), method,
                               answer_of(response.status, carried, mark), " ".join(carried),
                               " ".join(sorted(set(pairs))) or "none"))
            with lock:
                with open(RECORD, "a", encoding="utf-8") as handle:
                    handle.write(line + "\n")

    server = ThreadingHTTPServer(("127.0.0.1", OBSERVE_PORT), Observer)
    print(f"observing 127.0.0.1:{OBSERVE_PORT}, forwarding to 127.0.0.1:{TARGET_PORT}, "
          f"writing {RECORD}", file=sys.stderr)
    server.serve_forever()


if __name__ == "__main__":
    main()
