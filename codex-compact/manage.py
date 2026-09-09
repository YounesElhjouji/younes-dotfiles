#!/usr/bin/env python3
"""Build and update a display-only Codex variant without replacing a working build."""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

from normalize_lock import validate_lock


RECIPE = Path(__file__).resolve().parent
DOTFILES = "https://github.com/YounesElhjouji/younes-dotfiles.git"
UPSTREAM = "https://github.com/openai/codex.git"


def state_dir():
    return Path(os.environ.get("CODEX_COMPACT_HOME", Path.home() / ".local/share/codex-compact"))


def command(*args, cwd=None, capture=False):
    return subprocess.run(args, cwd=cwd, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None).stdout


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def api(path):
    return json.loads(command("gh", "api", f"repos/openai/codex/{path}", capture=True))


def release_info(version):
    if version != "latest" and not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Version must be 'latest' or a stable version such as 0.153.4")
    path = "releases/latest" if version == "latest" else f"releases/tags/rust-v{version}"
    release = api(path)
    tag = release["tag_name"]
    if not re.fullmatch(r"rust-v\d+\.\d+\.\d+", tag) or release["prerelease"]:
        raise ValueError(f"Refusing non-stable release: {tag}")
    return release


def platform_target():
    machine = {"x86_64": "x86_64", "AMD64": "x86_64", "arm64": "aarch64",
               "aarch64": "aarch64"}.get(platform.machine())
    system = {"Linux": "unknown-linux-musl", "Darwin": "apple-darwin"}.get(platform.system())
    if not machine or not system:
        raise ValueError("Supported platforms: Linux and macOS, x86_64 and arm64")
    return f"{machine}-{system}"


def atomic_link(link, target):
    temporary = link.with_name(link.name + ".new")
    temporary.unlink(missing_ok=True)
    temporary.symlink_to(target)
    temporary.replace(link)


def verify_bundle(bundle):
    manifest = json.loads((bundle / "manifest.json").read_text())
    if set(manifest["binaries"]) != {"codex", "codex-expanded"}:
        raise ValueError("Incomplete binary manifest")
    for name, expected in manifest["binaries"].items():
        if digest(bundle / name) != expected:
            raise ValueError(f"Binary checksum mismatch: {bundle / name}")
    return manifest


def promote(state, bundle):
    verify_bundle(bundle)
    current = state / "current"
    if current.exists() and current.resolve() != bundle.resolve():
        atomic_link(state / "previous", current.resolve())
    atomic_link(current, bundle.resolve())


def rollback(state):
    previous = state / "previous"
    if not previous.exists():
        raise ValueError("There is no previous installed build; use 'mode expanded' for stock Codex")
    target = previous.resolve()
    promote(state, target)
    print(f"Rolled back to {target.name}")


def refresh_recipe(state, args):
    checkout = state / "maintenance"
    if not checkout.exists():
        command("git", "clone", "--depth", "1", DOTFILES, str(checkout))
    if command("git", "status", "--porcelain", cwd=checkout, capture=True).strip():
        raise ValueError(f"Maintenance checkout has local edits: {checkout}")
    command("git", "fetch", "--depth", "1", "origin", "main", cwd=checkout)
    command("git", "checkout", "--detach", "FETCH_HEAD", cwd=checkout)
    script = checkout / "codex-compact/manage.py"
    if not script.exists():
        raise ValueError("The remote dotfiles repository does not contain the compact recipe")
    os.execv(sys.executable, [sys.executable, str(script), *args, "--local-recipe"])


def download_official(release, destination):
    target = platform_target()
    name = f"codex-{target}.tar.gz"
    asset = next(asset for asset in release["assets"] if asset["name"] == name)
    expected = asset.get("digest", "")
    if not expected.startswith("sha256:"):
        raise ValueError(f"GitHub did not provide a SHA-256 digest for {name}")
    archive = destination.parent / name
    print(f"Downloading official {release['tag_name']} for expanded mode", flush=True)
    with urllib.request.urlopen(asset["browser_download_url"], timeout=60) as response:
        with archive.open("wb") as output:
            shutil.copyfileobj(response, output)
    if digest(archive) != expected.removeprefix("sha256:"):
        raise ValueError(f"Official release checksum mismatch: {name}")
    with tarfile.open(archive) as tar:
        matches = [item for item in tar if item.isfile() and
                   Path(item.name).name == f"codex-{target}"]
        if len(matches) != 1:
            raise ValueError("Unexpected official release archive layout")
        with tar.extractfile(matches[0]) as source, destination.open("wb") as output:
            shutil.copyfileobj(source, output)
    destination.chmod(0o755)
    archive.unlink()


