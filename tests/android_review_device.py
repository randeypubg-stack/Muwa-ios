"""Record and verify the actual Android emulator used by native review captures.

Display overrides are reported separately from the AVD's hardware profile. An
emulator capture is never evidence that Muwa ran on that physical Pixel model.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
from urllib.request import urlopen
import xml.etree.ElementTree as ET

PLATFORMS_URL = "https://dl.google.com/android/repository/repository2-3.xml"
IMAGES_URL = "https://dl.google.com/android/repository/sys-img/google_apis/sys-img2-3.xml"


def select_profile(inventory, kind):
    """Choose a profile which actually exists in this runner's SDK catalog."""
    profiles = sorted({line.strip() for line in inventory.splitlines()
                       if re.fullmatch(r"[A-Za-z0-9 _().-]+", line.strip())})
    phones = []
    for profile in profiles:
        match = re.fullmatch(r"pixel_(\d+)(?:_(pro_xl|xl|pro))?", profile)
        if match:
            phones.append((int(match[1]), {None: 0, "pro": 1, "xl": 2, "pro_xl": 3}[match[2]], profile))
    phone = max(phones)[2] if phones else next((name for name in ["pixel", "Nexus 6"] if name in profiles), None)
    assert phone, "The installed SDK has no supported, identifiable phone hardware profile"
    reason = "newest numeric Pixel generation; Pro XL/XL preferred within that generation"
    fallback = not bool(phones)
    selected = phone
    if kind == "tablet":
        tablets = []
        for profile in profiles:
            match = re.fullmatch(r"pixel_tablet(?:_(\d+))?", profile)
            if match:
                tablets.append((int(match[1] or "1"), profile))
        if tablets:
            selected = max(tablets)[1]
            reason = "newest available Pixel Tablet hardware profile in the SDK catalog"
            fallback = False
        else:
            selected = next((name for name in ["large_tablet", "medium_tablet", "pixel_c", "Nexus 9", "Nexus 10"]
                             if name in profiles), phone)
            reason = ("available generic or legacy tablet profile with explicit display overrides"
                      if selected != phone else "no tablet profile available; phone profile with explicit tablet display overrides")
            fallback = True
    assert kind in {"phone", "tablet"}, "Unknown review form factor"
    return {"kind": kind, "profile": selected, "selectionReason": reason, "fallback": fallback,
            "availableProfileIDs": profiles, "source": "installed SDK: avdmanager list device -c",
            "physicalDeviceVerified": False, "checkedAtUTC": datetime.now(timezone.utc).isoformat()}


def stable_packages(document, prefix):
    """Exclude previews even when Google publishes them on channel-0."""
    for package in ET.fromstring(document).findall("remotePackage"):
        path = package.attrib["path"]
        channel = package.find("channelRef")
        details = package.find("type-details")
        if not path.startswith(prefix) or channel is None or channel.attrib.get("ref") != "channel-0":
            continue
        if details is None or (details.findtext("codename") or "").strip():
            continue
        version = path[len(prefix):].split(";")[0]
        # Extensions, beta and canary package names are not stable OS releases.
        if not re.fullmatch(r"\d+(?:\.\d+)?", version):
            continue
        if details.findtext("base-extension") == "false":
            continue
        yield package, tuple(map(int, version.split(".")))


def sdk_availability(api, target, arch, require_latest=False):
    documents = {}
    for label, url in [("platforms", PLATFORMS_URL), ("systemImages", IMAGES_URL)]:
        with urlopen(url, timeout=30) as response:
            documents[label] = response.read()
    platform_path = f"platforms;android-{api}"
    image_path = f"system-images;android-{api};{target};{arch}"
    platforms = {p.attrib["path"]: (p, version)
                 for p, version in stable_packages(documents["platforms"], "platforms;android-")}
    images = {p.attrib["path"]: (p, version)
              for p, version in stable_packages(documents["systemImages"], "system-images;android-")}
    assert platform_path in platforms, f"Google has no stable platform {platform_path}"
    assert image_path in images, f"Google has no stable image {image_path}"
    latest = max(version for _, version in platforms.values())
    requested = platforms[platform_path][1]
    if require_latest:
        assert requested == latest, f"Requested API {api} is not the latest stable Google SDK {latest}"
    image = images[image_path][0]
    return {
        "checkedAtUTC": datetime.now(timezone.utc).isoformat(), "channel": "stable",
        "platformPackage": platform_path, "systemImagePackage": image_path,
        "imageRevision": image.findtext("revision/major"),
        "latestStablePlatformAPI": ".".join(map(str, latest)),
        "isLatestStablePlatform": requested == latest,
        "sources": {label: {"url": url, "sha256": hashlib.sha256(documents[label]).hexdigest()}
                    for label, url in [("platforms", PLATFORMS_URL), ("systemImages", IMAGES_URL)]},
    }


