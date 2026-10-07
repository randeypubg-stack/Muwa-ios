"""Capture the real Simulator CarPlay display when available; never fabricate it."""
import argparse
import csv
import io
import json
import math
import os
import re
import shutil
import sys
import plistlib
import subprocess
import time
from pathlib import Path

from verify_home_frame import (MODEL_COMMIT, MODEL_DIRECTORY, MIN_CONFIDENCE,
                               digest, png_dimensions, verify_models)
from select_apple_review_devices import open_simulator_gui


def carplay_target(tsv, width, height):
    """Locate a confident Muwa launcher label in the actual external display."""
    if width <= height:
        raise AssertionError('Expected the landscape CarPlay framebuffer, not the phone')
    reader = csv.DictReader(io.StringIO(tsv), delimiter='\t')
    required = {'level', 'page_num', 'left', 'top', 'width', 'height', 'conf', 'text'}
    if not required.issubset(reader.fieldnames or []):
        raise AssertionError('OCR did not return a valid native framebuffer TSV')
    page_count = 0
    candidates = []
    for row in reader:
        if row['level'] == '1':
            if (int(row['page_num']) != 1 or int(row['width']) != width or
                    int(row['height']) != height):
                raise AssertionError('OCR page dimensions do not match the native PNG')
            page_count += 1
        if row['level'] != '5' or not (row['text'] or '').strip():
            continue
        if row['page_num'] != '1':
            raise AssertionError('OCR text does not belong to the native framebuffer page')
        confidence = float(row['conf'])
        left, top, word_width, word_height = (int(row[key]) for key in
                                             ('left', 'top', 'width', 'height'))
        if not math.isfinite(confidence) or not 0 <= confidence <= 100:
            raise AssertionError('OCR returned an invalid confidence')
        if (left < 0 or top < 0 or min(word_width, word_height) <= 0 or
                left + word_width > width or top + word_height > height):
            raise AssertionError('OCR returned text outside the native framebuffer')
        if row['text'].strip().casefold() != 'muwa' or confidence < MIN_CONFIDENCE:
            continue
        # Only a launcher grid label may select a tile. A sidebar item or an
        # already-open app title must not trigger another coordinate click.
        x, label_y = left + word_width / 2, top + word_height / 2
        y = label_y - height * 0.18
        if x <= width * 0.12 or not height * 0.30 <= label_y <= height * 0.92:
            continue
        if not 0 < x < width or not 0 < y < height:
            raise AssertionError('The native launcher tile target is out of bounds')
        candidates.append({'label': row['text'].strip(), 'confidence': confidence / 100,
                           'x': x, 'y': y, 'width': width, 'height': height,
                           'labelBounds': [left, top, word_width, word_height]})
    if page_count != 1:
        raise AssertionError('OCR must identify exactly one native framebuffer page')
    if len(candidates) != 1:
        raise AssertionError('Exactly one confident Muwa launcher tile must be visible')
    return candidates[0]


