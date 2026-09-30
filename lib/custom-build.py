#!/usr/bin/env python3
"""Build the pinned plugin against an existing, matching custom Hyprland tree."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

source, plugin, output = map(Path, sys.argv[1:4])
abi = sys.argv[4]
commit = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
version = (source / "src/version.h").read_text()
header_commit = re.search(r'#define GIT_COMMIT_HASH\s+"([a-f0-9]+)"', version).group(1)
if commit != abi.split("_", 1)[0] or header_commit != commit:
    sys.exit("Custom source and generated headers must match the running Hyprland commit")
with tempfile.TemporaryDirectory(prefix="custom-build-", dir=output.parent) as work:
    work = Path(work)
    headers = work / "include/hyprland"
    for path in (source / "src").rglob("*"):
        if path.is_file() and path.suffix in (".h", ".hpp", ".inc"):
            target = headers / path.relative_to(source)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
    (headers / "protocols").mkdir(parents=True)
    for path in (source / "protocols").glob("*.h*"):
        shutil.copy2(path, headers / "protocols" / path.name)
    pc = (source / "build/hyprland.pc").read_text()
    pc = "prefix=" + str(headers.parent) + "\n" + pc.split("\n", 1)[1]
    pkgconfig = work / "pkgconfig"
    pkgconfig.mkdir()
    (pkgconfig / "hyprland.pc").write_text(pc)
    build = work / "plugin"
    shutil.copytree(plugin, build, ignore=shutil.ignore_patterns(".git", "*.o", "*.so"))
    env = dict(os.environ, PKG_CONFIG_PATH=str(pkgconfig))
    subprocess.run(["make", "-j2"], cwd=build, env=env, check=True)
    # Replace the inode atomically: an existing plugin may still be mapped.
    os.replace(build / "hyprglass.so", output)
    abi_file = work / "hyprglass.abi"
    abi_file.write_text(abi + "\n")
    os.replace(abi_file, output.with_suffix(".abi"))
