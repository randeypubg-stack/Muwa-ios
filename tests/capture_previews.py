import json, re, subprocess, time
import shutil
import os
import struct
from pathlib import Path
from select_apple_review_devices import load_selection, open_simulator_gui

def run(*args, timeout=240):
    print("Running:", " ".join(args), flush=True)
    return subprocess.check_output(list(args), text=True, timeout=timeout)

def launch_ready(udid, args):
    data = Path(run('xcrun','simctl','get_app_container',udid,'app.muwa.nasheeds','data').strip())
    for name in ['preview-ready.txt', 'queue-ready.txt', 'clock-check.txt', 'artwork-check.txt']:
        (data / 'Documents' / name).unlink(missing_ok=True)
    response = run('xcrun','simctl','launch','--terminate-running-process',udid,'app.muwa.nasheeds',*args)
    match = re.search(r'app\.muwa\.nasheeds:\s*(\d+)', response)
    assert match, f'No native fixture process: {response}'
    pid = match.group(1)
    ready = data / 'Documents' / ('queue-ready.txt' if '--audit-queue' in args else 'preview-ready.txt')
    deadline = time.monotonic() + 30
    while not ready.exists() or ready.read_text() != pid:
        assert time.monotonic() < deadline, f'Native screen did not become ready: {args}'
        time.sleep(0.25)
    time.sleep(3)
    return data