def display_state(size, density):
    physical_size = re.search(r"Physical size:\s*(\d+)x(\d+)", size)
    physical_density = re.search(r"Physical density:\s*(\d+)", density)
    assert physical_size and physical_density, "Android did not report its physical display geometry"
    override_size = re.search(r"Override size:\s*(\d+)x(\d+)", size)
    override_density = re.search(r"Override density:\s*(\d+)", density)
    width, height = map(int, (override_size or physical_size).groups())
    dpi = int((override_density or physical_density).group(1))
    assert width > 0 and height > 0 and dpi > 0, "Invalid Android display geometry"
    return {"physicalSize": "x".join(physical_size.groups()),
            "physicalDensityDPI": int(physical_density.group(1)),
            "overrideSize": "x".join(override_size.groups()) if override_size else None,
            "overrideDensityDPI": int(override_density.group(1)) if override_density else None,
            "effectiveWidth": width, "effectiveHeight": height, "effectiveDensityDPI": dpi}


def assert_review_device(device, api=None, image=None, profile=None, avd_name=None,
                         expected_size=None, expected_density=None, page_size=None):
    assert device["isEmulator"], "Native review must identify an actual Android emulator"
    assert device["android"]["codename"] == "REL", "Preview Android image is not a stable review target"
    if api:
        assert int(device["android"]["sdk"]) == int(api.split(".")[0]), "Booted Android SDK does not match the requested API"
    if image:
        suffix = image.replace(";", "/").strip("/")
        assert device["avd"]["systemImageDirectory"].replace("\\", "/").strip("/").endswith(suffix), "AVD system image differs from requested SDK package"
    if profile:
        assert device["avd"]["hardwareProfile"] == profile, "AVD hardware profile differs from the requested profile"
    if avd_name:
        assert device["avd"]["name"] == avd_name, "Wrong AVD is connected"
    if expected_size:
        actual = f'{device["display"]["effectiveWidth"]}x{device["display"]["effectiveHeight"]}'
        assert actual == expected_size, "Requested native display size did not apply"
    if expected_density:
        assert device["display"]["effectiveDensityDPI"] == int(expected_density), "Requested display density did not apply"
    if page_size:
        assert device["pageSizeBytes"] == int(page_size), "Android page size differs from the selected system image"


