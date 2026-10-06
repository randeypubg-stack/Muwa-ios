"""Capture the real free subtitle rail, with a bounded disposable review clock.

Run after unpacking the simulator-review app produced by prepare_previews.py:
    python3 tests/capture_subtitle_motion.py

MUWA_REVIEW_DEVICE and MUWA_REVIEW_RUNTIME_VERSION select the actual stable
simulator. No frames are synthesized, no ASR is requested, and no Simulator GUI
appearance RPC is needed. PID-scoped handshakes hold each subtitle checkpoint
until its original simulator framebuffer has been saved.
"""
import argparse
import copy
import hashlib
import json
import math
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import time

from capture_launch_ios import (command_output_summary, finish_recording,
                                start_recording, validate_png, validate_video,
                                wait_recording_ready)
from select_apple_review_devices import KINDS, load_selection


PACKAGE = "app.muwa.nasheeds"
PROOF_PREFIX = "subtitle-motion-"


def verify_frame(frame, pid):
    keys = ("x", "y", "width", "height", "screenWidth", "screenHeight")
    if frame.get("pid") != pid:
        raise AssertionError("Native subtitle layout belongs to a stale app process")
    if any(not isinstance(frame.get(key), (int, float)) or not math.isfinite(frame[key]) for key in keys):
        raise AssertionError("Native subtitle rail has no finite actual layout bounds")
    if (min(frame["width"], frame["height"]) < 60 or min(frame["screenWidth"], frame["screenHeight"]) < 200
            or min(frame["x"], frame["y"]) < -1
            or frame["x"] + frame["width"] > frame["screenWidth"] + 1
            or frame["y"] + frame["height"] > frame["screenHeight"] + 1):
        raise AssertionError("Actual subtitle rail is clipped outside its native viewport")


def verify_runtime_proof(ready, rail, clock, finished, frame, pid):
    """Verify observed UI indices and isolated clock ticks, not source strings."""
    objects = [ready, finished, frame, *rail, *clock]
    if not objects or any(item.get("pid") != pid for item in objects):
        raise AssertionError("Motion proof contains a different or stale app process")
    if ready.get("count") != 5 or ready.get("duration") != 25:
        raise AssertionError("Ordinary five-line caption fixture did not become ready")
    for item in [ready, finished, *rail]:
        if item.get("source") != "ordinary-manual-captions" or item.get("aiOptIn") is not False:
            raise AssertionError("Motion review must exercise free ordinary captions without AI")
    indices = []
    for item in rail:
        index, timestamp = item.get("activeIndex"), item.get("time")
        if (not isinstance(index, int) or index not in range(5) or item.get("count") != 5
                or item.get("managerActiveIndex") != index
                or not isinstance(timestamp, (float, int)) or not math.isfinite(timestamp)
                or not index * 5 <= timestamp < (index + 1) * 5):
            raise AssertionError("Mounted native rail index does not match its playback time")
        if item.get("reduceMotion") is not False:
            raise AssertionError("Native animation review requires Reduce Motion to be disabled")
        if not indices or indices[-1] != index:
            indices.append(index)
    if indices != list(range(5)):
        raise AssertionError(f"Mounted rail skipped or rewound captions: {indices}")
    if len(clock) != 125 or finished.get("ticks") != 125:
        raise AssertionError("The bounded 125-tick motion clock did not finish")
    for tick, item in enumerate(clock):
        if (item.get("tick") != tick or item.get("duration") != 25
                or not math.isclose(item.get("time", -1), tick * 0.2, abs_tol=1e-8)
                or item.get("broadNotificationsDuringTick") != 0
                or item.get("trackId") != "muwa-01" or item.get("isPlaying") is not False):
            raise AssertionError(f"Clock tick {tick} was stale, overwritten, or invalidated PlayerManager")
    if (finished.get("duration") != 25 or not math.isclose(finished.get("time", -1), 24.8, abs_tol=1e-8)
            or finished.get("broadNotificationsDuringTicks") != 0 or finished.get("isPlaying") is not False):
        raise AssertionError("Motion clock did not retain its final isolated paused snapshot")
    verify_frame(frame, pid)
    return {"observedActiveIndices": indices, "clockTicks": len(clock),
            "broadNotificationsDuringTicks": 0, "ordinaryCaptionSource": True,
            "aiOptIn": False, "railInsideNativeViewport": True,
            "finalTime": finished["time"], "reduceMotion": False}


