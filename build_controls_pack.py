#!/usr/bin/env python3
"""
Build playOS & PortMaster package (nfsu2_controls.zip) from tools/nfsu2_controls.
Supports both Windows and Linux / WSL environments.
"""

import argparse
import os
from pathlib import Path
import re
import shutil
import sys
import zipfile

SCRIPT_DIR = Path(__file__).resolve().parent


def normalize_path(p) -> Path:
    s = str(p).strip()
    if os.name == "nt":
        m = re.match(r"^/mnt/([a-zA-Z])(?:/(.*))?$", s.replace("\\", "/"))
        if m:
            drive = m.group(1).upper()
            rest = (m.group(2) or "").replace("/", "\\")
            return Path(f"{drive}:\\{rest}")
    else:
        m = re.match(r"^([a-zA-Z]):[\\/](.*)$", s)
        if m:
            drive = m.group(1).lower()
            rest = m.group(2).replace("\\", "/")
            return Path(f"/mnt/{drive}/{rest}")
    return Path(s)


def build_controls_package(output_zip: Path = None):
    dist_dir = SCRIPT_DIR / "dist"
    dist_dir.mkdir(parents=True, exist_ok=True)
    if not output_zip:
        output_zip = dist_dir / "nfsu2_controls.zip"
    else:
        output_zip = normalize_path(output_zip)

    src_tools = SCRIPT_DIR / "tools" / "nfsu2_controls"
    if not src_tools.exists():
        print(f"[ERROR] Source directory not found: {src_tools}", file=sys.stderr)
        return False

    print("==================================================================")
    print("  Building NFSU2 Controls Package (nfsu2_controls.zip)")
    print(f"  Source : {src_tools}")
    print(f"  Target : {output_zip}")
    print("==================================================================")

    stage_dir = dist_dir / "_stage_controls"
    if stage_dir.exists():
        shutil.rmtree(stage_dir)
    stage_dir.mkdir(parents=True, exist_ok=True)

    print("\n[1/3] Staging package layout...")
    stage_pkg = stage_dir / "nfsu2_controls"
    shutil.copytree(src_tools, stage_pkg)

    # Clean zip structure: README.txt at root of zip
    readme = src_tools / "README.txt"
    if readme.exists():
        shutil.copy2(readme, stage_dir / "README.txt")

    pkg_readme = stage_pkg / "README.txt"
    if pkg_readme.exists():
        pkg_readme.unlink()

    print(f"\n[2/3] Compressing into {output_zip.name}...")
    if output_zip.exists():
        output_zip.unlink()

    with zipfile.ZipFile(output_zip, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zipf:
        for root, dirs, files in os.walk(stage_dir):
            for file in files:
                full_path = Path(root) / file
                rel_path = full_path.relative_to(stage_dir)
                zipf.write(full_path, arcname=str(rel_path).replace("\\", "/"))

    print("\n[3/3] Cleaning up staging directory...")
    shutil.rmtree(stage_dir, ignore_errors=True)

    size_kb = output_zip.stat().st_size / 1024
    print("\n[SUCCESS] Package generated successfully:")
    print(f"  Path : {output_zip}")
    print(f"  Size : {size_kb:.2f} KB")
    return True


def main():
    parser = argparse.ArgumentParser(description="Build NFSU2 Controls Package.")
    parser.add_argument("-o", "--output", type=normalize_path, help="Custom output zip path")
    args = parser.parse_args()

    success = build_controls_package(args.output)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