def install_launchers(state):
    bindir = Path.home() / ".local/bin"
    marker = b"# Managed by codex-compact\n"
    launchers = [("codex", "run"), ("codex-compact", "")]
    # Validate every destination before changing any launcher or its recipe.
    for name, _ in launchers:
        destination = bindir / name
        if destination.is_symlink():
            raise ValueError(f"Refusing to overwrite a launcher symlink: {destination}")
        if destination.exists():
            with destination.open("rb") as stream:
                if marker not in stream.read(256):
                    raise ValueError(f"Refusing to overwrite an unmanaged launcher: {destination}")
    installed_recipe = state / "recipe"
    if RECIPE != installed_recipe.resolve():
        shutil.copytree(RECIPE, installed_recipe, dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns("__pycache__"))
    bindir.mkdir(parents=True, exist_ok=True)
    for name, action in launchers:
        destination = bindir / name
        script = ('#!/bin/sh\n' + marker.decode() +
                  'exec python3 "${CODEX_COMPACT_HOME:-$HOME/.local/share/codex-compact}'
                  '/recipe/manage.py" ' + action + ' "$@"\n')
        temporary = destination.with_name(destination.name + ".new")
        temporary.write_text(script)
        temporary.chmod(0o755)
        temporary.replace(destination)


def expected_diff(source, patch):
    # Reconstruct the patch against this release. Hunk offsets and blob hashes
    # can differ on newer releases even when the patch applies cleanly.
    with tempfile.TemporaryDirectory(prefix="codex-compact-index-") as temporary:
        environment = {**os.environ, "GIT_INDEX_FILE": str(Path(temporary) / "index")}
        for args in [("read-tree", "HEAD"), ("apply", "--cached", str(patch))]:
            subprocess.run(["git", *args], cwd=source, env=environment, check=True)
        return subprocess.check_output(
            ["git", "diff", "--cached", "--binary"], cwd=source, env=environment)


def checkout_source(state, release, patch, source_override, check_only=False):
    version = release["tag_name"].removeprefix("rust-v")
    identity = version + "-" + digest(patch)[:12]
    source = source_override or state / "sources" / identity
    if not source.exists():
        if source_override:
            raise ValueError(f"Developer checkout does not exist: {source}")
        source.parent.mkdir(parents=True, exist_ok=True)
        command("git", "clone", "--depth", "1", "--branch", release["tag_name"], UPSTREAM, str(source))
    actual = command("git", "describe", "--tags", "--exact-match", cwd=source, capture=True).strip()
    if actual != release["tag_name"]:
        raise ValueError(f"Source has tag {actual}, expected {release['tag_name']}")
    if command("git", "diff", "--cached", "--name-only", cwd=source, capture=True).strip():
        raise ValueError("Build checkout contains staged changes")
    if command("git", "ls-files", "--others", "--exclude-standard", cwd=source, capture=True).strip():
        raise ValueError("Build checkout contains untracked files; inspect them before building")
    changed = command("git", "diff", "--name-only", cwd=source, capture=True).splitlines()
    if any(not name.startswith("codex-rs/tui/") and name != "codex-rs/Cargo.lock" for name in changed):
        raise ValueError("Build source contains changes outside the TUI and workspace lock metadata")
    validate_lock(source / "codex-rs")
    diff = subprocess.check_output(["git", "diff", "--binary", "--", "codex-rs/tui"], cwd=source)
    if diff:
        # A failed build can be retried, but unrelated edits are never reset.
        if diff != expected_diff(source, patch):
            raise ValueError("Source does not match the reviewed TUI patch; inspect local edits")
    else:
        command("git", "apply", "--check", str(patch), cwd=source)
        if not check_only:
            command("git", "apply", str(patch), cwd=source)
    return source, identity


