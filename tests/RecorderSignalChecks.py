"""Exercise actual terminal signals, including an ignored signal from the host."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

from capture_launch_ios import parse_home_proof, start_recording


with tempfile.TemporaryDirectory() as folder:
    logpath = Path(folder) / "recorder.log"
    original = signal.getsignal(signal.SIGINT)
    original_mask = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGINT, signal.SIGTERM})
    process = None
    terminal = None
    try:
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        child = """
import os, signal, sys, time
assert os.isatty(0)
assert os.tcgetpgrp(0) == os.getpgrp() == os.getpid()
assert signal.getsignal(signal.SIGINT) != signal.SIG_IGN
assert not ({signal.SIGINT, signal.SIGTERM} & signal.pthread_sigmask(signal.SIG_BLOCK, set()))
def finish(signum, frame):
    print('finalized', flush=True)
    sys.exit(0)
signal.signal(signal.SIGINT, finish)
print('recording', flush=True)
while True: time.sleep(0.05)
"""
        with logpath.open("w") as logfile:
            process, terminal = start_recording([sys.executable, "-c", child], logfile)
            deadline = time.monotonic() + 5
            while "recording" not in logpath.read_text():
                assert process.poll() is None, logpath.read_text()
                assert time.monotonic() < deadline, "Recorder did not become ready"
                time.sleep(0.01)
            os.write(terminal, b"\x03")
            assert process.wait(timeout=5) == 0
        assert logpath.read_text().splitlines() == ["recording", "finalized"]
        print("Inherited SIGINT ignored and blocked: isolated recorder finalized via terminal Ctrl-C")
    finally:
        signal.signal(signal.SIGINT, original)
        signal.pthread_sigmask(signal.SIG_SETMASK, original_mask)
        if process is not None and process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)
        if terminal is not None:
            os.close(terminal)

# Observed hosted Vision driver output must not corrupt a valid native proof.
frame = {"homeVisible": True, "width": 1206, "height": 2622, "lines": ["Главная", "Нашиды без музыки"]}
output = "IOServiceMatchingfailed for: AppleM2ScalerParavirtDriver\n" + json.dumps(frame) + "\n"
assert parse_home_proof(output) == frame
for invalid in ["driver diagnostic only", json.dumps({**frame, "homeVisible": False}), json.dumps(frame) + "\n" + json.dumps(frame)]:
    try:
        parse_home_proof(invalid)
    except AssertionError:
        pass
    else:
        raise AssertionError("Missing/false/ambiguous Home proof was accepted")
print("PASS: noisy Vision driver output, missing/false/ambiguous native proof rejection")
