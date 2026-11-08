#!/usr/bin/env python3
"""
Need for Speed: Underground 2 (Recompiled) — ARM64 Subtitle Patcher
Targets: nfsu2.aarch64 / nfsu2.aarch64.v10 (Linux ARM64 ELF Binaries)

Features:
- Dynamic ELF Symbol Resolver (.symtab) to find sub_0050CEF0 and sub_005535F0.
- Unlocks story comic cutscene subtitles (PSA Brooke Burke, Scene01..Scene20)
  by setting Guest Context AL = 1 and adjusting Guest ESP += 4.
- Dynamically resolves movie subtitle conditional branch in sub_005535F0
  (cmp w?, #0xc -> b.eq target) and converts to unconditional branch (b target).
- Supports verification (--verify) and revert (--revert).
"""

import argparse
import hashlib
import os
from pathlib import Path
import re
import struct
import sys
from typing import Dict, List, Optional, Tuple, Union


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

# ARM64 Subtitle Unlock Payload for sub_0050CEF0:
# mrs  x1, tpidr_el0
# ldrb w0, [x1, #0x28]   ; Guest AL
# orr  w0, w0, #1        ; AL = 1 (Subtitles enabled)
# strb w0, [x1, #0x28]
# ldr  w0, [x1, #0x38]   ; Guest ESP
# add  w0, w0, #4        ; ESP += 4 (Pop guest return address)
# str  w0, [x1, #0x38]
# ret
ARM64_SUB_CODE = bytes([
    0x41, 0xd0, 0x3b, 0xd5,
    0x20, 0xa0, 0x40, 0x39,
    0x00, 0x00, 0x00, 0x32,
    0x20, 0xa0, 0x00, 0x39,
    0x20, 0x38, 0x40, 0xb9,
    0x00, 0x10, 0x00, 0x11,
    0x20, 0x38, 0x00, 0xb9,
    0xc0, 0x03, 0x5f, 0xd6,
])

# Original ARM64 function prologue of sub_0050CEF0 in v1.1.0 release:
# sub sp, sp, #0x20; stp x29, x30, [sp, #0x10]; add x29, sp, #0x10; stp x19, x20, [sp]; mrs x19, tpidr_el0
ARM64_SUB_ORIG = bytes([
    0xff, 0x83, 0x00, 0xd1,
    0xfd, 0x7b, 0x01, 0xa9,
    0xfd, 0x43, 0x00, 0x91,
    0xf3, 0x53, 0x00, 0xa9,
    0x53, 0xd0, 0x3b, 0xd5,
    0x60, 0x3a, 0x40, 0xb9,
    0x00, 0x00, 0x80, 0x52,
    0xe0, 0x0b, 0x00, 0x54,
])


