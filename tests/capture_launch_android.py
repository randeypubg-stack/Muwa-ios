"""Record Muwa's real native cold launch and its reduced-animation fallback.

Run after installing the debug APK on an emulator. The normal review screenshots
disable animations; this capture restores them temporarily and always puts the
emulator settings back. All frames come from Android's screenrecord/screencap.
"""
import json
import os
from pathlib import Path
import struct
import subprocess
import time

PACKAGE = "app.muwa.nasheeds"
ANIMATION_KEYS = ("window_animation_scale", "transition_animation_scale", "animator_duration_scale")


def adb(*args, binary=False, timeout=30):
    return subprocess.check_output(["adb", *args], text=not binary, timeout=timeout)


def check_foreground():
    activities = adb("shell", "dumpsys", "activity", "activities", timeout=15)
    assert any(PACKAGE in line and ("mResumedActivity" in line or "topResumedActivity" in line)
               for line in activities.splitlines()), "Muwa is not the foreground activity"


def screenrecord_pids():
    result = subprocess.run(["adb", "shell", "pidof", "screenrecord"], capture_output=True, text=True, timeout=10)
    assert result.returncode in (0, 1), f"Cannot inspect Android recorder: {result.stderr}"
    values = result.stdout.split()
    assert all(value.isdigit() for value in values), "Invalid screenrecord process ID"
    return set(values)


def set_animation_scale(value):
    for key in ANIMATION_KEYS:
        adb("shell", "settings", "put", "global", key, str(value))
    confirmed = {key: adb("shell", "settings", "get", "global", key).strip() for key in ANIMATION_KEYS}
    assert all(float(scale) == value for scale in confirmed.values()), "Android animation settings did not apply"
    return confirmed


def screenshot(path):
    check_foreground()
    data = adb("exec-out", "screencap", "-p", binary=True, timeout=15)
    assert data.startswith(b"\x89PNG\r\n\x1a\n") and data[12:16] == b"IHDR", "Invalid Android PNG"
    width, height = struct.unpack(">II", data[16:24])
    assert 0 < width < height, f"Expected portrait screenshot, got {width}x{height}"
    path.write_bytes(data)
    return {"file": path.name, "width": width, "height": height, "bytes": len(data), "source": "adb screencap"}


def boxes(data):
    """Yield ISO BMFF boxes so a truncated screenrecord cannot pass as a video."""
    offset = 0
    while offset + 8 <= len(data):
        size, kind = struct.unpack(">I4s", data[offset:offset + 8])
        header = 8
        if size == 1:
            assert offset + 16 <= len(data), "Truncated MP4 box header"
            size = struct.unpack(">Q", data[offset + 8:offset + 16])[0]
            header = 16
        elif size == 0:
            size = len(data) - offset
        assert size >= header and offset + size <= len(data), "Incomplete MP4 box"
        yield kind, data[offset + header:offset + size]
        offset += size
    assert offset == len(data), "Trailing incomplete MP4 data"


def video_duration(path):
    data = path.read_bytes()
    assert len(data) > 1024 and data[4:8] == b"ftyp", "Invalid Android screen recording"
    top = dict(boxes(data))
    assert b"mdat" in top and b"moov" in top, "Recording is missing video data or its final MP4 index"
    movie = dict(boxes(top[b"moov"]))
    assert b"mvhd" in movie, "Recording has no duration metadata"
    header = movie[b"mvhd"]
    if header[0] == 1:
        timescale = struct.unpack(">I", header[20:24])[0]
        duration = struct.unpack(">Q", header[24:32])[0]
    else:
        timescale, duration = struct.unpack(">II", header[12:20])
    assert timescale > 0 and duration > 0, "Recording duration is empty"
    seconds = duration / timescale
    assert seconds >= 2, f"Recording is too short: {seconds:.3f}s"
    return seconds


def start_launch():
    adb("shell", "am", "force-stop", PACKAGE)
    result = adb("shell", "am", "start", "-W", "-n", f"{PACKAGE}/.MainActivity",
                 "--es", "review.route", "launch")
    assert "Error:" not in result, result
    return result.strip()


def assert_home(remote_xml):
    check_foreground()
    adb("shell", "uiautomator", "dump", remote_xml, timeout=15)
    hierarchy = adb("shell", "cat", remote_xml, timeout=15)
    assert 'text="Главная"' in hierarchy and 'text="Нашиды без музыки"' in hierarchy, "Launch did not reveal the native home screen"


