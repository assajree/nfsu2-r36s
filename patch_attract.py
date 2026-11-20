#!/usr/bin/env python3
"""
Need for Speed: Underground 2 (Recompiled) — Title Screen Attract Mode Patcher
Targets: nfsu2.aarch64 / nfsu2.aarch64.v10 / nfsu2.aarch64.v12 (Linux ARM64 ELF Binaries)

Root Cause:
  In sub_004C53B0 (SplashScreen / Title Screen NotificationMessage), after 30.0s of
  idle time on FE_TICK (0xc98356ba), the game switches to "UG_LS_IntroFMV.fng"
  (FMVOpening.vp6). When Fast Boot hides/renames FMVOpening.vp6, the game immediately
  fails/finishes playback and reloads the Title Screen, restarting "Riders on the Storm".

Fix:
  Converts the conditional branch `b.ne +0x164` (`0x54000b21`) at the end of the
  30.0s Attract Mode timeout check in sub_004C53B0 into an unconditional branch
  `b +0x164` (`0x14000059`), skipping the switch to UG_LS_IntroFMV.fng while
  preserving all other SplashScreen tick logic (e.g. PRESS_START prompt).
"""

import argparse
import hashlib
import os
from pathlib import Path
import re
import struct
import sys
from typing import List, Optional, Tuple, Union


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


# Pattern around the 30.0s Attract Mode timeout branch in sub_004C53B0:
#   +0x00: a51c0853  lsr w5, w5, #8
#   +0x04: bf000a6a  tst w21, #0x41000000 / ands ...
#   +0x08: 210b0054  b.ne +0x164   <-- target instruction to patch (0x54000b21 -> 0x14000059)
#   ...
#   +0x28: 904e9d52  movz w16, #0xea74  ("UG_LS_IntroFMV.fng" = 0x0078ea74)
#   +0x2c: 1000fa072 movk w16, #0x78, lsl #16
PREFIX_SIG = bytes.fromhex("a51c0853bf000a6a")
SUFFIX_SIG = bytes.fromhex(
    "0a200051c31000110102c0d20430005100400051234863b87402409194a20091904e9d52100fa07230482ab8"
)

ORIG_INSN = struct.pack("<I", 0x54000B21)  # b.ne +0x164
PATCH_INSN = struct.pack("<I", 0x14000059)  # b    +0x164


def find_branch_offset(data: bytes) -> Tuple[str, int]:
    """Locate the unique Attract Mode b.ne instruction offset and its state."""
    orig_pat = PREFIX_SIG + ORIG_INSN + SUFFIX_SIG
    patch_pat = PREFIX_SIG + PATCH_INSN + SUFFIX_SIG

    orig_hits = []
    idx = 0
    while True:
        idx = data.find(orig_pat, idx)
        if idx == -1:
            break
        orig_hits.append(idx + len(PREFIX_SIG))
        idx += 1

    patch_hits = []
    idx = 0
    while True:
        idx = data.find(patch_pat, idx)
        if idx == -1:
            break
        patch_hits.append(idx + len(PREFIX_SIG))
        idx += 1

    if len(orig_hits) == 1 and not patch_hits:
        return "ORIGINAL", orig_hits[0]
    if len(patch_hits) == 1 and not orig_hits:
        return "PATCHED", patch_hits[0]
    if not orig_hits and not patch_hits:
        return "NOT_FOUND", -1
    return "AMBIGUOUS", -1


def process_file(path: Path, verify: bool = False, revert: bool = False) -> int:
    """Verify, patch, or revert a single nfsu2.aarch64 binary."""
    if not path.is_file():
        print(f"[SKIP] Not found: {path}")
        return 0

    data = bytearray(path.read_bytes())
    state, off = find_branch_offset(data)
    md5_before = hashlib.md5(data).hexdigest()

    if state in ("NOT_FOUND", "AMBIGUOUS"):
        print(f"[ERROR] {path.name}: Could not uniquely locate SplashScreen Attract Mode branch ({state}).")
        return 1

    print(f"[INFO] {path.name}: state={state}, offset=0x{off:x}, md5={md5_before}")

    if verify:
        expected = "PATCHED" if not revert else "ORIGINAL"
        if state == expected:
            print(f"[OK] {path.name}: Verified ({state}).")
            return 0
        print(f"[FAIL] {path.name}: Expected {expected}, found {state}.")
        return 1

    if revert:
        if state == "ORIGINAL":
            print(f"[OK] {path.name}: Already unpatched.")
            return 0
        data[off : off + 4] = ORIG_INSN
        path.write_bytes(data)
        md5_after = hashlib.md5(data).hexdigest()
        print(f"[REVERTED] {path.name}: 0x{off:x} -> b.ne +0x164 (md5={md5_after})")
        return 0

    if state == "PATCHED":
        print(f"[OK] {path.name}: Already patched.")
        return 0

    data[off : off + 4] = PATCH_INSN
    path.write_bytes(data)
    md5_after = hashlib.md5(data).hexdigest()
    print(f"[PATCHED] {path.name}: 0x{off:x} -> b +0x164 (md5={md5_after})")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Patch NFSU2 Title Screen Attract Mode timeout.")
    parser.add_argument("targets", nargs="*", help="Target nfsu2.aarch64 binary path(s)")
    parser.add_argument("--all", action="store_true", help="Target all ports/nfsu2/nfsu2.aarch64* binaries")
    parser.add_argument("--verify", action="store_true", help="Verify patch state without modifying files")
    parser.add_argument("--revert", action="store_true", help="Revert patch back to original")
    args = parser.parse_args()

    paths: List[Path] = []
    if args.all or not args.targets:
        base = Path(__file__).resolve().parent / "ports" / "nfsu2"
        for name in ("nfsu2.aarch64", "nfsu2.aarch64.v10", "nfsu2.aarch64.v12"):
            p = base / name
            if p.exists():
                paths.append(p)
    else:
        paths = [normalize_path(t) for t in args.targets]

    if not paths:
        print("[ERROR] No target binaries found.")
        return 1

    rc = 0
    for p in paths:
        rc |= process_file(p, verify=args.verify, revert=args.revert)
    return rc


if __name__ == "__main__":
    sys.exit(main())
