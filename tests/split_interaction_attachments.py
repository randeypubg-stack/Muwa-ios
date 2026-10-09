"""Package native XCTest PNGs and proofs separately from test videos.

Usage: python3 tests/split_interaction_attachments.py --input SOURCE --output OUTPUT
SOURCE is the actual directory produced by `xcresulttool export attachments`.
No image bytes, image orientation or capture metadata are rewritten.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil


MAX_RECOMMENDED_BYTES = 31 * 1024 * 1024  # Leave ZIP metadata headroom below 32 MiB.


def safe_source(root, exported_name):
    if not isinstance(exported_name, str) or not exported_name:
        raise ValueError("Attachment is missing exportedFileName")
    candidate = root / exported_name
    if Path(exported_name).is_absolute() or ".." in Path(exported_name).parts:
        raise ValueError("Unsafe exported attachment path: " + exported_name)
    candidate = candidate.resolve()
    if not candidate.is_relative_to(root) or not candidate.is_file():
        raise ValueError("Attachment is missing or outside export directory: " + exported_name)
    return candidate


def unique_name(suggestion, source, used):
    # Treat the suggested display label as a label, never as a filesystem path.
    label = re.sub(r"[^A-Za-z0-9._-]", "_", str(suggestion or source.name))
    stem = Path(label).stem.strip("._")[:150] or "attachment"
    candidate = stem + source.suffix.lower()
    number = 1
    while candidate.casefold() in used:
        number += 1
        candidate = f"{stem}--{number}{source.suffix.lower()}"
    used.add(candidate.casefold())
    return candidate


def package_attachments(source, output, inventory=None):
    source, output = Path(source).resolve(), Path(output).resolve()
    if source == output or source.is_relative_to(output) or output.is_relative_to(source):
        raise ValueError("Output must be separate from the original export directory")
    manifest_path = source / "manifest.json"
    manifest_exists = manifest_path.is_file()
    manifest = json.loads(manifest_path.read_text()) if manifest_exists else []
    if not isinstance(manifest, list):
        raise ValueError("Expected xcresulttool's exported array manifest")
    if output.exists() and any(output.iterdir()):
        raise ValueError("Output must be empty; preserve earlier review packages separately")

    # Keep each changed feature small enough to inspect independently without
    # transforming the original PNGs or discarding the complete primary export.
    groups = {name: output / name for name in ("primary", "popular", "artwork", "loading", "layout")}
    mappings = {name: [] for name in groups}
    used = {name: {"manifest.json", "provenance.json", "interaction-devices.json"} for name in groups}
    excluded = []
    for directory in groups.values():
        directory.mkdir(parents=True, exist_ok=True)
        if manifest_exists:
            shutil.copyfile(manifest_path, directory / "manifest.json")
    inventory = Path(inventory).resolve() if inventory else source.parent / "interaction-devices.json"
    if inventory.is_file():
        for directory in groups.values():
            shutil.copyfile(inventory, directory / "interaction-devices.json")

    for test in manifest:
        for attachment in test.get("attachments", []):
            filename = attachment.get("exportedFileName")
            path = safe_source(source, filename)
            label = attachment.get("suggestedHumanReadableName") or path.name
            provenance = {
                "sourceFile": filename,
                "suggestedHumanReadableName": label,
                "testIdentifier": test.get("testIdentifier"),
                "testIdentifierURL": test.get("testIdentifierURL"),
                "configurationName": attachment.get("configurationName"),
                "deviceId": attachment.get("deviceId"),
                "deviceName": attachment.get("deviceName"),
                "timestamp": attachment.get("timestamp"),
                "isAssociatedWithFailure": attachment.get("isAssociatedWithFailure"),
                "bytes": path.stat().st_size,
            }
            suffix = path.suffix.lower()
            if suffix not in (".png", ".json"):
                excluded.append({**provenance, "reason": "Video or non-PNG/non-JSON attachment; retained in original xcresult/export"})
                continue
            destinations = ["primary"]
            for marker, group in [("popular-", "popular"), ("portrait-artwork", "artwork"), ("buffering-ring", "loading"), ("navigation-", "layout"), ("long-arabic-caption", "layout")]:
                if marker in str(label).lower(): destinations.append(group)
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            for group in destinations:
                name = unique_name(label, path, used[group])
                shutil.copyfile(path, groups[group] / name)
                mappings[group].append({**provenance, "packageFile": name, "sha256": digest})

    summary = {"schemaVersion": 1, "scope": "Unmodified native XCTest attachment exports; package contents do not establish test success", "exportManifestAvailable":manifest_exists, "excludedAttachments": excluded, "groups": {}}
    manifest_digest = hashlib.sha256(manifest_path.read_bytes()).hexdigest() if manifest_exists else None
    for group, directory in groups.items():
        report = {
            "schemaVersion": 1, "group": group,
            "scope": "Unmodified native XCTest screenshots; rotation follows original PNG EXIF",
            "originalExportManifest": {"packageFile": "manifest.json", "sha256": manifest_digest} if manifest_exists else None,
            "exportManifestAvailable":manifest_exists,
            "captureAvailable":any(item['packageFile'].endswith('.png') for item in mappings[group]),
            "attachments": mappings[group], "excludedAttachments": excluded,
            "testStatus": "Read the original xcresult; partial failure captures remain partial",
        }
        (directory / "provenance.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        total = sum(file.stat().st_size for file in directory.iterdir() if file.is_file())
        summary["groups"][group] = {"path": str(directory), "bytes": total,
            "files": len(list(directory.iterdir())), "attachmentCount": len(mappings[group]),
            "belowRecommendedLimit": total <= MAX_RECOMMENDED_BYTES,
            "recommendedLimitBytes": MAX_RECOMMENDED_BYTES}
    output.mkdir(parents=True, exist_ok=True)
    (output / "package-summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n")
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", dest="source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--inventory", type=Path)
    args = parser.parse_args()
    print(json.dumps(package_attachments(args.source, args.output, args.inventory), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
