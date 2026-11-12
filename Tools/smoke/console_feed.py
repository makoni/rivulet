#!/usr/bin/env python3
"""The run's console half for the clean container: it gives the command a terminal.

`create-admin` reads the username as plain input and the password as the secure input. On a pipe the
secure path answers nothing, which is what the parity harness's first live run showed, so a scratch
container cannot create the account through a pipe, and the port has no environment path for an
account: the reference reads `ADMIN_USERNAME` only on its daemon branch, which is not ported. A
terminal is therefore the one way the run creates the account through the command itself.

It asserts nothing. It takes the docker call as its arguments, attaches a pty to the call's stdin,
writes the values the run declares in the order the command reads its prompts, and prints what the
command said, which is the answer the run records.
"""

import os
import pty
import select
import subprocess
import sys
import time

FEED = os.environ["SMOKE_FEED"].split("\n")


def main(argv):
    master, slave = pty.openpty()
    process = subprocess.Popen(argv, stdin=slave, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True)
    os.close(slave)

    time.sleep(float(os.environ.get("SMOKE_PROMPT_WAIT", "2")))
    for value in FEED:
        os.write(master, f"{value}\n".encode("utf-8"))
        time.sleep(float(os.environ.get("SMOKE_FEED_GAP", "1")))

    out = ""
    deadline = time.time() + float(os.environ.get("SMOKE_READ_TIMEOUT", "30"))
    while time.time() < deadline:
        ready, _, _ = select.select([process.stdout], [], [], 1)
        if not ready:
            break
        line = process.stdout.readline()
        if not line:
            break
        out += line
    process.wait(timeout=15)
    print(out.strip())
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
