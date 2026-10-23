#!/usr/bin/env python3
"""Bind a Guides app package to the exact source and edition used to build it."""
from __future__ import annotations

import hashlib
import json
import pathlib
import plistlib
import subprocess
from datetime import datetime, timezone
from typing import Optional, Tuple


EDITION = {
    "baseline": ("Guides Replica", "uk.pipreps.guides.replica", "0.1.0-alpha.1", ["-DBASELINE", "-DGUIDES_REPLICA"]),
    "baseline-enhanced": ("Guides Enhanced", "uk.pipreps.guides.baseline.enhanced", "0.1.0-alpha.2", ["-DBASELINE", "-DGUIDES_ENHANCEMENTS"]),
    "pip": ("Pip Guides", "uk.pipreps.guides", "0.1.0-alpha.1", []),
    "pip-enhanced": ("Pip Guides Enhanced", "uk.pipreps.guides.enhanced", "0.1.0-alpha.2", ["-DGUIDES_ENHANCEMENTS"]),
}
RESOURCE_MANIFEST = "PipGuidesBuildManifest.json"
RESOURCE_RECEIPT = "PipGuidesBuildReceipt.json"
DISTRIBUTION_CONFIG = "distribution.json"


class IntegrityError(ValueError):
    pass


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _canonical(payload: object) -> bytes:
    return (json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode("utf-8")


def input_files(root: pathlib.Path) -> list[pathlib.Path]:
    fixed = [
        pathlib.Path("Package.swift"),
        pathlib.Path("scripts/build-app.sh"),
        pathlib.Path("scripts/release-info.py"),
        pathlib.Path("scripts/release_integrity.py"),
    ]
    dynamic: list[pathlib.Path] = []
    distribution = root / DISTRIBUTION_CONFIG
    if distribution.exists() or distribution.is_symlink():
        fixed.append(pathlib.Path(DISTRIBUTION_CONFIG))
    for directory in (pathlib.Path("Sources"), pathlib.Path("Tests")):
        base = root / directory
        if base.exists():
            dynamic.extend(path.relative_to(root) for path in base.rglob("*") if path.is_file())
    files = sorted(set(fixed + dynamic), key=lambda path: path.as_posix())
    for relative in files:
        path = root / relative
        if not path.is_file() or path.is_symlink():
            raise IntegrityError(f"Build input is missing or is a symlink: {relative}")
        for parent in relative.parents:
            if parent == pathlib.Path("."):
                break
            if (root / parent).is_symlink():
                raise IntegrityError(f"Build input has a symlinked parent: {relative}")
    return files


def distribution_policy(root: pathlib.Path) -> tuple[str, list[str]]:
    path = root / DISTRIBUTION_CONFIG
    if path.is_symlink():
        raise IntegrityError("Distribution config must be a regular file")
    if not path.exists():
        return "pip", list(EDITION)
    try:
        config = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise IntegrityError("Distribution config is invalid JSON") from error
    if not isinstance(config, dict) or set(config) != {"default_edition", "editions"}:
        raise IntegrityError("Distribution config must contain only default_edition and editions")
    default = config.get("default_edition")
    editions = config.get("editions")
    if (not isinstance(editions, list) or not editions or
            any(not isinstance(item, str) or item not in EDITION for item in editions) or
            len(editions) != len(set(editions)) or
            not isinstance(default, str) or default not in editions):
        raise IntegrityError("Distribution config must select unique supported editions and include its default")
    return default, editions


def select_edition(root: pathlib.Path, requested: Optional[str] = None) -> str:
    default, editions = distribution_policy(root)
    edition = default if requested is None else requested
    if edition not in editions:
        raise IntegrityError(f"Edition is not enabled by this distribution: {edition}")
    return edition


def source_manifest(root: pathlib.Path) -> dict:
    files = []
    for relative in input_files(root):
        data = (root / relative).read_bytes()
        files.append({"path": relative.as_posix(), "size": len(data), "sha256": _sha256(data)})
    return {"schema": 1, "files": files}


def manifest_digest(manifest: dict) -> str:
    return _sha256(_canonical(manifest))


def write_manifest(root: pathlib.Path, destination: pathlib.Path) -> str:
    manifest = source_manifest(root)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(_canonical(manifest))
    return manifest_digest(manifest)


def _load_json(path: pathlib.Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise IntegrityError(f"Could not read package receipt: {path}") from error
    if not isinstance(value, dict):
        raise IntegrityError(f"Package receipt is not an object: {path}")
    return value


def source_revision(root: pathlib.Path) -> Tuple[str, Optional[bool]]:
    try:
        revision = subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, check=True, capture_output=True, text=True).stdout.strip()
        dirty_output = subprocess.run(["git", "status", "--porcelain"], cwd=root, check=True, capture_output=True, text=True).stdout
        return revision, bool(dirty_output.strip())
    except (FileNotFoundError, subprocess.CalledProcessError):
        # Source archives do not carry Git metadata. The manifest digest remains
        # the identity for their exact build inputs.
        return "unversioned", None


def make_receipt(root: pathlib.Path, app: pathlib.Path, edition: str, manifest: dict, manifest_hash: str, compiler_flags: list[str]) -> dict:
    select_edition(root, edition)
    try:
        name, bundle_id, version, flags = EDITION[edition]
    except KeyError as error:
        raise IntegrityError(f"Unknown edition: {edition}") from error
    executable = app / "Contents/MacOS/PipGuides"
    if not executable.is_file():
        raise IntegrityError("Staged executable is missing")
    if compiler_flags != flags:
        raise IntegrityError(f"Compiler flags do not match edition: {edition}")
    revision, source_dirty = source_revision(root)
    swift_version = subprocess.run(["swift", "--version"], check=True, capture_output=True, text=True).stdout.strip().splitlines()[0]
    return {
        "schema": 1,
        "edition": edition,
        "bundle_name": name,
        "bundle_id": bundle_id,
        "version": version,
        "compiler_flags": compiler_flags,
        "source_revision": revision,
        "source_dirty": source_dirty,
        "source_manifest_sha256": manifest_hash,
        "swift_version": swift_version,
        "built_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }


def verify_package(root: pathlib.Path, app: pathlib.Path, edition: str) -> dict:
    select_edition(root, edition)
    try:
        name, bundle_id, version, flags = EDITION[edition]
    except KeyError as error:
        raise IntegrityError(f"Unknown edition: {edition}") from error
    resources = app / "Contents/Resources"
    manifest_path = resources / RESOURCE_MANIFEST
    receipt_path = resources / RESOURCE_RECEIPT
    manifest = _load_json(manifest_path)
    receipt = _load_json(receipt_path)
    manifest_hash = manifest_digest(manifest)
    current = source_manifest(root)
    current_hash = manifest_digest(current)
    if manifest_hash != current_hash or manifest != current:
        raise IntegrityError(f"Package source inputs are stale for {edition}")
    executable = app / "Contents/MacOS/PipGuides"
    try:
        with (app / "Contents/Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
    except (OSError, plistlib.InvalidFileException) as error:
        raise IntegrityError(f"Package Info.plist is invalid for {edition}") from error
    expected = {
        "schema": 1,
        "edition": edition,
        "bundle_name": name,
        "bundle_id": bundle_id,
        "version": version,
        "compiler_flags": flags,
        "source_manifest_sha256": current_hash,
    }
    if not executable.is_file():
        raise IntegrityError(f"Package executable is missing: {edition}")
    if any(receipt.get(key) != value for key, value in expected.items()):
        raise IntegrityError(f"Build receipt does not match package/source: {edition}")
    if (info.get("CFBundleIdentifier"), info.get("CFBundleShortVersionString"), info.get("CFBundleName")) != (bundle_id, version, name):
        raise IntegrityError(f"Package identity/version does not match edition: {edition}")
    return receipt


def cli() -> int:
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    manifest_parser = subparsers.add_parser("manifest")
    manifest_parser.add_argument("root", type=pathlib.Path)
    manifest_parser.add_argument("destination", type=pathlib.Path)
    select_parser = subparsers.add_parser("select-edition")
    select_parser.add_argument("root", type=pathlib.Path)
    select_parser.add_argument("requested", nargs="?")
    list_parser = subparsers.add_parser("list-editions")
    list_parser.add_argument("root", type=pathlib.Path)
    receipt_parser = subparsers.add_parser("receipt")
    receipt_parser.add_argument("root", type=pathlib.Path)
    receipt_parser.add_argument("app", type=pathlib.Path)
    receipt_parser.add_argument("edition", choices=sorted(EDITION))
    receipt_parser.add_argument("manifest", type=pathlib.Path)
    receipt_parser.add_argument("manifest_sha256")
    receipt_parser.add_argument("--compiler-flags-json", default="[]")
    verify_parser = subparsers.add_parser("verify")
    verify_parser.add_argument("root", type=pathlib.Path)
    verify_parser.add_argument("app", type=pathlib.Path)
    verify_parser.add_argument("edition", choices=sorted(EDITION))
    args = parser.parse_args()
    try:
        if args.command == "manifest":
            print(write_manifest(args.root.resolve(), args.destination.resolve()))
        elif args.command == "select-edition":
            print(select_edition(args.root.resolve(), args.requested))
        elif args.command == "list-editions":
            print(" ".join(distribution_policy(args.root.resolve())[1]))
        elif args.command == "receipt":
            manifest = _load_json(args.manifest)
            digest = manifest_digest(manifest)
            if digest != args.manifest_sha256 or manifest != source_manifest(args.root.resolve()):
                raise IntegrityError("Source changed during build; refusing to package")
            compiler_flags = json.loads(args.compiler_flags_json)
            if not isinstance(compiler_flags, list) or any(not isinstance(flag, str) for flag in compiler_flags):
                raise IntegrityError("Compiler flags must be a JSON array of strings")
            destination = args.app / "Contents/Resources" / RESOURCE_MANIFEST
            destination.write_bytes(_canonical(manifest))
            receipt = make_receipt(args.root.resolve(), args.app.resolve(), args.edition, manifest, digest, compiler_flags)
            (args.app / "Contents/Resources" / RESOURCE_RECEIPT).write_bytes(_canonical(receipt))
            print(digest)
        elif args.command == "verify":
            receipt = verify_package(args.root.resolve(), args.app.resolve(), args.edition)
            print(json.dumps(receipt, sort_keys=True))
    except (IntegrityError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"release integrity check failed: {error}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(cli())
