"""Check CarPlay registration without altering phone scenes or duplicating Xcode entries."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory) / 'native'
    shutil.copytree(Path(sys.argv[1]), root)
    info = root / 'Info.plist'
    data = plistlib.loads(info.read_bytes())
    phone = [{'UISceneConfigurationName': 'Existing phone scene', 'UISceneDelegateClassName': 'PhoneDelegate'}]
    data['UIApplicationSceneManifest'] = {'UISceneConfigurations': {'UIWindowSceneSessionRoleApplication': phone}}
    info.write_bytes(plistlib.dumps(data))
    script = Path(__file__).resolve().parents[1] / 'scripts/prepare_native_extras.py'
    subprocess.run([sys.executable, str(script), str(root)], check=True)
    first = (root / 'MuwaNasheeds.xcodeproj/project.pbxproj').read_bytes()
    subprocess.run([sys.executable, str(script), str(root)], check=True)
    assert first == (root / 'MuwaNasheeds.xcodeproj/project.pbxproj').read_bytes(), 'Registration is not idempotent'
    assert b'SubtitlePanel.swift' not in first and not (root / 'Sources/Views/Player/SubtitlePanel.swift').exists(), 'Retired subtitle UI is still compiled'
    for name in ['AuthService.swift', 'AuthManager.swift', 'DownloadManager.swift', 'LaunchExperience.swift', 'CatalogStore.swift', 'Track.swift', 'BackendConfig.swift', 'PublicationUploadService.swift']:
        assert first.count(f'/* {name} in Sources */ ='.encode()) == 1, f'Duplicate compiled implementation: {name}'
        assert first.count(f'/* {name} */ ='.encode()) == 1, f'Duplicate source reference: {name}'
    scenes = plistlib.loads(info.read_bytes())['UIApplicationSceneManifest']['UISceneConfigurations']
    assert scenes['UIWindowSceneSessionRoleApplication'] == phone, 'Phone scene was replaced'
    assert len(scenes['CPTemplateApplicationSceneSessionRoleApplication']) == 1
    assert scenes['CPTemplateApplicationSceneSessionRoleApplication'][0]['UISceneClassName'] == 'CPTemplateApplicationScene'
    entitlement = plistlib.loads((root / 'MuwaCarPlay.entitlements').read_bytes())
    assert entitlement['com.apple.developer.carplay-audio'] is True
    assert first.count(b'CODE_SIGN_ENTITLEMENTS = "$(MUWA_CARPLAY_ENTITLEMENTS)";') == 2, 'Debug/Release signing differs'
    assert b'MUWA_CARPLAY_ENTITLEMENTS = MuwaCarPlay.entitlements;' not in first, 'Normal signing requires an unapproved entitlement'
    assert plistlib.loads(info.read_bytes())['CFBundleDisplayName'] == 'Muwa'
    assert b'PRODUCT_NAME = Muwa;' in first
    assert (root / 'Resources/Assets.xcassets/AppMark.imageset/AppMark.png').read_bytes() == (script.parents[1] / 'branding/AppMark.png').read_bytes()
    print('PASS: phone scene preservation, CarPlay registration, Debug/Release entitlement and idempotency')
