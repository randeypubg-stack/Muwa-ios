"""Require the same native inputs before reviewing an existing compiled artifact."""
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
folders = ["native-patches", "branding", "source-base", "scripts"]
paths = subprocess.check_output([
    "git", "ls-files", "-z", *folders, "tests/prepare_previews.py"
]).decode().split("\0")
actual = {p for p in paths if p}
expected = {str(p.relative_to(root)) for folder in folders
            for p in (root / folder).rglob("*") if p.is_file()}
expected.add("tests/prepare_previews.py")
assert actual == expected, "Compiled snapshot differs from current native inputs"
for name in sorted(actual):
    assert Path(name).read_bytes() == (root / name).read_bytes(), f"Stale native fixture: {name}"
print(f"Verified all {len(actual)} native inputs against the compiled source artifact")
