#!/usr/bin/env python3
"""
Need for Speed: Underground 2 (v1.0 No-CD) — Thai Localization & Subtitle Enabler Patch
Target: SPEED2.EXE / speed2_en.exe (4,788,224 bytes, MD5: 95b4dc3e9a6c72b06a8bd62b0c56ea63)

Reverse-Engineered Architecture:
1. Re-routes default language mapping from English (0x00) to Thai (0x0b).
2. Maps "LANGUAGES\\JAPANESE.BIN" -> "LANGUAGES\\THAILAND.BIN" and "JAPANESE" -> "THAILAND"
   (enables automatic _thailand font suffix stripping).
3. Streams Thai font textures from LanguageTextures.bin:
   - 0x4815619d (CONDUITMDITC_TT21I_THAILAND)
   - 0xa73823ff (CONDUITMDITC_TT14I_THAILAND)
4. Patches sub_0050CEF0 to return AL=1 (unlocks story comic cutscenes PSA, Scene01..Scene20).
5. Patches sub_005535F0 to jump to movie subtitle loader (unlocks in-game movie subtitles).
"""

import argparse
import hashlib
import os
from pathlib import Path
import re
import struct
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

EXPECTED_EXE_SIZE = 4_788_224
UNPATCHED_EXE_MD5 = "95b4dc3e9a6c72b06a8bd62b0c56ea63"
PATCHED_EXE_MD5 = "7cbec03689721645a5456bc0292ef1bf"

EXE_PATCHES = [
    (
        0x10CEF0,
        b"\xe8\xcb\x37\x06\x00\x83\xf8\x05",
        b"\xb0\x01\xc3\x90\x90\x90\x90\x90",
        "VA 0x50cef0: Subtitles - Unconditionally enable subtitles (mov al, 1; ret)",
    ),
    (
        0x153703,
        b"\xe8\xb8\xcf\x01\x00\x83\xf8\x04\x74\x0a\xe8\xae\xcf\x01\x00\x83\xf8\x0c\x75\x0e",
        b"\xeb\x12" + b"\x90" * 18,
        "VA 0x553703: Subtitles - Movie subtitles bypass language check (jmp 0x553717)",
    ),
    (
        0x1B7677,
        b"\x75\x4b",
        b"\x75\x51",
        "VA 0x5b7677: Preserve default language ID when Registry 'Language' key is absent",
    ),
    (
        0x39A6E8,
        b"LANGUAGES\\JAPANESE.BIN",
        b"LANGUAGES\\THAILAND.BIN",
        'VA 0x79a6e8: Language bin path "LANGUAGES\\JAPANESE.BIN" -> "LANGUAGES\\THAILAND.BIN"',
    ),
    (
        0x39A700,
        b"JAPANESE",
        b"THAILAND",
        'VA 0x79a700: Language name "JAPANESE" -> "THAILAND" (strips _thailand font suffix)',
    ),
    (
        0x3F6F40,
        struct.pack("<I", 0x15192F5F),
        struct.pack("<I", 0x4815619D),
        "VA 0x7f6f40: Font texture stream slot 0 -> 0x4815619d (CONDUITMDITC_TT21I_THAILAND)",
    ),
    (
        0x3F6F48,
        struct.pack("<I", 0x743BF1C1),
        struct.pack("<I", 0xA73823FF),
        "VA 0x7f6f48: Font texture stream slot 2 -> 0xa73823ff (CONDUITMDITC_TT14I_THAILAND)",
    ),
    (
        0x3F70C0,
        struct.pack("<I", 0x0000000A),
        struct.pack("<I", 0x0000000B),
        "VA 0x7f70c0: Language descriptor slot 10 ID 0x0a -> 0x0b (Thai)",
    ),
    (
        0x3F7108,
        struct.pack("<I", 0x0000000A),
        struct.pack("<I", 0x0000000B),
        "VA 0x7f7108: Logo table slot 10 ID 0x0a -> 0x0b (logo_eng)",
    ),
    (
        0x3FCA00,
        struct.pack("<I", 0xFFFFFFFF),
        struct.pack("<I", 0x0000000B),
        "VA 0x7fca00: Default fallback language ID 0xffffffff -> 0x0b (Thai)",
    ),
]