def locate_carplay_app(path, model_folder, output_folder):
    """CPU-only OCR; retain original pixels and complete evidence on failure."""
    output_folder.mkdir(parents=True, exist_ok=True)
    proof = {'launcherVisible': False, 'recognitionEngine': 'Tesseract',
             'computeDevice': 'cpu', 'sourcePNG': str(path),
             'modelRepository': 'https://github.com/tesseract-ocr/tessdata_best',
             'modelCommit': MODEL_COMMIT}
    started = time.monotonic()
    try:
        width, height = png_dimensions(path)
        proof.update(width=width, height=height, sourceSHA256=digest(path))
        # The archive keeps the exact input bytes even for an offline verifier
        # invocation whose original PNG lives outside the artifact directory.
        shutil.copyfile(path, output_folder / 'source.png')
        models = verify_models(model_folder)
        proof['models'] = {'eng': models['eng']}
        executable = shutil.which('tesseract')
        if executable is None:
            raise RuntimeError('Tesseract is not installed on the verification host')
        version = subprocess.check_output([executable, '--version'], text=True,
                                          stderr=subprocess.STDOUT, timeout=15)
        if not re.match(r'tesseract [5-9]\.', version):
            raise RuntimeError('This verifier requires Tesseract 5 or newer')
        proof.update(engineVersion=version.splitlines()[0], engineExecutable=executable)
        command = [executable, str(path.resolve()), 'stdout', '--tessdata-dir',
                   str(model_folder.resolve()), '-l', 'eng', '--oem', '1', '--psm', '11',
                   '-c', 'tessedit_create_tsv=1', '-c', 'tessedit_create_txt=0']
        proof['command'] = command
        result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=60,
                                env={**os.environ, 'OMP_THREAD_LIMIT': '1'})
        (output_folder / 'recognition.tsv').write_text(result.stdout)
        (output_folder / 'recognition.log').write_text(result.stderr)
        if result.returncode:
            raise RuntimeError(f'CPU OCR exited with {result.returncode}: {result.stderr}')
        proof.update(carplay_target(result.stdout, width, height), launcherVisible=True)
        return proof
    except subprocess.TimeoutExpired as error:
        for name, partial in [('recognition.tsv', error.stdout), ('recognition.log', error.stderr)]:
            if isinstance(partial, bytes):
                partial = partial.decode('utf-8', errors='replace')
            (output_folder / name).write_text(partial or '')
        proof.update(errorType=type(error).__name__, errorMessage=str(error))
        raise
    except Exception as error:
        proof.update(errorType=type(error).__name__, errorMessage=str(error))
        raise
    finally:
        proof['elapsedSeconds'] = round(time.monotonic() - started, 3)
        (output_folder / 'proof.json').write_text(json.dumps(proof, ensure_ascii=False, indent=2))


def version_parts(value):
    """Normalize missing patch components; reject preview/version suffixes."""
    match = re.fullmatch(r'(\d+)(?:\.(\d+))?(?:\.(\d+))?', str(value).strip())
    return tuple(int(part or 0) for part in match.groups()) if match else None


def selected_phone(devices, runtimes, sdk_version='27.0'):
    """Prefer stable iOS 27.0 if installed; report any compatible older runtime."""
    candidates = []
    sdk_parts = version_parts(sdk_version)
    if sdk_parts is None:
        raise RuntimeError('The actual simulator SDK did not return a stable version')
    maximum_version = min((27, 0, 0), sdk_parts)
    for runtime in runtimes:
        if not runtime.get('isAvailable') or not runtime.get('identifier', '').startswith(
                'com.apple.CoreSimulator.SimRuntime.iOS-'):
            continue
        version = runtime.get('version', '')
        parts = version_parts(version)
        # Exclude preview/beta runtimes; these are compatibility screenshots,
        # never evidence of a newer version that the runner does not contain.
        if (parts is None or 'beta' in runtime.get('name', '').casefold() or
                parts > maximum_version):
            continue
        for phone in devices.get(runtime['identifier'], []):
            if phone.get('isAvailable') and phone.get('name', '').startswith('iPhone'):
                score = (parts == (27, 0, 0), parts,
                         phone['name'])
                candidates.append((score, phone, runtime))
    if not candidates:
        raise RuntimeError('No available iPhone with a compatible stable iOS runtime')
    _, phone, runtime = max(candidates, key=lambda item: item[0])
    return phone, runtime


def save_status():
    (out / 'status.json').write_text(json.dumps(status, ensure_ascii=False, indent=2))

def run(*args, timeout=180):
    command = [str(arg) for arg in args]
    print('Running:', ' '.join(command), flush=True)
    started = time.monotonic()
    step = {'command': command, 'timeout_seconds': timeout}
    status['steps'].append(step)
    save_status()
    try:
        result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=timeout)
        step['exit_code'] = result.returncode
        step['output'] = result.stdout[-4000:]
        if result.returncode:
            raise RuntimeError(f"Command failed ({result.returncode}): {' '.join(command)}\n{result.stdout[-4000:]}")
        return result.stdout
    except subprocess.TimeoutExpired as error:
        step['timed_out'] = True
        partial = error.stdout or ''
        if isinstance(partial, bytes):
            partial = partial.decode('utf-8', errors='replace')
        step['output'] = partial[-4000:]
        raise
    finally:
        step['elapsed_seconds'] = round(time.monotonic() - started, 3)
        save_status()
        print(f"Completed in {step['elapsed_seconds']}s: {' '.join(command)}", flush=True)

