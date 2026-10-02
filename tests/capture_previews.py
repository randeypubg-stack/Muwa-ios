import json, subprocess, time
import shutil
import os
from pathlib import Path

def run(*args):
    print("Running:", " ".join(args), flush=True)
    return subprocess.check_output(list(args), text=True, timeout=240)

devices=json.loads(run('xcrun','simctl','list','devices','available','--json'))['devices']
available=[d for group in devices.values() for d in group if d.get('isAvailable')]
phones=[d for d in available if d['name'].startswith('iPhone')]
pads=[d for d in available if d['name'].startswith('iPad')]
assert phones and pads, 'Need iPhone and iPad simulator runtimes'
selected=[phones[0],pads[0]]
large=next((d for d in phones if 'Pro Max' in d['name'] or 'Plus' in d['name']), None)
mini=next((d for d in pads if 'mini' in d['name']), None)
for device in [large, mini]:
    if device and device not in selected: selected.append(device)
small=next((d for d in phones if 'SE' in d['name']),None)
if small and small not in selected: selected.append(small)
kind = os.environ.get('MUWA_REVIEW_DEVICE')
if kind:
    requested = {'phone': phones[0], 'large-phone': large, 'tablet': pads[0], 'small-tablet': mini}.get(kind)
    assert requested is not None, f'Review device unavailable: {kind}'
    selected = [requested]
run('xcrun', 'simctl', 'shutdown', 'all')
app=next(Path('build/PreviewDerivedData/Build/Products/Debug-iphonesimulator').glob('*.app'))
out=Path('build/previews'); out.mkdir(parents=True,exist_ok=True)
(out/'manifest.json').write_text(json.dumps([{'device': d['name'], 'index': i} for i,d in enumerate(selected)], ensure_ascii=False, indent=2))
for i,d in enumerate(selected):
    udid=d['udid']
    print('Capture device:', d['name'], flush=True)
    (out/f'{i}-device.txt').write_text(d['name'])
    # shutdown all above invalidates the states from the original device list.
    run('xcrun','simctl','boot',udid)
    run('xcrun','simctl','bootstatus',udid,'-b')
    run('xcrun','simctl','ui',udid,'appearance','dark')
    run('xcrun','simctl','install',udid,str(app))
    for label,args in [('home',[]),('settings',['--audit-profile','--audit-settings']),('search',['--audit-search']),('queue',['--audit-player','--audit-queue']),('profile',['--audit-profile']),('premium',['--audit-profile','--audit-premium']),('promo',['--audit-profile','--audit-promo']),('owner-premium',['--audit-profile','--audit-premium','--audit-owner']),('owner-promo',['--audit-profile','--audit-promo','--audit-owner']),('ai-unavailable',['--audit-player','--audit-ai-unavailable']),('player',['--audit-player']),('library',['--audit-library']),('landscape',['--audit-player','--audit-landscape']),('ai',['--audit-player','--audit-ai']),('ai-reader',['--audit-player','--audit-ai','--audit-ai-expanded'])]:
        run('xcrun','simctl','launch','--terminate-running-process',udid,'app.muwa.nasheeds',*args)
        time.sleep(5)
        run('xcrun','simctl','io',udid,'screenshot',str(out/f'{i}-{label}.png'))
        data = Path(run('xcrun','simctl','get_app_container',udid,'app.muwa.nasheeds','data').strip())
        proof = (data/'Documents/clock-check.txt').read_text()
        assert proof == '100 ticks; PlayerManager notifications: 0', 'Clock isolation check did not complete'
        (out/f'{i}-clock-check.txt').write_text(proof)
        if label == 'player':
            report = (data/'Documents/artwork-check.txt').read_text()
            assert 'cover=true; backdrop=true' in report, report
            (out/f'{i}-artwork-check.txt').write_text(report)
            shutil.copy2(data/'Documents/cached-backdrop.png', out/f'{i}-cached-backdrop.png')
    # Capture actual large-text layouts after the ordinary states, then restore
    # the simulator setting before launch/motion review.
    try:
        run('xcrun','simctl','ui',udid,'content_size','accessibility-large')
        for label,args in [('home-large-text',[]),('queue-large-text',['--audit-player','--audit-queue'])]:
            run('xcrun','simctl','launch','--terminate-running-process',udid,'app.muwa.nasheeds',*args)
            time.sleep(4)
            run('xcrun','simctl','io',udid,'screenshot',str(out/f'{i}-{label}.png'))
    finally:
        run('xcrun','simctl','ui',udid,'content_size','large')
    # The phone review immediately records launch motion with the same installed
    # app. Keep its Simulator warm; every other matrix job closes its own device.
    if kind != 'phone': run('xcrun','simctl','shutdown',udid)
    (out/f'{i}-device.txt').write_text(d['name'])
(out/'manifest.json').write_text(json.dumps([{'device': d['name'], 'index': i} for i,d in enumerate(selected)], ensure_ascii=False, indent=2))
