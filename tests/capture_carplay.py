"""Capture the real Simulator CarPlay display when available; never fabricate it."""
import json
import plistlib
import subprocess
import time
from pathlib import Path

out = Path('build/previews/carplay')
out.mkdir(parents=True, exist_ok=True)
status = {'captured': False, 'distribution': 'requires Apple-approved CarPlay Audio provisioning', 'steps': []}

def run(*args, timeout=180):
    command = [str(arg) for arg in args]
    print('Running:', ' '.join(command), flush=True)
    started = time.monotonic()
    step = {'command': command, 'timeout_seconds': timeout}
    status['steps'].append(step)
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
    run('xcrun', 'simctl', 'launch', '--terminate-running-process', udid, 'app.muwa.nasheeds', '--audit-player')
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
    time.sleep(5)
    status['displays'] = run('xcrun', 'simctl', 'io', udid, 'enumerate')
    run('xcrun', 'simctl', 'io', udid, 'screenshot', '--display=external', str(out / 'carplay.png'))
    # Prove that the screenshot is from a connected CarPlay scene, not an empty display.
    data = Path(run('xcrun', 'simctl', 'get_app_container', udid, 'app.muwa.nasheeds', 'data').strip())
    proof = data / 'Documents/carplay-connected.txt'
    status['scene_connected'] = proof.exists() and proof.read_text() == 'Muwa CarPlay connected'
    if not status['scene_connected']:
        (out / 'carplay.png').unlink(missing_ok=True)
        raise RuntimeError('External display exists but Muwa CarPlay scene did not connect')
    status['captured'] = True
    status['device'] = phone['name']
except Exception as error:
    status['reason'] = str(error)
    # Preserve the native launch denial so signing/runtime failures can be
    # distinguished from a missing external display or an app scene failure.
    if status.get('booted'):
        predicate = '(process == "SpringBoard" OR process == "runningboardd" OR process == "amfid") AND (eventMessage CONTAINS "app.muwa.nasheeds" OR eventMessage CONTAINS "Muwa.app")'
        try:
            diagnostic = run('xcrun', 'simctl', 'spawn', udid, 'log', 'show',
                             '--style', 'compact', '--last', '3m', '--predicate', predicate,
                             timeout=30)
            (out / 'launch-diagnostic.log').write_text(diagnostic)
        except Exception as diagnostic_error:
            status['diagnostic_error'] = str(diagnostic_error)
finally:
    (out / 'status.json').write_text(json.dumps(status, ensure_ascii=False, indent=2))
    print(json.dumps(status, ensure_ascii=False), flush=True)
