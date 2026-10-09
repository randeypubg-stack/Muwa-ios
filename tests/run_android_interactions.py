"""Keep real UI evidence before emulator-runner shuts the device down."""
import os
from pathlib import Path
import subprocess
import sys

result = subprocess.run(["gradle", "-p", "android", ":app:connectedDebugAndroidTest", "--stacktrace"])
output = Path(os.environ["MUWA_ANDROID_OUTPUT"]) / "subtitle-reader"
output.mkdir(parents=True, exist_ok=True)
missing = []
for orientation in ("portrait", "landscape"):
    source = f"/sdcard/Download/muwa-subtitle-review/subtitle-reader-reduced-motion-{orientation}.png"
    capture = subprocess.run(["adb", "pull", source, str(output / f"{orientation}.png")])
    if capture.returncode:
        missing.append(orientation)
if result.returncode:
    sys.exit(result.returncode)
if missing:
    raise SystemExit(f"Passed UI tests did not preserve native subtitle evidence: {missing}")