def verify_or_patch_bytes(data: bytearray, patches: List[Tuple], expected_size: int, revert: bool = False) -> Tuple[bool, List[str]]:
    logs = []
    if len(data) != expected_size:
        raise ValueError(
            f"Invalid file size: {len(data):,} bytes (expected {expected_size:,} bytes)"
        )

    modified = False
    for offset, orig_bytes, new_bytes, desc in patches:
        src = new_bytes if revert else orig_bytes
        dst = orig_bytes if revert else new_bytes
        current = bytes(data[offset : offset + len(src)])
        if current == dst:
            logs.append(f"[SKIP] {desc} (already applied)")
        elif current == src:
            data[offset : offset + len(dst)] = dst
            modified = True
            logs.append(f"[OK]   {desc}")
        else:
            raise ValueError(
                f"Unexpected bytes at file offset 0x{offset:06x}: {current.hex()} "
                f"(expected {src.hex()} or {dst.hex()})"
            )
    return modified, logs


def patch_exe(input_path: Path, output_path: Path, revert: bool = False, verify_only: bool = False) -> bool:
    if not input_path.exists():
        print(f"ERROR: Input file not found: {input_path}", file=sys.stderr)
        return False

    raw = bytearray(input_path.read_bytes())
    if len(raw) != EXPECTED_EXE_SIZE:
        print(
            f"ERROR: Unexpected file size: {len(raw):,} bytes (expected {EXPECTED_EXE_SIZE:,} bytes). "
            f"Only the US v1.0 No-CD retail executable is supported.",
            file=sys.stderr,
        )
        return False

    before_md5 = hashlib.md5(raw).hexdigest()
    print(f"\nTarget : {input_path} ({len(raw):,} bytes, MD5: {before_md5})")

    try:
        modified, logs = verify_or_patch_bytes(raw, EXE_PATCHES, EXPECTED_EXE_SIZE, revert=revert)
        for line in logs:
            print(" ", line)
    except ValueError as e:
        print(f"ERROR: Patch verification failed: {e}", file=sys.stderr)
        return False

    if verify_only:
        all_patched = not modified and all("[SKIP]" in l for l in logs)
        print(f"Status : {'PATCHED (Thai & Subtitles Enabled)' if all_patched else 'UNPATCHED'}")
        return all_patched

    if modified:
        output_path.write_bytes(raw)
        after_md5 = hashlib.md5(raw).hexdigest()
        print(f"Output : {output_path} ({len(raw):,} bytes, MD5: {after_md5})")
        print(f"Status : {'Reverted' if revert else 'Patched'} successfully")
    else:
        print("Status : No changes required (all patches match requested state)")

    return True


def main():
    parser = argparse.ArgumentParser(description="Patch NFSU2 SPEED2.EXE for Thai language and subtitles support.")
    parser.add_argument("exe_files", nargs="*", type=normalize_path, help="Paths to SPEED2.EXE files")
    parser.add_argument("-i", "--input", type=normalize_path, help="Input executable path")
    parser.add_argument("-o", "--output", type=normalize_path, help="Output executable path (defaults to overwriting input)")
    parser.add_argument("--revert", action="store_true", help="Revert executable back to original US English state")
    parser.add_argument("--verify", action="store_true", help="Verify patch status without modifying file")

    args = parser.parse_args()

    targets = []
    if args.input:
        out = args.output if args.output else args.input
        targets.append((args.input, out))
    elif args.exe_files:
        for f in args.exe_files:
            targets.append((f, f))
    else:
        script_dir = Path(__file__).resolve().parent
        default_candidates = [
            script_dir / "ports" / "nfsu2" / "gamedata" / "SPEED2.EXE",
            script_dir / "nfsu2" / "gamedata" / "SPEED2.EXE",
            script_dir / "nfsu2_thai" / "SPEED2.EXE",
            script_dir / "nfsu2_thai" / "app" / "gamedata" / "SPEED2.EXE",
            script_dir / "nfsu2_thai_pack" / "SPEED2.EXE",
            script_dir / "SPEED2.EXE",
        ]
        found = [c for c in default_candidates if c.exists()]
        for f in found:
            targets.append((f, f))

    if not targets:
        print("ERROR: No SPEED2.EXE specified or found. Provide path as argument.", file=sys.stderr)
        return 1

    success = True
    for in_path, out_path in targets:
        if not patch_exe(in_path, out_path, revert=args.revert, verify_only=args.verify):
            success = False

    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