def self_test():
    pid = 101
    ready = {"pid": pid, "count": 5, "duration": 25,
             "source": "ordinary-manual-captions", "aiOptIn": False}
    rail = [{**ready, "activeIndex": index, "managerActiveIndex": index,
             "time": index * 5, "reduceMotion": False}
            for index in range(5)]
    clock = [{"pid": pid, "tick": tick, "duration": 25, "time": tick * 0.2,
              "broadNotificationsDuringTick": 0, "trackId": "muwa-01", "isPlaying": False}
             for tick in range(125)]
    finished = {**ready, "ticks": 125, "time": 24.8,
                "broadNotificationsDuringTicks": 0, "isPlaying": False}
    frame = {"pid": pid, "x": 210, "y": 250, "width": 110, "height": 160,
             "screenWidth": 402, "screenHeight": 874}
    verify_runtime_proof(ready, rail, clock, finished, frame, pid)
    cases = []
    def case(label, mutate):
        values = copy.deepcopy([ready, rail, clock, finished, frame])
        mutate(values)
        try:
            verify_runtime_proof(*values, pid)
        except AssertionError:
            cases.append(label)
        else:
            raise AssertionError(f"Invalid runtime proof was accepted: {label}")
    case("stale PID", lambda v: v[1][1].update(pid=99))
    case("AI only", lambda v: v[0].update(aiOptIn=True))
    case("missing caption", lambda v: v[1].pop(2))
    case("rewound rail", lambda v: v[1].reverse())
    case("mismatched displayed index", lambda v: v[1][1].update(time=0))
    case("mismatched manager index", lambda v: v[1][1].update(managerActiveIndex=0))
    case("Reduce Motion", lambda v: v[1][1].update(reduceMotion=True))
    case("missing clock tick", lambda v: v[2].pop(2))
    case("AVPlayer overwrote clock", lambda v: v[2][10].update(time=0))
    case("broad player invalidation", lambda v: v[2][10].update(broadNotificationsDuringTick=1))
    case("changed current track", lambda v: v[2][10].update(trackId="muwa-02"))
    case("unexpected live playback", lambda v: v[2][10].update(isPlaying=True))
    case("unfinished clock", lambda v: v[3].update(time=10))
    case("clipped caption bounds", lambda v: v[4].update(x=400))
    case("invalid caption bounds", lambda v: v[4].update(width=float("nan")))
    print(json.dumps({"selfTestsPassed": 1 + len(cases), "rejectedInvalidProofs": cases}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kind", choices=KINDS, default=os.environ.get("MUWA_REVIEW_DEVICE", "phone"))
    parser.add_argument("--app-folder", type=Path,
                        default=Path("build/PreviewDerivedData/Build/Products/Debug-iphonesimulator"))
    parser.add_argument("--output", type=Path, default=Path("build/previews/subtitle-motion"))
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    status = {"schemaVersion": 1, "captured": False, "package": PACKAGE,
              "scope": "Actual Simulator UI with disposable manual captions and isolated review clock; no ASR or physical-device claim",
              "commands": [], "screenshots": []}
    recorder = recorder_input = recorder_log = None
    device = None
    booted_here = False
    data = None

    def run(*argv, timeout=180):
        command = [str(value) for value in argv]
        print("Running:", " ".join(command), flush=True)
        log = output / f"command-{len(status['commands']) + 1:03d}.log"
        try:
            result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, timeout=timeout)
        except subprocess.TimeoutExpired as error:
            text = error.stdout or ""
            if isinstance(text, bytes):
                text = text.decode("utf-8", errors="replace")
            log.write_text(text)
            status["commands"].append({"command": command, "exitCode": None,
                                       "timeoutSeconds": timeout, "log": log.name,
                                       "output": command_output_summary(text)})
            raise RuntimeError(f"Command timed out after {timeout}s: {' '.join(command)}") from error
        log.write_text(result.stdout)
        status["commands"].append({"command": command, "exitCode": result.returncode,
                                   "log": log.name, "output": command_output_summary(result.stdout)})
        if result.returncode:
            raise RuntimeError(f"Command failed ({result.returncode}): {' '.join(command)}\n{result.stdout}")
        return result.stdout

    def stop():
        nonlocal recorder, recorder_input
        try:
            finish_recording(recorder, recorder_input, run, status)
        finally:
            recorder = recorder_input = None

    def wait_json(name, pid, seconds=35):
        deadline = time.monotonic() + seconds
        path = data / "Documents" / name
        error_file = data / "Documents/subtitle-motion-error.json"
        while time.monotonic() < deadline:
            if error_file.exists():
                raise AssertionError(f"Native motion fixture failed: {error_file.read_text()}")
            if path.exists():
                value = json.loads(path.read_text())
                if value.get("pid") == pid:
                    return value
            time.sleep(0.05)
        raise AssertionError(f"Current native process did not produce {name}")

    def acknowledge(name, pid):
        path = data / "Documents" / name
        temporary = path.with_suffix(".pending")
        temporary.write_text(str(pid))
        temporary.replace(path)

    try:
        selected, inventory = load_selection(args.kind, os.environ.get("MUWA_REQUESTED_DEVICE"),
                                             os.environ.get("MUWA_REQUESTED_IOS"),
                                             os.environ.get("MUWA_REVIEW_RUNTIME_VERSION"))
        if len(selected) != 1:
            raise AssertionError("Motion review requires exactly one actual selected Simulator")
        device = selected[0]
        status["device"] = device
        status["toolchain"] = inventory["toolchain"]
        status["requested"] = inventory["requested"]
        (output / "device-inventory.json").write_text(json.dumps(inventory, ensure_ascii=False, indent=2))
        apps = list(args.app_folder.glob("*.app"))
        if len(apps) != 1:
            raise AssertionError(f"Expected one prebuilt review app, found {len(apps)}")
        app = apps[0]
        info = plistlib.loads((app / "Info.plist").read_bytes())
        if info.get("CFBundleIdentifier") != PACKAGE:
            raise AssertionError("Review app has the wrong bundle identifier")
        status.update(version=info.get("CFBundleShortVersionString"), build=info.get("CFBundleVersion"))
        udid = device["udid"]
        if device["state"] != "Booted":
            run("xcrun", "simctl", "boot", udid)
            booted_here = True
        run("xcrun", "simctl", "bootstatus", udid, "-b", timeout=240)
        status["bootstatusCompleted"] = True
        status["appearanceSource"] = "Production Muwa preferredColorScheme(.dark); no Simulator GUI RPC"
        run("xcrun", "simctl", "install", udid, app)
        data = Path(run("xcrun", "simctl", "get_app_container", udid, PACKAGE, "data").strip())
        for path in (data / "Documents").glob(PROOF_PREFIX + "*"):
            if path.is_file():
                path.unlink()
        launch = run("xcrun", "simctl", "launch", "--terminate-running-process", udid,
                     PACKAGE, "--audit-player", "--audit-subtitle-motion")
        match = re.search(r"app\.muwa\.nasheeds:\s*(\d+)", launch)
        if match is None:
            raise AssertionError(f"Simulator did not report Muwa's launched PID: {launch}")
        pid = int(match.group(1))
        status["launchPid"] = pid
        ready = wait_json("subtitle-motion-ready.json", pid)
        mounted = wait_json("subtitle-motion-mounted.json", pid)
        if mounted.get("activeIndex") != 0 or mounted.get("source") != "ordinary-manual-captions":
            raise AssertionError("The free ordinary rail did not mount its first caption")
        video = output / "subtitle-rail-motion.mp4"
        video.unlink(missing_ok=True)
        recording_log_path = output / "recording.log"
        recorder_log = recording_log_path.open("w")
        command = [run("xcrun", "--find", "simctl").strip(), "io", udid,
                   "recordVideo", "--codec=h264", str(video)]
        recorder, recorder_input = start_recording(command, recorder_log)
        status["recordingCommand"] = command
        status["recordingStopMethod"] = "Shared owned-recorder SIGINT finalizer"
        wait_recording_ready(recorder, recording_log_path)
        recording_start = time.monotonic()
        acknowledge("subtitle-motion-start.txt", pid)
        for index in range(5):
            checkpoint = wait_json(f"subtitle-motion-checkpoint-{index}.json", pid)
            if checkpoint.get("expectedIndex") != index or checkpoint.get("time") != 1 + index * 5:
                raise AssertionError("Motion clock reported an unexpected capture checkpoint")
            # The clock remains held until this PNG completes, including slow
            # hosted simctl commands. Allow the real spring to settle first.
            time.sleep(0.5)
            rail_now = wait_json("subtitle-motion-mounted.json", pid)
            if rail_now.get("activeIndex") != index or rail_now.get("managerActiveIndex") != index:
                raise AssertionError(f"Visible native rail did not follow caption {index}")
            frame = wait_json("subtitle-motion-frame.json", pid)
            verify_frame(frame, pid)
            screenshot = output / f"ordinary-rail-{index}.png"
            run("xcrun", "simctl", "io", udid, "screenshot", screenshot)
            status["screenshots"].append({"file": screenshot.name, "activeIndex": index,
                "time": checkpoint["time"], "rail": rail_now, "frame": frame,
                "sha256": hashlib.sha256(screenshot.read_bytes()).hexdigest(), **validate_png(screenshot)})
            if recorder.poll() is not None:
                raise RuntimeError("Recorder exited while the native caption rail was moving")
            acknowledge(f"subtitle-motion-captured-{index}.txt", pid)
        finished = wait_json("subtitle-motion-finished.json", pid)
        status["recordingWallSeconds"] = round(time.monotonic() - recording_start, 3)
        stop()
        recorder_log.close()
        recorder_log = None
        if status.get("recorder_exit_code") != 0:
            raise AssertionError("Native recorder did not finalize successfully")
        status["videoAtoms"] = validate_video(video)
        status["videoBytes"] = video.stat().st_size
        status["videoSha256"] = hashlib.sha256(video.read_bytes()).hexdigest()
        if status["videoBytes"] < 10000:
            raise AssertionError("Native motion recording is empty")
        rail = [json.loads(line) for line in (data / "Documents/subtitle-motion-rail.jsonl").read_text().splitlines()]
        clock = [json.loads(line) for line in (data / "Documents/subtitle-motion-clock.jsonl").read_text().splitlines()]
        frame = wait_json("subtitle-motion-frame.json", pid)
        status["runtimeProof"] = verify_runtime_proof(ready, rail, clock, finished, frame, pid)
        dimensions = {(item["width"], item["height"]) for item in status["screenshots"]}
        if len(dimensions) != 1 or len({item["sha256"] for item in status["screenshots"]}) < 3:
            raise AssertionError("Native caption checkpoint framebuffers are inconsistent or unchanged")
        status["screenPixels"] = {key: status["screenshots"][0][key] for key in ("width", "height")}
        for path in (data / "Documents").glob(PROOF_PREFIX + "*"):
            if path.is_file() and path.suffix in (".json", ".jsonl"):
                shutil.copy2(path, output / path.name)
        os.kill(pid, 0)
        status["appAliveAfterMotion"] = True
        status["captureOutputBytes"] = sum(path.stat().st_size for path in output.rglob("*") if path.is_file())
        if status["captureOutputBytes"] > 31 * 1024 * 1024:
            raise AssertionError("Native motion artifact exceeds the review download budget")
        status["captured"] = True
        print(f"PASS: ordinary subtitle rail on {device['name']} / {device['runtimeName']}; five native PNGs and finalized MP4")
    except Exception as error:
        status["error"] = {"type": type(error).__name__, "message": str(error)}
        raise
    finally:
        try:
            stop()
        except Exception as error:
            status["cleanupError"] = str(error)
        if recorder_log is not None:
            recorder_log.close()
        if data is not None:
            # Preserve fixture diagnostics even on failure; never copy account
            # files, cookies or another app's container.
            for path in (data / "Documents").glob(PROOF_PREFIX + "*"):
                if path.is_file() and path.suffix in (".json", ".jsonl"):
                    shutil.copy2(path, output / path.name)
        if booted_here and device is not None:
            try:
                run("xcrun", "simctl", "shutdown", device["udid"])
            except Exception as error:
                status["shutdownError"] = str(error)
        (output / "status.json").write_text(json.dumps(status, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
