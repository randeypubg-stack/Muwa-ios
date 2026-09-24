import json, os, signal, subprocess, time
from pathlib import Path

def run(*args):
    print("Running:", " ".join(args), flush=True)
    return subprocess.check_output(list(args), text=True, timeout=240)

devices=json.loads(run('xcrun','simctl','list','devices','available','--json'))['devices']
available=[d for group in devices.values() for d in group if d.get('isAvailable')]
phones=[d for d in available if d['name'].startswith('iPhone')]
assert phones, 'Need an iPhone simulator runtime'
device=phones[0]
udid=device['udid']
app=next(Path('build/PreviewDerivedData/Build/Products/Debug-iphonesimulator').glob('*.app'))
out=Path('build/previews')
out.mkdir(parents=True,exist_ok=True)

print('Subtitle motion device:',device['name'],flush=True)
if device['state']!='Booted':
    run('xcrun','simctl','boot',udid)
run('xcrun','simctl','bootstatus',udid,'-b')
run('xcrun','simctl','ui',udid,'appearance','dark')
run('xcrun','simctl','install',udid,str(app))
run(
    'xcrun','simctl','launch','--terminate-running-process',udid,
    'app.muwa.nasheeds','--audit-player','--audit-ai','--audit-subtitle-motion'
)
time.sleep(4)

video=(out/'subtitle-rail-motion.mp4').resolve()
cmd=['xcrun','simctl','io',udid,'recordVideo','--codec=h264',str(video)]
print("Running:"," ".join(cmd),flush=True)
proc=subprocess.Popen(
    cmd,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    start_new_session=True
)
time.sleep(8)
os.killpg(proc.pid,signal.SIGINT)
stdout,stderr=proc.communicate(timeout=30)
if stdout.strip():
    print('recordVideo stdout:',stdout.strip(),flush=True)
if stderr.strip():
    print('recordVideo stderr:',stderr.strip(),flush=True)

for _ in range(30):
    if video.exists() and video.stat().st_size > 10000:
        break
    time.sleep(0.5)

assert video.exists(), f'Video file was not created: {video}'
assert video.stat().st_size > 10000, f'Video file is too small: {video.stat().st_size}'
print(f'PASS: subtitle motion video {video.stat().st_size} bytes',flush=True)
run('xcrun','simctl','shutdown',udid)
