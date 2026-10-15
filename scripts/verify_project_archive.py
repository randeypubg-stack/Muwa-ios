#!/usr/bin/env python3
"""Verify and restore a Muwa export entirely offline, including iOS assembly."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys
import tempfile
import zipfile

from export_project import CHUNK_SIZE, assemble, command, digest, forbidden, git, git_environment, inventory, safe_path, unpack_git_archive


def compare_files(left: Path, right: Path, label: str) -> int:
    def values(root: Path) -> dict[str, tuple[str, int, str]]:
        return {str(item["path"]): (str(item["sha256"]), int(item["sizeBytes"]), str(item["mode"])) for item in inventory(root)}
    expected, actual = values(left), values(right)
    if expected != actual:
        changed = sorted(path for path in set(expected) | set(actual) if expected.get(path) != actual.get(path))
        raise ValueError(f"{label} differs: {changed[:10]}")
    return len(expected)


def validate_zip(archive: zipfile.ZipFile, maximum: int) -> tuple[str, dict[str, zipfile.ZipInfo]]:
    entries: dict[str, zipfile.ZipInfo] = {}
    case_names: set[str] = set()
    total = 0
    roots: set[str] = set()
    for info in archive.infolist():
        name = info.filename.removesuffix("/") if info.is_dir() else info.filename
        relative = safe_path(name)
        if name in entries or name.casefold() in case_names:
            raise ValueError(f"Duplicate archive path: {name}")
        mode = info.external_attr >> 16
        kind = stat.S_IFMT(mode)
        if kind not in (0, stat.S_IFREG, stat.S_IFDIR):
            raise ValueError(f"Archive contains a link or special file: {name}")
        if info.is_dir() and kind == stat.S_IFREG or not info.is_dir() and kind == stat.S_IFDIR:
            raise ValueError(f"Archive file type disagrees with path: {name}")
        if info.flag_bits & 1:
            raise ValueError("Encrypted ZIP entries are not supported")
        roots.add(relative.parts[0])
        entries[name] = info
        case_names.add(name.casefold())
        total += info.file_size
        if total > maximum:
            raise ValueError("Archive exceeds --max-bytes")
    if len(roots) != 1:
        raise ValueError("Archive must contain one project root")
    root = next(iter(roots))
    if not re.fullmatch(r"Muwa-Project-\d{4}-\d{2}-\d{2}", root):
        raise ValueError("Unexpected project root directory")
    for name, info in entries.items():
        for parent in PurePosixPath(name).parents:
            parent_name = str(parent)
            if parent_name in entries and not entries[parent_name].is_dir():
                raise ValueError(f"A file is used as a directory: {parent_name}")
    bad = archive.testzip()
    if bad:
        raise ValueError(f"ZIP CRC mismatch: {bad}")
    return root, entries


def verify(args: argparse.Namespace) -> dict[str, object]:
    source = args.archive.resolve()
    with tempfile.TemporaryDirectory(prefix="muwa-verify-") as temporary:
        extracted = Path(temporary) / "extracted"
        extracted.mkdir()
        with zipfile.ZipFile(source) as archive:
            root_name, entries = validate_zip(archive, args.max_bytes)
            manifest_name = root_name + "/MANIFEST.json"
            if manifest_name not in entries or entries[manifest_name].file_size > 16 * 1024 * 1024:
                raise ValueError("Missing or oversized MANIFEST.json")
            manifest = json.loads(archive.read(manifest_name))
            if not isinstance(manifest, dict) or manifest.get("version") != 1 or manifest.get("rootDirectory") != root_name:
                raise ValueError("Unsupported manifest or wrong project root")
            payload = manifest.get("files")
            if not isinstance(payload, list):
                raise ValueError("Manifest file catalog is invalid")
            expected: dict[str, dict[str, object]] = {}
            for item in payload:
                if not isinstance(item, dict):
                    raise ValueError("Manifest file entry is invalid")
                path = str(safe_path(item.get("path")))
                if path == "MANIFEST.json" or path in expected or forbidden(PurePosixPath(path)):
                    raise ValueError(f"Invalid manifest path: {path}")
                size = item.get("sizeBytes")
                if not isinstance(size, int) or isinstance(size, bool) or size < 0 or not re.fullmatch(r"[a-f0-9]{64}", str(item.get("sha256", ""))) or item.get("mode") not in ("0644", "0755"):
                    raise ValueError(f"Invalid manifest metadata: {path}")
                expected[path] = item
            actual = {name[len(root_name) + 1:]: info for name, info in entries.items() if not info.is_dir() and name != manifest_name}
            if set(expected) != set(actual):
                raise ValueError("Manifest does not describe every payload file exactly once")
            for relative, item in expected.items():
                info = actual[relative]
                if info.file_size != item["sizeBytes"]:
                    raise ValueError(f"File size mismatch: {relative}")
                destination = extracted / root_name / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                sha = hashlib.sha256()
                with archive.open(info) as stream, destination.open("xb") as target:
                    for chunk in iter(lambda: stream.read(CHUNK_SIZE), b""):
                        sha.update(chunk)
                        target.write(chunk)
                if sha.hexdigest() != item["sha256"]:
                    raise ValueError(f"SHA-256 mismatch: {relative}")
                archive_executable = bool((info.external_attr >> 16) & 0o111)
                if archive_executable != (item["mode"] == "0755"):
                    raise ValueError(f"Executable mode mismatch: {relative}")
                destination.chmod(int(str(item["mode"]), 8))
            (extracted / manifest_name).write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
        root = extracted / root_name
        metadata = manifest.get("source", {})
        commit, tree, branch = metadata.get("commit"), metadata.get("tree"), metadata.get("branch")
        if not isinstance(commit, str) or not re.fullmatch(r"[a-f0-9]{40,64}", commit) or not isinstance(tree, str) or not re.fullmatch(r"[a-f0-9]{40,64}", tree) or not isinstance(branch, str):
            raise ValueError("Invalid source commit/tree/branch metadata")
        command(["git", "check-ref-format", "refs/heads/" + branch], env=git_environment())
        if manifest.get("bundleHead") != {"commit": commit, "ref": "refs/heads/" + branch}:
            raise ValueError("Bundle metadata disagrees with source metadata")
        bundle = root / "History/muwa.bundle"
        heads = command(["git", "bundle", "list-heads", str(bundle)], env=git_environment()).splitlines()
        if heads != [commit + " refs/heads/" + branch]:
            raise ValueError("Offline bundle has unexpected heads")
        restored = Path(temporary) / "restored-git"
        command(["git", "-c", "core.fsmonitor=false", "clone", "--no-checkout", "--branch", branch, str(bundle), str(restored)], env=git_environment())
        if git(restored, "rev-parse", "HEAD") != commit or git(restored, "rev-parse", "HEAD^{tree}") != tree:
            raise ValueError("Restored Git commit/tree disagrees with manifest")
        git(restored, "bundle", "verify", str(bundle))
        canonical = Path(temporary) / "canonical-source"
        unpack_git_archive(restored, commit, canonical)
        repository_files = compare_files(canonical, root / "Repository", "Repository vs offline Git tree")
        generated = Path(temporary) / "regenerated-ios"
        assemble(root / "Repository", generated, commit)
        ios_metadata = manifest.get("iOS")
        if ios_metadata != {"path": "iOS/MuwaNasheedsNative", "build": 54, "kind": "assembled source"}:
            raise ValueError("Unexpected iOS source metadata")
        ios_files = compare_files(generated, root / "iOS/MuwaNasheedsNative", "Regenerated iOS sources")
        registration = root / "Repository/tests/check_native_registration.py"
        if not registration.is_file():
            raise ValueError("Missing native registration check")
        command([sys.executable, str(registration), str(generated)], cwd=root / "Repository")
    return {"result": "passed", "archive": str(source), "sha256": digest(source), "sourceCommit": commit, "sourceTree": tree, "branch": branch, "payloadFiles": len(expected), "repositoryFiles": repository_files, "iOSFiles": ios_files, "checks": ["safe ZIP paths and CRC", "complete SHA-256/size/mode manifest", "offline Git bundle restore", "Repository equals canonical committed source", "iOS source regeneration", "native registration and idempotency"], "scope": "Source/archive verification; no new simulator run, signed app build or live server/database backup"}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--max-bytes", type=int, default=2 * 1024 * 1024 * 1024)
    args = parser.parse_args()
    if args.max_bytes <= 0:
        parser.error("--max-bytes must be positive")
    try:
        result = verify(args)
    except (ValueError, TypeError, AttributeError, OSError, subprocess.SubprocessError, zipfile.BadZipFile, RuntimeError) as error:
        parser.exit(1, "Verification failed: " + str(error) + "\n")
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
