"""Record the actual native iOS cold-launch reveal in an installed Simulator app.

Run from the repository root after building the review app:
    python3 tests/capture_launch_ios.py

The review build mounts the real Home while its account service is held for
45 seconds. Home opens without a launch overlay or toolbar mark. This
script never synthesizes frames or waits for artwork/network fixtures. It preserves recording logs and status.json even when capture fails.
"""
import json
import errno
import fcntl
import os
from pathlib import Path
import plistlib
import pty
import re
import select
import shutil
import signal
import struct
import subprocess
import termios
import threading
import time


PACKAGE = "app.muwa.nasheeds"
OUTPUT = Path("build/previews/launch")
APP_FOLDER = Path("build/PreviewDerivedData/Build/Products/Debug-iphonesimulator")


def start_recording(command, logfile):
    """Give simctl terminal input AND output, preserving live readiness logs.

    Hosted shells can pass an ignored SIGINT to children. A detached process
    group alone does not restore that signal or provide terminal input.
    Regular-file stdout can buffer the readiness acknowledgement even while
    video frames are already encoded. Drain terminal output continuously into
    the original log. Start that reader only after the child has been spawned.
    """
    master, slave = pty.openpty()
    attributes = termios.tcgetattr(slave)
    attributes[3] &= ~(termios.ECHO | termios.ECHONL)
    termios.tcsetattr(slave, termios.TCSANOW, attributes)

    def prepare_terminal():
        signal.signal(signal.SIGINT, signal.SIG_DFL)
        signal.signal(signal.SIGTERM, signal.SIG_DFL)
        # A default disposition does not clear a mask inherited from the host.
        # Keep both the terminal interrupt and explicit group stop deliverable.
        signal.pthread_sigmask(signal.SIG_UNBLOCK, {signal.SIGINT, signal.SIGTERM})
        fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
        os.tcsetpgrp(slave, os.getpgrp())

    try:
        process = subprocess.Popen(command, stdin=slave, stdout=slave,
                                   stderr=slave, start_new_session=True,
                                   preexec_fn=prepare_terminal)
    except BaseException:
        os.close(master)
        raise
    finally:
        os.close(slave)
    output = os.dup(master)
    process.muwa_output_errors = []

    def copy_output():
        try:
            while True:
                readable, _, _ = select.select([output], [], [], 0.1)
                if not readable:
                    if process.poll() is not None:
                        break
                    continue
                try:
                    data = os.read(output, 65536)
                except OSError as error:
                    if error.errno == errno.EIO:  # slave closed after recorder exit
                        break
                    raise
                if not data:
                    break
                logfile.write(data.decode("utf-8", errors="replace"))
                logfile.flush()
        except Exception as error:
            process.muwa_output_errors.append(type(error).__name__)
        finally:
            os.close(output)

    process.muwa_output_reader = threading.Thread(target=copy_output, daemon=True)
    process.muwa_output_reader.start()
    return process, master


def validate_png(path):
    header = path.read_bytes()[:24]
    if not header.startswith(b"\x89PNG\r\n\x1a\n") or len(header) != 24:
        raise AssertionError(f"Invalid native screenshot: {path.name}")
    width, height = struct.unpack(">II", header[16:24])
    if min(width, height) < 100:
        raise AssertionError(f"Unexpected native screenshot size: {width}x{height}")
    return {"width": width, "height": height}


def wait_recording_ready(process, log_path, seconds=45):
    """Wait for simctl's real readiness acknowledgement before advancing the app.

    Cold hosted Simulators can take longer than 10–15 seconds to attach their
    recorder. The deadline stays bounded and an exited recorder fails immediately.
    """
    deadline = time.monotonic() + seconds
    while "Recording started" not in log_path.read_text():
        if process.muwa_output_errors:
            raise RuntimeError("Native recorder output could not be preserved")
        if process.poll() is not None or time.monotonic() >= deadline:
            raise RuntimeError(f"Native recorder did not become ready: {log_path.read_text()}")
        time.sleep(0.1)


def validate_video(path):
    """Reject unfinished MP4/QuickTime files even when ffmpeg is unavailable."""
    length = path.stat().st_size
    atoms = []
    with path.open("rb") as stream:
        offset = 0
        while offset < length:
            stream.seek(offset)
            header = stream.read(8)
            if len(header) != 8:
                raise AssertionError("Native recording has a truncated atom header")
            size, kind = struct.unpack(">I4s", header)
            header_size = 8
            if size == 1:
                extended = stream.read(8)
                if len(extended) != 8:
                    raise AssertionError("Native recording has a truncated extended atom")
                size = struct.unpack(">Q", extended)[0]
                header_size = 16
            elif size == 0:
                size = length - offset
            if size < header_size or offset + size > length:
                raise AssertionError("Native recording has an incomplete MP4 atom")
            atoms.append(kind.decode("ascii", errors="replace"))
            offset += size
    if not all(kind in atoms for kind in ("ftyp", "mdat", "moov")):
        raise AssertionError(f"Native recording is not finalized (MP4 atoms: {', '.join(atoms)})")
    return atoms



