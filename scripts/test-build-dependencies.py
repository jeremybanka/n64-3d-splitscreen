#!/usr/bin/env python3
"""Exercise the real Make/Zig/ABI recipe with imports created after the first build."""

import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
install = Path(os.environ.get("N64_INST", root / ".build/libdragon")).resolve()
env = dict(os.environ, N64_INST=str(install))


def fingerprint(path):
    return hashlib.sha256(path.read_bytes()).hexdigest(), path.stat().st_mtime_ns


with tempfile.TemporaryDirectory(prefix="zig-dependency-test-") as directory:
    project = Path(directory)
    for name in ("Makefile", "scripts/verify-zig-abi.sh", "tools/patch_mips_abi.zig"):
        target = project / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(root / name, target)
    (project / ".build/tiny3d").mkdir(parents=True)
    (project / ".build/tiny3d/t3d.mk").write_text("# No renderer needed for object-only test\n")
    shutil.copytree(root / "src", project / "src")
    (project / "src/nested").mkdir(exist_ok=True)
    scene = project / "src/scene.zig"
    object_file = project / "build/scene.o"

    def build():
        subprocess.run(["make", "build/scene.o"], cwd=project, env=env, check=True)
        return fingerprint(object_file)

    scene.write_text("export fn dependency_value() u32 { return 7; }\n")
    initial = build()
    assert build() == initial, "A cache hit replaced the object"

    module = project / "src/nested/new.zig"
    module.write_text("pub const value: u32 = 11;\n")
    scene.write_text('export fn dependency_value() u32 { return @import("nested/new.zig").value; }\n')
    introduced = build()
    assert introduced[0] != initial[0], "Adding an imported module did not change the object"
    source_time = scene.stat().st_mtime_ns
    module.write_text("pub const value: u32 = 29;\n")
    edited = build()
    assert scene.stat().st_mtime_ns == source_time, "Regression fixture accidentally changed the root"
    assert edited[0] != introduced[0], "Editing the new module left a stale object"
    assert build() == edited, "Unchanged imported module replaced the object"

    data = project / "src/nested/value.bin"
    data.write_bytes(bytes([31]))
    module.write_text('pub const value: u32 = @embedFile("value.bin")[0];\n')
    embedded = build()
    data.write_bytes(bytes([47]))
    assert build()[0] != embedded[0], "Editing embedded data left a stale object"

    scene.write_text("export fn dependency_value() u32 { return 7; }\n")
    module.unlink()
    data.unlink()
    assert build()[0] == initial[0], "Removing an import kept a stale dependency or object"

print("Build dependencies: new/nested imports, embedded data, deletion and unchanged output verified")

# Also prove that checking Zig's cache does not spuriously rebuild the real
# adapter, link, or ROM packaging. This uses the current sample configuration.
subprocess.run(["make", "-j4", "all"], cwd=root, env=env, check=True)
outputs = [root / name for name in ("build/main.o", "build/scene.o",
                                    "build/n64-3d-splitscreen.elf", "n64-3d-splitscreen.z64")]
before = {path: fingerprint(path) for path in outputs}
subprocess.run(["make", "-j4", "all"], cwd=root, env=env, check=True)
assert before == {path: fingerprint(path) for path in outputs}, "No-op make rebuilt a project artifact"
print("No-op make: C/Zig objects, ELF and ROM contents and mtimes preserved")
