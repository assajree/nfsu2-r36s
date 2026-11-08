#!/usr/bin/env python3
"""
Need for Speed: Underground 2 — Thailand.bin Patcher
Target: LANGUAGES/Thailand.bin (264,184 bytes)

Features:
- Fixes crash during profile creation (PC_NAME_ENTRY) on handheld virtual keyboards
  (PortMaster vkbd / ASCII-only keyboard overlays).
- Replaces non-ASCII Thai default profile name 'ผู้เล่น' with 'PLAYER'.
- Replaces Thai name entry prompt and title labels with ASCII equivalents.
- Preserves exact byte offsets and total file size (264,184 bytes).
- Supports verification (--verify) and revert (--revert).
"""

import argparse
import hashlib
import os
from pathlib import Path
import re
import sys
from typing import List, Tuple, Union


def normalize_path(p: Union[str, Path]) -> Path:
    """Resolve both Windows (D:\\...) and Linux/WSL (/mnt/d/...) paths across OSes."""
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

THAILAND_BIN_PATCHES = [
    (
        0x3A8AF,
        b"\xad\xa3\x86\x87\x8b\x83\x81\x00",
        b"PLAYER\x00\x00",
        "Hash 0xd9dc2f12: Default profile name 'PLAYER' (prevents PC_NAME_ENTRY / vkbd crash)",
    ),
    (
        0x243AA,
        b"\x88\x84\x85\x88\xa4\x9e\x83\x85:\x00",
        b"Name:\x00\x00\x00\x00\x00",
        "Hash 0x22729437: Name entry prompt label 'Name:'",
    ),
    (
        0x24228,
        b"\xa4\x9e\x83\x85\x00",
        b"NAME\x00",
        "Hash 0x818f0385: Name entry header label 'NAME'",
    ),
    (
        0x24158,
        b"\x92\x84\x86\x82\x89\xa4\x9e\x83\x85\xad\xa3\x86\xa2\xa4\x86\x00",
        b"Create Name\x00\x00\x00\x00\x00",
        "Hash 0x3de4eff0: Name entry title 'Create Name'",
    ),
]


def patch_thailand_bin(file_path: Path, revert: bool = False, verify_only: bool = False) -> bool:
    if not file_path.exists():
        print(f"ERROR: File not found: {file_path}", file=sys.stderr)
        return False

    raw = bytearray(file_path.read_bytes())
    if len(raw) != 264184:
        print(f"ERROR: Unexpected file size ({len(raw):,} bytes, expected 264,184 bytes): {file_path}", file=sys.stderr)
        return False

    before_md5 = hashlib.md5(raw).hexdigest()
    print(f"\nTarget: {file_path} (264,184 bytes, MD5: {before_md5})")

    modified = False
    all_patched = True

    for offset, orig_bytes, new_bytes, desc in THAILAND_BIN_PATCHES:
        src = new_bytes if revert else orig_bytes
        dst = orig_bytes if revert else new_bytes
        curr = bytes(raw[offset : offset + len(src)])

        if curr == dst:
            print(f"  [SKIP] {desc} (already applied)")
        elif curr == src:
            all_patched = False
            if not verify_only:
                raw[offset : offset + len(dst)] = dst
                modified = True
                print(f"  [OK]   {desc}")
            else:
                print(f"  [UNPATCHED] {desc}")
        else:
            print(f"  [WARN] Unexpected bytes at offset 0x{offset:06x}: {curr.hex()}")
            all_patched = False

    if verify_only:
        print(f"Status: {'PATCHED (ASCII Name Entry Safe)' if all_patched else 'UNPATCHED'}")
        return all_patched

    if modified:
        file_path.write_bytes(raw)
        after_md5 = hashlib.md5(raw).hexdigest()
        print(f"Status: {'Reverted' if revert else 'Patched'} successfully -> MD5: {after_md5}")
    else:
        print("Status: No changes required (all patches match requested state)")

    return True


def main():
    parser = argparse.ArgumentParser(description="Patch NFSU2 Thailand.bin to resolve virtual keyboard name entry crash.")
    parser.add_argument("files", nargs="*", type=normalize_path, help="Paths to Thailand.bin files")
    parser.add_argument("--revert", action="store_true", help="Revert file back to original unpatched Thai text")
    parser.add_argument("--verify", action="store_true", help="Verify patch status without modifying file")

    args = parser.parse_args()

    targets = args.files
    if not targets:
        script_dir = Path(__file__).resolve().parent
        default_candidates = [
            script_dir / "ports" / "nfsu2" / "gamedata" / "LANGUAGES" / "Thailand.bin",
            script_dir / "nfsu2" / "gamedata" / "LANGUAGES" / "Thailand.bin",
            script_dir / "nfsu2_thai" / "LANGUAGES" / "Thailand.bin",
            script_dir / "nfsu2_thai" / "app" / "gamedata" / "LANGUAGES" / "Thailand.bin",
            script_dir / "nfsu2_thai_pack" / "LANGUAGES" / "Thailand.bin",
            script_dir / "Thailand.bin",
        ]
        targets = [c for c in default_candidates if c.exists()]

    if not targets:
        print("ERROR: No Thailand.bin specified or found. Provide path as argument.", file=sys.stderr)
        return 1

    success = True
    for target in targets:
        if not patch_thailand_bin(target, revert=args.revert, verify_only=args.verify):
            success = False

    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
