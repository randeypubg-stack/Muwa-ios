#!/usr/bin/env python3
"""Build the complete Xcode source tree from the verified base and canonical patches.

Uses only Python's standard library; works on Linux, macOS and Windows.
Compilation and signing still require Xcode on macOS.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from zipfile import ZipFile

BASE_SHA256 = 'f07bce80d5b9b39583a8bce19f3e3b71caed205332649f13ccb45a8b28997f84'
DEFAULT_BUILD = 54


def assemble(repository: Path, output: Path, build: int) -> None:
    output = output.resolve()
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise ValueError('Output must be a new or empty directory; choose another --output.')
    if build < 1:
        raise ValueError('Build number must be positive.')
    base = repository / 'source-base/MuwaNativeBase.zip'
    if hashlib.sha256(base.read_bytes()).hexdigest() != BASE_SHA256:
        raise ValueError('Immutable iOS base checksum mismatch.')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='muwa-ios-', dir=output.parent) as directory:
        staging = Path(directory)
        with ZipFile(base) as archive:
            names = set()
            for entry in archive.infolist():
                path = PurePosixPath(entry.filename)
                if (entry.filename in names or path.is_absolute() or '..' in path.parts
                        or '\\' in entry.filename or not path.parts
                        or path.parts[0] != 'MuwaNasheedsNative'
                        or stat.S_ISLNK(entry.external_attr >> 16)):
                    raise ValueError(f'Unsafe or duplicate base entry: {entry.filename}')
                names.add(entry.filename)
            if archive.testzip() is not None:
                raise ValueError('Immutable iOS base CRC mismatch.')
            archive.extractall(staging)
        root = staging / 'MuwaNasheedsNative'
        subprocess.run([sys.executable, str(repository / 'scripts/prepare_native_extras.py'), str(root)], check=True)
        info = root / 'Info.plist'
        properties = plistlib.loads(info.read_bytes())
        properties['UILaunchScreen'] = {'UIColorName': 'LaunchBackground'}
        properties['CADisableMinimumFrameDurationOnPhone'] = True
        info.write_bytes(plistlib.dumps(properties))
        project = root / 'MuwaNasheeds.xcodeproj/project.pbxproj'
        content, count = re.subn(r'CURRENT_PROJECT_VERSION = 8;', f'CURRENT_PROJECT_VERSION = {build};', project.read_text(encoding='utf-8'))
        if count != 2:
            raise ValueError(f'Expected two immutable Debug/Release build settings, found {count}.')
        project.write_text(content, encoding='utf-8', newline='\n')
        # Content identity survives git archive extraction and offline restoration.
        digest = hashlib.sha256()
        for folder in ['native-patches', 'branding', 'source-base', 'scripts']:
            for path in sorted((repository / folder).rglob('*')):
                if path.is_file() and '__pycache__' not in path.parts and path.suffix != '.pyc':
                    if folder == 'scripts' and path.name not in ['assemble_ios.py', 'prepare_native_extras.py']:
                        continue
                    digest.update(path.relative_to(repository).as_posix().encode() + b'\0')
                    digest.update(path.read_bytes())
        (root / '.muwa-generated.json').write_text(json.dumps({
            'generated': True, 'application_id': 'app.muwa.nasheeds',
            'version': '1.4.0', 'build': build, 'base_sha256': BASE_SHA256,
            'source_sha256': digest.hexdigest(),
            'canonical_sources': 'Repository/native-patches and Repository/branding',
            'regenerate': 'python3 scripts/assemble_ios.py --output build-src/MuwaNasheedsNative',
        }, indent=2) + '\n', encoding='utf-8', newline='\n')
        (root / 'GENERATED_PROJECT.md').write_text(
            '# Muwa: generated Xcode project\n\n'
            'This complete project is generated from the canonical repository.\n'
            'Edit Repository/native-patches/Sources, Configuration, Resources or branding,\n'
            'then run scripts/assemble_ios.py again into a new directory.\n'
            'Older reports inside the immutable base are historical; current status is\n'
            'in Repository/docs/CURRENT_STATE.md and the portable archive Handoff.\n\n'
            'Open MuwaNasheeds.xcodeproj in Xcode on macOS; scheme MuwaNasheeds.\n'
            'Device installation requires your Apple signing configuration.\n',
            encoding='utf-8', newline='\n',
        )
        if output.exists():
            output.rmdir()  # Only the previously checked empty directory.
        shutil.move(str(root), str(output))
    print(f'Complete Xcode project assembled: {output} (1.4.0 build {build})')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True, help='New or empty Xcode project directory')
    parser.add_argument('--build', type=int, default=DEFAULT_BUILD)
    args = parser.parse_args()
    assemble(Path(__file__).resolve().parents[1], args.output, args.build)


if __name__ == '__main__':
    main()
