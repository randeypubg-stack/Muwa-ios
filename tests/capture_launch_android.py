"""Record Muwa's real native cold launch and its reduced-animation fallback.

Run after installing the debug APK on an emulator. The normal review screenshots
disable animations; this capture restores them temporarily and always puts the
emulator settings back. Set MUWA_ANDROID_LAUNCH_VIDEO=0 for independent cold-launch
and reduced-motion verification without the host recorder. Requested recordings
remain strict: no missing video or failed launch is converted into success.
All frames come from Emulator screenrecord/adb screencap.
"""
import json
import os
from pathlib import Path
import re
import shutil
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


def emulator_recording(*args):
    result = adb("emu", "screenrecord", *args)
    assert "KO:" not in result, f"Emulator recording command failed: {result}"
    return result.strip()


def recorded_file(name):
    # Current emulator releases write console recordings inside the AVD. Some
    # older releases write to its root or the caller's working directory.
    roots = {Path(os.environ.get("ANDROID_AVD_HOME", str(Path.home() / ".android/avd")))}
    if os.environ.get("ANDROID_USER_HOME"):
        roots.add(Path(os.environ["ANDROID_USER_HOME"]) / "avd")
    candidates = [Path.cwd() / name]
    for root in roots:
        candidates.extend(root.glob(f"*.avd/console_out/{name}"))
        candidates.extend(root.glob(f"*.avd/{name}"))
    matches = [p for p in candidates if p.is_file() and p.stat().st_size > 0]
    if not matches:
        raise FileNotFoundError("Emulator console did not produce the requested native WebM")
    return matches[0]


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


def assert_home(remote_xml, out):
    # Cold emulator renderers can keep the starting window above Compose after
    # am start -W returns. Verify a fresh hierarchy until actual home is visible.
    deadline = time.monotonic() + 30
    hierarchy = ""
    while time.monotonic() < deadline:
        check_foreground()
        # Never accept the first launch's stale XML on the reduced-motion launch.
        adb("shell", "rm", "-f", remote_xml)
        try:
            # UiAutomator can report a null root on stderr while exiting zero,
            # without creating XML. Retry a fresh dump rather than accepting an
            # old hierarchy or failing on a transient missing file.
            result = adb("shell", "uiautomator", "dump", "--compressed", remote_xml, timeout=10)
            if "ERROR:" in result:
                time.sleep(0.4)
                continue
            hierarchy = adb("shell", "cat", remote_xml, timeout=10)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            time.sleep(0.4)
            continue
        if 'text="Главная"' in hierarchy and 'text="Нашиды без музыки"' in hierarchy:
            (out / "home-hierarchy.xml").write_text(hierarchy)
            return
        time.sleep(0.4)
    (out / "failed-hierarchy.xml").write_text(hierarchy)
    screenshot(out / "launch-failed.png")
    raise AssertionError("Launch did not reveal native home within 30 seconds")