def capture():
    global out, status
    out = Path('build/previews/carplay')
    out.mkdir(parents=True, exist_ok=True)
    status = {'captured': False, 'distribution': 'requires Apple-approved CarPlay Audio provisioning', 'steps': []}
    try:
        status['toolchain'] = {
            'xcodeVersion': run('xcodebuild', '-version').strip(),
            'simulatorSDKVersion': run('xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version').strip(),
            'simulatorSDKBuild': run('xcrun', '--sdk', 'iphonesimulator', '--show-sdk-build-version').strip(),
            'simctlExecutable': run('xcrun', '--find', 'simctl').strip(),
        }
        devices = json.loads(run('xcrun', 'simctl', 'list', 'devices', 'available', '--json'))['devices']
        runtimes = json.loads(run('xcrun', 'simctl', 'list', 'runtimes', '--json'))['runtimes']
        phone, runtime = selected_phone(devices, runtimes,
                                         status['toolchain']['simulatorSDKVersion'])
        udid = phone['udid']
        status['device'] = phone['name']
        status['deviceTypeIdentifier'] = phone['deviceTypeIdentifier']
        status['udid'] = udid
        status['runtime'] = {key: runtime[key] for key in
                             ('identifier', 'name', 'version', 'buildversion') if key in runtime}
        status['requestedStableRuntime'] = '27.0'
        status['requestedRuntimeAvailable'] = any(
            item.get('identifier', '').startswith('com.apple.CoreSimulator.SimRuntime.iOS-')
            and 'beta' not in item.get('name', '').casefold()
            and version_parts(item.get('version')) == (27, 0, 0)
            and item.get('isAvailable')
            for item in runtimes)
        status['selectedRequestedRuntime'] = version_parts(runtime['version']) == (27, 0, 0)
        status['runtimeSelection'] = 'stable runtime compatible with the measured simulator SDK'
        status['scope'] = 'native CarPlay simulator compatibility, not a physical vehicle'
        save_status()
        app = next(Path('build/PreviewDerivedData/Build/Products/Debug-iphonesimulator').glob('*.app'))
        # Xcode signs the dedicated Simulator build and its debug dylib together.
        # Re-signing only the app here would discard Xcode's platform/debug grants.
        # The ordinary device IPA remains unsigned.
        run('codesign', '--verify', '--deep', '--strict', '--verbose=2', str(app))
        # Device entitlements live in the signature. Xcode instead embeds Simulator
        # grants in the Mach-O __TEXT.__entitlements section; its signature may be {}.
        # Verify the actual executable against Xcode's generated simulated grants,
        # rather than accepting the requested source entitlement file as evidence.
        signed = run('codesign', '--display', '--entitlements', ':-', str(app))
        start = signed.find('<?xml')
        end = signed.find('</plist>', start)
        if start < 0 or end < 0:
            raise RuntimeError('Could not read the signed Simulator entitlements')
        entitlements = plistlib.loads(signed[start:end + len('</plist>')].encode())
        if entitlements.get('com.apple.developer.carplay-audio') is True:
            status['entitlement_location'] = 'code signature'
        else:
            simulated = next(Path('build/PreviewDerivedData/Build/Intermediates.noindex')
                             .rglob('Muwa.app-Simulated.xcent'))
            embedded = simulated.read_bytes()
            entitlements = plistlib.loads(embedded)
            executable = plistlib.loads((app / 'Info.plist').read_bytes())['CFBundleExecutable']
            if (entitlements.get('com.apple.developer.carplay-audio') is not True
                    or embedded not in (app / executable).read_bytes()):
                raise RuntimeError('Executable lacks the generated Simulator CarPlay Audio grants')
            status['entitlement_location'] = 'Xcode Simulator Mach-O section'
        status['codesign_verified'] = True
        if phone['state'] != 'Booted':
            run('xcrun', 'simctl', 'boot', udid)
        run('xcrun', 'simctl', 'bootstatus', udid, '-b', timeout=240)
        status['booted'] = True
        # A fresh hosted runner can finish bootstatus before installd is responsive.
        # The previous 45-second cap failed before any CarPlay UI could be inspected.
        run('xcrun', 'simctl', 'install', udid, str(app), timeout=180)
        data = Path(run('xcrun', 'simctl', 'get_app_container', udid, 'app.muwa.nasheeds', 'data').strip())
        (data / 'Documents/carplay-connected.txt').unlink(missing_ok=True)
        # LaunchServices may not register an app named Simulator, and a stripped
        # CLI runner may have no GUI at all. Use the selected toolchain's exact
        # bundle; never substitute a different Simulator/runtime silently.
        status['simulatorGUI'] = open_simulator_gui(udid)
        save_status()
        if not status['simulatorGUI']['opened']:
            raise RuntimeError('The selected Xcode has no usable Simulator GUI for CarPlay capture')
        time.sleep(3)
        # Launch the phone scene before enabling the automotive display. SpringBoard
        # may reject a new foreground phone launch while the CarPlay display is active.
        # A cold hosted SpringBoard can still be registering the newly installed
        # bundle after installd/get_app_container return. Retry only a command
        # timeout; signing denials and other explicit launch failures remain errors.
        try:
            run('xcrun', 'simctl', 'launch', '--terminate-running-process', udid,
                'app.muwa.nasheeds', '--audit-player', timeout=300)
        except subprocess.TimeoutExpired:
            status['cold_launch_retry'] = True
            save_status()
            run('xcrun', 'simctl', 'launch', '--terminate-running-process', udid,
                'app.muwa.nasheeds', '--audit-player', timeout=180)
        time.sleep(5)
        script = '''tell application "System Events"
          tell process "Simulator"
            set frontmost to true
            set displayMenu to menu 1 of menu item "External Displays" of menu 1 of menu bar item "I/O" of menu bar 1
            set carItem to first menu item of displayMenu whose name contains "CarPlay"
            if exists menu 1 of carItem then
              click first menu item of menu 1 of carItem whose name contains "800"
            else
              click carItem
            end if
          end tell
        end tell'''
        status['menu'] = run('osascript', '-e', script)
        # The external display becomes available after the first phone launch.
        # Reconnect the process with that display already attached so UIKit can
        # request its CarPlay role from the existing scene manifest.
        time.sleep(3)
        run('xcrun', 'simctl', 'launch', '--terminate-running-process', udid,
            'app.muwa.nasheeds', '--audit-player')
        status['displays'] = run('xcrun', 'simctl', 'io', udid, 'enumerate')
        # Prove that the screenshot is from a connected CarPlay scene, not an empty display.
        data = Path(run('xcrun', 'simctl', 'get_app_container', udid, 'app.muwa.nasheeds', 'data').strip())
        proof = data / 'Documents/carplay-connected.txt'
        if not proof.exists():
            # Connecting CarPlay exposes its launcher, not automatically Muwa's
            # template scene. Select the app from the actual external framebuffer.
            launcher = out / 'launcher.png'
            run('xcrun', 'simctl', 'io', udid, 'screenshot', '--display=external', str(launcher))
            target = locate_carplay_app(launcher, MODEL_DIRECTORY, out / 'launcher-ocr')
            assert target['label'].lower() == 'muwa' and target['confidence'] >= 0.5
            bounds_script = '''tell application "System Events"
              tell process "Simulator"
                set frontmost to true
                set chosenWindow to missing value
                repeat with w in windows
                  if name of w contains "CarPlay" then
                    set chosenWindow to w
                    exit repeat
                  end if
                end repeat
                if chosenWindow is missing value then
                  repeat with w in windows
                    set windowSize to size of w
                    if item 1 of windowSize > item 2 of windowSize then
                      set chosenWindow to w
                      exit repeat
                    end if
                  end repeat
                end if
                if chosenWindow is missing value then error "CarPlay window was not found"
                perform action "AXRaise" of chosenWindow
                set windowPosition to position of chosenWindow
                set windowSize to size of chosenWindow
                return (item 1 of windowPosition as text) & "," & (item 2 of windowPosition as text) & "," & (item 1 of windowSize as text) & "," & (item 2 of windowSize as text)
              end tell
            end tell'''
            wx, wy, ww, wh = map(float, run('osascript', '-e', bounds_script).strip().split(','))
            scale = ww / target['width']
            x = round(wx + target['x'] * scale)
            y = round(wy + wh - target['height'] * scale + target['y'] * scale)
            status['launcher_selection'] = {'label': target['label'], 'confidence': target['confidence'],
                                            'nativeTarget': target, 'windowBounds': [wx, wy, ww, wh]}
            save_status()
            run('screencapture', '-x', str(out / 'desktop-before-input.png'))
            # AXRaise orders the window but does not guarantee it is the key window.
            # Focus its title bar first; otherwise Simulator may consume the icon
            # click just to activate the external-display window.
            run('cliclick', f'c:{round(wx + ww / 2)},{round(wy + 14)}')
            time.sleep(0.2)
            # A cold Simulator may consume the first input while activating its
            # external display. Keep a real pointer press long enough to span a
            # guest input frame, and retry only while the fresh framebuffer still
            # positively identifies Muwa's launcher tile. Never click coordinates
            # from the launcher once the app has opened.
            status['launcher_attempts'] = []
            for attempt in range(3):
                if proof.exists():
                    break
                if attempt:
                    retry_frame = out / f'launcher-retry-{attempt}.png'
                    run('xcrun', 'simctl', 'io', udid, 'screenshot',
                        '--display=external', str(retry_frame))
                    try:
                        retry_target = locate_carplay_app(retry_frame, MODEL_DIRECTORY,
                                                          out / f'launcher-retry-{attempt}-ocr')
                        if retry_target['label'].lower() != 'muwa' or retry_target['confidence'] < 0.5:
                            break
                        x = round(wx + retry_target['x'] * scale)
                        y = round(wy + wh - retry_target['height'] * scale + retry_target['y'] * scale)
                    except (RuntimeError, AssertionError, ValueError):
                        break
                status['launcher_attempts'].append({'attempt': attempt + 1, 'x': x, 'y': y})
                save_status()
                run('cliclick', f'm:{x},{y}', 'w:300', f'dd:{x},{y}', 'w:150', f'du:{x},{y}')
                input_deadline = time.monotonic() + 5
                while time.monotonic() < input_deadline and not proof.exists():
                    time.sleep(0.2)
            status['mouse_position'] = run('cliclick', 'p').strip()
            run('screencapture', '-x', str(out / 'desktop-after-input.png'))
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline and not proof.exists():
            time.sleep(0.5)
        status['scene_connected'] = proof.exists() and proof.read_text() == 'Muwa CarPlay connected'
        if not status['scene_connected']:
            run('xcrun', 'simctl', 'io', udid, 'screenshot', '--display=external',
                str(out / 'external-display-unconnected.png'))
            raise RuntimeError('External display exists but Muwa CarPlay scene did not connect')
        time.sleep(2)
        frame = out / 'carplay.png'
        run('xcrun', 'simctl', 'io', udid, 'screenshot', '--display=external', str(frame))
        width, height = png_dimensions(frame)
        status['nativeFrame'] = {'png': frame.name, 'width': width, 'height': height,
                                 'sha256': digest(frame), 'unmodified': True}
        status['sceneProof'] = proof.read_text()
        (out / 'carplay-connected.txt').write_bytes(proof.read_bytes())
        status['captured'] = True
        status['device'] = phone['name']
    except Exception as error:
        status['reason'] = str(error)
        # Preserve the native launch denial so signing/runtime failures can be
        # distinguished from a missing external display or an app scene failure.
        if status.get('booted'):
            predicate = 'process == "Muwa" OR process CONTAINS "CarPlay" OR subsystem CONTAINS[c] "carplay" OR ((process == "SpringBoard" OR process == "runningboardd" OR process == "amfid") AND (eventMessage CONTAINS "app.muwa.nasheeds" OR eventMessage CONTAINS "Muwa.app"))'
            try:
                diagnostic = run('xcrun', 'simctl', 'spawn', udid, 'log', 'show',
                                 '--style', 'compact', '--last', '3m', '--predicate', predicate,
                                 timeout=30)
                (out / 'launch-diagnostic.log').write_text(diagnostic)
            except Exception as diagnostic_error:
                status['diagnostic_error'] = str(diagnostic_error)
    finally:
        save_status()
        print(json.dumps(status, ensure_ascii=False), flush=True)

    # Preserve diagnostics, but fail the check when no real Muwa scene was captured.
    # A successful signing/build or launcher image must not hide a runtime crash.
    if not status['captured']:
        return 1
    return 0