def finish_recording(recorder, recorder_input, run, status):
    """Finalize only the recorder we started; share ownership with all captures.

    The caller clears its references after this function, including on failure.
    The terminal descriptor is closed exactly once even if encoder flush fails.
    """
    if recorder is None:
        return
    try:
        def signal_group(value):
            try:
                os.killpg(recorder.pid, value)
            except ProcessLookupError:
                # The process can finish between poll() and delivery.
                pass
            except PermissionError:
                # Hosted macOS can elevate simctl after exec. The caller then
                # cannot interrupt it, even though we created its private group.
                # Signal only that owned group; never stop unrelated simulators.
                status["recorder_privileged_signal"] = True
                run("sudo", "-n", "/bin/kill", "-s",
                    signal.Signals(value).name.removeprefix("SIG"), "--",
                    str(-recorder.pid), timeout=10)
        if recorder.poll() is None:
            if os.getpgid(recorder.pid) != recorder.pid:
                raise RuntimeError("Recorder no longer belongs to its owned process group")
            status["recorder_process"] = run("ps", "-o", "pid=,pgid=,uid=,comm=",
                                            "-p", str(recorder.pid), timeout=10)
            # SIGINT is the documented Ctrl-C stop. A terminal-generated signal
            # alone cannot stop an elevated simctl on the hosted macOS runner.
            signal_group(signal.SIGINT)
            try:
                # Hosted Simulator encoders may need longer than the recording
                # itself to flush frames and write the MP4's final moov atom.
                # Terminating early produces an unplayable recording.
                recorder.wait(timeout=60)
            except subprocess.TimeoutExpired:
                signal_group(signal.SIGTERM)
                try:
                    recorder.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    signal_group(signal.SIGKILL)
                    recorder.wait(timeout=5)
                raise RuntimeError("Simulator recorder did not finish after SIGINT")
        status["recorder_exit_code"] = recorder.returncode
    finally:
        recorder.muwa_output_reader.join(timeout=5)
        if recorder_input is not None:
            os.close(recorder_input)
        if recorder.muwa_output_reader.is_alive() or recorder.muwa_output_errors:
            raise RuntimeError("Native recorder output did not finish draining")


def parse_home_proof(output):
    # Preserve command diagnostics but accept exactly one successful frame proof.
    proofs = []
    for line in output.splitlines():
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict) and value.get("homeVisible") is True:
            if value.get("width", 0) >= 100 and value.get("height", 0) >= 100:
                proofs.append(value)
    if len(proofs) != 1:
        raise AssertionError("Expected exactly one successful native Home frame proof")
    return proofs[0]


