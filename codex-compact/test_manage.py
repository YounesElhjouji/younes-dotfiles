import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import manage
from normalize_lock import normalize, validate_lock


class CompactTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.state = self.root / "state"
        self.state.mkdir()

    def bundle(self, name):
        bundle = self.state / "versions" / name
        bundle.mkdir(parents=True)
        for binary in ("codex", "codex-expanded"):
            (bundle / binary).write_text(name + binary)
        manifest = {"version": name, "binaries": {
            binary: manage.digest(bundle / binary) for binary in ("codex", "codex-expanded")}}
        (bundle / "manifest.json").write_text(json.dumps(manifest))
        return bundle

    def fixture_source(self):
        source = self.root / "source"
        workspace = source / "codex-rs"
        target = workspace / "tui/src/render.rs"
        target.parent.mkdir(parents=True)
        target.write_text("fn display() { expanded(); }\n")
        (workspace / "Cargo.toml").write_text('[workspace.package]\nversion = "1.2.3"\n')
        (workspace / "Cargo.lock").write_text(
            'version = 4\n\n[[package]]\nname = "codex-tui"\nversion = "0.0.0"\n\n'
            '[[package]]\nname = "external"\nversion = "9.8.7"\n'
            'source = "registry+https://example.com/index"\nchecksum = "abc"\n')
        def git(*args):
            return subprocess.check_output(["git", *args], cwd=source, stderr=subprocess.PIPE)
        git("init", "-q")
        git("add", ".")
        git("-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-qm", "Fixture")
        git("tag", "rust-v1.2.3")
        target.write_text("fn display() { compact(); }\n")
        patch_file = self.root / "display.patch"
        patch_file.write_bytes(git("diff", "--binary"))
        git("restore", ".")
        return source, patch_file, target

    def test_failed_verification_preserves_current_and_previous(self):
        old, current, broken = (self.bundle(name) for name in ("old", "current", "broken"))
        manage.promote(self.state, old)
        manage.promote(self.state, current)
        (broken / "codex").write_text("truncated download")
        with self.assertRaisesRegex(ValueError, "checksum"):
            manage.promote(self.state, broken)
        self.assertEqual((self.state / "current").resolve(), current)
        self.assertEqual((self.state / "previous").resolve(), old)

    def test_rollback_swaps_complete_bundles(self):
        old, new = self.bundle("old"), self.bundle("new")
        manage.promote(self.state, old)
        manage.promote(self.state, new)
        manage.rollback(self.state)
        self.assertEqual((self.state / "current").resolve(), old)
        self.assertEqual((self.state / "previous").resolve(), new)
        manage.rollback(self.state)
        self.assertEqual((self.state / "current").resolve(), new)

    def test_modes_forward_every_argument_unchanged(self):
        bundle = self.bundle("current")
        manage.promote(self.state, bundle)
        arguments = ["resume", "--last", "-c", 'model="example"', "literal $x; `command`\n"]
        for mode, binary in [("compact", "codex"), ("expanded", "codex-expanded")]:
            with patch.dict(os.environ, {"CODEX_TOOL_DISPLAY": mode}), patch("os.execv") as execute:
                manage.run_codex(self.state, arguments)
            path = str(self.state / "current" / binary)
            execute.assert_called_once_with(path, [path, *arguments])

    def test_launcher_conflict_changes_neither_destination(self):
        home = self.root / "home"
        bindir = home / ".local/bin"
        bindir.mkdir(parents=True)
        unmanaged = bindir / "codex-compact"
        unmanaged.write_bytes(b"unrelated executable\x00")
        with patch.object(Path, "home", return_value=home):
            with self.assertRaisesRegex(ValueError, "unmanaged"):
                manage.install_launchers(self.state)
        self.assertFalse((bindir / "codex").exists())
        self.assertFalse((self.state / "recipe").exists())
        self.assertEqual(unmanaged.read_bytes(), b"unrelated executable\x00")

    def test_check_is_read_only_and_failed_build_can_retry(self):
        source, patch_file, target = self.fixture_source()
        release = {"tag_name": "rust-v1.2.3"}
        manage.checkout_source(self.state, release, patch_file, source, check_only=True)
        self.assertEqual(target.read_text(), "fn display() { expanded(); }\n")
        manage.checkout_source(self.state, release, patch_file, source)
        normalize(source / "codex-rs")
        manage.checkout_source(self.state, release, patch_file, source)
        self.assertEqual(target.read_text(), "fn display() { compact(); }\n")

    def test_unrelated_source_changes_are_not_overwritten(self):
        source, patch_file, target = self.fixture_source()
        target.write_text("fn display() { custom(); }\n")
        with self.assertRaisesRegex(ValueError, "reviewed TUI patch"):
            manage.checkout_source(self.state, {"tag_name": "rust-v1.2.3"}, patch_file, source)
        self.assertEqual(target.read_text(), "fn display() { custom(); }\n")

    def test_lock_repair_is_idempotent_and_rejects_dependency_changes(self):
        source, _, _ = self.fixture_source()
        workspace = source / "codex-rs"
        lock = workspace / "Cargo.lock"
        original = lock.read_text()
        normalize(workspace)
        self.assertEqual(lock.read_text(), original.replace('version = "0.0.0"', 'version = "1.2.3"'))
        normalized = lock.read_text()
        normalize(workspace)
        self.assertEqual(lock.read_text(), normalized)
        lock.write_text(normalized.replace('version = "9.8.7"', 'version = "9.8.8"'))
        with self.assertRaisesRegex(ValueError, "beyond the release"):
            validate_lock(workspace)

    def test_check_does_not_activate_cached_bundle(self):
        old = self.bundle("old")
        manage.promote(self.state, old)
        patch_file = self.root / "patches/0001-restore-command-grouping.patch"
        patch_file.parent.mkdir()
        patch_file.write_text("fixture patch")
        new = self.bundle("1.2.3-" + manage.digest(patch_file)[:12])
        args = type("Args", (), {"version": "1.2.3", "check": True})()
        with patch.object(manage, "RECIPE", self.root), patch.object(
                manage, "release_info", return_value={"tag_name": "rust-v1.2.3"}):
            manage.update(self.state, args)
        self.assertEqual((self.state / "current").resolve(), old)
        self.assertTrue(new.exists())


if __name__ == "__main__":
    unittest.main()
