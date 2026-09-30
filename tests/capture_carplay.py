"""Capture the real Simulator CarPlay display when available; never fabricate it."""
import json
import subprocess
import time
from pathlib import Path

out = Path('build/previews/carplay')
out.mkdir(parents=True, exist_ok=True)
status = {'captured': False, 'distribution': 'requires Apple-approved CarPlay Audio provisioning'}

def run(*args, timeout=45):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT, timeout=timeout)

try:
    devices = json.loads(run('xcrun', 'simctl', 'list', 'devices', 'available', '--json'))['devices']
    phone = next(d for group in devices.values() for d in group if d.get('isAvailable') and d['name'].startswith('iPhone'))
    udid = phone['udid']
    app = next(Path('build/PreviewDerivedData/Build/Products/Debug-iphonesimulator').glob('*.app'))
    # Only the simulator fixture is ad-hoc signed. The device IPA remains unsigned.
    entitlement = Path('native-patches/MuwaCarPlay.entitlements').resolve()
    run('codesign', '--force', '--sign', '-', '--entitlements', str(entitlement), str(app))
    if phone['state'] != 'Booted':
        run('xcrun', 'simctl', 'boot', udid)
    run('xcrun', 'simctl', 'bootstatus', udid, '-b', timeout=180)
    run('xcrun', 'simctl', 'install', udid, str(app))
    data = Path(run('xcrun', 'simctl', 'get_app_container', udid, 'app.muwa.nasheeds', 'data').strip())
    (data / 'Documents/carplay-connected.txt').unlink(missing_ok=True)
    run('open', '-a', 'Simulator', '--args', '-CurrentDeviceUDID', udid)
    time.sleep(3)
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
    run('xcrun', 'simctl', 'launch', '--terminate-running-process', udid, 'app.muwa.nasheeds', '--audit-player')
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
finally:
    (out / 'status.json').write_text(json.dumps(status, ensure_ascii=False, indent=2))
    print(json.dumps(status, ensure_ascii=False), flush=True)
