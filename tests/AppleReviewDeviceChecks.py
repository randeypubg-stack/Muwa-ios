"""Selection checks with mixed real-shaped simctl inventories; no macOS needed."""
import copy
import io
import json
from pathlib import Path
import tempfile
import subprocess
import unittest
from unittest.mock import patch

from select_apple_review_devices import boot_selected_device, ensure_reported_phone, main, normalize_inventory, open_simulator_gui, request_status, select_devices


def runtime(version, available=True, name=None):
    return {
        "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-" + version.replace(".", "-"),
        "name": name or "iOS " + version, "version": version,
        "buildversion": "fixture-build", "isAvailable": available,
    }


def fixtures():
    old, current, beta, too_new = runtime("18.6"), runtime("27.0"), runtime("27.2", name="iOS 27.2 beta"), runtime("27.1")
    types = [{"name": name, "identifier": "com.apple.CoreSimulator.SimDeviceType." + name.replace(" ", "-")}
             for name in ("iPhone 16 Pro Max", "iPhone 18 Pro", "iPhone 18 Pro Max", "iPhone 17e", "iPad Pro 13-inch (M5)", "iPad Pro 11-inch (M5)", "iPad Pro 13-inch (M4)", "iPad mini (A17 Pro)", "iPad mini (6th generation)")]
    def device(name, udid=None):
        kind = next(item for item in types if item["name"] == name)
        return {"name": name, "udid": udid or name, "isAvailable": True, "deviceTypeIdentifier": kind["identifier"]}
    devices = {
        old["identifier"]: [device("iPhone 16 Pro Max", "old-phone")],
        current["identifier"]: [device(item["name"]) for item in types],
        beta["identifier"]: [device("iPhone 18 Pro Max", "beta-phone")],
        too_new["identifier"]: [device("iPhone 18 Pro Max", "newer-unsupported-sdk")],
    }
    return devices, [old, beta, current, too_new], types


