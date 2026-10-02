"""Register additional native sources in the existing immutable Xcode project."""
from pathlib import Path
import hashlib
import plistlib
import sys

root = Path(sys.argv[1])
patches = Path(__file__).resolve().parents[1] / 'native-patches'
project = root / 'MuwaNasheeds.xcodeproj/project.pbxproj'
text = project.read_text()
# The old subtitle panel has no callers after the player moved to the rail and
# reader. Remove its original registration instead of compiling a second UI.
text = ''.join(line for line in text.splitlines(keepends=True) if '/* SubtitlePanel.swift' not in line)
(root / 'Sources/Views/Player/SubtitlePanel.swift').unlink(missing_ok=True)
files = {
    'CatalogStore.swift': 'Services',
    'Track.swift': 'Models',
    'FeatureAccess.swift': 'Services',
    'Diagnostics.swift': 'Services',
    'AppSettingsView.swift': 'Views/Profile',
    'CarPlaySceneDelegate.swift': 'App',
    'MuwaApplicationDelegate.swift': 'App',
    'LaunchExperience.swift': 'App',
    'DownloadManager.swift': 'Services',
    'AuthManager.swift': 'Services',
    'AuthService.swift': 'Services',
    'BackendConfig.swift': 'Services',
    'PublicationUploadService.swift': 'Services',
    'SearchView.swift': 'Views/Search',
    'AppBackground.swift': 'Theme',
    'DesignTokens.swift': 'Theme',
    'Typography.swift': 'Theme',
    'DisplayText.swift': 'Views/Components',
    'Motion.swift': 'Theme',
    'ScreenHeader.swift': 'Views/Components',
    'HomeCollectionViews.swift': 'Views/Home',
    'QueueTrackRow.swift': 'Views/Player',
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
    text = text.replace('CODE_SIGN_STYLE = Automatic;', 'CODE_SIGN_STYLE = Automatic;\n\t\t\tCODE_SIGN_ENTITLEMENTS = "$(MUWA_CARPLAY_ENTITLEMENTS)";')
else:
    text = text.replace('CODE_SIGN_ENTITLEMENTS = MuwaCarPlay.entitlements;', 'CODE_SIGN_ENTITLEMENTS = "$(MUWA_CARPLAY_ENTITLEMENTS)";')
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

# Apply the supplied brand assets after the immutable source has been verified.
brand = patches.parent / 'branding'
manifest = __import__('json').loads((brand / 'manifest.json').read_text())
for name, directory in [('AppIcon-1024.png', 'AppIcon.appiconset'), ('AppMark.png', 'AppMark.imageset')]:
    payload = (brand / name).read_bytes()
    if hashlib.sha256(payload).hexdigest() != manifest['assets'][name]:
        raise ValueError(f'Brand asset checksum mismatch: {name}')
    destination = root / 'Resources/Assets.xcassets' / directory / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(payload)
data['CFBundleDisplayName'] = 'Muwa'
data['CFBundleName'] = 'Muwa'
info.write_bytes(plistlib.dumps(data))
text = text.replace('PRODUCT_NAME = "Muwa Nasheeds";', 'PRODUCT_NAME = Muwa;')
text = text.replace('/* Muwa Nasheeds.app */', '/* Muwa.app */').replace('path = "Muwa Nasheeds.app";', 'path = Muwa.app;')
project.write_text(text)
scheme = root / 'MuwaNasheeds.xcodeproj/xcshareddata/xcschemes/MuwaNasheeds.xcscheme'
scheme.write_text(scheme.read_text().replace('BuildableName="Muwa Nasheeds.app"', 'BuildableName="Muwa.app"'))
