#!/usr/bin/env python3
"""Offline regression tests; every fake SDK is confined to temporary storage."""

import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("sdk_identity", Path(__file__).with_name("sdk-identity.py"))
sdk = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sdk)


class IdentityTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="sdk-identity-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.install = self.root / "sdk"
        self.receipt = self.root / "project/identity.json"
        (self.install / "bin").mkdir(parents=True)
        (self.install / "include").mkdir()
        (self.install / "include/n64.mk").write_text("pinned SDK makefile\n")
        self.gcc = self.install / "bin/mips64-elf-gcc"
        self.write_compiler(sdk.GCC_VERSION)

    def write_compiler(self, version):
        self.gcc.write_text(f'#!/bin/sh\ncase "$1" in\n-dumpfullversion) echo {version};;\n'
                            f'-dumpmachine) echo {sdk.TARGET};;\nesac\n')
        self.gcc.chmod(0o755)

    def record(self):
        sdk.record(self.install, self.install / sdk.MANIFEST, "test fixture")

    def test_matching_sdk_and_relocation(self):
        self.record()
        sdk.verify(self.install, self.receipt)
        relocated = self.root / "relocated"
        self.install.rename(relocated)
        sdk.verify(relocated, self.receipt)

    def test_unidentified_sdk_rejected_without_mutation(self):
        before = sdk.fingerprints(self.install)
        with self.assertRaisesRegex(ValueError, "no identity receipt"):
            sdk.verify(self.install, self.receipt)
        self.assertEqual(before, sdk.fingerprints(self.install))
        self.assertFalse((self.install / sdk.MANIFEST).exists())

    def test_revision_mismatch(self):
        self.record()
        path = self.install / sdk.MANIFEST
        data = json.loads(path.read_text())
        data["libdragon_revision"] = "another-revision"
        path.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, "pinned revision"):
            sdk.verify(self.install, self.receipt)

    def test_shared_compiler_directory_is_fingerprinted(self):
        shared = self.root / "shared-bin"
        (self.install / "bin").rename(shared)
        (self.install / "bin").symlink_to(shared, target_is_directory=True)
        self.record()
        self.gcc.write_text(self.gcc.read_text() + "# replaced shared binary\n")
        with self.assertRaisesRegex(ValueError, "contents differ.*mips64-elf-gcc"):
            sdk.verify(self.install, self.receipt)

    def test_changed_compiler_version(self):
        self.record()
        self.write_compiler("0.0.0")
        with self.assertRaisesRegex(ValueError, "Expected GCC"):
            sdk.verify(self.install, self.receipt)

    def test_same_version_compiler_replacement(self):
        self.record()
        self.gcc.write_text(self.gcc.read_text() + "# different compiler binary\n")
        with self.assertRaisesRegex(ValueError, "contents differ.*mips64-elf-gcc"):
            sdk.verify(self.install, self.receipt)

    def test_changed_or_missing_sdk_file(self):
        for change in ("replace", "delete"):
            with self.subTest(change=change):
                path = self.install / "include/n64.mk"
                path.write_text("original")
                self.record()
                if change == "replace":
                    path.write_text("incompatible header")
                else:
                    path.unlink()
                with self.assertRaisesRegex(ValueError, "contents differ.*n64.mk"):
                    sdk.verify(self.install, self.receipt)

    def test_project_receipt_leaves_external_sdk_untouched(self):
        before = sdk.fingerprints(self.install)
        sdk.record(self.install, self.receipt, "verified external fixture")
        sdk.verify(self.install, self.receipt)
        self.assertEqual(before, sdk.fingerprints(self.install))
        self.assertFalse((self.install / sdk.MANIFEST).exists())

    def test_ci_compiler_origin_preserved(self):
        origin = "ghcr.io/dragonminded/libdragon@sha256:fixture"
        subprocess.run([sys.executable, str(Path(sdk.__file__)), "record-compiler",
                        "--install", str(self.install), "--origin", origin], check=True)
        stamp = json.loads((self.install / sdk.COMPILER_MANIFEST).read_text())
        self.assertEqual(stamp["origin"], origin)
        self.assertEqual(stamp["compiler"], sdk.compiler(self.install))
        self.record()
        sdk.verify(self.install, self.receipt)

    def test_ci_compiler_receipt_detects_replacement(self):
        sdk.write_json(self.install / sdk.COMPILER_MANIFEST,
                       {"compiler": sdk.compiler(self.install), "origin": "pinned image fixture",
                        "files": sdk.fingerprints(self.install)})
        self.gcc.write_text(self.gcc.read_text() + "# replaced binary with same version\n")
        with self.assertRaisesRegex(ValueError, "Compiler file changed"):
            sdk.compiler(self.install)

    def test_bootstrap_unknown_external_sdk_reports_recovery(self):
        project = self.root / "project"
        scripts = project / "scripts"
        scripts.mkdir(parents=True)
        import os
        import shutil
        for name in ("bootstrap-libdragon.sh", "sdk-identity.py"):
            shutil.copy(Path(__file__).with_name(name), scripts / name)
        env = dict(os.environ, N64_INST=str(self.install))
        before = sdk.fingerprints(self.install)
        result = subprocess.run(["bash", str(scripts / "bootstrap-libdragon.sh")],
                                env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--verify-source", result.stderr)
        self.assertIn("new empty N64_INST", result.stderr)
        self.assertEqual(before, sdk.fingerprints(self.install))
        self.assertFalse((project / ".build/libdragon-src").exists())


if __name__ == "__main__":
    unittest.main()