class Arm64ElfResolver:
    """Parses 64-bit ELF binary to resolve symbols and function offsets dynamically."""

    def __init__(self, data: bytearray):
        self.data = data
        self.is_valid_elf = len(data) >= 64 and data[:4] == b"\x7fELF" and data[4] == 2
        self.symbols: Dict[str, Tuple[int, int]] = {}
        if self.is_valid_elf:
            self._parse_elf()

    def _parse_elf(self):
        try:
            e_shoff = struct.unpack("<Q", self.data[40:48])[0]
            e_shentsize = struct.unpack("<H", self.data[58:60])[0]
            e_shnum = struct.unpack("<H", self.data[60:62])[0]
            e_shstrndx = struct.unpack("<H", self.data[62:64])[0]

            sections = []
            for i in range(e_shnum):
                off = e_shoff + i * e_shentsize
                hdr = struct.unpack("<IIQQQQIIQQ", self.data[off : off + 64])
                sections.append({
                    "name_idx": hdr[0],
                    "type": hdr[1],
                    "addr": hdr[3],
                    "offset": hdr[4],
                    "size": hdr[5],
                    "link": hdr[6],
                    "entsize": hdr[9],
                })

            shstrtab_hdr = sections[e_shstrndx]
            shstrtab = self.data[shstrtab_hdr["offset"] : shstrtab_hdr["offset"] + shstrtab_hdr["size"]]

            symtab_hdr = None
            strtab_hdr = None
            for s in sections:
                name_end = shstrtab.find(b"\x00", s["name_idx"])
                s_name = shstrtab[s["name_idx"] : name_end].decode("ascii", errors="ignore")
                if s["type"] == 2 and s_name == ".symtab":
                    symtab_hdr = s
                    strtab_hdr = sections[s["link"]]
                    break

            if symtab_hdr and strtab_hdr:
                sym_data = self.data[symtab_hdr["offset"] : symtab_hdr["offset"] + symtab_hdr["size"]]
                str_data = self.data[strtab_hdr["offset"] : strtab_hdr["offset"] + strtab_hdr["size"]]
                entry_sz = symtab_hdr["entsize"] or 24

                for i in range(0, len(sym_data), entry_sz):
                    entry = sym_data[i : i + entry_sz]
                    st_name, st_info, _, _, st_value, st_size = struct.unpack("<IBBHQQ", entry[:24])
                    if st_name != 0:
                        n_end = str_data.find(b"\x00", st_name)
                        sym_name = str_data[st_name:n_end].decode("ascii", errors="ignore")
                        self.symbols[sym_name] = (st_value, st_size)
        except Exception:
            pass

    def va_to_file_offset(self, va: int) -> Optional[int]:
        if 0x400000 <= va < len(self.data) + 0x400000:
            return va - 0x400000
        return None

    def find_sub_0050cef0(self) -> Optional[int]:
        if "sub_0050CEF0" in self.symbols:
            va, _ = self.symbols["sub_0050CEF0"]
            return self.va_to_file_offset(va)
        pos = self.data.find(ARM64_SUB_CODE)
        if pos != -1:
            return pos
        pos = self.data.find(ARM64_SUB_ORIG)
        if pos != -1:
            return pos
        if len(self.data) == 87_349_296 and (
            self.data[0x1FD660 : 0x1FD660 + 32] == ARM64_SUB_CODE or
            self.data[0x1FD660 : 0x1FD660 + 32] == ARM64_SUB_ORIG
        ):
            return 0x1FD660
        return None

    def find_movie_branch(self) -> Optional[Tuple[int, int, bool]]:
        func_off = None
        func_sz = 2048
        if "sub_005535F0" in self.symbols:
            va, sz = self.symbols["sub_005535F0"]
            func_off = self.va_to_file_offset(va)
            func_sz = sz or 2048
        elif len(self.data) == 87_349_296:
            func_off = 0x3B62970

        if func_off is None or func_off + func_sz > len(self.data):
            return None

        func_bytes = self.data[func_off : func_off + func_sz]
        for i in range(0, len(func_bytes) - 20, 4):
            inst = struct.unpack("<I", func_bytes[i : i + 4])[0]
            if (inst & 0xffe0fc1f) == 0x7100301f:
                for j in range(1, 5):
                    b_off = func_off + i + j * 4
                    b_inst = struct.unpack("<I", self.data[b_off : b_off + 4])[0]
                    if (b_inst & 0xff00001f) == 0x54000000:
                        imm19 = (b_inst >> 5) & 0x7FFFF
                        target_delta = (imm19 if imm19 < 0x40000 else imm19 - 0x80000) * 4
                        return (b_off, b_off + target_delta, False)
                    elif (b_inst & 0xfc000000) == 0x14000000:
                        imm26 = b_inst & 0x03FFFFFF
                        target_delta = (imm26 if imm26 < 0x02000000 else imm26 - 0x04000000) * 4
                        return (b_off, b_off + target_delta, True)
        return None


