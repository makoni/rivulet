#!/usr/bin/env python3
"""The run's console half for the client run: it gives the two commands a terminal.

Same shape as `Tools/smoke/console_feed.py`: `create-admin` and `integration-credentials` read the
password through the secure path, which answers nothing on a pipe, so the run attaches a pty and
writes the values it declares in the order each command reads its prompts. It asserts nothing; it
prints what the commands said, which is what the run records.

The secure path is narrower than a terminal on stdin: the dependency reads the passphrase from the
process's controlling terminal, not from stdin, so the pty has to be the child's controlling
terminal for the read to answer. That is what this half does, in its own session, which is why a run
that only redirects a pty to stdin reports the minimum length rule before any row is written.

Usage: CLIENT_FEED="<name>\n<password>" python3 Tools/clients/feed_prompts.py <binary> <args...>
"""

import fcntl
import os
import pty
import select
import subprocess
import sys
import time

FEED = os.environ["CLIENT_FEED"].split("\n")
GAP = float(os.environ.get("CLIENT_FEED_GAP", "1"))
TIMEOUT = float(os.environ.get("CLIENT_READ_TIMEOUT", "30"))

# The request the kernel uses to make a terminal the controlling terminal of the calling process.
SET_CONTROLLING_TERMINAL = 0x540E


def main(argv):
    master, slave = pty.openpty()
    # The child half is run through this same file so the controlling terminal is set by the process
    # that reads it: a pipe handed to the command is not a controlling terminal, and the secure read
    # answers nothing there.
    inner = [sys.executable, os.path.abspath(__file__)] + argv
    process = subprocess.Popen(inner, stdin=slave, stdout=slave, stderr=slave,
                               env=dict(os.environ, CLIENT_FEED_CHILD="1"))
    os.close(slave)

    time.sleep(float(os.environ.get("CLIENT_PROMPT_WAIT", "2")))
    for value in FEED:
        os.write(master, f"{value}\n".encode("utf-8"))
        time.sleep(GAP)

    out = ""
    deadline = time.time() + TIMEOUT
    while time.time() < deadline:
        ready, _, _ = select.select([master], [], [], 1)
        if not ready:
            break
        try:
            out += os.read(master, 4096).decode("utf-8", "replace")
        except OSError:
            break
    process.wait()
    print(out.strip())
    return 0


def child(argv):
    """The second half of the same half: the process the terminal is made for."""
    os.setsid()
    fcntl.ioctl(0, SET_CONTROLLING_TERMINAL, 0)
    os.execv(argv[0], argv)


if __name__ == "__main__":
    if os.environ.get("CLIENT_FEED_CHILD"):
        child(sys.argv[1:])
        raise SystemExit(0)
    raise SystemExit(main(sys.argv[1:]))
