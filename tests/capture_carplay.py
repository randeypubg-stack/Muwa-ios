"""Capture the real Simulator CarPlay display when available; never fabricate it."""
import json
import plistlib
import subprocess
import time
from pathlib import Path

out = Path('build/previews/carplay')
out.mkdir(parents=True, exist_ok=True)
status = {'captured': False, 'distribution': 'requires Apple-approved CarPlay Audio provisioning', 'steps': []}

def save_status():
    (out / 'status.json').write_text(json.dumps(status, ensure_ascii=False, indent=2))

def run(*args, timeout=180):
    command = [str(arg) for arg in args]
    print('Running:', ' '.join(command), flush=True)
    started = time.monotonic()
    step = {'command': command, 'timeout_seconds': timeout}
    status['steps'].append(step)
    save_status()
    try:
        result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=timeout)
        step['exit_code'] = result.returncode
        step['output'] = result.stdout[-4000:]
        if result.returncode:
            raise RuntimeError(f"Command failed ({result.returncode}): {' '.join(command)}\n{result.stdout[-4000:]}")
        return result.stdout
    except subprocess.TimeoutExpired as error:
        step['timed_out'] = True
        partial = error.stdout or ''
        if isinstance(partial, bytes):
            partial = partial.decode('utf-8', errors='replace')
        step['output'] = partial[-4000:]
        raise
    finally:
        step['elapsed_seconds'] = round(time.monotonic() - started, 3)
        save_status()
        print(f"Completed in {step['elapsed_seconds']}s: {' '.join(command)}", flush=True)