kind = os.environ.get('MUWA_REVIEW_DEVICE')
selected, inventory = load_selection(kind, os.environ.get('MUWA_REQUESTED_DEVICE'), os.environ.get('MUWA_REQUESTED_IOS'), os.environ.get('MUWA_REVIEW_RUNTIME_VERSION'))
run('xcrun', 'simctl', 'shutdown', 'all')
app=next(Path('build/PreviewDerivedData/Build/Products/Debug-iphonesimulator').glob('*.app'))
out=Path('build/previews'); out.mkdir(parents=True,exist_ok=True)
(out/'device-inventory.json').write_text(json.dumps(inventory, ensure_ascii=False, indent=2))
manifest = [{
    'device': device['name'], 'index': index, 'kind': device['kind'],
    'simulatorName': device['simulatorName'], 'udid': device['udid'],
    'deviceTypeIdentifier': device['deviceTypeIdentifier'],
    'runtimeIdentifier': device['runtimeIdentifier'], 'runtime': device['runtimeName'],
    'osVersion': device['runtimeVersion'], 'osBuild': device['runtimeBuild'],
    'requiredRuntimeVersion': inventory['requiredRuntimeVersion'],
    'toolchain': inventory['toolchain'], 'requested': inventory['requested'],
    'captureCompleted': False,
} for index, device in enumerate(selected)]
(out/'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
for i,d in enumerate(selected):
    udid=d['udid']
    print('Capture device:', d['name'], flush=True)
    (out/f'{i}-device.txt').write_text(d['name'])
    # shutdown all above invalidates the states from the original device list.
    run('xcrun','simctl','boot',udid)
    preparation = {'gui':open_simulator_gui(udid), 'appearanceAttempts':0, 'recoveredOnce':False}
    run('xcrun','simctl','bootstatus',udid,'-b')
    preparation['bootstatusCompleted'] = True
    preparation_path = out/f'{i}-simulator-preparation.json'
    # simctl bootstatus succeeded but appearance timed out before Muwa install
    # on the cold iOS 27 mini runner. Warm the GUI, bound that command, and allow
    # one explicit restart of this selected device before declaring a failure.
    for attempt in range(2):
        preparation['appearanceAttempts'] = attempt + 1
        preparation_path.write_text(json.dumps(preparation, ensure_ascii=False, indent=2))
        try:
            run('xcrun','simctl','ui',udid,'appearance','dark',timeout=60)
            preparation['appearanceConfigured'] = True
            break
        except subprocess.TimeoutExpired as error:
            preparation['appearanceTimeout'] = {'command':error.cmd,'seconds':error.timeout}
            preparation_path.write_text(json.dumps(preparation, ensure_ascii=False, indent=2))
            if attempt:
                raise
            run('xcrun','simctl','shutdown',udid,timeout=60)
            run('xcrun','simctl','boot',udid)
            open_simulator_gui(udid)
            run('xcrun','simctl','bootstatus',udid,'-b')
            preparation['recoveredOnce'] = True
    preparation_path.write_text(json.dumps(preparation, ensure_ascii=False, indent=2))
    manifest[i]['simulatorPreparation'] = preparation
    run('xcrun','simctl','install',udid,str(app))
    for label,args in [('home',[]),('settings',['--audit-profile','--audit-settings']),('search',['--audit-search']),('queue',['--audit-player','--audit-queue']),('profile',['--audit-profile']),('premium',['--audit-profile','--audit-premium']),('promo',['--audit-profile','--audit-promo']),('owner-premium',['--audit-profile','--audit-premium','--audit-owner']),('owner-promo',['--audit-profile','--audit-promo','--audit-owner']),('ai-unavailable',['--audit-player','--audit-ai-unavailable']),('player',['--audit-player']),('library-empty',['--audit-library-empty']),('playlist-create',['--audit-playlist-create']),('library',['--audit-library']),('landscape',['--audit-player','--audit-landscape']),('ai',['--audit-player','--audit-ai']),('ai-reader',['--audit-player','--audit-ai','--audit-ai-expanded'])]:
        if label == 'landscape' and d['name'].startswith('iPad'):
            # iPad window geometry requests may be ignored in multitasking. Its
            # physical rotation is exercised and captured by the separate XCTest
            # matrix; never package a portrait framebuffer as landscape proof.
            (out/f'{i}-landscape.png').unlink(missing_ok=True)
            manifest[i]['landscapeReview'] = {
                'status':'requires-separate-native-rotation-test',
                'test':'NativeInteractionTests.testHomeAndPlayerFollowActualDeviceRotation',
                'method':'XCUIDevice.orientation with device PNG dimension assertions',
            }
            continue
        data = launch_ready(udid, args)
        run('xcrun','simctl','io',udid,'screenshot',str(out/f'{i}-{label}.png'))
        if label in ('home', 'landscape'):
            header = (out/f'{i}-{label}.png').read_bytes()[:24]
            assert header.startswith(b'\x89PNG\r\n\x1a\n') and len(header) == 24, 'Invalid native screenshot'
            width, height = struct.unpack('>II', header[16:24])
            if label == 'home':
                manifest[i]['screenPixels'] = {'width': width, 'height': height}
            else:
                assert width > height, f'A portrait PNG cannot prove landscape: {d["name"]} {width}x{height}'
                manifest[i]['landscapeReview'] = {'status':'captured','width':width,'height':height,'method':'Unmodified Simulator framebuffer'}
        proof = (data/'Documents/clock-check.txt').read_text()
        assert proof == '100 ticks; PlayerManager notifications: 0', 'Clock isolation check did not complete'
        (out/f'{i}-clock-check.txt').write_text(proof)
        if label == 'player':
            report_path = data/'Documents/artwork-check.txt'
            deadline = time.monotonic() + 45
            while not report_path.exists():
                assert time.monotonic() < deadline, 'Current fixture artwork check did not finish'
                time.sleep(0.25)
            report = report_path.read_text()
            assert 'cover=true; backdrop=true' in report, report
            (out/f'{i}-artwork-check.txt').write_text(report)
            shutil.copy2(data/'Documents/cached-backdrop.png', out/f'{i}-cached-backdrop.png')
    # Capture actual large-text layouts after the ordinary states, then restore
    # the simulator setting before launch/motion review.
    try:
        run('xcrun','simctl','ui',udid,'content_size','accessibility-large')
        for label,args in [('home-large-text',[]),('queue-large-text',['--audit-player','--audit-queue'])]:
            launch_ready(udid, args)
            run('xcrun','simctl','io',udid,'screenshot',str(out/f'{i}-{label}.png'))
    finally:
        run('xcrun','simctl','ui',udid,'content_size','large')
    # The phone review immediately records launch motion with the same installed
    # app. Keep its Simulator warm; every other matrix job closes its own device.
    if kind != 'phone': run('xcrun','simctl','shutdown',udid)
    (out/f'{i}-device.txt').write_text(d['name'])
    manifest[i]['captureCompleted'] = True
    (out/'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2))

# UI/decoder checks use controlled fixtures; record live service availability
# separately so a successful design capture never implies CDN playback works.
import urllib.request, urllib.error
live=[]
origin = 'https://93.188.187.96'
for path, expected_status in [('/_health', 200), ('/_api/auth/session', 401)]:
    entry={'path':path, 'expectedStatus':expected_status, 'authenticated':False}
    try:
        with urllib.request.urlopen(origin+path,timeout=10) as response:
            entry.update(status=response.status,contentType=response.headers.get('Content-Type'),passed=response.status == expected_status)
    except urllib.error.HTTPError as error:
        entry.update(status=error.code,passed=error.code == expected_status)
    except Exception as error:
        entry.update(error=str(error),passed=False)
    live.append(entry)
(out/'live-assets-status.json').write_text(json.dumps({'origin':origin,'checks':live,'scope':'Read-only Beget health and anonymous authentication checks; no account cookies or credentials','uiFixture':'Native app with local paused audio and controlled artwork decoder/catalogue fixtures; screenshots do not prove production media playback'},ensure_ascii=False,indent=2))