def command_output_summary(output, limit=4000):
    """Keep the first diagnostic as well as the tail of a verbose failure."""
    if len(output) <= limit:
        return output
    half = limit // 2
    return output[:half] + "\n[output truncated; full command log preserved]\n" + output[-half:]


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    status = {"captured": False, "package": PACKAGE, "commands": []}
    recorder = None
    recorder_log = None
    recorder_input = None
    udid = None
    booted_here = False

    def run(*args, timeout=180):
        command = [str(arg) for arg in args]
        print("Running:", " ".join(command), flush=True)
        log_path = OUTPUT / f"command-{len(status['commands']) + 1:03d}.log"
        try:
            result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, timeout=timeout)
        except subprocess.TimeoutExpired as error:
            output = error.stdout or ""
            if isinstance(output, bytes):
                output = output.decode("utf-8", errors="replace")
            log_path.write_text(output)
            summary = command_output_summary(output)
            status["commands"].append({"command": command, "exit_code": None,
                                       "timeout_seconds": timeout,
                                       "output": summary, "log_file": log_path.name})
            raise RuntimeError(f"Command timed out after {timeout}s: {' '.join(command)}\n"
                               f"Full log: {log_path}\n{summary}") from error
        log_path.write_text(result.stdout)
        summary = command_output_summary(result.stdout)
        status["commands"].append({"command": command, "exit_code": result.returncode,
                                   "output": summary, "log_file": log_path.name})
        if result.returncode:
            raise RuntimeError(f"Command failed ({result.returncode}): {' '.join(command)}\n"
                               f"Full log: {log_path}\n{summary}")
        return result.stdout

    def stop_recording():
        nonlocal recorder, recorder_input
        try:
            finish_recording(recorder, recorder_input, run, status)
        finally:
            recorder = None
            recorder_input = None

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

        requested = os.environ.get("MUWA_LAUNCH_DEVICE")
        devices = json.loads(run("xcrun", "simctl", "list", "devices", requested or "available", "--json"))["devices"]
        phones = [device for group in devices.values() for device in group
                  if device.get("isAvailable") and device["name"].startswith("iPhone")]
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
        # Muwa applies preferredColorScheme(.dark) to its production WindowGroup.
        # Changing Simulator's global appearance is unnecessary and can deadlock
        # the GUI-backed RPC on the headless Xcode 27 runner before app install.
        status["appearanceSource"] = "Production Muwa preferredColorScheme(.dark)"
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
        simctl = run("xcrun", "--find", "simctl").strip()
        if not Path(simctl).is_file():
            raise RuntimeError("xcrun did not resolve the Simulator control executable")
        recording_command = [simctl, "io", udid, "recordVideo", "--codec=h264", str(video)]
        status["parent_sigint_ignored"] = signal.getsignal(signal.SIGINT) == signal.SIG_IGN
        status["parent_blocked_signals"] = [signal.Signals(value).name for value in signal.pthread_sigmask(signal.SIG_BLOCK, set())]
        recorder, recorder_input = start_recording(recording_command, recorder_log)
        status["recording_stop_method"] = "SIGINT to the owned recorder group"
        status["recording_command"] = recording_command
        # Launch only once simctl confirms that the screen recording is active.
        wait_recording_ready(recorder, log_path)
        data_container = Path(run("xcrun", "simctl", "get_app_container", udid, PACKAGE, "data").strip())
        for name in ["launch-home-mounted.txt", "launch-auth-pending.txt", "launch-auth-finished.txt"]:
            (data_container / "Documents" / name).unlink(missing_ok=True)
        launch_offset = time.monotonic() - recording_start
        response = run("xcrun", "simctl", "launch", "--terminate-running-process", udid, PACKAGE, "--audit-launch")
        pid_match = re.search(r":\s*(\d+)\s*$", response)
        if pid_match is None:
            raise AssertionError(f"Simulator did not report Muwa's PID: {response}")
        status["launch_pid"] = int(pid_match.group(1))
        status["launch_offset_seconds"] = round(launch_offset, 3)
        mounted = data_container / "Documents/launch-home-mounted.txt"
        pending = data_container / "Documents/launch-auth-pending.txt"
        deadline = time.monotonic() + 25
        pid = str(status["launch_pid"])
        while not all(p.exists() and p.read_text() == pid for p in [mounted, pending]):
            if time.monotonic() >= deadline:
                raise AssertionError("Home did not mount while account restoration was pending")
            time.sleep(0.1)
        status["home_mounted_while_auth_pending"] = True
        # Timing includes simctl/host overhead; it is not physical iPhone latency.
        status["shell_proof_after_launch_command_seconds"] = round(time.monotonic() - recording_start - launch_offset, 3)
        time.sleep(0.5)
        if recorder.poll() is not None:
            raise RuntimeError("Simulator recorder exited during the launch animation")
        # Simulator app processes run on the host; this catches a startup crash.
        os.kill(status["launch_pid"], 0)
        final = OUTPUT / "home-after-launch.png"
        run("xcrun", "simctl", "io", udid, "screenshot", final)
        status["final_screen"] = validate_png(final)
        if (data_container / "Documents/launch-auth-finished.txt").exists():
            raise AssertionError("Auth finished before Home screenshot; pending-session proof is invalid")
        stop_recording()
        recorder_log.close()
        recorder_log = None
        status["recording_duration_seconds"] = round(time.monotonic() - recording_start, 3)
        if not video.exists() or video.stat().st_size < 10000:
            raise AssertionError("Native launch video is empty or truncated")
        status["video_atoms"] = validate_video(video)
        status["video_bytes"] = video.stat().st_size
        # Finish the encoder before CPU OCR. The
        # screenshot above was captured while the real session was still held.
        status["home_frame_proof"] = parse_home_proof(run(
            "python3", "tests/verify_home_frame.py", final, "--output", OUTPUT / "ocr"))

        # Extract real recorded frames only when ffmpeg is present on the runner.
        ffmpeg = shutil.which("ffmpeg")
        if ffmpeg:
            frames = []
            for label, offset in [("first-frame", 0.25), ("toolbar-mark", 0.60), ("home", 1.80)]:
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
