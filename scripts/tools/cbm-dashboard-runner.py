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
    def record(message):
        log.write((message + "\n").encode("utf-8", errors="replace"))

    record("Starting persistent CBM UI session: {} --ui=true --port={}".format(binary, port))
    try:
        child = subprocess.Popen(
            [binary, "--ui=true", "--port=" + port],
            stdin=subprocess.PIPE,
            stdout=log,
            stderr=log,
            start_new_session=True,
        )
    except OSError as error:
        record("ERROR: could not launch CBM UI session: {}".format(error))
        log.close()
        return 1
    record("CBM UI session process started: {}".format(child.pid))

    def stop(_signal, _frame):
        if child.poll() is None:
            child.terminate()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        status = child.wait()
        record("CBM UI session exited with status {}".format(status))
        return status
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
