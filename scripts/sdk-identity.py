#!/usr/bin/env python3
"""Verify installed SDK provenance without trusting a directory's existence."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile

REVISION = "494f1f586d3d6d5fc65b516a8ce29ccf42f85e15"
GCC_VERSION = "16.2.0"
TARGET = "mips64-elf"
MANIFEST = ".n64-template-sdk.json"
COMPILER_MANIFEST = ".n64-template-compiler.json"


def command(*args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip()


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def compiler(install):
    gcc = install / "bin/mips64-elf-gcc"
    identity = {
        "version": command(str(gcc), "-dumpfullversion"),
        "target": command(str(gcc), "-dumpmachine"),
    }
    if identity != {"version": GCC_VERSION, "target": TARGET}:
        raise ValueError(f"Expected GCC {GCC_VERSION} for {TARGET}; found {identity}")
    provenance = install / COMPILER_MANIFEST
    if provenance.is_file():
        recorded = json.loads(provenance.read_text())
        if recorded.get("compiler") != identity or not isinstance(recorded.get("files"), dict):
            raise ValueError("Compiler receipt is invalid")
        for name, expected in recorded["files"].items():
            if digest(install / name) != expected:
                raise ValueError(f"Compiler file changed since bootstrap: {name}")
    return identity


def fingerprints(install):
    # Follow externally shared bin/include directories as well as ordinary SDK
    # trees; record their contents, not just the symlink's existence.
    result = {}

    def visit(directory, ancestors):
        resolved = directory.resolve()
        if resolved in ancestors:
            raise ValueError(f"SDK contains a directory symlink cycle: {directory}")
        for path in sorted(directory.iterdir()):
            if path.is_dir():
                visit(path, ancestors | {resolved})
            elif path.name not in (MANIFEST, COMPILER_MANIFEST):
                result[str(path.relative_to(install))] = digest(path)

    visit(install, set())
    return result


def source_revision(source):
    if command("git", "-C", str(source), "rev-parse", "HEAD") != REVISION:
        raise ValueError(f"Source must be checked out at pinned revision {REVISION}")
    if command("git", "-C", str(source), "status", "--porcelain", "--untracked-files=no"):
        raise ValueError("Source contains tracked changes; use a clean pinned checkout")


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def record(install, receipt, origin):
    if not (install / "include/n64.mk").is_file():
        raise ValueError("The SDK is incomplete (missing include/n64.mk)")
    write_json(receipt, {
        "format": 1,
        "libdragon_revision": REVISION,
        "compiler": compiler(install),
        "origin": origin,
        "files": fingerprints(install),
    })


def verify(install, receipt):
    installed_receipt = install / MANIFEST
    path = installed_receipt if installed_receipt.is_file() else receipt
    if not path.is_file():
        raise ValueError("SDK has no identity receipt")
    expected = json.loads(path.read_text())
    if not isinstance(expected, dict) or expected.get("format") != 1 or expected.get("libdragon_revision") != REVISION:
        raise ValueError(f"SDK receipt does not identify pinned revision {REVISION}")
    if expected.get("compiler") != compiler(install):
        raise ValueError("SDK compiler identity changed")
    actual = fingerprints(install)
    recorded = expected.get("files", {})
    if not isinstance(recorded, dict):
        raise ValueError("SDK receipt has invalid file fingerprints")
    if actual != recorded:
        changed = sorted(key for key in actual.keys() | recorded.keys()
                         if actual.get(key) != recorded.get(key))
        raise ValueError("SDK contents differ from the receipt: " + ", ".join(changed[:8]))
    print(f"Verified libdragon {REVISION[:12]}, GCC {GCC_VERSION} at {install}")


def compare_source_files(source, install):
    pairs = [(source / "n64.mk", install / "include/n64.mk")]
    for pattern in ("*.h", "*.inc", "ucode.S"):
        pairs.extend((path, install / TARGET / "include" / path.name)
                     for path in (source / "include").glob(pattern))
    pairs.extend((source / "src" / path, install / TARGET / "include" / path)
                 for path in ("libcart/cart.h", "fatfs/diskio.h", "fatfs/ff.h", "fatfs/ffconf.h"))
    pairs.extend((source / name, install / TARGET / "lib" / name)
                 for name in ("n64.ld", "rsp.ld", "dso.ld"))
    for original, installed in pairs:
        if digest(original) != digest(installed):
            raise ValueError(f"Installed SDK file does not match pinned source: {installed}")


def verify_source(install, source, receipt):
    """Rebuild pinned runtime archives in isolation; never install or alter the SDK."""
    source_revision(source)
    compiler(install)
    compare_source_files(source, install)
    receipt.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="sdk-verify-", dir=receipt.parent) as directory:
        scratch = Path(directory)
        archive = scratch / "source.tar"
        with archive.open("wb") as output:
            subprocess.run(["git", "-C", str(source), "archive", REVISION], stdout=output, check=True)
        reference = scratch / "source"
        reference.mkdir()
        # git archive contains only the explicitly selected local pinned tree.
        with tarfile.open(archive) as files:
            files.extractall(reference, filter="data")
        env = dict(os.environ, N64_INST=str(install))
        subprocess.run(["make", "-C", str(reference), "-j" + os.environ.get("JOBS", "4"),
                        "libdragon"], env=env, check=True)
        for name in ("libdragon.a", "libdragonsys.a"):
            # GNU ar embeds timestamps by default. Normalize them in temporary
            # copies; compare all object bytes including debug information.
            for kind, original in (("reference", reference / name),
                                   ("installed", install / TARGET / "lib" / name)):
                subprocess.run([str(install / "bin/mips64-elf-objcopy"),
                                "--enable-deterministic-archives", str(original),
                                str(scratch / f"{kind}.a")], check=True)
            if digest(scratch / "reference.a") != digest(scratch / "installed.a"):
                raise ValueError(f"{name} differs from a rebuild of pinned source")
    record(install, receipt, "Existing SDK: headers/linker scripts and rebuilt runtime archives verified; "
           "compiler version/target checked; installed tools and compiler binaries fingerprinted")
    print(f"Verified existing SDK without modifying it; wrote project receipt {receipt}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("revision", "gcc-version", "compiler", "record-compiler",
                                           "verify", "record", "verify-source"))
    parser.add_argument("--install", type=Path)
    parser.add_argument("--receipt", type=Path)
    parser.add_argument("--source", type=Path)
    parser.add_argument("--origin", default="Built from pinned libdragon source")
    args = parser.parse_args()
    if args.action in ("revision", "gcc-version"):
        print(REVISION if args.action == "revision" else GCC_VERSION)
        return
    if args.install is None:
        parser.error("--install is required")
    install = args.install.resolve()
    if args.action == "compiler":
        compiler(install)
    elif args.action == "record-compiler":
        write_json(install / COMPILER_MANIFEST,
                   {"compiler": compiler(install), "origin": args.origin,
                    "files": fingerprints(install)})
    elif args.action == "verify":
        if args.receipt is None:
            parser.error("--receipt is required")
        verify(install, args.receipt)
    elif args.action == "record":
        if args.source is None:
            parser.error("--source is required")
        source_revision(args.source)
        provenance = install / COMPILER_MANIFEST
        origin = args.origin
        if provenance.is_file():
            origin += "; compiler: " + json.loads(provenance.read_text())["origin"]
        record(install, install / MANIFEST, origin)
    else:
        if args.source is None or args.receipt is None:
            parser.error("--source and --receipt are required")
        verify_source(install, args.source.resolve(), args.receipt.resolve())


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"SDK verification failed: {error}", file=sys.stderr)
        sys.exit(1)
