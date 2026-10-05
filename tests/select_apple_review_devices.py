"""Select real installed iOS simulators and preserve their toolchain provenance.

The selected stable Xcode's simulator SDK bounds the runtime version. Device
names come from simctl's device-type catalogue, never from a requested label.
Use ``--print-udid`` in CI destinations or ``--output`` for an inventory report.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys


KINDS = ("phone", "large-phone", "tablet", "small-tablet", "small-phone")


def version_key(value):
    parts = [int(part) for part in re.findall(r"\d+", str(value))[:3]]
    return tuple((parts + [0, 0, 0])[:3])


def is_ios(runtime):
    return runtime.get("identifier", "").startswith("com.apple.CoreSimulator.SimRuntime.iOS-")


def runtime_is_preview(runtime):
    label = " ".join(str(runtime.get(key, "")) for key in ("name", "bundlePath", "version"))
    return bool(re.search(r"beta|preview|seed", label, re.IGNORECASE))


def normalize_inventory(devices, runtimes, device_types, sdk_version):
    """Build records from actual simctl identifiers, retaining renamed devices."""
    types = {item["identifier"]: item for item in device_types}
    by_name = {}
    for item in device_types:
        by_name.setdefault(item["name"], []).append(item)
    records = []
    sdk_limit = version_key(sdk_version)
    for runtime in runtimes:
        if not is_ios(runtime) or not runtime.get("isAvailable"):
            continue
        if runtime_is_preview(runtime) or version_key(runtime["version"]) > sdk_limit:
            continue
        for device in devices.get(runtime["identifier"], []):
            if not device.get("isAvailable"):
                continue
            identifier = device.get("deviceTypeIdentifier")
            actual_type = types.get(identifier)
            if actual_type is None and identifier is None:
                matches = by_name.get(device["name"], [])
                actual_type = matches[0] if len(matches) == 1 else None
            if actual_type is None:
                raise ValueError(f"Cannot verify device type for {device['name']} ({device['udid']})")
            model = actual_type["name"]
            if not model.startswith(("iPhone", "iPad")):
                continue
            records.append({
                **device,
                "name": model,
                "simulatorName": device["name"],
                "deviceTypeIdentifier": actual_type["identifier"],
                "runtimeIdentifier": runtime["identifier"],
                "runtimeName": runtime["name"],
                "runtimeVersion": runtime["version"],
                "runtimeBuild": runtime.get("buildversion"),
            })
    return records


def model_rank(device, kind):
    name = device["name"]
    if kind in ("phone", "large-phone", "small-phone"):
        generation = re.search(r"iPhone (\d+)", name)
        generation = int(generation.group(1)) if generation else 0
        variant = 3 if "Pro" in name else 2 if "Plus" in name else 1
        return (generation, variant)
    chip = re.search(r"\(([MA])(\d+)\)", name)
    if chip is None:
        chip = re.search(r"\(([MA])(\d+) Pro\)", name)
    generation = re.search(r"\((\d+)(?:st|nd|rd|th) generation\)", name)
    chip_generation = int(chip.group(2)) if chip else int(generation.group(1)) if generation else 0
    size = re.search(r"(\d+(?:\.\d+)?)-inch", name)
    size = float(size.group(1)) if size else 0
    family = 3 if "Pro" in name and "mini" not in name else 2 if "Air" in name else 1
    return (family, chip_generation, size)


def select_devices(records, kind=None, runtime_version=None):
    if runtime_version:
        records = [device for device in records if version_key(device['runtimeVersion']) == version_key(runtime_version)]
        if not records:
            raise ValueError(f"Requested stable iOS runtime unavailable: {runtime_version}")
    if not records:
        raise ValueError("No available stable iOS simulators compatible with the selected Xcode SDK")
    newest = max(version_key(device["runtimeVersion"]) for device in records)
    latest = [device for device in records if version_key(device["runtimeVersion"]) == newest]
    phones = [device for device in latest if device["name"].startswith("iPhone")]
    pads = [device for device in latest if device["name"].startswith("iPad")]
    groups = {
        "phone": [device for device in phones if not any(part in device["name"] for part in ("Pro Max", "Plus", "SE"))] or phones,
        "large-phone": [device for device in phones if any(part in device["name"] for part in ("Pro Max", "Plus"))],
        "tablet": [device for device in pads if "mini" not in device["name"]] or pads,
        "small-tablet": [device for device in pads if "mini" in device["name"]],
        "small-phone": [device for device in phones if "SE" in device["name"]],
    }
    if kind is not None and kind not in groups:
        raise ValueError(f"Unknown review device kind: {kind}")
    result = []
    for requested_kind in ([kind] if kind else KINDS):
        candidates = groups[requested_kind]
        if not candidates:
            if kind is not None or requested_kind in ("phone", "tablet"):
                raise ValueError(f"Review device unavailable on newest iOS runtime: {requested_kind}")
            continue
        # A repeatable tie break avoids depending on simctl's JSON array order.
        chosen = sorted(candidates, key=lambda item: (model_rank(item, requested_kind), item["name"], item["udid"]))[-1]
        if not any(item["udid"] == chosen["udid"] for item in result):
            result.append({**chosen, "kind": requested_kind})
    return result


def request_status(records, selected, requested_device=None, requested_ios=None):
    def matches_os(device):
        if not requested_ios:
            return True
        requested = tuple(int(part) for part in str(requested_ios).split("."))
        return version_key(device["runtimeVersion"])[:len(requested)] == requested

    def matches_device(device):
        return not requested_device or device["name"] == requested_device

    matching = [device for device in records if matches_os(device) and matches_device(device)]
    tested = [device for device in selected if matches_os(device) and matches_device(device)]
    return {
        "device": requested_device,
        "iOS": requested_ios,
        "deviceAvailable": any(matches_device(device) for device in records),
        "runtimeAvailable": any(matches_os(device) for device in records),
        "exactCombinationAvailable": bool(matching),
        "selectedMatchesRequest": bool(tested),
        "status": "not-requested" if not requested_device and not requested_ios else "selected" if tested else "available-not-selected" if matching else "unavailable",
        "scope": "available installed stable runtimes compatible with selected Xcode SDK",
    }


def command(*args, timeout=120):
    return subprocess.check_output(args, text=True, timeout=timeout).strip()


def open_simulator_gui(udid, developer_directory=None):
    """Warm the selected Xcode's actual Simulator UI before device UI commands.

    Boot status can finish before the GUI-backed appearance service responds on
    cold hosted runners. Opening a different/default Simulator would not prove
    that the selected Xcode/runtime has been prepared.
    """
    developer_directory = developer_directory or os.environ.get("DEVELOPER_DIR") or command("xcode-select", "-p")
    simulator = Path(developer_directory) / "Applications/Simulator.app"
    status = {"bundle":str(simulator), "available":simulator.is_dir(), "opened":False}
    if not status['available']:
        status['reason'] = 'Selected Xcode image has no Simulator GUI bundle; using its actual headless runtime'
        print(status['reason'] + ': ' + str(simulator), file=sys.stderr, flush=True)
        return status
    argv = ["/usr/bin/open", "-a", str(simulator), "--args", "-CurrentDeviceUDID", udid]
    print("Opening selected Simulator GUI:", " ".join(argv), file=sys.stderr, flush=True)
    try:
        subprocess.run(argv, check=True, timeout=45, stdout=subprocess.DEVNULL)
        status['opened'] = True
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        # The GUI is optional on stripped hosted images; the exact selected
        # runtime must still pass bootstatus and all actual capture assertions.
        status['reason'] = str(error)
        status['launchErrorType'] = type(error).__name__
        print('Selected Simulator GUI could not open: ' + str(error), file=sys.stderr, flush=True)
    return status


def boot_selected_device(device):
    """Boot and verify the same selected runtime/UDID before XCTest starts."""
    def live_device():
        groups = json.loads(command('xcrun', 'simctl', 'list', 'devices', device['udid'], '--json'))['devices']
        matches = [(runtime, item) for runtime, items in groups.items()
                   for item in items if item['udid'] == device['udid']]
        if len(matches) != 1:
            raise ValueError(f"Selected Simulator UDID unavailable: {device['udid']}")
        runtime, item = matches[0]
        if runtime != device['runtimeIdentifier'] or not item.get('isAvailable'):
            raise ValueError(f"Selected Simulator runtime changed or unavailable: {device['udid']}")
        return item

    current = live_device()
    requested_boot = current['state'] == 'Shutdown'
    if requested_boot:
        print('Booting selected Simulator: ' + device['udid'], file=sys.stderr, flush=True)
        command('xcrun', 'simctl', 'boot', device['udid'])
    print('Waiting for selected Simulator bootstatus: ' + device['udid'], file=sys.stderr, flush=True)
    boot_output = command('xcrun', 'simctl', 'bootstatus', device['udid'], '-b', timeout=240)
    print('Selected Simulator bootstatus completed:\n' + boot_output, file=sys.stderr, flush=True)
    # The selected UDID/runtime was verified immediately before boot. The
    # blocking bootstatus command verifies this same immutable device directly.
    # A repeated inventory RPC after boot deadlocks on some headless Xcode 27
    # hosts; do not replace successful bootstatus with an unrelated list query.
    return {'udid':device['udid'], 'runtimeIdentifier':device['runtimeIdentifier'],
            'state':'Booted', 'stateVerification':'Selected UDID bootstatus -b completed successfully',
            'bootRequested':requested_boot, 'bootstatusCompleted':True,
            'bootstatusOutput':boot_output}


def load_selection(kind=None, requested_device=None, requested_ios=None, runtime_version=None):
    devices = json.loads(command("xcrun", "simctl", "list", "devices", "available", "--json"))["devices"]
    runtimes = json.loads(command("xcrun", "simctl", "list", "runtimes", "--json"))["runtimes"]
    device_types = json.loads(command("xcrun", "simctl", "list", "devicetypes", "--json"))["devicetypes"]
    sdk_version = command("xcrun", "--sdk", "iphonesimulator", "--show-sdk-version")
    records = normalize_inventory(devices, runtimes, device_types, sdk_version)
    selected = select_devices(records, kind, runtime_version)
    report = {
        "schemaVersion": 1,
        "selectionPolicy": "Newest available stable iOS runtime within selected SDK; latest real model per size class",
        "requiredRuntimeVersion": runtime_version,
        "toolchain": {
            "xcode": command("xcodebuild", "-version"),
            "developerDirectory": os.environ.get("DEVELOPER_DIR") or command("xcode-select", "-p"),
            "simctlExecutable": command("xcrun", "--find", "simctl"),
            "simulatorSDKVersion": sdk_version,
            "hostOSVersion": command("sw_vers", "-productVersion"),
            "hostArchitecture": command("uname", "-m"),
        },
        "requested": request_status(records, selected, requested_device, requested_ios),
        "runtimes": runtimes,
        "availableDevices": records,
        "selected": selected,
    }
    return selected, report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kind", choices=KINDS, default=os.environ.get("MUWA_REVIEW_DEVICE"))
    parser.add_argument("--requested-device", default=os.environ.get("MUWA_REQUESTED_DEVICE"))
    parser.add_argument("--requested-ios", default=os.environ.get("MUWA_REQUESTED_IOS"))
    parser.add_argument("--runtime-version", default=os.environ.get("MUWA_REVIEW_RUNTIME_VERSION"))
    parser.add_argument("--output", type=Path)
    parser.add_argument("--print-udid", action="store_true")
    parser.add_argument("--open-gui", action="store_true", help="Open the selected Xcode Simulator GUI for one selected device")
    parser.add_argument("--boot", action="store_true", help="Require the selected runtime and UDID to finish booting before XCTest")
    args = parser.parse_args()
    selected, report = load_selection(args.kind, args.requested_device, args.requested_ios, args.runtime_version)
    def write_report():
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")

    # Preserve actual preflight evidence even when a hosted CoreSimulator service
    # stops responding before XCTest starts. A failed boot remains a failure.
    write_report()
    try:
        if args.open_gui:
            if len(selected) != 1:
                parser.error("--open-gui requires one --kind")
            report["simulatorGUI"] = open_simulator_gui(selected[0]["udid"])
        if args.boot:
            if len(selected) != 1:
                parser.error("--boot requires one --kind")
            report['simulatorBoot'] = {'completed':False, 'udid':selected[0]['udid'],
                                       'runtimeIdentifier':selected[0]['runtimeIdentifier']}
            write_report()
            try:
                report['simulatorBoot'].update(boot_selected_device(selected[0]), completed=True)
            except Exception as error:
                failure = {'type':type(error).__name__, 'message':str(error)}
                if isinstance(error, subprocess.TimeoutExpired):
                    failure.update(command=list(error.cmd), timeoutSeconds=error.timeout)
                elif isinstance(error, subprocess.CalledProcessError):
                    failure.update(command=list(error.cmd), exitCode=error.returncode)
                report['simulatorBoot']['error'] = failure
                raise
    finally:
        write_report()
    if args.print_udid:
        if len(selected) != 1:
            parser.error("--print-udid requires one --kind")
        print(selected[0]["udid"])
    elif not args.output:
        print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