try:
    devices = json.loads(run('xcrun', 'simctl', 'list', 'devices', 'available', '--json'))['devices']
    phone = next(d for group in devices.values() for d in group if d.get('isAvailable') and d['name'].startswith('iPhone'))
    udid = phone['udid']
    status['device'] = phone['name']
    status['udid'] = udid
    app = next(Path('build/PreviewDerivedData/Build/Products/Debug-iphonesimulator').glob('*.app'))
    # Xcode signs the dedicated Simulator build and its debug dylib together.
    # Re-signing only the app here would discard Xcode's platform/debug grants.
    # The ordinary device IPA remains unsigned.
    run('codesign', '--verify', '--deep', '--strict', '--verbose=2', str(app))
    # Device entitlements live in the signature. Xcode instead embeds Simulator
    # grants in the Mach-O __TEXT.__entitlements section; its signature may be {}.
    # Verify the actual executable against Xcode's generated simulated grants,
    # rather than accepting the requested source entitlement file as evidence.
    signed = run('codesign', '--display', '--entitlements', ':-', str(app))
    start = signed.find('<?xml')
    end = signed.find('</plist>', start)
    if start < 0 or end < 0:
        raise RuntimeError('Could not read the signed Simulator entitlements')
    entitlements = plistlib.loads(signed[start:end + len('</plist>')].encode())
    if entitlements.get('com.apple.developer.carplay-audio') is True:
        status['entitlement_location'] = 'code signature'
    else:
        simulated = next(Path('build/PreviewDerivedData/Build/Intermediates.noindex')
                         .rglob('Muwa.app-Simulated.xcent'))
        embedded = simulated.read_bytes()
        entitlements = plistlib.loads(embedded)
        executable = plistlib.loads((app / 'Info.plist').read_bytes())['CFBundleExecutable']
        if (entitlements.get('com.apple.developer.carplay-audio') is not True
                or embedded not in (app / executable).read_bytes()):
            raise RuntimeError('Executable lacks the generated Simulator CarPlay Audio grants')
        status['entitlement_location'] = 'Xcode Simulator Mach-O section'
    status['codesign_verified'] = True
    if phone['state'] != 'Booted':
        run('xcrun', 'simctl', 'boot', udid)
    run('xcrun', 'simctl', 'bootstatus', udid, '-b', timeout=240)
    status['booted'] = True
    # A fresh hosted runner can finish bootstatus before installd is responsive.
    # The previous 45-second cap failed before any CarPlay UI could be inspected.
    run('xcrun', 'simctl', 'install', udid, str(app), timeout=180)
    data = Path(run('xcrun', 'simctl', 'get_app_container', udid, 'app.muwa.nasheeds', 'data').strip())
    (data / 'Documents/carplay-connected.txt').unlink(missing_ok=True)
    run('open', '-a', 'Simulator', '--args', '-CurrentDeviceUDID', udid)
    time.sleep(3)
    # Launch the phone scene before enabling the automotive display. SpringBoard
    # may reject a new foreground phone launch while the CarPlay display is active.
    # A cold hosted SpringBoard can still be registering the newly installed
    # bundle after installd/get_app_container return. Retry only a command
    # timeout; signing denials and other explicit launch failures remain errors.
    try:
        run('xcrun', 'simctl', 'launch', '--terminate-running-process', udid,
            'app.muwa.nasheeds', '--audit-player', timeout=300)
    except subprocess.TimeoutExpired:
        status['cold_launch_retry'] = True
        save_status()
        run('xcrun', 'simctl', 'launch', '--terminate-running-process', udid,
            'app.muwa.nasheeds', '--audit-player', timeout=180)
    time.sleep(5)
    script = '''tell application "System Events"
      tell process "Simulator"
        set frontmost to true
        set displayMenu to menu 1 of menu item "External Displays" of menu 1 of menu bar item "I/O" of menu bar 1
        set carItem to first menu item of displayMenu whose name contains "CarPlay"
        if exists menu 1 of carItem then
          click first menu item of menu 1 of carItem whose name contains "800"
        else
          click carItem
        end if
      end tell
    end tell'''
    status['menu'] = run('osascript', '-e', script)
    # The external display becomes available after the first phone launch.
    # Reconnect the process with that display already attached so UIKit can
    # request its CarPlay role from the existing scene manifest.
    time.sleep(3)
    run('xcrun', 'simctl', 'launch', '--terminate-running-process', udid,
        'app.muwa.nasheeds', '--audit-player')
    status['displays'] = run('xcrun', 'simctl', 'io', udid, 'enumerate')
    # Prove that the screenshot is from a connected CarPlay scene, not an empty display.
    data = Path(run('xcrun', 'simctl', 'get_app_container', udid, 'app.muwa.nasheeds', 'data').strip())
    proof = data / 'Documents/carplay-connected.txt'
    if not proof.exists():
        # Connecting CarPlay exposes its launcher, not automatically Muwa's
        # template scene. Select the app from the actual external framebuffer.
        launcher = out / 'launcher.png'
        run('xcrun', 'simctl', 'io', udid, 'screenshot', '--display=external', str(launcher))
        recognition = run('swift', 'tests/locate_carplay_app.swift', str(launcher))
        # Vision may print a driver notice before our single-line JSON result.
        # Read the structured result rather than treating native notices as JSON.
        target = json.loads(next(line for line in reversed(recognition.splitlines())
                                 if line.strip().startswith('{') and line.strip().endswith('}')))
        assert target['label'].lower() == 'muwa' and target['confidence'] >= 0.5
        bounds_script = '''tell application "System Events"
          tell process "Simulator"
            set frontmost to true
            set chosenWindow to missing value
            repeat with w in windows
              if name of w contains "CarPlay" then
                set chosenWindow to w
                exit repeat
              end if
            end repeat
            if chosenWindow is missing value then
              repeat with w in windows
                set windowSize to size of w
                if item 1 of windowSize > item 2 of windowSize then
                  set chosenWindow to w
                  exit repeat
                end if
              end repeat
            end if
            if chosenWindow is missing value then error "CarPlay window was not found"
            perform action "AXRaise" of chosenWindow
            set windowPosition to position of chosenWindow
            set windowSize to size of chosenWindow
            return (item 1 of windowPosition as text) & "," & (item 2 of windowPosition as text) & "," & (item 1 of windowSize as text) & "," & (item 2 of windowSize as text)
          end tell
        end tell'''
        wx, wy, ww, wh = map(float, run('osascript', '-e', bounds_script).strip().split(','))
        scale = ww / target['width']
        x = round(wx + target['x'] * scale)
        y = round(wy + wh - target['height'] * scale + target['y'] * scale)
        status['launcher_selection'] = {'label': target['label'], 'confidence': target['confidence'],
                                        'nativeTarget': target, 'windowBounds': [wx, wy, ww, wh]}
        save_status()
        run('screencapture', '-x', str(out / 'desktop-before-input.png'))
        # AXRaise orders the window but does not guarantee it is the key window.
        # Focus its title bar first; otherwise Simulator may consume the icon
        # click just to activate the external-display window.
        run('cliclick', f'c:{round(wx + ww / 2)},{round(wy + 14)}')
        time.sleep(0.2)
        # A cold Simulator may consume the first input while activating its
        # external display. Keep a real pointer press long enough to span a
        # guest input frame, and retry only while the fresh framebuffer still
        # positively identifies Muwa's launcher tile. Never click coordinates
        # from the launcher once the app has opened.
        status['launcher_attempts'] = []
        for attempt in range(3):
            if proof.exists():
                break
            if attempt:
                retry_frame = out / f'launcher-retry-{attempt}.png'
                run('xcrun', 'simctl', 'io', udid, 'screenshot',
                    '--display=external', str(retry_frame))
                try:
                    retry_recognition = run('swift', 'tests/locate_carplay_app.swift', str(retry_frame))
                    retry_target = json.loads(next(line for line in reversed(retry_recognition.splitlines())
                                                   if line.strip().startswith('{') and line.strip().endswith('}')))
                    if retry_target['label'].lower() != 'muwa' or retry_target['confidence'] < 0.5:
                        break
                    x = round(wx + retry_target['x'] * scale)
                    y = round(wy + wh - retry_target['height'] * scale + retry_target['y'] * scale)
                except (RuntimeError, StopIteration, ValueError):
                    break
            status['launcher_attempts'].append({'attempt': attempt + 1, 'x': x, 'y': y})
            save_status()
            run('cliclick', f'm:{x},{y}', 'w:300', f'dd:{x},{y}', 'w:150', f'du:{x},{y}')
            input_deadline = time.monotonic() + 5
            while time.monotonic() < input_deadline and not proof.exists():
                time.sleep(0.2)
        status['mouse_position'] = run('cliclick', 'p').strip()
        run('screencapture', '-x', str(out / 'desktop-after-input.png'))
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline and not proof.exists():
        time.sleep(0.5)
    status['scene_connected'] = proof.exists() and proof.read_text() == 'Muwa CarPlay connected'
    if not status['scene_connected']:
        run('xcrun', 'simctl', 'io', udid, 'screenshot', '--display=external',
            str(out / 'external-display-unconnected.png'))
        raise RuntimeError('External display exists but Muwa CarPlay scene did not connect')
    time.sleep(2)
    run('xcrun', 'simctl', 'io', udid, 'screenshot', '--display=external', str(out / 'carplay.png'))
    status['captured'] = True
    status['device'] = phone['name']
except Exception as error:
    status['reason'] = str(error)
    # Preserve the native launch denial so signing/runtime failures can be
    # distinguished from a missing external display or an app scene failure.
    if status.get('booted'):
        predicate = 'process == "Muwa" OR process CONTAINS "CarPlay" OR subsystem CONTAINS[c] "carplay" OR ((process == "SpringBoard" OR process == "runningboardd" OR process == "amfid") AND (eventMessage CONTAINS "app.muwa.nasheeds" OR eventMessage CONTAINS "Muwa.app"))'
        try:
            diagnostic = run('xcrun', 'simctl', 'spawn', udid, 'log', 'show',
                             '--style', 'compact', '--last', '3m', '--predicate', predicate,
                             timeout=30)
            (out / 'launch-diagnostic.log').write_text(diagnostic)
        except Exception as diagnostic_error:
            status['diagnostic_error'] = str(diagnostic_error)
finally:
    save_status()
    print(json.dumps(status, ensure_ascii=False), flush=True)

# Preserve diagnostics, but fail the check when no real Muwa scene was captured.
# A successful signing/build or launcher image must not hide a runtime crash.
if not status['captured']:
    raise SystemExit(1)
