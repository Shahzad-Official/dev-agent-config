#!/usr/bin/env python3
"""Keep the CBM stdio process alive for its loopback UI; managed by the shell adapter."""
import signal
import subprocess
import sys


def main():
    if len(sys.argv) != 5:
        raise SystemExit("usage: cbm-dashboard-runner.py BINARY PORT LOG NONCE")
    binary, port, log_path, _nonce = sys.argv[1:]
    log = open(log_path, "ab", buffering=0)
    child = subprocess.Popen(
        [binary, "--ui=true", "--port=" + port],
        stdin=subprocess.PIPE,
        stdout=log,
        stderr=log,
        start_new_session=True,
    )

    def stop(_signal, _frame):
        if child.poll() is None:
            child.terminate()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        return child.wait()
    finally:
        if child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
        if child.stdin:
            child.stdin.close()
        log.close()


if __name__ == "__main__":
    raise SystemExit(main())