def main():
    out = Path(os.environ.get("MUWA_ANDROID_OUTPUT", "build/android-previews")) / "launch"
    out.mkdir(parents=True, exist_ok=True)
    unique = f"{os.getpid()}-{int(time.time())}"
    remote_video = f"/sdcard/Download/muwa-launch-{unique}.mp4"
    remote_xml = f"/sdcard/Download/muwa-launch-{unique}.xml"
    setting_keys = [("global", key) for key in ANIMATION_KEYS] + [
        ("system", "accelerometer_rotation"), ("system", "user_rotation")]
    previous = {(namespace, key): adb("shell", "settings", "get", namespace, key).strip()
                for namespace, key in setting_keys}
    manifest = {
        "package": PACKAGE, "route": "launch", "captureStatus": "started",
        "model": adb("shell", "getprop", "ro.product.model").strip(),
        "size": adb("shell", "wm", "size").strip(),
        "density": adb("shell", "wm", "density").strip(),
        "orientation": "portrait", "requestedPostLaunchSeconds": 3,
        "previousSettings": {f"{namespace}.{key}": value for (namespace, key), value in previous.items()},
        "recordingAnimationScale": 1, "reducedAnimationScale": 0,
        "files": [], "cleanupErrors": []
    }
    recorder = None
    recorder_pids = set()
    try:
        adb("shell", "input", "keyevent", "KEYCODE_WAKEUP")
        adb("shell", "wm", "dismiss-keyguard")
        adb("shell", "mkdir", "-p", "/sdcard/Download")
        adb("shell", "settings", "put", "system", "accelerometer_rotation", "0")
        adb("shell", "settings", "put", "system", "user_rotation", "0")
        manifest["confirmedRecordingScales"] = set_animation_scale(1)
        time.sleep(1)
        adb("shell", "am", "force-stop", PACKAGE)
        # Refuse to interfere with any other recording already on the emulator.
        assert not screenrecord_pids(), "Another Android screen recording is already running"
        recorder = subprocess.Popen(
            ["adb", "shell", "screenrecord", "--time-limit", "20", "--bit-rate", "6000000", remote_video],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        # Verify the recorder is running before asking Android to launch Muwa.
        for _ in range(20):
            assert recorder.poll() is None, "Android screenrecord exited before launch"
            found = screenrecord_pids()
            if found:
                recorder_pids = found
                break
            time.sleep(0.1)
        assert recorder_pids, "Android screenrecord did not start"
        print("Record actual Android launch: review.route=launch", flush=True)
        manifest["launchResult"] = start_launch()
        started = time.monotonic()
        time.sleep(0.25)
        manifest["files"].append(screenshot(out / "launch-logo.png"))
        remaining = 3 - (time.monotonic() - started)
        if remaining > 0:
            time.sleep(remaining)
        check_foreground()
        for pid in recorder_pids:
            adb("shell", "kill", "-2", pid, timeout=10)
        stdout, stderr = recorder.communicate(timeout=15)
        assert recorder.returncode == 0, f"Android screenrecord failed: {stdout} {stderr}"
        recorder_pids.clear()
        path = out / "launch.mp4"
        adb("pull", remote_video, str(path), timeout=30)
        manifest["durationSeconds"] = video_duration(path)
        manifest["files"].append({"file": path.name, "bytes": path.stat().st_size, "source": "adb screenrecord"})
        assert_home(remote_xml)
        manifest["files"].append(screenshot(out / "launch-home.png"))
        manifest["captureStatus"] = "recorded"
        # A real second cold start proves that disabling motion reveals usable home.
        manifest["confirmedReducedScales"] = set_animation_scale(0)
        manifest["reducedLaunchResult"] = start_launch()
        time.sleep(0.4)
        assert_home(remote_xml)
        manifest["files"].append(screenshot(out / "launch-reduced-motion-home.png"))
        manifest["captureStatus"] = "complete"
    except Exception as error:
        manifest["captureStatus"] = "failed"
        manifest["error"] = str(error)
        raise
    finally:
        for pid in recorder_pids:
            try:
                adb("shell", "kill", "-2", pid, timeout=10)
            except Exception as error:
                manifest["cleanupErrors"].append(str(error))
        if recorder is not None and recorder.poll() is None:
            try:
                recorder.communicate(timeout=10)
            except subprocess.TimeoutExpired:
                try:
                    recorder.terminate()
                    recorder.communicate(timeout=5)
                except Exception as error:
                    manifest["cleanupErrors"].append(f"Stop adb recorder: {error}")
        for (namespace, key), value in previous.items():
            try:
                if value == "null":
                    adb("shell", "settings", "delete", namespace, key, timeout=10)
                else:
                    adb("shell", "settings", "put", namespace, key, value, timeout=10)
            except Exception as error:
                manifest["cleanupErrors"].append(f"Restore {namespace}.{key}: {error}")
        try:
            adb("shell", "rm", "-f", remote_video, remote_xml, timeout=10)
        except Exception as error:
            manifest["cleanupErrors"].append(str(error))
        (out / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
    assert not manifest["cleanupErrors"], "Android settings could not be fully restored"
    print(f"Captured native Android launch: {manifest['durationSeconds']:.3f}s", flush=True)


if __name__ == "__main__":
    main()
