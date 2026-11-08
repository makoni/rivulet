#!/usr/bin/env python3
"""The stub the run serves the corpus from: it writes one response name twice, on purpose.

The header rule reads a name that appears twice as the list of its values in the order they arrive,
which is what `Header.Get` reads through. A stub that writes a name once — and `python3 -m
http.server` writes none at all — leaves that rule nothing to read on run data, so the stub is the
half that makes the rule reachable there. The value each side acted on is recorded with the
response,
which is what the rule compares the first value against.

Run it through `Scripts/parity.sh`; it is not a check and it asserts nothing.
"""

import http.server
import os
import sys

CORPUS = os.environ["PARITY_CORPUS"]
NAME = "X-Trace"
VALUES = ["one", "two"]


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        path = os.path.join(CORPUS, os.path.basename(self.path))
        if not os.path.isfile(path):
            self.send_response(404)
            self.send_header(NAME, VALUES[0])
            self.send_header(NAME, VALUES[1])
            self.end_headers()
            return
        body = open(path, "rb").read()
        self.send_response(200)
        self.send_header("Content-Type", "application/rss+xml")
        self.send_header(NAME, VALUES[0])
        self.send_header(NAME, VALUES[1])
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *parts):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1])
    http.server.HTTPServer(("127.0.0.1", port), Handler).serve_forever()
