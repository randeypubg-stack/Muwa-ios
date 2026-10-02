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
    return subprocess.check_output(['adb', *args], text=not binary, timeout=30)

def lock_rotation(rotation):
    adb('shell', 'settings', 'put', 'system', 'accelerometer_rotation', '0')
    adb('shell', 'settings', 'put', 'system', 'user_rotation', str(rotation))
    # Use WindowManager's live rotation API as well as the persisted preference.
    # A cold launch may briefly inherit the launcher's portrait starting window.
    adb('shell', 'wm', 'user-rotation', 'lock', str(rotation))

def capture_oriented(rotation, diagnostic_path):
    deadline = time.monotonic() + 10
    retries = 0
    while True:
        screenshot = adb('exec-out', 'screencap', '-p', binary=True)
        assert screenshot.startswith(b'\x89PNG\r\n\x1a\n'), 'Invalid screenshot'
        width, height = struct.unpack('>II', screenshot[16:24])
        correct = height > width if rotation == 0 else width > height
        if correct:
            return screenshot, width, height, retries
        # Preserve the actual bad frame, so a persistent layout/rotation problem
        # is inspectable even when the orientation assertion rejects the capture.
        diagnostic_path.parent.mkdir(parents=True, exist_ok=True)
        diagnostic_path.write_bytes(screenshot)
        assert time.monotonic() < deadline, f'Incorrect orientation after settling: {width}x{height}'
        lock_rotation(rotation)
        retries += 1
        time.sleep(0.5)

out = Path(os.environ.get('MUWA_ANDROID_OUTPUT', 'build/android-previews'))
out.mkdir(parents=True, exist_ok=True)
manifest = {'package': PACKAGE, 'model': adb('shell', 'getprop', 'ro.product.model').strip(),
            'size': adb('shell', 'wm', 'size').strip(), 'density': adb('shell', 'wm', 'density').strip(), 'screens': []}
for rotation, orientation in [(0, 'portrait'), (1, 'landscape')]:
    adb('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP')
    adb('shell', 'wm', 'dismiss-keyguard')
    lock_rotation(rotation)
    time.sleep(2)
    folder = out / orientation
    folder.mkdir(parents=True, exist_ok=True)
    for route in ROUTES:
        print(f'Capture Android {orientation}: {route}', flush=True)
        adb('shell', 'am', 'force-stop', PACKAGE)
        result = adb('shell', 'am', 'start', '-W', '-n', f'{PACKAGE}/.MainActivity', '--es', 'review.route', route)
        assert 'Error:' not in result, result
        lock_rotation(rotation)
        time.sleep(5 if route == 'player' else 2)
        foreground = adb('shell', 'dumpsys', 'activity', 'activities')
        assert any(PACKAGE in line and ('mResumedActivity' in line or 'topResumedActivity' in line) for line in foreground.splitlines()), 'Muwa is not in the foreground'
        screenshot, width, height, retries = capture_oriented(rotation, out / 'diagnostics' / f'{orientation}-{route}-orientation.png')
        assert (height > width) if rotation == 0 else (width > height), f'Incorrect orientation: {width}x{height}'
        path = folder / f'{route}.png'
        path.write_bytes(screenshot)
        manifest['screens'].append({'route': route, 'orientation': orientation, 'width': width, 'height': height, 'orientationRetries': retries, 'file': str(path.relative_to(out))})
        (out / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
assert len(manifest['screens']) == len(ROUTES) * 2
try:
    lock_rotation(0)
    adb('shell', 'settings', 'put', 'system', 'font_scale', '1.45')
    for route in ['home', 'queue']:
        adb('shell', 'am', 'force-stop', PACKAGE)
        result = adb('shell', 'am', 'start', '-W', '-n', f'{PACKAGE}/.MainActivity', '--es', 'review.route', route)
        assert 'Error:' not in result, result
        time.sleep(3)
        path = out / 'large-text' / f'{route}.png'
        path.parent.mkdir(parents=True, exist_ok=True)
        screenshot, width, height, retries = capture_oriented(0, out / 'diagnostics' / f'{route}-large-text.png')
        path.write_bytes(screenshot)
        manifest['screens'].append({'route': route, 'orientation': 'portrait', 'fontScale': 1.45,
            'width': width, 'height': height, 'orientationRetries': retries, 'file': str(path.relative_to(out))})
finally:
    adb('shell', 'settings', 'put', 'system', 'font_scale', '1.0')
(out / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
print(f'Captured {len(manifest["screens"])} native Android screens', flush=True)