def review_device(adb):
    properties = dict(re.findall(r"^\[([^]]+)\]: \[([^]]*)\]$", adb("shell", "getprop"), re.MULTILINE))
    avd_name = next((line.strip() for line in adb("emu", "avd", "name").splitlines()
                     if line.strip() and line.strip() != "OK"), "")
    assert re.fullmatch(r"[\w.-]+", avd_name), "Android Emulator did not report a valid AVD name"
    avd_root = Path(os.environ.get("ANDROID_AVD_HOME", str(Path.home() / ".android/avd")))
    config = {}
    for line in (avd_root / f"{avd_name}.avd" / "config.ini").read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            key, value = line.split("=", 1)
            config[key.strip()] = value.strip()
    size = adb("shell", "wm", "size").strip()
    density = adb("shell", "wm", "density").strip()
    sdk_root = os.environ.get("ANDROID_SDK_ROOT") or os.environ.get("ANDROID_HOME")
    emulator = str(Path(sdk_root) / "emulator/emulator") if sdk_root else "emulator"
    version = subprocess.check_output([emulator, "-version"], text=True, timeout=15).splitlines()[0]
    source = Path(__file__).resolve().parents[1] / "android/app/build.gradle.kts"
    configuration = {key: int(re.search(rf"\b{key}\s*=\s*(\d+)", source.read_text()).group(1))
                     for key in ["compileSdk", "targetSdk", "minSdk", "versionCode"]}
    device = {
        "kind": "Android emulator", "physicalDeviceVerified": False,
        "geometryDescription": "Native emulator pixels; display overrides do not change the hardware model",
        "model": properties.get("ro.product.model"), "manufacturer": properties.get("ro.product.manufacturer"),
        "isEmulator": (properties.get("ro.kernel.qemu") or properties.get("ro.boot.qemu")) == "1",
        "abi": properties.get("ro.product.cpu.abi"), "emulatorVersion": version,
        "android": {"sdk": properties.get("ro.build.version.sdk"),
                    "sdkFull": properties.get("ro.build.version.sdk_full"),
                    "sdkMinor": properties.get("ro.build.version.sdk_minor"),
                    "release": properties.get("ro.build.version.release"),
                    "codename": properties.get("ro.build.version.codename"),
                    "securityPatch": properties.get("ro.build.version.security_patch"),
                    "buildFingerprint": properties.get("ro.build.fingerprint")},
        "avd": {"name": avd_name, "hardwareProfile": config.get("hw.device.name"),
                "hardwareManufacturer": config.get("hw.device.manufacturer"),
                "systemImageDirectory": config.get("image.sysdir.1", ""),
                "graphicsMode": config.get("hw.gpu.mode")},
        "pageSizeBytes": int(adb("shell", "getconf", "PAGESIZE").strip()),
        "display": display_state(size, density), "size": size, "density": density,
        "sourceConfiguration": configuration, "sourceCommit": os.environ.get("GITHUB_SHA"),
        "requestedAPI": os.environ.get("MUWA_ANDROID_API"),
        "requestedSystemImage": os.environ.get("MUWA_ANDROID_SYSTEM_IMAGE"),
    }
    assert_review_device(device, api=os.environ.get("MUWA_ANDROID_API"),
                         image=os.environ.get("MUWA_ANDROID_SYSTEM_IMAGE"),
                         profile=os.environ.get("MUWA_ANDROID_PROFILE"),
                         avd_name=os.environ.get("MUWA_ANDROID_AVD_NAME"),
                         expected_size=os.environ.get("MUWA_ANDROID_SCREEN_SIZE"),
                         expected_density=os.environ.get("MUWA_ANDROID_SCREEN_DENSITY"),
                         page_size=os.environ.get("MUWA_ANDROID_PAGE_SIZE"))
    availability = Path(os.environ.get("MUWA_ANDROID_OUTPUT", "build/android-previews")) / "sdk-availability.json"
    if availability.exists():
        device["sdkAvailability"] = json.loads(availability.read_text())
        assert device["sdkAvailability"]["systemImagePackage"] == device["requestedSystemImage"], "SDK availability proof is for another image"
    selection = availability.with_name("avd-profile-selection.json")
    if selection.exists():
        device["profileSelection"] = json.loads(selection.read_text())
        assert device["profileSelection"]["profile"] == device["avd"]["hardwareProfile"], "Booted profile differs from the recorded SDK selection"
    return device


def assert_frame_dimensions(device, width, height, orientation):
    expected = sorted([device["display"]["effectiveWidth"], device["display"]["effectiveHeight"]])
    assert sorted([width, height]) == expected, "Capture dimensions differ from the actual configured native display"
    assert (height > width) if orientation == "portrait" else (width > height), "Capture orientation differs from its label"


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--api")
    mode.add_argument("--select-profile", choices=["phone", "tablet"])
    parser.add_argument("--target")
    parser.add_argument("--arch", default="x86_64")
    parser.add_argument("--require-latest", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.select_profile:
        inventory = subprocess.check_output(["avdmanager", "list", "device", "-c"], text=True, timeout=30)
        proof = select_profile(inventory, args.select_profile)
        if os.environ.get("GITHUB_OUTPUT"):
            with Path(os.environ["GITHUB_OUTPUT"]).open("a") as output:
                output.write(f'profile={proof["profile"]}\n')
        print(f'Selected actual SDK hardware profile: {proof["profile"]}', flush=True)
    else:
        assert args.target, "--target is required for SDK availability verification"
        proof = sdk_availability(args.api, args.target, args.arch, args.require_latest)
        print(f'Verified stable Google SDK image: {proof["systemImagePackage"]}', flush=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(proof, ensure_ascii=False, indent=2))
