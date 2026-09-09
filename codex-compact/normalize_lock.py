#!/usr/bin/env python3
"""Repair release-tag workspace versions without updating any dependency."""

from pathlib import Path
import re
import subprocess
import sys
import tomllib


def normalized_text(original, version):
    before = tomllib.loads(original)
    blocks = original.split("[[package]]")
    changes = 0
    for index in range(1, len(blocks)):
        package = tomllib.loads("[[package]]" + blocks[index])["package"][0]
        if "source" not in package and package["version"] != version:
            if package["version"] != "0.0.0":
                raise ValueError(f"Unexpected local package version: {package['name']}")
            blocks[index], count = re.subn(r'^version = "0\.0\.0"$',
                                          f'version = "{version}"', blocks[index],
                                          count=1, flags=re.MULTILINE)
            assert count == 1
            changes += 1
    result = "[[package]]".join(blocks)
    after = tomllib.loads(result)
    expected = {**before, "package": [
        {**package, "version": version} if "source" not in package else package
        for package in before["package"]]}
    if after != expected:
        raise ValueError("Lock repair would change more than workspace version metadata")
    return result, changes


def validate_lock(workspace):
    manifest = tomllib.loads((workspace / "Cargo.toml").read_text())
    version = manifest["workspace"]["package"]["version"]
    original = subprocess.check_output(
        ["git", "show", "HEAD:codex-rs/Cargo.lock"], cwd=workspace, text=True)
    result, changes = normalized_text(original, version)
    current = (workspace / "Cargo.lock").read_text()
    if current not in (original, result):
        raise ValueError("Cargo.lock contains edits beyond the release workspace version repair")
    return result, changes if current == original else 0


def normalize(workspace):
    result, changes = validate_lock(workspace)
    (workspace / "Cargo.lock").write_text(result)
    print(f"Workspace lock metadata: {changes} version entries normalized; external dependencies unchanged")


if __name__ == "__main__":
    normalize(Path(sys.argv[1]))