def patch_arm64_binary(path: Path, revert: bool = False, verify_only: bool = False) -> bool:
    if not path.exists():
        print(f"ERROR: Binary not found: {path}", file=sys.stderr)
        return False

    raw = bytearray(path.read_bytes())
    before_md5 = hashlib.md5(raw).hexdigest()
    print(f"\nTarget: {path} ({len(raw):,} bytes, MD5: {before_md5})")

    resolver = Arm64ElfResolver(raw)
    if not resolver.is_valid_elf:
        print(f"  [ERROR] {path} is not a valid 64-bit ELF binary", file=sys.stderr)
        return False

    sub_offset = resolver.find_sub_0050cef0()
    movie_info = resolver.find_movie_branch()

    if sub_offset is None:
        print("  [ERROR] Unable to resolve sub_0050CEF0 dynamically or via signature", file=sys.stderr)
        return False
    if movie_info is None:
        print("  [ERROR] Unable to resolve movie subtitle branch in sub_005535F0", file=sys.stderr)
        return False

    branch_off, target_off, is_movie_patched = movie_info
    print(f"  [Dynamic Resolver] sub_0050CEF0 @ File 0x{sub_offset:06x}")
    print(f"  [Dynamic Resolver] Movie Branch  @ File 0x{branch_off:06x} -> Target 0x{target_off:06x}")

    is_sub_patched = raw[sub_offset : sub_offset + len(ARM64_SUB_CODE)] == ARM64_SUB_CODE

    if verify_only:
        all_patched = is_sub_patched and is_movie_patched
        print(f"Status: {'PATCHED (Subtitles Enabled)' if all_patched else 'UNPATCHED'}")
        return all_patched

    modified = False

    # 1. Patch sub_0050CEF0
    if revert:
        if is_sub_patched:
            raw[sub_offset : sub_offset + len(ARM64_SUB_ORIG)] = ARM64_SUB_ORIG
            modified = True
            print("  [OK]   Reverted sub_0050CEF0 to original prologue")
        else:
            print("  [SKIP] sub_0050CEF0 is already in original state")
    else:
        if is_sub_patched:
            print("  [SKIP] sub_0050CEF0 (already unlocked)")
        else:
            raw[sub_offset : sub_offset + len(ARM64_SUB_CODE)] = ARM64_SUB_CODE
            modified = True
            print("  [OK]   Unlocked sub_0050CEF0 (guest AL=1, ESP+=4)")

    # 2. Patch Movie Subtitle Branch
    target_delta_inst = (target_off - branch_off) // 4
    imm19 = target_delta_inst & 0x7FFFF
    orig_b_eq = struct.pack("<I", 0x54000000 | (imm19 << 5))
    imm26 = target_delta_inst & 0x03FFFFFF
    new_b = struct.pack("<I", 0x14000000 | imm26)

    if revert:
        if is_movie_patched:
            raw[branch_off : branch_off + 4] = orig_b_eq
            modified = True
            print(f"  [OK]   Reverted movie branch to b.eq 0x{target_off:06x}")
        else:
            print("  [SKIP] movie branch is already conditional")
    else:
        if is_movie_patched:
            print("  [SKIP] movie branch (already unconditional)")
        else:
            raw[branch_off : branch_off + 4] = new_b
            modified = True
            print(f"  [OK]   Unlocked movie subtitles (b 0x{target_off:06x})")

    if modified:
        path.write_bytes(raw)
        after_md5 = hashlib.md5(raw).hexdigest()
        print(f"Status: {'Reverted' if revert else 'Patched'} successfully -> MD5: {after_md5}")
    else:
        print("Status: No changes required (all patches match requested state)")

    return True


def main():
    parser = argparse.ArgumentParser(description="Patch NFSU2 ARM64 binary to unlock Thai / Universal subtitles.")
    parser.add_argument("binaries", nargs="*", type=normalize_path, help="Paths to ARM64 binaries (e.g. nfsu2.aarch64 nfsu2.aarch64.v10)")
    parser.add_argument("--revert", action="store_true", help="Revert binary back to original unpatched state")
    parser.add_argument("--verify", action="store_true", help="Verify patch status without modifying binary")

    args = parser.parse_args()

    targets = args.binaries
    if not targets:
        script_dir = Path(__file__).resolve().parent
        default_candidates = [
            script_dir / "ports" / "nfsu2" / "nfsu2.aarch64",
            script_dir / "ports" / "nfsu2" / "nfsu2.aarch64.v10",
            script_dir / "nfsu2" / "nfsu2.aarch64",
            script_dir / "nfsu2" / "nfsu2.aarch64.v10",
            script_dir / "nfsu2.aarch64",
            script_dir / "nfsu2.aarch64.v10",
        ]
        targets = [c for c in default_candidates if c.exists()]

    if not targets:
        print("ERROR: No ARM64 binary specified or found. Provide path as argument.", file=sys.stderr)
        return 1

    success = True
    for target in targets:
        if not patch_arm64_binary(target, revert=args.revert, verify_only=args.verify):
            success = False

    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
