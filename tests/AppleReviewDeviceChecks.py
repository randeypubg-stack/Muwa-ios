"""Selection checks with mixed real-shaped simctl inventories; no macOS needed."""
import copy
import unittest

from select_apple_review_devices import normalize_inventory, request_status, select_devices


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


if __name__ == "__main__":
    unittest.main()
