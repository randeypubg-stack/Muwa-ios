"""Record the actual native iOS cold-launch reveal in an installed Simulator app.

Run from the repository root after building the review app:
    python3 tests/capture_launch_ios.py

The review build uses its normal native intro for --audit-launch and restores a
guest session. This script never synthesizes frames or waits for artwork/network
fixtures. It preserves recording logs and status.json even when capture fails.
"""
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import struct
import subprocess
import time


PACKAGE = "app.muwa.nasheeds"
OUTPUT = Path("build/previews/launch")
APP_FOLDER = Path("build/PreviewDerivedData/Build/Products/Debug-iphonesimulator")


def validate_png(path):
    header = path.read_bytes()[:24]
    if not header.startswith(b"\x89PNG\r\n\x1a\n") or len(header) != 24:
        raise AssertionError(f"Invalid native screenshot: {path.name}")
    width, height = struct.unpack(">II", header[16:24])
    if min(width, height) < 100:
        raise AssertionError(f"Unexpected native screenshot size: {width}x{height}")
    return {"width": width, "height": height}


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    status = {"captured": False, "package": PACKAGE, "commands": []}
    recorder = None
    recorder_log = None
    udid = None
    booted_here = False

    def run(*args, timeout=45):
        command = [str(arg) for arg in args]
        print("Running:", " ".join(command), flush=True)
        result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=timeout)
        status["commands"].append({"command": command, "exit_code": result.returncode,
                                   "output": result.stdout[-4000:]})
        if result.returncode:
            raise RuntimeError(f"Command failed ({result.returncode}): {' '.join(command)}\n{result.stdout[-4000:]}")
        return result.stdout

    def stop_recording():
        nonlocal recorder
        if recorder is None:
            return
        if recorder.poll() is None:
            recorder.send_signal(signal.SIGINT)
            try:
                recorder.wait(timeout=15)
            except subprocess.TimeoutExpired:
                recorder.terminate()
                try:
                    recorder.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    recorder.kill()
                    recorder.wait(timeout=5)
                raise RuntimeError("Simulator recorder did not finish after SIGINT")
        status["recorder_exit_code"] = recorder.returncode
        recorder = None

    try:
        apps = list(APP_FOLDER.glob("*.app"))
        if len(apps) != 1:
            raise AssertionError(f"Expected one review app in {APP_FOLDER}, found {len(apps)}")
        app = apps[0]
        info = plistlib.loads((app / "Info.plist").read_bytes())
        if info.get("CFBundleIdentifier") != PACKAGE:
            raise AssertionError("Review app has the wrong bundle identifier")
        status["version"] = info.get("CFBundleShortVersionString")
        status["build"] = info.get("CFBundleVersion")

        devices = json.loads(run("xcrun", "simctl", "list", "devices", "available", "--json"))["devices"]
        phones = [device for group in devices.values() for device in group
                  if device.get("isAvailable") and device["name"].startswith("iPhone")]
        requested = os.environ.get("MUWA_LAUNCH_DEVICE")
        phone = next((device for device in phones
                      if not requested or requested in (device["name"], device["udid"])), None)
        if phone is None:
            raise AssertionError(f"No available iPhone simulator for {requested or 'launch review'}")
        udid = phone["udid"]
        status["device"] = {"name": phone["name"], "udid": udid}
        if phone["state"] != "Booted":
            run("xcrun", "simctl", "boot", udid)
            booted_here = True
        run("xcrun", "simctl", "bootstatus", udid, "-b", timeout=240)
        run("xcrun", "simctl", "ui", udid, "appearance", "dark")
        run("xcrun", "simctl", "install", udid, app, timeout=180)

        # A warm, idle Simulator avoids recording SpringBoard animations as Muwa.
        run("xcrun", "simctl", "launch", "--terminate-running-process", udid, PACKAGE, "--audit-home")
        time.sleep(1.5)
        run("xcrun", "simctl", "terminate", udid, PACKAGE)
        time.sleep(0.25)
        video = OUTPUT / "muwa-native-launch.mp4"
        video.unlink(missing_ok=True)
        log_path = OUTPUT / "recording.log"
        recorder_log = log_path.open("w")
        recording_start = time.monotonic()
        recording_command = ["xcrun", "simctl", "io", udid, "recordVideo", "--codec=h264", str(video)]
        recorder = subprocess.Popen(recording_command, stdout=recorder_log, stderr=subprocess.STDOUT)
        status["recording_command"] = recording_command
        # Launch only once simctl confirms that the screen recording is active.
        ready_deadline = time.monotonic() + 10
        while "Recording started" not in log_path.read_text():
            if recorder.poll() is not None:
                raise RuntimeError(f"Simulator recorder exited before launch: {log_path.read_text()}")
            if time.monotonic() >= ready_deadline:
                raise RuntimeError(f"Simulator recorder never became ready: {log_path.read_text()}")
            time.sleep(0.1)
        launch_offset = time.monotonic() - recording_start
        response = run("xcrun", "simctl", "launch", "--terminate-running-process", udid, PACKAGE, "--audit-launch")
        pid_match = re.search(r":\s*(\d+)\s*$", response)
        if pid_match is None:
            raise AssertionError(f"Simulator did not report Muwa's PID: {response}")
        status["launch_pid"] = int(pid_match.group(1))
        status["launch_offset_seconds"] = round(launch_offset, 3)
        time.sleep(3)
        if recorder.poll() is not None:
            raise RuntimeError("Simulator recorder exited during the launch animation")
        # Simulator app processes run on the host; this catches a startup crash.
        os.kill(status["launch_pid"], 0)
        final = OUTPUT / "home-after-launch.png"
        run("xcrun", "simctl", "io", udid, "screenshot", final)
        status["final_screen"] = validate_png(final)
        stop_recording()
        recorder_log.close()
        recorder_log = None
        status["recording_duration_seconds"] = round(time.monotonic() - recording_start, 3)
        if not video.exists() or video.stat().st_size < 10000:
            raise AssertionError("Native launch video is empty or truncated")
        with video.open("rb") as stream:
            if b"ftyp" not in stream.read(64):
                raise AssertionError("Native recording is not a valid MP4 container")
        status["video_bytes"] = video.stat().st_size

        # Extract real recorded frames only when ffmpeg is present on the runner.
        ffmpeg = shutil.which("ffmpeg")
        if ffmpeg:
            frames = []
            for label, offset in [("reveal", 0.25), ("sheen", 0.60), ("home", 1.80)]:
                frame = OUTPUT / f"recorded-{label}.png"
                timestamp = launch_offset + offset
                run(ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-ss", f"{timestamp:.3f}",
                    "-i", video, "-frames:v", "1", frame)
                frames.append({"file": frame.name, "video_time_seconds": round(timestamp, 3),
                               **validate_png(frame)})
            status["recorded_frames"] = frames
        else:
            status["recorded_frames"] = "ffmpeg unavailable; inspect the original native MP4"
        status["captured"] = True
        print(f"Captured native Muwa launch on {phone['name']}: {video}", flush=True)
    except Exception as error:
        status["error"] = {"type": type(error).__name__, "message": str(error)}
        raise
    finally:
        try:
            stop_recording()
        except Exception as error:
            status["cleanup_error"] = str(error)
        if recorder_log is not None:
            recorder_log.close()
        if booted_here and udid:
            try:
                run("xcrun", "simctl", "shutdown", udid)
            except Exception as error:
                status["shutdown_error"] = str(error)
        (OUTPUT / "status.json").write_text(json.dumps(status, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
