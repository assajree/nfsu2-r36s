#!/usr/bin/env python3
"""
Need for Speed: Underground 2 (Recompiled) — ARM64 Cutscene Video Performance Patcher
Targets: nfsu2.aarch64 / nfsu2.aarch64.v10 / nfsu2.aarch64.v12 (Linux ARM64 ELF Binaries)

Fixes cutscene/FMV video stuttering on R36H / R36S (RK3326) via 5 targeted binary patches:
1. Async MovieTexture Lock (rt::textureLockAsync):
   - Bypasses the (!fresh && !(flags & D3DLOCK_DISCARD)) rejection so full-surface dynamic
     textures (MovieTexture 1024x512 A8R8G8B8) lock asynchronously without stalling the game
     thread on 2x syncCall round-trips per frame.
2. Render-Thread OpTexUpload Discard Flag (rt::exec):
   - Passes D3DLOCK_DISCARD (0x2000) to tex->LockRect inside OpTexUpload so the GLES backend
     never triggers glReadPixels (readBack) on frame 2+.
3. Persistent Upload Buffer for Dynamic Surfaces (IDirect3DSurface9GLES::UnlockRect):
   - Retains m_upload (2 MB) across frames when m_keepShadow is set instead of calling
     std::vector<uint8_t>().swap(m_upload) every frame (eliminates mmap/munmap syscalls,
     512 minor page faults, cross-core TLB shootdowns, and 2 MB zero-init per frame).
4. Hardware ARM64 NEON BGRA->RGBA Swizzle (d3d9_gles::convertRowToRGBA8):
   - Replaces the 11-instruction/pixel scalar byte loop for D3DFMT_A8R8G8B8 with a 16-pixel
     vectorized ARM64 NEON ld4/st4 loop (~20x fewer instructions per frame).
5. Native ARM64 NEON YUV420->ARGB8888 & Scalar 32-bit VP6 Codec:
   - Replaces the 236-instruction V128 union-emulated MMX YUV420->ARGB8888 scanline converter
     (sub_006FFAA7 in v10 / sub_006FFD4A in v12) with a 43-instruction native ARM64 NEON
     routine using sqadd + sqxtun (~16x fewer instructions per frame).
   - Configures VP6 CPU feature detection (sub_0070CCE8 in v10 / sub_0070CF98 in v12) to
     select native 32-bit scalar C routines instead of V128 stack-union emulated MMX/SSE2.

Supports verification (--verify) and full restoration (--revert).
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


def pack_u32_list(words: List[int]) -> bytes:
    return struct.pack(f"<{len(words)}I", *words)


# ---------------------------------------------------------------------------
# Patch 1: rt::textureLockAsync (_ZN2rt16textureLockAsyncEjPKjPjS2_ + 0x3E0)
# VA 0x49b860: tbz w25, #13, 0x49b61c -> nop
# ---------------------------------------------------------------------------
PATCH1_SYM = "_ZN2rt16textureLockAsyncEjPKjPjS2_"
PATCH1_OFFSET_IN_FUNC = 0x3E0
PATCH1_FALLBACK_VA = 0x49B860
PATCH1_ORIG = pack_u32_list([0x366FEDF9])
PATCH1_NEW = pack_u32_list([0xD503201F])

# ---------------------------------------------------------------------------
# Patch 2: rt::exec OpTexUpload LockRect flags (_ZN2rt4execERKNS_3CmdE + 0x4D0 & + 0x58C)
# VA 0x4a3640 & 0x4a36fc: mov w4, #0 -> mov w4, #0x2000 (D3DLOCK_DISCARD)
# ---------------------------------------------------------------------------
PATCH2_SYM = "_ZN2rt4execERKNS_3CmdE"
PATCH2A_OFFSET_IN_FUNC = 0x4D0
PATCH2B_OFFSET_IN_FUNC = 0x58C
PATCH2A_FALLBACK_VA = 0x4A3640
PATCH2B_FALLBACK_VA = 0x4A36FC
PATCH2_ORIG = pack_u32_list([0x52800004])
PATCH2_NEW = pack_u32_list([0x52840004])

# ---------------------------------------------------------------------------
# Patch 3: IDirect3DSurface9GLES::UnlockRect (_ZN9d3d9_gles21IDirect3DSurface9GLES10UnlockRectEv + 0x310)
# VA 0x4ce8d0..0x4ce8e4 (6 instructions = 24 bytes):
# Keep m_upload allocated when m_keepShadow (byte at [x19, #0x43]) != 0.
# ---------------------------------------------------------------------------
PATCH3_SYM = "_ZN9d3d9_gles21IDirect3DSurface9GLES10UnlockRectEv"
PATCH3_OFFSET_IN_FUNC = 0x310
PATCH3_FALLBACK_VA = 0x4CE8D0
PATCH3_ORIG = pack_u32_list([
    0xF9403260,  # ldr  x0, [x19, #0x60]
    0xF9400AA1,  # ldr  x1, [x21, #0x10]
    0xF900327F,  # str  xzr, [x19, #0x60]
    0xA900FEBF,  # stp  xzr, xzr, [x21, #8]
    0xB4000060,  # cbz  x0, 0x4ce8ec
    0xCB000021,  # sub  x1, x1, x0
])
PATCH3_NEW = pack_u32_list([
    0x39410E60,  # ldrb w0, [x19, #0x43]   ; m_keepShadow
    0x350000C0,  # cbnz w0, 0x4ce8ec       ; keep m_upload if m_keepShadow != 0
    0xF9403260,  # ldr  x0, [x19, #0x60]   ; m_upload._M_start
    0xF900327F,  # str  xzr, [x19, #0x60]
    0xA900FEBF,  # stp  xzr, xzr, [x21, #8]
    0xB4000040,  # cbz  x0, 0x4ce8ec
])

# ---------------------------------------------------------------------------
# Patch 4: d3d9_gles::convertRowToRGBA8 (_ZN9d3d9_gles17convertRowToRGBA8E10_D3DFORMATPKhPhj + 0x2BC)
# VA 0x4c869c..0x4c86d8 (16 instructions = 64 bytes):
# Hardware ARM64 NEON 16-pixel ld4/st4 BGRA->RGBA loop with 1-pixel rev/extr scalar tail.
# ---------------------------------------------------------------------------
PATCH4_SYM = "_ZN9d3d9_gles17convertRowToRGBA8E10_D3DFORMATPKhPhj"
PATCH4_OFFSET_IN_FUNC = 0x2BC
PATCH4_FALLBACK_VA = 0x4C869C
PATCH4_ORIG = pack_u32_list([
    0x34FFEFC3,  # cbz  w3, 0x4c8494
    0x8B234823,  # add  x3, x1, w3, uxtw #2
    0xD503201F,  # nop
    0x39400820,  # ldrb w0, [x1, #2]
    0x39000080,  # strb w0, [x4]
    0x91001021,  # add  x1, x1, #4
    0x385FD020,  # ldurb w0, [x1, #-3]
    0x39000480,  # strb w0, [x4, #1]
    0x91001084,  # add  x4, x4, #4
    0x385FC020,  # ldurb w0, [x1, #-4]
    0x381FE080,  # sturb w0, [x4, #-2]
    0x385FF020,  # ldurb w0, [x1, #-1]
    0x381FF080,  # sturb w0, [x4, #-1]
    0xEB01007F,  # cmp  x3, x1
    0x54FFFEA1,  # b.ne 0x4c86a8
    0xD65F03C0,  # ret
])
PATCH4_PREV = pack_u32_list([
    0x71004063, 0x540000E3, 0x4CDF0420, 0x4EA01C04, 0x4EA21C40, 0x4EA41C82, 0x4C9F0480, 0x17FFFFF9,
    0x31004063, 0x54FFEEA0, 0xB8404425, 0x5AC008A6, 0x138660A5, 0xB8004485, 0x71000463, 0x17FFFFFA,
])
PATCH4_NEW = pack_u32_list([
    0x71004063,  # subs w3, w3, #16
    0x540000E3,  # b.cc 0x4c86bc
    0x4CDF0020,  # ld4  {v0.16b, v1.16b, v2.16b, v3.16b}, [x1], #64
    0x4EA01C04,  # mov  v4.16b, v0.16b
    0x4EA21C40,  # mov  v0.16b, v2.16b
    0x4EA41C82,  # mov  v2.16b, v4.16b
    0x4C9F0080,  # st4  {v0.16b, v1.16b, v2.16b, v3.16b}, [x4], #64
    0x17FFFFF9,  # b    0x4c869c
    0x31004063,  # adds w3, w3, #16
    0x54FFEEA0,  # b.eq 0x4c8494
    0xB8404425,  # ldr  w5, [x1], #4
    0x5AC008A6,  # rev  w6, w5
    0x138660A5,  # extr w5, w5, w6, #24
    0xB8004485,  # str  w5, [x4], #4
    0x71000463,  # subs w3, w3, #1
    0x17FFFFFA,  # b    0x4c86c0
])

# ---------------------------------------------------------------------------
# Patch 5A: Native ARM64 NEON YUV420->ARGB8888 (sub_006FFAA7 in v10 / sub_006FFD4A in v12)
# 43 instructions = 172 bytes
# ---------------------------------------------------------------------------
PATCH5A_SYMS = ("sub_006FFAA7", "sub_006FFD4A")
PATCH5A_ORIG_V10 = pack_u32_list([
    0xA9B87BFD, 0xD53BD041, 0x910003FD, 0xA90153F3, 0x91400034, 0x9100A294, 0xA9025BF5, 0x5285478B,
    0x72A0020B, 0xA90363F7, 0xD2C00218, 0xA9046BF9, 0x52856797, 0x72A00217, 0xA90573FB, 0xF001957A,
    0x9112235A, 0xF9003FE1, 0xB9401281, 0xB9400E88, 0x51001027, 0x51002024, 0x51003022, 0x29428E85,
    0x51004029, 0xB9401E86, 0x7940928C, 0x2948368E, 0xB8274B08, 0xB8244B05, 0xB8224B03, 0x11001025,
    0x11003023, 0x11004022, 0x11002024, 0x11005021, 0xB8294B06, 0x9001959C, 0x913BE39C, 0xB8634B07,
    0xB8624B08, 0x5285279B, 0x72A0021B,
])
PATCH5A_ORIG_V10_GCC11 = pack_u32_list([
    0xA9B87BFD, 0xD53BD041, 0x910003FD, 0xA90153F3, 0x91400034, 0x9100A294, 0xA9025BF5, 0x5285478B,
    0x72A0020B, 0xA90363F7, 0xD2C00218, 0xA9046BF9, 0x52856797, 0x72A00217, 0xA90573FB, 0xB00190FA,
    0x9112E35A, 0xF9003FE1, 0xB9401281, 0xB9400E88, 0x51001027, 0x51002024, 0x51003022, 0x29428E85,
    0x51004029, 0xB9401E86, 0x7940928C, 0x2948368E, 0xB8274B08, 0xB8244B05, 0xB8224B03, 0x11001025,
    0x11003023, 0x11004022, 0x11002024, 0x11005021, 0xB8294B06, 0xD00190FC, 0x913CA39C, 0xB8634B07,
    0xB8624B08, 0x5285279B, 0x72A0021B,
])
PATCH5A_ORIG_V12 = pack_u32_list([
    0xA9B87BFD, 0xD53BD041, 0x910003FD, 0xA90153F3, 0x91400034, 0x9100A294, 0xA9025BF5, 0x5285478B,
    0x72A0020B, 0xA90363F7, 0xD2C00218, 0xA9046BF9, 0x52856797, 0x72A00217, 0xA90573FB, 0x900196DA,
    0x9112635A, 0xF9003FE1, 0xB9401281, 0xB9400E88, 0x51001027, 0x51002024, 0x51003022, 0x29428E85,
    0x51004029, 0xB9401E86, 0x7940928C, 0x2948368E, 0xB8274B08, 0xB8244B05, 0xB8224B03, 0x11001025,
    0x11003023, 0x11004022, 0x11002024, 0x11005021, 0xB8294B06, 0xB00196DC, 0x913C239C, 0xB8634B07,
    0xB8624B08, 0x5285279B, 0x72A0021B,
])
PATCH5A_PREV = pack_u32_list([
    0xD53BD041, 0xB9403822, 0x11001040, 0xB9003820, 0xB900283F, 0xD2C00208, 0x8B224102, 0x29409043,
    0x29419845, 0xB9401447, 0x6B0600EB, 0x540003E9, 0x53037D6B, 0x0B0B0469, 0x0B0B008A, 0x2905A829,
    0x8B234103, 0x8B244104, 0x8B254105, 0x8B264106, 0xD2893C0C, 0xF2A0102C, 0x8B0C010C, 0x9120018D,
    0x912001AE, 0x3840148F, 0x384014B0, 0xFC6F59A2, 0xFC7059C3, 0x4E630C42, 0x3940006F, 0x39400470,
    0x91000863, 0xFC6F5980, 0xFC705981, 0x4E620C00, 0x4E620C21, 0x6E081C20, 0x2E212800, 0xFC0084C0,
    0x7100056B, 0x54FFFE01, 0xD65F03C0,
])
PATCH5A_NEW = pack_u32_list([
    0xD53BD041,  # [0]  mrs  x1, tpidr_el0
    0xB9403822,  # [1]  ldr  w2, [x1, #0x38]       ; g_esp
    0x11001040,  # [2]  add  w0, w2, #4
    0xB9003820,  # [3]  str  w0, [x1, #0x38]       ; g_esp += 4 (pop return address)
    0xB900283F,  # [4]  str  wzr, [x1, #0x28]      ; g_eax = 0
    0xD2C00208,  # [5]  movz x8, #0x10, lsl #32    ; x8 = 0x1000000000 (guest base)
    0x8B224102,  # [6]  add  x2, x8, w2, uxtw      ; host stack ptr
    0x29409043,  # [7]  ldp  w3, w4, [x2, #4]      ; w3 = y_va, w4 = u_va
    0x29419845,  # [8]  ldp  w5, w6, [x2, #12]     ; w5 = v_va, w6 = dst_va
    0xB9401447,  # [9]  ldr  w7, [x2, #20]         ; w7 = dst_end_va
    0x6B0600EB,  # [10] subs w11, w7, w6           ; w11 = byte length
    0x540003E9,  # [11] b.ls [42] (done)
    0x53037D6B,  # [12] lsr  w11, w11, #3          ; w11 = N (2-pixel pairs)
    0x0B0B0469,  # [13] add  w9, w3, w11, lsl #1   ; g_ecx = y_va + 2*N
    0x0B0B008A,  # [14] add  w10, w4, w11          ; g_edx = u_va + N
    0x2905A829,  # [15] stp  w9, w10, [x1, #0x2c]  ; update g_ecx, g_edx
    0x8B234103,  # [16] add  x3, x8, w3, uxtw      ; x3 = y_ptr
    0x8B244104,  # [17] add  x4, x8, w4, uxtw      ; x4 = u_ptr
    0x8B254105,  # [18] add  x5, x8, w5, uxtw      ; x5 = v_ptr
    0x8B264106,  # [19] add  x6, x8, w6, uxtw      ; x6 = dst_ptr
    0xD2893C0C,  # [20] movz x12, #0x49e0
    0xF2A0102C,  # [21] movk x12, #0x0081, lsl #16
    0x8B0C010C,  # [22] add  x12, x8, x12          ; x12 = Y_tab (0x10008149e0)
    0x9120018D,  # [23] add  x13, x12, #0x800      ; x13 = U_tab (0x10008151e0)
    0x912001AE,  # [24] add  x14, x13, #0x800      ; x14 = V_tab (0x10008159e0)
    0x3840148F,  # [25] ldrb w15, [x4], #1         ; u = *u_ptr++
    0x384014B0,  # [26] ldrb w16, [x5], #1         ; v = *v_ptr++
    0xFC6F59A2,  # [27] ldr  d2, [x13, w15, uxtw #3]
    0xFC7059C3,  # [28] ldr  d3, [x14, w16, uxtw #3]
    0x4E630C42,  # [29] sqadd v2.8h, v2.8h, v3.8h
    0x3940006F,  # [30] ldrb w15, [x3]             ; y0 = y_ptr[0]
    0x39400470,  # [31] ldrb w16, [x3, #1]         ; y1 = y_ptr[1]
    0x91000863,  # [32] add  x3, x3, #2
    0xFC6F5980,  # [33] ldr  d0, [x12, w15, uxtw #3]
    0xFC705981,  # [34] ldr  d1, [x12, w16, uxtw #3]
    0x4E620C00,  # [35] sqadd v0.8h, v0.8h, v2.8h
    0x4E620C21,  # [36] sqadd v1.8h, v1.8h, v2.8h
    0x6E180420,  # [37] mov  v0.d[1], v1.d[0]
    0x2E212800,  # [38] sqxtun v0.8b, v0.8h
    0xFC0084C0,  # [39] str  d0, [x6], #8
    0x7100056B,  # [40] subs w11, w11, #1
    0x54FFFE01,  # [41] b.ne [25]
    0xD65F03C0,  # [42] ret
])

# ---------------------------------------------------------------------------
# Patch 5B: VP6 CPU Feature Probe (sub_0070CCE8 in v10 / sub_0070CF98 in v12)
# Sets *has_mmx = 0, *has_xmm = 0, *has_wmt = 0 so VP6 uses pure 32-bit scalar C
# instead of V128 stack-union emulated MMX/SSE2.
# ---------------------------------------------------------------------------
PATCH5B_SYMS = ("sub_0070CCE8", "sub_0070CF98")
PATCH5B_ORIG = pack_u32_list([
    0xA9B87BFD, 0x52BBD5A6, 0x910003FD, 0xA90153F3, 0xD53BD054, 0x91400293, 0x9100A273,
    0xA9025BF5, 0xD28000C5, 0xA90363F7, 0xD2C00217, 0xA9046BF9, 0xD2800024,
])
PATCH5B_NEW = pack_u32_list([
    0xD53BD041,  # [0]  mrs  x1, tpidr_el0
    0xB9403822,  # [1]  ldr  w2, [x1, #0x38]       ; g_esp
    0x11001040,  # [2]  add  w0, w2, #4
    0xB9003820,  # [3]  str  w0, [x1, #0x38]       ; g_esp += 4
    0xB900283F,  # [4]  str  wzr, [x1, #0x28]      ; g_eax = 0
    0xD2C00208,  # [5]  movz x8, #0x10, lsl #32    ; x8 = 0x1000000000
    0x8B224102,  # [6]  add  x2, x8, w2, uxtw      ; host stack ptr
    0x29409043,  # [7]  ldp  w3, w4, [x2, #4]      ; has_mmx_va, has_xmm_va
    0xB9400C45,  # [8]  ldr  w5, [x2, #12]         ; has_wmt_va
    0xB823491F,  # [9]  str  wzr, [x8, w3, uxtw]   ; *has_mmx = 0
    0xB824491F,  # [10] str  wzr, [x8, w4, uxtw]   ; *has_xmm = 0
    0xB825491F,  # [11] str  wzr, [x8, w5, uxtw]   ; *has_wmt = 0
    0xD65F03C0,  # [12] ret
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

    def resolve_sym_offset(self, sym_name: str, offset_in_func: int = 0, fallback_va: Optional[int] = None) -> Optional[int]:
        if sym_name in self.symbols:
            va, _ = self.symbols[sym_name]
            return self.va_to_file_offset(va + offset_in_func)
        if fallback_va is not None:
            return self.va_to_file_offset(fallback_va)
        return None


def apply_or_verify_site(
    raw: bytearray,
    name: str,
    file_off: Optional[int],
    orig_bytes_list: List[bytes],
    new_bytes: bytes,
    revert: bool,
    verify_only: bool,
) -> Tuple[bool, bool]:
    """Returns (ok_or_patched, modified)."""
    if file_off is None or file_off + len(new_bytes) > len(raw):
        print(f"  [ERROR] {name}: Invalid file offset")
        return (False, False)

    cur = bytes(raw[file_off : file_off + len(new_bytes)])
    is_patched = cur == new_bytes
    orig_match = next((ob for ob in orig_bytes_list if cur == ob), None)

    if verify_only:
        state_str = "PATCHED" if is_patched else ("ORIGINAL" if orig_match else "UNKNOWN")
        print(f"  [{'OK' if is_patched else '  '}] {name:48s} @ File 0x{file_off:07x} -> {state_str}")
        return (is_patched, False)

    if revert:
        if is_patched:
            raw[file_off : file_off + len(new_bytes)] = orig_bytes_list[0]
            print(f"  [OK]   Reverted {name} @ File 0x{file_off:07x}")
            return (True, True)
        elif orig_match is not None:
            print(f"  [SKIP] {name} (already in original state)")
            return (True, False)
        else:
            print(f"  [ERROR] {name} @ File 0x{file_off:07x}: unexpected bytes {cur[:8].hex()}")
            return (False, False)
    else:
        if is_patched:
            print(f"  [SKIP] {name} (already patched)")
            return (True, False)
        elif orig_match is not None:
            raw[file_off : file_off + len(new_bytes)] = new_bytes
            print(f"  [OK]   Patched  {name} @ File 0x{file_off:07x}")
            return (True, True)
        else:
            print(f"  [ERROR] {name} @ File 0x{file_off:07x}: unexpected bytes {cur[:8].hex()}")
            return (False, False)


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

    off_p1 = resolver.resolve_sym_offset(PATCH1_SYM, PATCH1_OFFSET_IN_FUNC, PATCH1_FALLBACK_VA)
    off_p2a = resolver.resolve_sym_offset(PATCH2_SYM, PATCH2A_OFFSET_IN_FUNC, PATCH2A_FALLBACK_VA)
    off_p2b = resolver.resolve_sym_offset(PATCH2_SYM, PATCH2B_OFFSET_IN_FUNC, PATCH2B_FALLBACK_VA)
    off_p3 = resolver.resolve_sym_offset(PATCH3_SYM, PATCH3_OFFSET_IN_FUNC, PATCH3_FALLBACK_VA)
    off_p4 = resolver.resolve_sym_offset(PATCH4_SYM, PATCH4_OFFSET_IN_FUNC, PATCH4_FALLBACK_VA)

    # Resolve YUV420->ARGB8888 (v10: sub_006FFAA7, v12: sub_006FFD4A)
    off_p5a = None
    is_v12_yuv = False
    for sym in PATCH5A_SYMS:
        if sym in resolver.symbols:
            off_p5a = resolver.resolve_sym_offset(sym, 0)
            is_v12_yuv = sym == "sub_006FFD4A"
            break
    if off_p5a is None:
        if len(raw) == 87_349_296:
            off_p5a = 0x47C0440 - 0x400000
        elif len(raw) == 88_589_712:
            off_p5a = 0x48C6C40 - 0x400000
            is_v12_yuv = True

    # Resolve VP6 CPU feature probe (v10: sub_0070CCE8, v12: sub_0070CF98)
    off_p5b = None
    for sym in PATCH5B_SYMS:
        if sym in resolver.symbols:
            off_p5b = resolver.resolve_sym_offset(sym, 0)
            break
    if off_p5b is None:
        if len(raw) == 87_349_296:
            off_p5b = 0x4D16B90 - 0x400000
        elif len(raw) == 88_589_712:
            off_p5b = 0x4959D00 - 0x400000

    p5a_orig_list = (
        [PATCH5A_ORIG_V12, PATCH5A_ORIG_V10, PATCH5A_ORIG_V10_GCC11, PATCH5A_PREV]
        if is_v12_yuv
        else [PATCH5A_ORIG_V10, PATCH5A_ORIG_V10_GCC11, PATCH5A_ORIG_V12, PATCH5A_PREV]
    )
    # Accept any relinked build whose 39 non-PC-relative instructions match PATCH5A_ORIG_V10
    # and whose 4 ADRP+ADD slots (15,16 = x26; 37,38 = x28) have the exact expected opcodes/regs.
    if off_p5a is not None and off_p5a + len(PATCH5A_ORIG_V10) <= len(raw):
        cur_p5a = bytes(raw[off_p5a:off_p5a + len(PATCH5A_ORIG_V10)])
        if cur_p5a not in p5a_orig_list and cur_p5a != PATCH5A_NEW:
            got_w = struct.unpack("<43I", cur_p5a)
            ref_w = struct.unpack("<43I", PATCH5A_ORIG_V10)
            reloc_checks = {
                15: (0x9F00001F, 0x9000001A),  # adrp x26, #page
                16: (0xFFC003FF, 0x9100035A),  # add  x26, x26, #off
                37: (0x9F00001F, 0x9000001C),  # adrp x28, #page
                38: (0xFFC003FF, 0x9100039C),  # add  x28, x28, #off
            }
            if all(
                ((got_w[i] & reloc_checks[i][0]) == reloc_checks[i][1])
                if i in reloc_checks
                else (got_w[i] == ref_w[i])
                for i in range(43)
            ):
                p5a_orig_list.append(cur_p5a)

    sites = [
        ("1. Async MovieTexture Lock (textureLockAsync)", off_p1, [PATCH1_ORIG], PATCH1_NEW),
        ("2a. OpTexUpload LockRect Discard (2D)", off_p2a, [PATCH2_ORIG], PATCH2_NEW),
        ("2b. OpTexUpload LockRect Discard (Cube/Vol)", off_p2b, [PATCH2_ORIG], PATCH2_NEW),
        ("3. Keep Dynamic Surface m_upload (UnlockRect)", off_p3, [PATCH3_ORIG], PATCH3_NEW),
        ("4. NEON 16-px BGRA->RGBA (convertRowToRGBA8)", off_p4, [PATCH4_ORIG, PATCH4_PREV], PATCH4_NEW),
        ("5a. NEON YUV420->ARGB8888 (sub_006FFAA7/D4A)", off_p5a, p5a_orig_list, PATCH5A_NEW),
        ("5b. VP6 32-bit Scalar C Mode (sub_0070CCE8/F98)", off_p5b, [PATCH5B_ORIG], PATCH5B_NEW),
    ]

    all_ok = True
    any_modified = False
    for name, f_off, orig_list, new_b in sites:
        ok, mod = apply_or_verify_site(raw, name, f_off, orig_list, new_b, revert=revert, verify_only=verify_only)
        if not ok:
            all_ok = False
        if mod:
            any_modified = True

    if verify_only:
        print(f"Status: {'PATCHED (All 7 Video Optimizations Active)' if all_ok else 'UNPATCHED / PARTIAL'}")
        return all_ok

    if not all_ok:
        print("Status: FAILED — binary was NOT modified due to unexpected byte patterns", file=sys.stderr)
        return False

    if any_modified:
        path.write_bytes(raw)
        after_md5 = hashlib.md5(raw).hexdigest()
        print(f"Status: {'Reverted' if revert else 'Patched'} successfully -> MD5: {after_md5}")
    else:
        print("Status: No changes required (all patches match requested state)")

    return True


def main():
    parser = argparse.ArgumentParser(description="Patch NFSU2 ARM64 binary to fix cutscene/FMV video stuttering.")
    parser.add_argument(
        "binaries",
        nargs="*",
        type=normalize_path,
        help="Paths to ARM64 binaries (e.g. nfsu2.aarch64 nfsu2.aarch64.v10 nfsu2.aarch64.v12)",
    )
    parser.add_argument("--revert", action="store_true", help="Revert binary back to original unpatched video state")
    parser.add_argument("--verify", action="store_true", help="Verify video patch status without modifying binary")

    args = parser.parse_args()

    targets = args.binaries
    if not targets:
        script_dir = Path(__file__).resolve().parent
        default_candidates = [
            script_dir / "ports" / "nfsu2" / "nfsu2.aarch64",
            script_dir / "ports" / "nfsu2" / "nfsu2.aarch64.v10",
            script_dir / "ports" / "nfsu2" / "nfsu2.aarch64.v12",
            script_dir / "nfsu2" / "nfsu2.aarch64",
            script_dir / "nfsu2" / "nfsu2.aarch64.v10",
            script_dir / "nfsu2" / "nfsu2.aarch64.v12",
            script_dir / "nfsu2.aarch64",
            script_dir / "nfsu2.aarch64.v10",
            script_dir / "nfsu2.aarch64.v12",
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