def self_test():
    """Reject unsafe pointer targets without launching or altering a simulator."""
    import unittest

    def tsv(words, dimensions=(800, 480)):
        output = io.StringIO()
        writer = csv.writer(output, delimiter="\t")
        writer.writerow(['level', 'page_num', 'left', 'top', 'width', 'height', 'conf', 'text'])
        writer.writerow([1, 1, 0, 0, *dimensions, -1, ''])
        for text, confidence, left, top, width, height in words:
            writer.writerow([5, 1, left, top, width, height, confidence, text])
        return output.getvalue()

    class CarPlayEvidenceChecks(unittest.TestCase):
        label = ('Muwa', 96, 164, 363, 65, 23)

        def test_actual_launcher_label_selects_icon_above_it(self):
            target = carplay_target(tsv([self.label]), 800, 480)
            self.assertEqual(target['x'], 196.5)
            self.assertAlmostEqual(target['y'], 288.1)
            self.assertEqual(target['confidence'], 0.96)

        def test_missing_or_substring_label_is_rejected(self):
            for words in ([], [('MuwaPremium', *self.label[1:])], [('NowPlaying', *self.label[1:])]):
                with self.subTest(words=words), self.assertRaises(AssertionError):
                    carplay_target(tsv(words), 800, 480)

        def test_low_confidence_and_ambiguous_labels_are_rejected(self):
            for words in ([('Muwa', 49, *self.label[2:])], [self.label, ('Muwa', 95, 400, 363, 60, 23)]):
                with self.subTest(words=words), self.assertRaises(AssertionError):
                    carplay_target(tsv(words), 800, 480)

        def test_invalid_confidences_are_rejected(self):
            for confidence in ('nan', 'inf', -1, 101):
                with self.subTest(confidence=confidence), self.assertRaises(AssertionError):
                    carplay_target(tsv([('Muwa', confidence, *self.label[2:])]), 800, 480)

        def test_outside_framebuffer_and_empty_bounds_are_rejected(self):
            for bounds in [(-1, 363, 65, 23), (164, -1, 65, 23), (790, 363, 65, 23),
                           (164, 470, 65, 23), (164, 363, 0, 23)]:
                with self.subTest(bounds=bounds), self.assertRaises(AssertionError):
                    carplay_target(tsv([('Muwa', 96, *bounds)]), 800, 480)

        def test_sidebar_and_open_app_header_never_select_a_tile(self):
            for bounds in [(10, 363, 65, 23), (164, 10, 65, 23)]:
                with self.subTest(bounds=bounds), self.assertRaises(AssertionError):
                    carplay_target(tsv([('Muwa', 96, *bounds)]), 800, 480)

        def test_mismatched_framebuffer_is_rejected(self):
            with self.assertRaises(AssertionError):
                carplay_target(tsv([self.label], (801, 480)), 800, 480)

        def test_phone_and_diagnostics_are_not_launcher_evidence(self):
            with self.assertRaises(AssertionError):
                carplay_target(tsv([self.label], (480, 800)), 480, 800)
            with self.assertRaises(AssertionError):
                carplay_target('Tesseract failed: Muwa', 800, 480)

        def test_missing_page_is_rejected(self):
            lines = tsv([self.label]).splitlines()
            with self.assertRaises(AssertionError):
                carplay_target('\n'.join([lines[0], *lines[2:]]), 800, 480)

        def test_duplicate_and_foreign_pages_are_rejected(self):
            lines = tsv([self.label]).splitlines()
            with self.assertRaises(AssertionError):
                carplay_target('\n'.join([*lines, lines[1]]), 800, 480)
            with self.assertRaises(AssertionError):
                carplay_target(tsv([self.label]).replace('5\t1\t', '5\t2\t'), 800, 480)

        def test_stable_27_is_preferred_over_preview(self):
            def runtime(identifier, version, name):
                return {'identifier': identifier, 'version': version, 'name': name, 'isAvailable': True}
            old = 'com.apple.CoreSimulator.SimRuntime.iOS-18-5'
            stable = 'com.apple.CoreSimulator.SimRuntime.iOS-27-0'
            beta = 'com.apple.CoreSimulator.SimRuntime.iOS-27-1'
            devices = {key: [{'name': 'iPhone', 'isAvailable': True, 'udid': key}]
                       for key in (old, stable, beta)}
            runtimes = [runtime(old, '18.5', 'iOS 18.5'), runtime(stable, '27.0', 'iOS 27.0'),
                        runtime(beta, '27.1', 'iOS 27.1 beta')]
            self.assertEqual(selected_phone(devices, runtimes)[1]['version'], '27.0')
            self.assertEqual(selected_phone(devices, [runtimes[0], runtimes[2]])[1]['version'], '18.5')

        def test_unavailable_or_missing_runtime_is_not_selected(self):
            with self.assertRaises(RuntimeError):
                selected_phone({}, [])

        def test_older_xcode_never_selects_a_newer_incompatible_runtime(self):
            old = 'com.apple.CoreSimulator.SimRuntime.iOS-18-5'
            newer = 'com.apple.CoreSimulator.SimRuntime.iOS-26-2'
            devices = {key: [{'name': 'iPhone', 'isAvailable': True, 'udid': key}]
                       for key in (old, newer)}
            runtimes = [{'identifier': key, 'version': version, 'name': f'iOS {version}',
                         'isAvailable': True} for key, version in [(old, '18.5'), (newer, '26.2')]]
            self.assertEqual(selected_phone(devices, runtimes, '18.5')[1]['version'], '18.5')
            with self.assertRaises(RuntimeError):
                selected_phone(devices, [runtimes[1]], '18.5')

        def test_sdk_and_runtime_patch_components_are_equivalent(self):
            identifier = 'com.apple.CoreSimulator.SimRuntime.iOS-27-0'
            devices = {identifier: [{'name': 'iPhone', 'isAvailable': True}]}
            runtimes = [{'identifier': identifier, 'name': 'iOS 27.0',
                         'version': '27.0.0', 'isAvailable': True}]
            self.assertEqual(version_parts(' 27.0 '), version_parts('27.0.0'))
            self.assertEqual(selected_phone(devices, runtimes, '27.0')[1]['version'], '27.0.0')
            self.assertEqual(selected_phone(devices, runtimes, '27.0.0')[1]['version'], '27.0.0')

        def test_malformed_or_preview_versions_are_not_stable(self):
            for value in (None, '', 'unknown', '27.0 beta', '27.1b'):
                with self.subTest(value=value):
                    self.assertIsNone(version_parts(value))
            with self.assertRaises(RuntimeError):
                selected_phone({}, [], 'SDK unknown')

    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(CarPlayEvidenceChecks))
    return 0 if result.wasSuccessful() else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--self-test', action='store_true')
    parser.add_argument('--verify-launcher', type=Path)
    parser.add_argument('--models', type=Path, default=MODEL_DIRECTORY)
    parser.add_argument('--output', type=Path, default=Path('build/previews/carplay/launcher-ocr'))
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if args.verify_launcher is not None:
        try:
            print(json.dumps(locate_carplay_app(args.verify_launcher, args.models, args.output),
                             ensure_ascii=False, sort_keys=True))
            return 0
        except Exception as error:
            print(json.dumps({'launcherVisible': False, 'errorType': type(error).__name__,
                              'errorMessage': str(error)}, ensure_ascii=False), file=sys.stderr)
            return 1
    return capture()


if __name__ == '__main__':
    sys.exit(main())
