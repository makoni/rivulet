#!/usr/bin/env python3
"""The stub the clean container fetches from: it answers the corpus files, and it holds one of them.
It asserts nothing and is not a check. The held file is what makes a round be mid-way when the run
stops the container: the run declares which file it holds and for how long, and the check half reads
the declaration as the run's own, because nothing in the document can say that a fetch was still in
flight. It writes one line per event to the event file in the order the events happened — the
request and, once the response is written, the answer for it — which is the record the run reads to
know the round had the held file still open when it took the snapshot of the rows. Run it through
`Scripts/smoke.sh`, which sets the environment this reads.
"""

import http.server
import os
import time

CORPUS = os.environ["SMOKE_CORPUS"]
EVENTS = os.environ["SMOKE_EVENTS"]
HELD = os.environ["SMOKE_HELD_FILE"]
HELD_SECONDS = int(os.environ["SMOKE_HELD_SECONDS"])


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def record(self, action, name, held):
        with open(EVENTS, "a", encoding="utf-8") as handle:
            handle.write(f"{time.time():.3f} {action} {name}{' held' if held else ''}\n")

    def do_GET(self):
        name = os.path.basename(self.path)
        path = os.path.join(CORPUS, name)
        if not os.path.isfile(path):
            self.record("miss", name, False)
            self.send_response(404)
            self.end_headers()
            return

        held = name == HELD
        self.record("request", name, held)
        if held:
            time.sleep(HELD_SECONDS)

        body = open(path, "rb").read()
        self.send_response(200)
        self.send_header("Content-Type", "application/rss+xml")
        self.end_headers()
        self.wfile.write(body)
        self.record("answered", name, held)


if __name__ == "__main__":
    http.server.ThreadingHTTPServer(("127.0.0.1", int(os.environ["SMOKE_STUB_PORT"])),
                                    Handler).serve_forever()
