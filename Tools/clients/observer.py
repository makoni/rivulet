#!/usr/bin/env python3
"""A logging reverse proxy for manual client checks.

It listens on OBSERVE_HOST:OBSERVE_PORT, forwards every request to the Rivulet server on
TARGET_HOST:TARGET_PORT, and appends one JSON line per request to RECORD: the arrival order, the
method, the path, the query parameter names, the form field names, the response status, and the
top-level keys of a JSON response. Values are never written, so the record holds no credentials
or feed content.

`Scripts/client-run.sh` starts it; it can also be run on its own:

    RECORD=record.jsonl OBSERVE_PORT=8099 TARGET_PORT=8098 python3 Tools/clients/observer.py
"""

import http.client
import http.server
import itertools
import json
import os
import threading
import urllib.parse

RECORD = os.environ.get("RECORD", "client-record.jsonl")
OBSERVE_HOST = os.environ.get("OBSERVE_HOST", "0.0.0.0")
OBSERVE_PORT = int(os.environ.get("OBSERVE_PORT", "8099"))
TARGET_HOST = os.environ.get("TARGET_HOST", "127.0.0.1")
TARGET_PORT = int(os.environ.get("TARGET_PORT", "8098"))

HOP_BY_HOP = {"connection", "keep-alive", "proxy-connection", "transfer-encoding", "upgrade", "te",
              "trailer", "proxy-authenticate", "proxy-authorization"}

order = itertools.count(1)
lock = threading.Lock()


def form_names(content_type, body):
    """The field names a urlencoded or multipart body carries."""
    if content_type.startswith("application/x-www-form-urlencoded"):
        return sorted({name for name, _ in urllib.parse.parse_qsl(body.decode("utf-8", "replace"),
                                                                    keep_blank_values=True)})
    if content_type.startswith("multipart/form-data"):
        names = set()
        for line in body.decode("utf-8", "replace").splitlines():
            if line.lower().startswith("content-disposition:") and "name=" in line:
                names.add(line.split("name=", 1)[1].split(";", 1)[0].strip().strip('"'))
        return sorted(names)
    return []


def json_keys(content_type, payload):
    """The top-level keys of a JSON response, or of its first element when it is a list."""
    if "json" not in content_type:
        return []
    try:
        document = json.loads(payload)
    except ValueError:
        return []
    if isinstance(document, list):
        document = document[0] if document else {}
    return list(document.keys()) if isinstance(document, dict) else []


class Proxy(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def forward(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        headers = {name: value for name, value in self.headers.items() if name.lower() not in HOP_BY_HOP}

        connection = http.client.HTTPConnection(TARGET_HOST, TARGET_PORT, timeout=60)
        connection.request(self.command, self.path, body=body, headers=headers)
        response = connection.getresponse()
        payload = response.read()
        connection.close()

        self.send_response(response.status, response.reason)
        for name, value in response.getheaders():
            if name.lower() not in HOP_BY_HOP and name.lower() != "content-length":
                self.send_header(name, value)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(payload)

        url = urllib.parse.urlsplit(self.path)
        line = {
            "order": next(order),
            "method": self.command,
            "path": url.path,
            "query": sorted({name for name, _ in urllib.parse.parse_qsl(url.query, keep_blank_values=True)}),
            "form": form_names(self.headers.get("Content-Type", ""), body),
            "status": response.status,
            "keys": json_keys(response.getheader("Content-Type", ""), payload),
        }
        with lock, open(RECORD, "a", encoding="utf-8") as record:
            record.write(json.dumps(line) + "\n")

    do_GET = do_POST = do_PUT = do_DELETE = do_PATCH = do_HEAD = forward

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    server = http.server.ThreadingHTTPServer((OBSERVE_HOST, OBSERVE_PORT), Proxy)
    print(f"observing {OBSERVE_HOST}:{OBSERVE_PORT} -> {TARGET_HOST}:{TARGET_PORT}, record {RECORD}", flush=True)
    server.serve_forever()
