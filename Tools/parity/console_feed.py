#!/usr/bin/env python3
"""The run's console half: it gives one command a terminal, because the secure read reads from one.

`create-admin` reads the username as plain input and the password as the secure input. On a pipe the
secure path answers nothing, so the min-length rule reports the run before any row is written — that
is what the first live execution of this harness showed. Nothing in a pair document can state which
device the run's read took its value from, so the guard that reads the account name cannot tell a
run that fed a terminal from a run that fed a pipe.

The port has no environment path for an account: the reference reads `ADMIN_USERNAME` and
`ADMIN_PASSWORD` on the daemon branch only, and that half is not ported. So a terminal is the one
way the run can create the account on the port side through the command itself, which is the
reference's own shape for this command — `askCredentials` asks for an interactive terminal, and this
port's console seam has no check for one.

Usage: run through `Scripts/parity.sh`, which sets the environment this reads. It asserts nothing.
"""

import os
import pty
import select
import sys
import time

BINARY = os.environ["RIVULET_BINARY"]
COMMAND = os.environ["RIVULET_COMMAND"].split()
FEED = [os.environ["PARITY_USER"], os.environ["PARITY_PASSWORD"]]


def drain(master, seconds):
    """Read what the command wrote, so the run reports what it said rather than nothing."""
    end = time.time() + seconds
    while time.time() < end:
        ready, _, _ = select.select([master], [], [], 0.2)
        if not ready:
            continue
        try:
            chunk = os.read(master, 4096)
        except OSError:
            return
        if not chunk:
            return
        sys.stdout.write(chunk.decode(errors="replace"))
        sys.stdout.flush()


def main():
    pid, master = pty.fork()
    if pid == 0:
        os.execv(BINARY, [os.path.basename(BINARY)] + COMMAND)

    drain(master, 2)
    for name in FEED:
        os.write(master, (name + "\n").encode())
        drain(master, 2)
    status = os.waitpid(pid, 0)[1]
    return 1 if status else 0


if __name__ == "__main__":
    raise SystemExit(main())
