import json, subprocess, time
from pathlib import Path

def run(*args):
    return subprocess.check_output(list(args), text=True)

devices=json.loads(run('xcrun','simctl','list','devices','available','--json'))['devices']
available=[d for group in devices.values() for d in group if d.get('isAvailable')]
phones=[d for d in available if d['name'].startswith('iPhone')]
pads=[d for d in available if d['name'].startswith('iPad')]
assert phones and pads, 'Need iPhone and iPad simulator runtimes'
selected=[phones[0],pads[0]]
small=next((d for d in phones if 'SE' in d['name']),None)
if small and small not in selected: selected.append(small)
app=next(Path('build/PreviewDerivedData/Build/Products/Debug-iphonesimulator').glob('*.app'))
out=Path('build/previews'); out.mkdir(parents=True,exist_ok=True)
for i,d in enumerate(selected):
    udid=d['udid']
    print('Capture device:', d['name'], flush=True)
    if d['state']!='Booted': run('xcrun','simctl','boot',udid)
    run('xcrun','simctl','bootstatus',udid,'-b')
    run('xcrun','simctl','ui',udid,'appearance','dark')
    run('xcrun','simctl','install',udid,str(app))
    for label,args in [('home',[]),('player',['--audit-player']),('library',['--audit-library']),('landscape',['--audit-player','--audit-landscape'])]:
        run('xcrun','simctl','launch','--terminate-running-process',udid,'app.muwa.nasheeds',*args)
        time.sleep(5)
        run('xcrun','simctl','io',udid,'screenshot',str(out/f'{i}-{label}.png'))
    run('xcrun','simctl','shutdown',udid)
    (out/f'{i}-device.txt').write_text(d['name'])
