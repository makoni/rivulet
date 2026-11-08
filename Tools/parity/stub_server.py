#!/usr/bin/env python3
"""The stub the run serves the corpus from: it writes one response name twice, on purpose.

The header rule reads a name that appears twice as the list of its values in the order they arrive,
which is what `Header.Get` reads through, so writing the name twice is what makes the shape the rule
reads exist on a run. But the pair document carries the response each side answered the collector
with, and the fetch hop this stub answers is not in it, so on run data the value the rule compares
is written from the same read as the list it reads, and only crafted data can fire the rule. The
value each side acted on is recorded with the response, which is what the rule compares the first
value against.

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