def main():
    out = Path(os.environ.get("MUWA_ANDROID_OUTPUT", "build/android-previews")) / "launch"
    out.mkdir(parents=True, exist_ok=True)
    record_video = os.environ.get("MUWA_ANDROID_LAUNCH_VIDEO", "1") != "0"
    unique = f"{os.getpid()}-{int(time.time())}"
    recording_name = f"muwa-launch-{unique}.webm"
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
    width, height = map(int, re.findall(r"(\d+)x(\d+)", manifest["size"])[-1])
    # Keep original PNG/WebM frames at device resolution. Scale only the MP4
    # transport copy after recording, without creating a guest virtual display.
    recording_width = min(width, 720)
    recording_height = round(height * recording_width / width / 2) * 2
    manifest["videoRequested"] = record_video
    if record_video:
        manifest["videoResolution"] = f"{recording_width}x{recording_height}"
    recording = False
    try:
        adb("shell", "input", "keyevent", "KEYCODE_WAKEUP")
        adb("shell", "wm", "dismiss-keyguard")
        adb("shell", "mkdir", "-p", "/sdcard/Download")
        adb("shell", "settings", "put", "system", "accelerometer_rotation", "0")
        adb("shell", "settings", "put", "system", "user_rotation", "0")
        manifest["confirmedRecordingScales"] = set_animation_scale(1)
        time.sleep(1)
        adb("shell", "am", "force-stop", PACKAGE)
        # Host/guest video recorders can stall hosted GLES emulators. Keep
        # functional cold-launch verification independent of recording support.
        # Video is explicit and strict, never silently skipped after a failure.
        if record_video:
            manifest["recordingBackend"] = "Android Emulator console screenrecord"
            manifest["recordingStart"] = emulator_recording("start", recording_name)
            recording = True
        print("Verify actual Android launch: review.route=launch", flush=True)
        manifest["launchResult"] = start_launch()
        time.sleep(0.25)
        manifest["files"].append(screenshot(out / "launch-window.png"))
        # am start -W can return while the GPU is still presenting the starting
        # window on a cold CI emulator. Keep recording through actual native home.
        assert_home(remote_xml, out)
        manifest["nativeHomeVerified"] = True
        if record_video:
            manifest["nativeHomeVerifiedBeforeStop"] = True
        time.sleep(3)
        check_foreground()
        if record_video:
            manifest["recordingStop"] = emulator_recording("stop")
            recording = False
            original = recorded_file(recording_name)
            raw_path = out / "launch.webm"
            shutil.copy2(original, raw_path)
            original.unlink()
            path = out / "launch.mp4"
            probe = json.loads(subprocess.check_output(
                ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                 "stream=width,height", "-of", "json", str(raw_path)], text=True, timeout=15))
            video_width, video_height = (int(probe['streams'][0][key]) for key in ['width', 'height'])
            assert 0 < video_width < video_height, "Console recording is not a native portrait video"
            recording_width = min(video_width, 720)
            recording_height = round(video_height * recording_width / video_width / 2) * 2
            manifest["originalVideoResolution"] = f"{video_width}x{video_height}"
            manifest["videoResolution"] = f"{recording_width}x{recording_height}"
            subprocess.run(["ffmpeg", "-nostdin", "-y", "-hide_banner", "-loglevel", "error",
                            "-i", str(raw_path), "-vf", f"scale={recording_width}:{recording_height}",
                            "-c:v", "libx264", "-preset", "veryfast", "-crf", "18",
                            "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(path)],
                           check=True, timeout=120)
            manifest["durationSeconds"] = video_duration(path)
            manifest["files"].append({"file": raw_path.name, "bytes": raw_path.stat().st_size,
                                      "source": "original Emulator console recording"})
            manifest["files"].append({"file": path.name, "bytes": path.stat().st_size,
                                      "source": "Emulator recording converted to MP4"})
        # Preserve the verified actual foreground frame before the second
        # cold start. The video branch also verified home during recording.
        manifest["files"].append(screenshot(out / "launch-home.png"))
        manifest["captureStatus"] = "recorded" if record_video else "verified"
        # A real second cold start proves that disabling motion reveals usable home.
        manifest["confirmedReducedScales"] = set_animation_scale(0)
        manifest["reducedLaunchResult"] = start_launch()
        time.sleep(0.4)
        assert_home(remote_xml, out)
        manifest["files"].append(screenshot(out / "launch-reduced-motion-home.png"))
        manifest["captureStatus"] = "complete"
    except Exception as error:
        manifest["captureStatus"] = "failed"
        manifest["error"] = str(error)
        try:
            screenshot(out / "launch-failed.png")
        except Exception as capture_error:
            manifest["failureScreenshotError"] = str(capture_error)
        try:
            diagnostic = adb("logcat", "-d", "-t", "100", "-s", "UiAutomation", "UiAutomatorBridge",
                             "UiAutomationConnection", timeout=5)
            (out / "automation-diagnostic.log").write_text(diagnostic)
        except Exception as diagnostic_error:
            manifest["diagnosticError"] = str(diagnostic_error)
        raise
    finally:
        if recording:
            try:
                emulator_recording("stop")
            except Exception as error:
                manifest["cleanupErrors"].append(str(error))
        for (namespace, key), value in previous.items():
            try:
                if value == "null":
                    adb("shell", "settings", "delete", namespace, key, timeout=10)
                else:
                    adb("shell", "settings", "put", namespace, key, value, timeout=10)
            except Exception as error:
                manifest["cleanupErrors"].append(f"Restore {namespace}.{key}: {error}")
        try:
            adb("shell", "rm", "-f", remote_xml, timeout=10)
        except Exception as error:
            manifest["cleanupErrors"].append(str(error))
        (out / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
    assert not manifest["cleanupErrors"], "Android settings could not be fully restored"
    if record_video:
        print(f"Captured native Android launch: {manifest['durationSeconds']:.3f}s", flush=True)
    else:
        print("Verified native Android cold launch and reduced-motion home", flush=True)


if __name__ == "__main__":
    main()
