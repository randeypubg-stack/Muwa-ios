"""Capture installed native Android debug screens directly onto the CI runner."""
import json
import os
from pathlib import Path
import struct
import subprocess
import time

PACKAGE = 'app.muwa.nasheeds'
ROUTES = ['home', 'library', 'profile', 'premium', 'promo', 'settings', 'search', 'queue', 'downloads', 'auth', 'publication', 'player']

def adb(*args, binary=False):
    return subprocess.check_output(['adb', *args], text=not binary, timeout=60)

out = Path(os.environ.get('MUWA_ANDROID_OUTPUT', 'build/android-previews'))
out.mkdir(parents=True, exist_ok=True)
manifest = {'package': PACKAGE, 'model': adb('shell', 'getprop', 'ro.product.model').strip(),
            'size': adb('shell', 'wm', 'size').strip(), 'density': adb('shell', 'wm', 'density').strip(), 'screens': []}
for rotation, orientation in [(0, 'portrait'), (1, 'landscape')]:
    adb('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP')
    adb('shell', 'wm', 'dismiss-keyguard')
    adb('shell', 'settings', 'put', 'system', 'accelerometer_rotation', '0')
    adb('shell', 'settings', 'put', 'system', 'user_rotation', str(rotation))
    time.sleep(2)
    folder = out / orientation
    folder.mkdir(parents=True, exist_ok=True)
    for route in ROUTES:
        print(f'Capture Android {orientation}: {route}', flush=True)
        adb('shell', 'am', 'force-stop', PACKAGE)
        result = adb('shell', 'am', 'start', '-W', '-n', f'{PACKAGE}/.MainActivity', '--es', 'review.route', route)
        assert 'Error:' not in result, result
        time.sleep(5 if route == 'player' else 2)
        foreground = adb('shell', 'dumpsys', 'activity', 'activities')
        assert any(PACKAGE in line and ('mResumedActivity' in line or 'topResumedActivity' in line) for line in foreground.splitlines()), 'Muwa is not in the foreground'
        screenshot = adb('exec-out', 'screencap', '-p', binary=True)
        assert screenshot.startswith(b'\x89PNG\r\n\x1a\n'), 'Invalid screenshot'
        width, height = struct.unpack('>II', screenshot[16:24])
        assert (height > width) if rotation == 0 else (width > height), f'Incorrect orientation: {width}x{height}'
        path = folder / f'{route}.png'
        path.write_bytes(screenshot)
        manifest['screens'].append({'route': route, 'orientation': orientation, 'width': width, 'height': height, 'file': str(path.relative_to(out))})
        (out / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
assert len(manifest['screens']) == len(ROUTES) * 2
print(f'Captured {len(manifest["screens"])} native Android screens', flush=True)
