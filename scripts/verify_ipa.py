#!/usr/bin/env python3
import hashlib,json,os,plistlib,struct,subprocess,sys,zipfile
from pathlib import Path
p=Path(sys.argv[1])
with zipfile.ZipFile(p) as z:
    app="Payload/Muwa.app/"
    info=plistlib.loads(z.read(app+"Info.plist"))
    assert info["CFBundleIdentifier"]=="app.muwa.nasheeds"
    exe=z.read(app+info["CFBundleExecutable"])
    magic,cpu=struct.unpack_from("<II",exe)
    assert magic==0xFEEDFACF and cpu==0x0100000C
    assert app+"public/index.html" in z.namelist()
    assert not any("/_CodeSignature/" in x or x.endswith(".mobileprovision") for x in z.namelist())
manifest=json.loads((Path(__file__).resolve().parents[1]/"floot-export.json").read_text())
report={"file":"Muwa.ipa","bundle_id":"app.muwa.nasheeds","version":info["CFBundleShortVersionString"],
"build_number":info["CFBundleVersion"],"architecture":"arm64","signed":False,
"source_commit":subprocess.check_output(["git","rev-parse","HEAD"],text=True).strip(),
"floot_export_sha256":manifest["source_archive_sha256"],"sha256":hashlib.sha256(p.read_bytes()).hexdigest(),
"run_url":f"https://github.com/{os.environ.get('GITHUB_REPOSITORY','randeypubg-stack/Muwa-ios')}/actions/runs/{os.environ.get('GITHUB_RUN_ID','')}"}
(p.parent/"build-info.json").write_text(json.dumps(report,indent=2)+"\n")
print(json.dumps(report,indent=2))