def update(state, args):
    patch = RECIPE / "patches/0001-restore-command-grouping.patch"
    release = release_info(args.version)
    version = release["tag_name"].removeprefix("rust-v")
    identity = version + "-" + digest(patch)[:12]
    bundle = state / "versions" / identity
    if (bundle / "manifest.json").exists():
        verify_bundle(bundle)
        if args.check:
            print(f"Already tested and built: {release['tag_name']}; installation unchanged")
            return
        install_launchers(state)
        promote(state, bundle)
        print(f"Ready: Codex {version}, compact command display")
        return
    if bundle.exists():
        raise ValueError(f"Incomplete build directory exists: {bundle}; inspect it before retrying")
    if shutil.disk_usage(state).free < 6 * 1024**3:
        raise ValueError("At least 6 GiB of free disk is required before starting a build")
    source, identity = checkout_source(state, release, patch, args.source, args.check)
    if args.check:
        print(f"Patch applies to {release['tag_name']}; no build or installation performed")
        return
    bundle.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=identity + "-", dir=bundle.parent) as temporary:
        staging = Path(temporary)
        command("bash", str(RECIPE / "build.sh"), str(source), str(staging))
        download_official(release, staging / "codex-expanded")
        expected_version = f"codex-cli {version}"
        for name in ("codex", "codex-expanded"):
            actual = command(str(staging / name), "--version", capture=True).strip()
            if actual != expected_version:
                raise ValueError(f"Version mismatch: {name}: {actual}")
        manifest = {"version": version, "upstream_tag": release["tag_name"],
                    "upstream_commit": command("git", "rev-parse", "HEAD", cwd=source, capture=True).strip(),
                    "patch_sha256": digest(patch), "official_target": platform_target(),
                    "build_host": platform.platform(), "cargo_lock_sha256": digest(staging / "Cargo.lock"),
                    "binaries": {name: digest(staging / name) for name in ("codex", "codex-expanded")}}
        (staging / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        shutil.copytree(staging, bundle)
    install_launchers(state)
    promote(state, bundle)
    print(f"Installed Codex {version} with compact command display. Restart Codex to use it.")


def run_codex(state, args):
    if args and args[0] == "update":
        os.execv(sys.executable, [sys.executable, str(RECIPE / "manage.py"), *args])
    mode_file = state / "mode"
    mode = os.environ.get("CODEX_TOOL_DISPLAY", mode_file.read_text().strip() if mode_file.exists() else "compact")
    if mode not in ("compact", "expanded"):
        raise ValueError("CODEX_TOOL_DISPLAY must be compact or expanded")
    name = "codex" if mode == "compact" else "codex-expanded"
    binary = state / "current" / name
    if not binary.exists():
        raise ValueError("No tested build installed. Run codex-compact update first")
    os.execv(str(binary), [str(binary), *args])


def main():
    state = state_dir()
    state.mkdir(parents=True, exist_ok=True)
    if len(sys.argv) > 1 and sys.argv[1] == "run":
        run_codex(state, sys.argv[2:])
        return
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    build = sub.add_parser("update", help="Refresh the recipe, then build, test and install an official release")
    build.add_argument("--version", default="latest")
    build.add_argument("--local-recipe", action="store_true", help="Use this local recipe without fetching dotfiles")
    build.add_argument("--source", type=Path, help="Use a matching, prepatched developer checkout")
    build.add_argument("--check", action="store_true", help="Check patch compatibility without building")
    sub.add_parser("status")
    sub.add_parser("rollback")
    mode = sub.add_parser("mode")
    mode.add_argument("value", choices=("compact", "expanded"))
    args = parser.parse_args()
    if args.action == "update" and not args.local_recipe:
        refresh_recipe(state, sys.argv[1:])
    if args.action == "status":
        manifest = verify_bundle((state / "current").resolve())
        print(json.dumps(manifest, indent=2))
        print("Mode:", (state / "mode").read_text().strip() if (state / "mode").exists() else "compact")
        return
    with (state / "update.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if args.action == "update":
            update(state, args)
        elif args.action == "rollback":
            rollback(state)
        elif args.action == "mode":
            (state / "mode").write_text(args.value + "\n")
            print(f"New Codex launches will use {args.value} tool display")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError, StopIteration) as error:
        print(f"codex-compact: {error}\nThe currently installed build was not replaced.", file=sys.stderr)
        sys.exit(1)
