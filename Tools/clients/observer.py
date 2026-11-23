#!/usr/bin/env python3
"""The run's observing half for the client run: it writes one record line per request it forwarded.

It asserts nothing. It listens on the port the run declares, forwards every request to the port
the run names, and writes what each request looked like as it arrived: the order it arrived in,
the path the client sent to, the call as the recorded set names it, the method, the answer the
port gave, the key names the answer carried, and the field names the request carried. The answer
is written as the run saw it — the name the dispatch case answered on when the port wrote a
document of this path, and the status when it wrote something else — so the record says what
happened rather than what the matrix expected to see, which is what lets the check half read the
record against the matrix and report a run that answered differently. On the half whose calls the
check half reads through the tolerance table the run answered on the other side, so the answer is the
pattern that side registers for the path, which is the name the set has for the call, and the status
when the handler answered something other than its document. The side the run answered on is the value
the run half declares for its target, read as the set names it for the half, so this half and the
check half use one name for it.

The order column is the order the requests arrived at, counted per request rather than per
connection, because a client that keeps its connections open sends several requests on one
connection. The name order is part of what the record says: the key names are the names the
answer carried, in the order the answer wrote them, and the call name is read from the path the
client used, not from a prefix this half assumes, because a client can send to a path this port
registers no route for.

The record carries no value. The names the merged form gives are read as the transport chooses
which side it reads: the pair names from the query, and from the body only when the body is read
as a form, which is only for the methods the reference reads a body form for — pair names for a
urlencoded body, quoted or unquoted part names for a multipart one, which is the read PR #61
pins. A record line is exempt from the width rule because it is one record.

Usage: CLIENT_RECORD=<the file the run writes> CLIENT_NAME=<the client the run names>
CLIENT_HOST=<the address the client was given> CLIENT_OBSERVE_PORT=<the port the client is
pointed at> CLIENT_TARGET_PORT=<the port the run serves on> CLIENT_TARGET=<the side the set names
for the half the run answered on> python3 Tools/clients/observer.py

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
# The side the run answered on, as the run half names it: this port, or the reference. The answer a
# record line carries is read against the side the run answered on, which is what makes a run on the
# reference a run whose answers are read through the tolerance table rather than against this port's
# handler.
TARGET = os.environ.get("CLIENT_TARGET", "port")
# The address the client was given. A client on another device reaches the observer through it, so
# the run half reads it as the value it declares for the client and binds this half on it.
HOST = os.environ.get("CLIENT_HOST", "127.0.0.1")
QUOTE = chr(34)

# The set the check half reads for the client the run names, read through the same reader, so the
# record names the call, the path and the pair the way the rule reads them. The path the set reads
# the client on decides which half writes the answer: the path that dispatches names the case it
# answered on, and the path that answers on a route names the registration the file writes, or the
# catch-all the matrix names it with.
SET = read.set_for(CLIENT)
API = SET["api"]
TOKEN = SET["redaction"]["token"]
ROUTES = read.port_routes(read.read(read.DEFAULTS["port_routes"]))
# The name the record writes for the pair when the transport reads the token as a header rather than
# as a field, which is the half the redaction names and no value can show.
TOKEN_FROM_HEADER = any(call["auth"] == "header" for call in SET["calls"])
BRANCH_FIELD, BRANCH_MARK = "s", "#"

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


def form_names(method, body, content_type):
    """The names the merged form gives, read as the transport chooses which side it reads: the pair
    names for a urlencoded body, the part names for a multipart body, and nothing for a body the
    transport does not read as a form, the urlencoded half running only for the methods the
    reference reads a body form for, which is the guard `FeverForm.readsBodyHalf` pins. No value
    is read here, only the names.
    """
    if "multipart/form-data" in content_type:
        return part_names(body)
    if method in ("POST", "PUT", "PATCH") and "application/x-www-form-urlencoded" in content_type:
        return [pair.split("=", 1)[0] for pair in body.split("&") if pair]
    return []


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


def answer_of(status, method, base, keys, mark, call):
    """The answer the run saw: the name the dispatch case answered on for the path that dispatches,
    the registration the file writes for the path that answers on a route, the catch-all as the
    matrix names it for a path this port registers no route for, and the status when the port
    wrote something other than an answer of this path. On the half whose calls are read through the
    tolerance table the run answered on the other side, so the answer is the pattern that side
    registers for the path, which is the name the set has for the call, and the status when the
    handler answered something other than its document.
    """
    if status != 200:
        return "status " + str(status)
    if read.half_for(CLIENT, call)["calls_read"] == read.TOLERANCE_READ:
        return call
    if API == "google-reader":
        route = next((one for one in ROUTES if one.startswith(method) and one.endswith("/" + base)),
                     None)
        return route or ("catch-all" if f"catch-all {method}" in ROUTES else "status " + str(status))
    if not keys or keys[0] not in BASE:
        return "status " + str(status)
    if mark:
        return "dispatch: mark=" + mark
    named = [key for key in keys if key not in BASE]
    return "dispatch: " + named[0] if named else "dispatch: default"


def call_of(path, names, mark, method):
    """The call as the set names it, read from the path the client sent to, with the branch it
    takes.

    The head name is read from the merged form, not from the bare query names, because the
    dispatch takes `mark` from the merged read: the run sent `?api&&mark=item&as=read&id=1`,
    where `mark` is a pair, so the call the record names for that line is the branch the switch
    ran on. For the path that answers on a route the name is the path, with the branch the merged
    form gives written as the set names that branch. On the half whose calls are read through the
    tolerance table the set names the call as the pattern the other side registers, which carries
    the method, so the segment the pattern writes as a placeholder is read as the value the client
    sent and the record names the pattern rather than the concrete id.
    """
    base = path.split("?")[0].strip("/") or "the root"
    if read.half_for(CLIENT, base)["calls_read"] == read.TOLERANCE_READ:
        return read.call_for(CLIENT, method, path)
    if API == "google-reader":
        return next((one for one in (call["key"] for call in SET["calls"])
                     if BRANCH_MARK in one and one.split(BRANCH_MARK)[0] == base
                     and BRANCH_FIELD in names), None) or base
    head = next((one for one in names if one in KEYS), None)
    if head is None:
        return base + "/?api"
    if head == "mark":
        return base + "/mark/" + mark if mark else base + "/mark"
    item = next((one for one in names if one in ITEM_PARAMS), None)
    return base + "/" + head + ("/" + item if item else "")


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

        # The methods the reference registers routes for on the half a set names as answered here:
        # a client that writes through that half sends them, so this half has to answer them rather
        # than refuse them, which is what left the walk with no record line for a write on that half.
        def do_PUT(self):
            self.forward("PUT")

        def do_DELETE(self):
            self.forward("DELETE")

        def do_PATCH(self):
            self.forward("PATCH")

        def forward(self, method):
            with lock:
                seen[0] += 1
                order = seen[0]
            query = self.path.split("?", 1)[1] if "?" in self.path else ""
            body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode("utf-8",
                                                                                       "replace")
            names, pairs = read_pairs(query)
            pairs = pairs + form_names(method, body, self.headers.get("Content-Type", ""))
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

            base = self.path.split("?")[0].strip("/") or "the root"
            mark = pair_value(query, "mark") or pair_value(body, "mark")
            carried = keys_in_answer(payload.decode("utf-8", "replace"))
            fields = sorted(set(pairs))
            if TOKEN_FROM_HEADER and "authorization" in self.headers:
                fields = sorted(set(fields) | {TOKEN})
            call = call_of(self.path, names + pairs, mark, method)
            line = " | ".join((CLIENT, str(order), call, method,
                               answer_of(response.status, method, base, carried, mark, call),
                               " ".join(carried), " ".join(fields) or "none"))
            with lock:
                with open(RECORD, "a", encoding="utf-8") as handle:
                    handle.write(line + "\n")

    server = ThreadingHTTPServer((HOST, OBSERVE_PORT), Observer)
    print(f"observing {HOST}:{OBSERVE_PORT}, forwarding to 127.0.0.1:{TARGET_PORT}, "
          f"writing {RECORD}", file=sys.stderr)
    server.serve_forever()


if __name__ == "__main__":
    main()
