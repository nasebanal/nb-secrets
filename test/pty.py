#!/usr/bin/env python3
"""Run a command in a pseudo-terminal and type lines into it (test helper for run.sh).

usage: printf 'line1\nline2\n' | pty.py <command> [args...]

Each stdin line is typed after the command has been quiet for a moment, so prompts that switch
the terminal mode (hidden input) do not discard it. Output goes to stdout; the exit status is
the command's. Nothing here is specific to nb-secrets.
"""
import os
import pty
import select
import sys
import time

if len(sys.argv) < 2:
    sys.exit("usage: pty.py <command> [args...]")

lines = [] if sys.stdin.isatty() else sys.stdin.read().splitlines(keepends=True)
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[1], sys.argv[1:])

out = bytearray()
deadline = time.time() + 30


def drain(idle):
    """Read until the child is quiet for `idle` seconds. False once the child has gone."""
    while time.time() < deadline:
        ready, _, _ = select.select([fd], [], [], idle)
        if not ready:
            return True
        try:
            data = os.read(fd, 4096)
        except OSError:
            return False
        if not data:
            return False
        out.extend(data)
    return False


alive = drain(0.4)
for line in lines:
    if not alive:
        break
    os.write(fd, line.encode())
    alive = drain(0.4)
while alive:
    alive = drain(0.5)

sys.stdout.buffer.write(bytes(out))
sys.stdout.flush()
_, status = os.waitpid(pid, 0)
sys.exit(os.waitstatus_to_exitcode(status))
