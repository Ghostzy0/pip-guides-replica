#!/usr/bin/env python3
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from release_integrity import (  # noqa: E402
    EDITION,
    IntegrityError,
    RESOURCE_MANIFEST,
    RESOURCE_RECEIPT,
    manifest_digest,
    source_revision,
    source_manifest,
    distribution_policy,
    select_edition,
    verify_package,
)


class ReleaseIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)
        (self.root / "Sources").mkdir()
        (self.root / "Tests").mkdir()
        (self.root / "scripts").mkdir()
        for relative in (
            "Package.swift",
            "scripts/build-app.sh",
            "scripts/release-info.py",
            "scripts/release_integrity.py",
            "Sources/Guide.swift",
            "Tests/GuideTests.swift",
        ):
            (self.root / relative).write_text("fixture " + relative)
        self.app = self.root / "dist/Pip Guides.app"
        resources = self.app / "Contents/Resources"
        resources.mkdir(parents=True)
        self.executable = self.app / "Contents/MacOS/PipGuides"
        self.executable.parent.mkdir(parents=True)
        self.executable.write_bytes(b"fixture executable")
        name, bundle_id, version, flags = EDITION["pip"]
        with (self.app / "Contents/Info.plist").open("wb") as stream:
            import plistlib
            plistlib.dump({
                "CFBundleName": name,
                "CFBundleIdentifier": bundle_id,
                "CFBundleShortVersionString": version,
            }, stream)
        self.manifest = source_manifest(self.root)
        self.digest = manifest_digest(self.manifest)
        (resources / RESOURCE_MANIFEST).write_text(json.dumps(self.manifest, sort_keys=True, separators=(",", ":")) + "\n")
        (resources / RESOURCE_RECEIPT).write_text(json.dumps({
            "schema": 1,
            "edition": "pip",
            "bundle_name": name,
            "bundle_id": bundle_id,
            "version": version,
            "compiler_flags": flags,
            "source_revision": "fixture-revision",
            "source_dirty": False,
            "source_manifest_sha256": self.digest,
            "swift_version": "fixture swift",
            "built_at_utc": "2026-10-23T00:00:00+00:00",
        }))

    def tearDown(self):
        self.temp.cleanup()

    def test_manifest_is_stable_and_sorted(self):
        first = source_manifest(self.root)
        second = source_manifest(self.root)
        self.assertEqual(first, second)
        paths = [item["path"] for item in first["files"]]
        self.assertEqual(paths, sorted(paths))

    def test_missing_distribution_config_keeps_internal_default_and_matrix(self):
        default, editions = distribution_policy(self.root)
        self.assertEqual(default, "pip")
        self.assertEqual(editions, list(EDITION))
        self.assertEqual(select_edition(self.root), "pip")

    def test_distribution_config_controls_default_manifest_and_allowed_editions(self):
        path = self.root / "distribution.json"
        path.write_text(json.dumps({"default_edition": "baseline", "editions": ["baseline"]}))
        self.assertEqual(select_edition(self.root), "baseline")
        self.assertEqual(select_edition(self.root, "baseline"), "baseline")
        self.assertEqual(distribution_policy(self.root), ("baseline", ["baseline"]))
        self.assertIn("distribution.json", [item["path"] for item in source_manifest(self.root)["files"]])
        with self.assertRaisesRegex(IntegrityError, "not enabled"):
            select_edition(self.root, "pip")

    def test_invalid_distribution_policy_is_rejected(self):
        path = self.root / "distribution.json"
        for payload in (
            {"default_edition": "pip", "editions": ["baseline"]},
            {"default_edition": "pip", "editions": ["pip", "pip"]},
            {"default_edition": "unknown", "editions": ["pip"]},
            {"default_edition": "pip", "editions": ["pip"], "extra": True},
        ):
            path.write_text(json.dumps(payload))
            with self.subTest(payload=payload), self.assertRaises(IntegrityError):
                distribution_policy(self.root)

    def test_select_edition_cli_rejects_disabled_explicit_edition(self):
        (self.root / "distribution.json").write_text(json.dumps({"default_edition": "baseline", "editions": ["baseline"]}))
        script = pathlib.Path(__file__).with_name("release_integrity.py")
        accepted = subprocess.run(
            [sys.executable, str(script), "select-edition", str(self.root)],
            check=True, capture_output=True, text=True,
        )
        self.assertEqual(accepted.stdout.strip(), "baseline")
        rejected = subprocess.run(
            [sys.executable, str(script), "select-edition", str(self.root), "pip"],
            capture_output=True, text=True,
        )
        self.assertNotEqual(rejected.returncode, 0)
        self.assertIn("not enabled", rejected.stderr)

    def test_build_app_rejects_disabled_explicit_edition_before_building(self):
        (self.root / "distribution.json").write_text(json.dumps({"default_edition": "baseline", "editions": ["baseline"]}))
        scripts = self.root / "scripts"
        real_scripts = pathlib.Path(__file__).resolve().parent
        shutil.copy2(real_scripts / "build-app.sh", scripts / "build-app.sh")
        shutil.copy2(real_scripts / "release_integrity.py", scripts / "release_integrity.py")
        result = subprocess.run(["/bin/bash", str(scripts / "build-app.sh"), "pip"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("not enabled", result.stderr)
        self.assertFalse((self.root / ".build").exists())

    def test_current_receipt_and_executable_are_accepted(self):
        result = verify_package(self.root, self.app, "pip")
        self.assertEqual(result["source_manifest_sha256"], self.digest)

    def test_same_bundle_identity_with_stale_source_is_rejected(self):
        (self.root / "Sources/Guide.swift").write_text("changed code, same bundle identity")
        with self.assertRaisesRegex(IntegrityError, "source inputs are stale"):
            verify_package(self.root, self.app, "pip")

    def test_wrong_edition_flags_are_rejected(self):
        receipt_path = self.app / "Contents/Resources" / RESOURCE_RECEIPT
        receipt = json.loads(receipt_path.read_text())
        receipt["compiler_flags"] = ["-DBASELINE"]
        receipt_path.write_text(json.dumps(receipt))
        with self.assertRaisesRegex(IntegrityError, "does not match package/source"):
            verify_package(self.root, self.app, "pip")

    def test_missing_executable_is_rejected(self):
        self.executable.unlink()
        with self.assertRaisesRegex(IntegrityError, "executable is missing"):
            verify_package(self.root, self.app, "pip")

    def test_unversioned_source_uses_manifest_identity(self):
        revision, dirty = source_revision(self.root)
        self.assertEqual((revision, dirty), ("unversioned", None))

    def test_receipt_cli_accepts_json_flags_and_stamps_current_inputs(self):
        fake_bin = self.root / "fake-bin"
        fake_bin.mkdir()
        fake_git = fake_bin / "git"
        fake_git.write_text('#!/bin/sh\nif [ "$1 $2" = "rev-parse HEAD" ]; then echo fixture-revision; elif [ "$1 $2" = "status --porcelain" ]; then echo " M /private/path/that/must/not/be-recorded"; else exit 0; fi\n')
        fake_swift = fake_bin / "swift"
        fake_swift.write_text('#!/bin/sh\necho "Swift version fixture"\n')
        fake_git.chmod(0o755)
        fake_swift.chmod(0o755)
        manifest_path = self.root / "inputs.json"
        script = pathlib.Path(__file__).with_name("release_integrity.py")
        env = dict(os.environ, PATH=str(fake_bin) + os.pathsep + os.environ.get("PATH", ""))
        manifest_run = subprocess.run(
            [sys.executable, str(script), "manifest", str(self.root), str(manifest_path)],
            env=env, check=True, capture_output=True, text=True,
        )
        subprocess.run(
            [sys.executable, str(script), "receipt", str(self.root), str(self.app), "pip", str(manifest_path), manifest_run.stdout.strip(), "--compiler-flags-json", "[]"],
            env=env, check=True, capture_output=True, text=True,
        )
        receipt = json.loads((self.app / "Contents/Resources" / RESOURCE_RECEIPT).read_text())
        self.assertEqual(receipt["source_revision"], "fixture-revision")
        self.assertTrue(receipt["source_dirty"])
        self.assertNotIn("/private/path", json.dumps(receipt))
        self.assertEqual(receipt["compiler_flags"], [])
        subprocess.run(
            [sys.executable, str(script), "verify", str(self.root), str(self.app), "pip"],
            env=env, check=True, capture_output=True, text=True,
        )


if __name__ == "__main__":
    unittest.main()
