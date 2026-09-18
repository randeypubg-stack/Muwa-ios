#!/usr/bin/env python3
import argparse, hashlib, json, os, plistlib, re, shutil, stat, tempfile, urllib.parse, urllib.request, zipfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
BUNDLE_ID = "app.muwa.nasheeds"
PROJECT_ID = "20d2f317-3710-4331-80ee-ea6072056928"
ROOT_FILES = ("package.json","pnpm-lock.yaml","capacitor.config.json")
REQUIRED = ROOT_FILES + (
    "ios/App/Podfile","ios/App/App.xcodeproj/project.pbxproj","ios/App/App/Info.plist",
    "ios/App/App/capacitor.config.json","ios/App/App/public/index.html","ios/App/App/AppDelegate.swift",
)

def req(ok,msg):
    if not ok: raise ValueError(msg)

def sha(path):
    h=hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda:f.read(1024*1024),b""): h.update(block)
    return h.hexdigest()

def verify(root):
    for name in REQUIRED: req((root/name).is_file(),f"Missing export file: {name}")
    for name in ("capacitor.config.json","ios/App/App/capacitor.config.json"):
        cfg=json.loads((root/name).read_text())
        req(cfg.get("appId")==BUNDLE_ID,f"Unexpected appId in {name}")
        req(not cfg.get("server",{}).get("url"),"Remote site wrapper is not allowed")
    pbx=(root/"ios/App/App.xcodeproj/project.pbxproj").read_text()
    req(BUNDLE_ID in re.findall(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*"?([^;"\s]+)',pbx),"Wrong bundle id")
    html=(root/"ios/App/App/public/index.html").read_text()
    refs=re.findall(r'(?:src|href)=["\'](/_assets/[^"\']+)',html)
    req(any(x.endswith(".js") for x in refs),"Bundled JS entry missing")
    for ref in refs: req((root/"ios/App/App/public"/ref.lstrip("/")).is_file(),f"Missing bundled asset: {ref}")
    pkg=json.loads((root/"package.json").read_text())
    req(pkg.get("dependencies",{}).get("@capacitor/ios")=="8.0.0","Expected Capacitor iOS 8.0.0")

def normalize(root):
    pod=root/"ios/App/Podfile"
    pod.write_text(re.sub(r"node_modules/\.pnpm/[^/]+/node_modules/","node_modules/",pod.read_text()))
    plist=root/"ios/App/App/Info.plist"
    data=plistlib.loads(plist.read_bytes())
    data["CFBundleShortVersionString"]="$(MARKETING_VERSION)"
    data["CFBundleVersion"]="$(CURRENT_PROJECT_VERSION)"
    plist.write_bytes(plistlib.dumps(data,sort_keys=False))
    pbx=(root/"ios/App/App.xcodeproj/project.pbxproj").read_text()
    m=re.search(r"([A-F0-9]{24}) /\* App \*/ = \{\s*isa = PBXNativeTarget;",pbx)
    req(m is not None,"App target not found")
    schemes=root/"ios/App/App.xcodeproj/xcshareddata/xcschemes"; schemes.mkdir(parents=True,exist_ok=True)
    (schemes/"App.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{m.group(1)}" BuildableName="App.app" BlueprintName="App" ReferencedContainer="container:App.xcodeproj"/>
</BuildActionEntry></BuildActionEntries></BuildAction>
<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')

def import_export(archive):
    with tempfile.TemporaryDirectory(prefix="muwa-import-") as d:
        stage=Path(d)
        with zipfile.ZipFile(archive) as z:
            names=z.namelist()
            prefixes=[n[:-len("capacitor.config.json")] for n in names if n.endswith("capacitor.config.json") and n[:-len("capacitor.config.json")]+"ios/App/Podfile" in names]
            req(len(prefixes)==1,"ZIP must contain exactly one native project")
            prefix=prefixes[0]
            for info in z.infolist():
                if not info.filename.startswith(prefix) or info.is_dir(): continue
                rel=info.filename[len(prefix):]
                if not (rel.startswith("ios/") or rel in ROOT_FILES): continue
                p=PurePosixPath(rel)
                req(not p.is_absolute() and ".." not in p.parts and "\\" not in rel,"Unsafe ZIP path")
                req(not stat.S_ISLNK(info.external_attr>>16),"Symlinks are not supported")
                dst=stage/rel; dst.parent.mkdir(parents=True,exist_ok=True)
                with z.open(info) as src, dst.open("wb") as out: shutil.copyfileobj(src,out)
        verify(stage); normalize(stage); verify(stage)
        if (ROOT/"ios").exists(): shutil.rmtree(ROOT/"ios")
        shutil.copytree(stage/"ios",ROOT/"ios")
        for n in ROOT_FILES: shutil.copy2(stage/n,ROOT/n)
        files=sorted(p for p in (ROOT/"ios").rglob("*") if p.is_file())+[ROOT/n for n in ROOT_FILES]
        manifest={"project_id":PROJECT_ID,"bundle_id":BUNDLE_ID,"source_archive_sha256":sha(archive),
                  "files":{p.relative_to(ROOT).as_posix():sha(p) for p in files}}
        (ROOT/"floot-export.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n")
        print(f"Imported {len(files)} files for {BUNDLE_ID}")

def download(url,path):
    u=urllib.parse.urlsplit(url); req(u.scheme=="https" and u.hostname and not u.username,"HTTPS URL required")
    request=urllib.request.Request(url,headers={"User-Agent":"Muwa-iOS-Builder/1.0"})
    with urllib.request.urlopen(request,timeout=120) as r, path.open("wb") as f:
        shutil.copyfileobj(r,f)

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("archive",nargs="?"); ap.add_argument("--from-url"); ap.add_argument("--check",action="store_true")
    a=ap.parse_args()
    if a.check:
        verify(ROOT)
        manifest=json.loads((ROOT/"floot-export.json").read_text())
        for name,expected in manifest["files"].items():
            req((ROOT/name).is_file() and sha(ROOT/name)==expected,f"Export changed: {name}")
        print("Floot export verified")
    elif a.from_url:
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/"floot.zip"; download(a.from_url,p); import_export(p)
    elif a.archive:
        import_export(Path(a.archive).resolve())
    else:
        ap.error("provide archive, --from-url, or --check")

if __name__=="__main__": main()