class AppleReviewDeviceChecks(unittest.TestCase):
    def setUp(self):
        self.devices, self.runtimes, self.types = fixtures()
        self.records = normalize_inventory(self.devices, self.runtimes, self.types, "27.0")

    def test_current_real_models_in_all_size_classes(self):
        expected = {"phone": "iPhone 18 Pro", "large-phone": "iPhone 18 Pro Max", "tablet": "iPad Pro 13-inch (M5)", "small-tablet": "iPad mini (A17 Pro)"}
        for kind, name in expected.items():
            selected = select_devices(self.records, kind)
            self.assertEqual(selected[0]["name"], name)
            self.assertEqual(selected[0]["runtimeVersion"], "27.0")
            self.assertEqual(selected[0]["runtimeBuild"], "fixture-build")
            self.assertTrue(selected[0]["deviceTypeIdentifier"].startswith("com.apple.CoreSimulator.SimDeviceType."))

    def test_reported_phone_requires_the_actual_model_without_relabelling(self):
        with self.assertRaisesRegex(ValueError, "Review device unavailable"):
            select_devices(self.records, "reported-phone")
        record = {**self.records[0], "name": "iPhone 17 Pro", "udid": "actual-17-pro",
                  "runtimeVersion": "27.0"}
        selected = select_devices([*self.records, record], "reported-phone")
        self.assertEqual(selected[0]["udid"], "actual-17-pro")
        self.assertEqual(request_status([record], selected, "iPhone 17 Pro", "27.2")["status"], "unavailable")

    def test_reported_phone_is_created_from_the_verified_installed_type_on_the_current_runtime(self):
        kind = {'name':'iPhone 17 Pro', 'identifier':'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro'}
        self.types.append(kind)
        udid = '43ac2f71-676e-4809-9d99-3cb47e5c8a66'
        with patch('select_apple_review_devices.command', return_value=udid) as create:
            records = ensure_reported_phone(self.devices, self.runtimes, self.types, '27.0', '27.0')
            create.assert_called_once_with('xcrun','simctl','create','Muwa iPhone 17 Pro',kind['identifier'],'com.apple.CoreSimulator.SimRuntime.iOS-27-0')
        selected = select_devices(records, 'reported-phone', '27.0')[0]
        self.assertEqual(selected['name'], 'iPhone 17 Pro')
        self.assertEqual(selected['deviceTypeIdentifier'], kind['identifier'])
        self.assertEqual(selected['udid'], udid)
        with patch('select_apple_review_devices.command') as create:
            ensure_reported_phone(self.devices, self.runtimes, self.types, '27.0', '27.0')
            create.assert_not_called()

    def test_preview_and_newer_sdk_runtime_never_selected(self):
        self.assertNotIn("beta-phone", [item["udid"] for item in self.records])
        self.assertNotIn("newer-unsupported-sdk", [item["udid"] for item in self.records])

    def test_json_order_does_not_change_selection(self):
        reversed_devices = {key: list(reversed(value)) for key, value in reversed(list(self.devices.items()))}
        shuffled = normalize_inventory(reversed_devices, list(reversed(self.runtimes)), list(reversed(self.types)), "27.0")
        self.assertEqual([item["udid"] for item in select_devices(self.records)], [item["udid"] for item in select_devices(shuffled)])

    def test_requested_exact_model_and_os_are_confirmed(self):
        report = request_status(self.records, select_devices(self.records, "large-phone"), "iPhone 18 Pro Max", "27")
        self.assertEqual(report["status"], "selected")
        self.assertTrue(report["exactCombinationAvailable"])
        other = request_status(self.records, select_devices(self.records, "tablet"), "iPhone 18 Pro Max", "27")
        self.assertEqual(other["status"], "available-not-selected")

    def test_renaming_old_device_cannot_fake_requested_hardware(self):
        device = copy.deepcopy(self.devices[self.runtimes[0]["identifier"]][0])
        device["name"] = "iPhone 18 Pro Max"
        old_only = normalize_inventory({self.runtimes[0]["identifier"]: [device]}, self.runtimes, self.types, "27.0")
        self.assertEqual(old_only[0]["name"], "iPhone 16 Pro Max")
        self.assertEqual(old_only[0]["simulatorName"], "iPhone 18 Pro Max")
        report = request_status(old_only, select_devices(old_only, "large-phone"), "iPhone 18 Pro Max", "27")
        self.assertFalse(report["deviceAvailable"])
        self.assertFalse(report["runtimeAvailable"])
        self.assertEqual(report["status"], "unavailable")

    def test_required_runtime_never_falls_back_silently(self):
        with self.assertRaisesRegex(ValueError, "Requested stable iOS runtime unavailable: 28.0"):
            select_devices(self.records, "large-phone", "28.0")
        self.assertEqual(select_devices(self.records, "large-phone", "18.6")[0]["udid"], "old-phone")

    def test_unavailable_devices_and_runtimes_are_excluded(self):
        self.runtimes[2]["isAvailable"] = False
        self.devices[self.runtimes[0]["identifier"]][0]["isAvailable"] = False
        self.assertEqual(normalize_inventory(self.devices, self.runtimes, self.types, "27.0"), [])

    def test_unknown_type_is_rejected_instead_of_labelled_as_hardware(self):
        self.devices[self.runtimes[2]["identifier"]][0]["deviceTypeIdentifier"] = "unrecognized"
        with self.assertRaisesRegex(ValueError, "Cannot verify device type"):
            normalize_inventory(self.devices, self.runtimes, self.types, "27.0")

    def test_missing_type_identifier_uses_unique_real_catalogue_name(self):
        self.devices[self.runtimes[2]["identifier"]][0].pop("deviceTypeIdentifier")
        records = normalize_inventory(self.devices, self.runtimes, self.types, "27.0")
        self.assertEqual(records[1]["name"], "iPhone 16 Pro Max")

    def test_non_ios_runtime_is_not_an_ios_review(self):
        extra = {**runtime("27.0"), "identifier": "com.apple.CoreSimulator.SimRuntime.tvOS-27-0"}
        self.runtimes.append(extra)
        self.devices[extra["identifier"]] = [copy.deepcopy(self.devices[self.runtimes[2]["identifier"]][0])]
        self.assertEqual(len(normalize_inventory(self.devices, self.runtimes, self.types, "27.0")), len(self.records))

    def test_gui_warmup_uses_exact_xcode_bundle_and_device(self):
        with tempfile.TemporaryDirectory() as directory:
            bundle = Path(directory) / "Applications/Simulator.app"
            bundle.mkdir(parents=True)
            with patch("select_apple_review_devices.subprocess.run") as launch:
                self.assertEqual(open_simulator_gui("requested-udid", directory), {'bundle':str(bundle),'available':True,'opened':True})
                launch.assert_called_once_with(["/usr/bin/open", "-a", str(bundle), "--args", "-CurrentDeviceUDID", "requested-udid"], check=True, timeout=45, stdout=subprocess.DEVNULL)

    def test_gui_warmup_does_not_fall_back_to_another_xcode(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch("select_apple_review_devices.subprocess.run") as launch:
                status = open_simulator_gui("requested-udid", directory)
                self.assertEqual(status['bundle'], str(Path(directory) / 'Applications/Simulator.app'))
                self.assertFalse(status['available'])
                self.assertFalse(status['opened'])
                launch.assert_not_called()

    def test_gui_open_failure_remains_explicit_and_does_not_fake_warmup(self):
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / 'Applications/Simulator.app').mkdir(parents=True)
            with patch('select_apple_review_devices.subprocess.run', side_effect=subprocess.CalledProcessError(1, ['/usr/bin/open'])):
                status = open_simulator_gui('requested-udid', directory)
                self.assertTrue(status['available'])
                self.assertFalse(status['opened'])
                self.assertEqual(status['launchErrorType'], 'CalledProcessError')

    def test_explicit_boot_verifies_exact_runtime_then_waits_for_same_udid(self):
        device = select_devices(self.records, 'large-phone')[0]
        def live(state):
            return json.dumps({'devices':{device['runtimeIdentifier']:[{'udid':device['udid'],'isAvailable':True,'state':state}]}})
        with patch('select_apple_review_devices.command', side_effect=[live('Shutdown'), '', 'ready']) as commands:
            status = boot_selected_device(device)
            self.assertEqual(status['udid'], device['udid'])
            self.assertEqual(status['runtimeIdentifier'], device['runtimeIdentifier'])
            self.assertTrue(status['bootstatusCompleted'])
            self.assertTrue(status['bootRequested'])
            self.assertEqual(status['bootstatusOutput'], 'ready')
            self.assertEqual(commands.call_args_list[0].args, ('xcrun','simctl','list','devices',device['udid'],'--json'))
            self.assertEqual(commands.call_args_list[1].args, ('xcrun','simctl','boot',device['udid']))
            self.assertEqual(commands.call_args_list[2].args, ('xcrun','simctl','bootstatus',device['udid'],'-b'))
            self.assertEqual(commands.call_args_list[2].kwargs, {'timeout':240})
            self.assertEqual(commands.call_count, 3)
            self.assertEqual(status['stateVerification'], 'Selected UDID bootstatus -b completed successfully')

    def test_explicit_boot_rejects_runtime_substitution(self):
        device = select_devices(self.records, 'large-phone')[0]
        wrong = json.dumps({'devices':{'com.apple.CoreSimulator.SimRuntime.iOS-18-6':[{'udid':device['udid'],'isAvailable':True,'state':'Booted'}]}})
        with patch('select_apple_review_devices.command', return_value=wrong) as commands:
            with self.assertRaisesRegex(ValueError, 'Selected Simulator runtime changed'):
                boot_selected_device(device)
            self.assertEqual(commands.call_count, 1)

    def test_failed_boot_preserves_inventory_and_reraises_original_timeout(self):
        device = select_devices(self.records, 'large-phone')[0]
        report = {'selected':[device], 'requiredRuntimeVersion':'27.0'}
        timeout = subprocess.TimeoutExpired(('xcrun','simctl','list','devices',device['udid'],'--json'), 120)
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'inventory.json'
            def fail_boot(selected):
                early = json.loads(output.read_text())
                self.assertEqual(early['selected'][0]['udid'], device['udid'])
                self.assertEqual(early['simulatorBoot']['runtimeIdentifier'], device['runtimeIdentifier'])
                self.assertFalse(early['simulatorBoot']['completed'])
                raise timeout
            with patch('select_apple_review_devices.load_selection', return_value=([device], report)), \
                 patch('select_apple_review_devices.boot_selected_device', side_effect=fail_boot), \
                 patch('sys.argv', ['select', '--kind','large-phone','--boot','--output',str(output)]):
                with self.assertRaises(subprocess.TimeoutExpired) as failure:
                    main()
                self.assertIs(failure.exception, timeout)
            saved = json.loads(output.read_text())
            self.assertFalse(saved['simulatorBoot']['completed'])
            self.assertEqual(saved['simulatorBoot']['error']['type'], 'TimeoutExpired')
            self.assertEqual(saved['simulatorBoot']['error']['command'], list(timeout.cmd))
            self.assertEqual(saved['simulatorBoot']['error']['timeoutSeconds'], 120)

    def test_successful_boot_updates_report_and_prints_only_selected_udid(self):
        device = select_devices(self.records, 'large-phone')[0]
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'inventory.json'
            stdout = io.StringIO()
            with patch('select_apple_review_devices.load_selection', return_value=([device], {'selected':[device]})), \
                 patch('select_apple_review_devices.boot_selected_device', return_value={'state':'Booted','bootstatusCompleted':True}), \
                 patch('sys.argv', ['select','--kind','large-phone','--boot','--print-udid','--output',str(output)]), \
                 patch('sys.stdout', stdout):
                main()
            self.assertEqual(stdout.getvalue(), device['udid'] + '\n')
            saved = json.loads(output.read_text())
            self.assertTrue(saved['simulatorBoot']['completed'])
            self.assertTrue(saved['simulatorBoot']['bootstatusCompleted'])
            self.assertEqual(saved['simulatorBoot']['state'], 'Booted')
            self.assertNotIn('error', saved['simulatorBoot'])


if __name__ == "__main__":
    unittest.main()
