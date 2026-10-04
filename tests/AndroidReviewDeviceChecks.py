"""Reject misleading OS, hardware-profile and native screenshot review evidence."""
from copy import deepcopy
import unittest
from unittest.mock import patch
from android_review_device import (assert_frame_dimensions, assert_review_device,
                                   display_state, sdk_availability, select_profile, stable_packages)


def package(path, codename="", channel="channel-0", base="true"):
    return (f'<remotePackage path="{path}"><type-details><codename>{codename}</codename>'
            f'<base-extension>{base}</base-extension></type-details>'
            f'<revision><major>5</major></revision><channelRef ref="{channel}"/></remotePackage>')


class Response:
    def __init__(self, data): self.data = data
    def __enter__(self): return self
    def __exit__(self, *args): pass
    def read(self): return self.data


class AndroidReviewDeviceChecks(unittest.TestCase):
    def device(self):
        return {"isEmulator": True, "android": {"sdk": "37", "codename": "REL"},
                "avd": {"name": "muwa-api37.2-phone-large", "hardwareProfile": "pixel_6",
                        "systemImageDirectory": "/sdk/system-images/android-37.2/google_apis_ps16k/x86_64/"},
                "display": display_state("Physical size: 1080x2400\nOverride size: 720x1280",
                                         "Physical density: 420\nOverride density: 320"),
                "pageSizeBytes": 16384}

    def test_stable_index_excludes_preview_and_extension_even_on_stable_channel(self):
        document = "<repository>" + "".join([
            package("platforms;android-37.2"), package("platforms;android-35"),
            package("platforms;android-38.0", channel="channel-1"),
            package("platforms;android-39.0", codename="DEV"),
            package("platforms;android-37.2-beta3", codename="DEV"),
            package("platforms;android-canary-20260909", codename="CANARY"),
            package("platforms;android-37-ext25", base="false"),
        ]) + "</repository>"
        self.assertEqual([version for _, version in stable_packages(document, "platforms;android-")],
                         [(37, 2), (35,)])

    def test_latest_proof_requires_matching_stable_platform_and_image(self):
        platforms = ("<repository>" + package("platforms;android-35") + package("platforms;android-37.2") + "</repository>").encode()
        images = ("<repository>" + package("system-images;android-35;google_apis;x86_64") +
                  package("system-images;android-37.2;google_apis_ps16k;x86_64") + "</repository>").encode()
        def fetch(url, **kwargs): return Response(platforms if "repository2-3" in url else images)
        with patch("android_review_device.urlopen", side_effect=fetch):
            self.assertTrue(sdk_availability("37.2", "google_apis_ps16k", "x86_64", True)["isLatestStablePlatform"])
            self.assertFalse(sdk_availability("35", "google_apis", "x86_64")["isLatestStablePlatform"])
            with self.assertRaises(AssertionError): sdk_availability("35", "google_apis", "x86_64", True)
            with self.assertRaises(AssertionError): sdk_availability("37.2", "google_apis", "x86_64")

    def test_display_override_preserves_physical_profile_geometry(self):
        state = self.device()["display"]
        self.assertEqual(state["physicalSize"], "1080x2400")
        self.assertEqual(state["physicalDensityDPI"], 420)
        self.assertEqual((state["effectiveWidth"], state["effectiveHeight"], state["effectiveDensityDPI"]),
                         (720, 1280, 320))
        with self.assertRaises(AssertionError): display_state("Override size: 720x1280", "Physical density: 320")

    def test_phone_selection_uses_actual_latest_numeric_generation_and_largest_model(self):
        inventory = "\n".join(["pixel_6", "pixel_9_pro_xl", "pixel_10", "pixel_10_pro", "pixel_10_pro_xl",
                               "pixel_11_pro_fold", "pixel_tablet_12", "pixel_12a", "Warning: SDK catalog refresh"])
        proof = select_profile(inventory, "phone")
        self.assertEqual(proof["profile"], "pixel_10_pro_xl")
        self.assertIn(proof["profile"], proof["availableProfileIDs"])
        self.assertFalse(proof["physicalDeviceVerified"])
        self.assertEqual(select_profile("pixel_6\npixel_6_pro\npixel_6_xl", "phone")["profile"], "pixel_6_xl")

    def test_tablet_selection_and_fallback_record_only_available_sdk_profiles(self):
        inventory = "pixel_10_pro_xl\npixel_tablet\npixel_tablet_2\nmedium_tablet"
        self.assertEqual(select_profile(inventory, "tablet")["profile"], "pixel_tablet_2")
        proof = select_profile("pixel_6\nmedium_tablet", "tablet")
        self.assertEqual(proof["profile"], "medium_tablet")
        self.assertTrue(proof["fallback"])
        proof = select_profile("pixel_6", "tablet")
        self.assertEqual(proof["profile"], "pixel_6")
        self.assertIn("display overrides", proof["selectionReason"])
        with self.assertRaises(AssertionError): select_profile("unidentified-device", "phone")

    def test_device_requires_exact_image_profile_os_and_effective_geometry(self):
        expected = dict(api="37.2", image="system-images;android-37.2;google_apis_ps16k;x86_64",
                        profile="pixel_6", avd_name="muwa-api37.2-phone-large", expected_size="720x1280",
                        expected_density="320", page_size="16384")
        assert_review_device(self.device(), **expected)
        for key, wrong in [("api", "35"), ("image", "system-images;android-37.0;google_apis;x86_64"),
                           ("profile", "pixel_9"), ("avd_name", "old-avd"), ("expected_size", "1080x2400"),
                           ("expected_density", "440"), ("page_size", "4096")]:
            with self.subTest(key=key), self.assertRaises(AssertionError):
                assert_review_device(self.device(), **{**expected, key: wrong})

    def test_preview_or_physical_device_cannot_pass_stable_emulator_review(self):
        for update in [lambda d: d.update(isEmulator=False), lambda d: d["android"].update(codename="DEV")]:
            device = deepcopy(self.device())
            update(device)
            with self.assertRaises(AssertionError): assert_review_device(device)

    def test_resized_or_mislabelled_pixels_cannot_pass_native_capture(self):
        assert_frame_dimensions(self.device(), 720, 1280, "portrait")
        assert_frame_dimensions(self.device(), 1280, 720, "landscape")
        for width, height, orientation in [(1080, 2400, "portrait"), (360, 640, "portrait"), (720, 1280, "landscape")]:
            with self.subTest(width=width, height=height), self.assertRaises(AssertionError):
                assert_frame_dimensions(self.device(), width, height, orientation)


if __name__ == "__main__": unittest.main()
