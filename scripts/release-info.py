#!/usr/bin/env python3
"""Write local release checksums only for packages built from current inputs."""
import hashlib
import json
import pathlib
import subprocess
import sys

from release_integrity import EDITION, IntegrityError, RESOURCE_RECEIPT, distribution_policy, signature_metadata, verify_package


root = pathlib.Path(__file__).resolve().parents[1]
entries = []
try:
    for edition in distribution_policy(root)[1]:
        name, bundle_id, version, flags = EDITION[edition]
        app = root / "dist" / (name + ".app")
        executable = app / "Contents" / "MacOS" / "PipGuides"
        if not executable.is_file():
            raise IntegrityError(f"Build all enabled editions before generating release information (missing {edition}).")
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
        receipt = verify_package(root, app, edition)
        signing = signature_metadata(app)
        expected_signature = {"adhoc": "ad-hoc", "apple-development": "Apple Development"}[receipt["signing_mode"]]
        if signing["type"] != expected_signature:
            raise IntegrityError(f"Package signature does not match its build receipt: {edition}")
        receipt_path = app / "Contents" / "Resources" / RESOURCE_RECEIPT
        entries.append({
            "edition": edition,
            "release_identity": edition + "-v" + version,
            "name": name,
            "bundle_id": bundle_id,
            "version": version,
            "platform": "macOS14+",
            "architecture": subprocess.check_output(["lipo", "-archs", str(executable)], text=True).strip(),
            "compiler_flags": flags,
            "source_revision": receipt["source_revision"],
            "source_dirty": receipt["source_dirty"],
            "source_manifest_sha256": receipt["source_manifest_sha256"],
            "build_receipt_sha256": hashlib.sha256(receipt_path.read_bytes()).hexdigest(),
            "executable_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
            "signature": signing,
            "acceptance": "See PUBLIC-VERIFICATION.md for actual workflows and gaps.",
        })
except (IntegrityError, OSError, subprocess.CalledProcessError) as error:
    raise SystemExit(f"Could not generate current-source release information: {error}") from error

out = root / "dist" / "release-info.json"
out.write_text(json.dumps({"apps": entries}, indent=2) + "\n")
print(out)
