"""Register additional native sources in the existing immutable Xcode project."""
from pathlib import Path
import hashlib
import plistlib
import sys

root = Path(sys.argv[1])
patches = Path(__file__).resolve().parents[1] / 'native-patches'
project = root / 'MuwaNasheeds.xcodeproj/project.pbxproj'
text = project.read_text()
files = {
    'FeatureAccess.swift': 'Services',
    'Diagnostics.swift': 'Services',
    'AppSettingsView.swift': 'Views/Profile',
    'CarPlaySceneDelegate.swift': 'App',
    'DownloadManager.swift': 'Services',
    'AuthManager.swift': 'Services',
    'SearchView.swift': 'Views/Search',
}
for name, directory in files.items():
    path = root / 'Sources' / directory / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes((patches / name).read_bytes())
    if f'/* {name} in Sources */' in text:
        continue
    ref = hashlib.sha256(f'ref:{name}'.encode()).hexdigest()[:24].upper()
    build = hashlib.sha256(f'build:{name}'.encode()).hexdigest()[:24].upper()
    text = text.replace('/* End PBXBuildFile section */', f'\t\t{build} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref}; }};\n/* End PBXBuildFile section */')
    text = text.replace('/* End PBXFileReference section */', f'\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {directory}/{name}; sourceTree = "<group>"; }};\n/* End PBXFileReference section */')
    text = text.replace('932704417AB46D25E8F18983 /* Sources */ = {isa = PBXGroup; children = (', f'932704417AB46D25E8F18983 /* Sources */ = {{isa = PBXGroup; children = (\n\t\t\t{ref} /* {name} */,')
    text = text.replace('E4F78730D65EE9F55E2BAC2F /* Sources */ = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (', f'E4F78730D65EE9F55E2BAC2F /* Sources */ = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (\n\t\t\t{build} /* {name} in Sources */,')
(root / 'MuwaCarPlay.entitlements').write_bytes((patches / 'MuwaCarPlay.entitlements').read_bytes())
if 'CODE_SIGN_ENTITLEMENTS' not in text:
    text = text.replace('CODE_SIGN_STYLE = Automatic;', 'CODE_SIGN_STYLE = Automatic;\n\t\t\tCODE_SIGN_ENTITLEMENTS = MuwaCarPlay.entitlements;')
project.write_text(text)
info = root / 'Info.plist'
data = plistlib.loads(info.read_bytes())
manifest = data.setdefault('UIApplicationSceneManifest', {})
manifest['UIApplicationSupportsMultipleScenes'] = True
manifest.setdefault('UISceneConfigurations', {})['CPTemplateApplicationSceneSessionRoleApplication'] = [{
            'UISceneConfigurationName': 'Muwa CarPlay',
            'UISceneClassName': 'CPTemplateApplicationScene',
            'UISceneDelegateClassName': '$(PRODUCT_MODULE_NAME).CarPlaySceneDelegate',
        }]
info.write_bytes(plistlib.dumps(data))
