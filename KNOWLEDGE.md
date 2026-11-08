# Need for Speed: Underground 2 (R36H / R36S PortMaster) — Engineering Knowledge Base

**Document ID:** `NFSU2-R36H-KB-001`  
**Revision:** `2.0.0` (Modular Architecture)  
**Last Updated:** 2026-11-08  
**Scope:** Architecture, Reverse Engineering, Thai Localization, Subtitles, Tool Suite, and Packaging  

---

## 1. System Architecture & Recompilation Fundamentals

### 1.1 Static Binary Recompilation vs. Emulation
* **No x86 Emulation:** The game does **not** run via Wine, Box86/Box64, or FEX-Emu.
* **Architecture:** The original x86 Windows machine instructions from retail `SPEED2.EXE` were statically lifted to Intermediate Representation (IR), translated to native C/C++ code, and compiled into a native **Linux ARM64 (aarch64)** ELF binary (`nfsu2.aarch64`).
* **Role of `SPEED2.EXE`:** The Windows `.EXE` file is loaded strictly as a PE asset container at runtime to verify byte segments, read initial data sections, and provide unlifted raw assets.

### 1.2 Guest Runtime Context (ABI & Register Mapping)
* The recompiled engine simulates the x86 CPU context within a thread-local structure accessible via ARM64 system register `tpidr_el0`:
  * `[tpidr_el0 + 0x28]`: Guest `EAX` / `AL` register.
  * `[tpidr_el0 + 0x38]`: Guest `ESP` register.
* **Stack Alignment Rule:** When patching functions in the recompiled binary that represent x86 `cdecl` or `stdcall` functions returning a boolean, the patch must:
  1. Set bit 0 of Guest `EAX` (`[tpidr_el0 + 0x28] |= 1`).
  2. Increment Guest `ESP` by 4 (`[tpidr_el0 + 0x38] += 4`) to simulate the x86 `ret` instruction popping the return address off the guest stack.
  3. Execute native ARM64 `ret`.

---

## 2. Localization & Thai Engine Reverse-Engineering

### 2.1 Asset Analysis
* `gamedata/LANGUAGES/Thailand.bin` (264,184 bytes):
  * **Chunk `0x00039000` (`STR_BLOCK`):** Contains 3,924 localized strings. Byte values $\ge \text{0x80}$ index into a 16-bit lookup table at chunk offset `+0x114` mapping to Thai Unicode codepoints `U+0E01..U+0E5B`.
  * **Chunk `0x00030201` (`FEngFont` / `FNTF`):** Embeds font glyph tables `conduitmditc_tt14i_thailand` (`0xa73823ff`) and `conduitmditc_tt21i_thailand` (`0x4815619d`) with advance widths and negative kernings for Thai combining vowels and tone marks.
* `gamedata/LANGUAGES/LanguageTextures.bin` (1,286,144 bytes):
  * Embeds JDLZ-compressed DXT3 font textures for `CONDUITMDITC_TT14I_THAI` (hash `0xa73823ff` at `0x817c0`) and `CONDUITMDITC_TT21I_THAI` (hash `0x4815619d` at `0x126340`).

### 2.2 Root Cause of Unpatched Language Failure
1. Setting `--lang=Thai` writes `"language" = "Thai"` to the guest virtual registry.
2. The game maps `"Thai"` to Language ID `0x0b` (11).
3. The retail v1.0 language descriptor table (`VA 0x7f7020..0x7f70d0`) contains only 11 slots (`0x00..0x0a`, English to Japanese). Slot 11 (`0x0b`) causes a NULL pointer dereference at `VA 0x4ff3dc`.
4. The font suffix stripper (`VA 0x51baa0`) fails to recognize the language, fails to strip `"_thailand"` from font names, and never streams texture hashes `0x4815619d` / `0xa73823ff`.

### 2.3 Binary Hijack Resolution (Slot 10 Redirection)
* The patch redirects slot 10 (formerly Japanese) to Thai ID `0x0b`:
  * `VA 0x79a6e8`: `"LANGUAGES\\JAPANESE.BIN"` $\rightarrow$ `"LANGUAGES\\THAILAND.BIN"`
  * `VA 0x79a700`: `"JAPANESE"` $\rightarrow$ `"THAILAND"`
  * `VA 0x7f6f40` & `0x7f6f48`: Injects streaming hashes `0x4815619d` and `0xa73823ff`.
  * `VA 0x7f70c0` & `0x7f7108`: Changes slot 10 ID from `0x0a` to `0x0b`.
  * `VA 0x7fca00` & `0x5b7677`: Changes default fallback language ID from `0xffffffff` to `0x0b`.

---

## 3. Subtitle Subsystem Reverse-Engineering

### 3.1 Subtitle Engine Whitelist Flaw
* In the retail engine, function `sub_0050CEF0` (`VA 0x50cef0` in x86 / `VA 0x5fd660` in ARM64) checks language IDs:
  ```c
  bool IsSubtitlesEnabled(void) {
      int lang = getLanguageId();
      if (lang == 2 && g_Flag) return true;  // German
      if (lang == 4) return true;           // French
      if (lang == 5 && g_Flag) return true;  // Spanish / Italian
      if (lang == 12) return true;          // Polish
      return false; // All other languages (Thai = 11, English = 0) -> FALSE!
  }
  ```
* Callers (`VA 0x4a8a1e` for PSA/Intro, `VA 0x55accf` for story comics Scene01..Scene20) skip calling the subtitle stream loader `sub_0057D730` if `sub_0050CEF0` returns `0`.
* In-game movie player (`sub_005535F0` / `VA 0x553708`) hardcoded `cmp $4, %eax` and `cmp $12, %eax`.

### 3.2 Dual-Layer Binary Patch Solution
1. **x86 PE Patch (`SPEED2.EXE`):**
   * File `0x10cef0` (`VA 0x50cef0`): `b0 01 c3 90 90 90 90 90` (`mov al, 1; ret; nop...`)
   * File `0x153703` (`VA 0x553703`): `eb 12 90...` (`jmp 0x153717`)
2. **ARM64 ELF Patch (`nfsu2.aarch64`):**
   * `sub_0050CEF0` (File `0x1fd660`): 32-byte sequence setting guest `AL = 1`, guest `ESP += 4`, and `ret`.
   * `sub_005535F0` (File `0x3b62ef0`): Dynamically resolves conditional branch `b.eq target` and replaces it with unconditional branch `b target`.

---

## 4. Virtual Keyboard Crash & Name Entry Resolution

### 4.1 Root Cause
* In retail `Thailand.bin`, default profile name is UTF-16LE Thai string `"ผู้เล่น"` and name entry prompt is `"ป้อนชื่อ:"`.
* PortMaster virtual keyboard overlay (`vkbd`) on R36H only supports ASCII character sets.
* Attempting to render Thai glyphs in the edit box causes an out-of-bounds glyph index crash in `PC_NAME_ENTRY`.

### 4.2 Thailand.bin Patch Table (Exact Size Preserved: 264,184 Bytes)
| Offset | Original (Thai) | Replacement (ASCII) | Hash | Description |
| :--- | :--- | :--- | :--- | :--- |
| `0x3A8AF` | `\xad\xa3\x86\x87\x8b\x83\x81\x00` (8 B) | `PLAYER\0\0` (8 B) | `0xd9dc2f12` | Default profile name |
| `0x243AA` | `\x88\x84\x85\x88\xa4\x9e\x83\x85:\x00` (10 B) | `Name:\0\0\0\0\0` (10 B) | `0x22729437` | Name entry prompt |
| `0x24228` | `\xa4\x9e\x83\x85\x00` (5 B) | `NAME\0` (5 B) | `0x818f0385` | Header label |
| `0x24158` | Thai title string (16 B) | `Create Name\0\0\0\0\0` (16 B) | `0x3de4eff0` | Dialog title |

---

## 5. Modular Script Architecture (Single Responsibility)

The development suite in the repository root (`./`) is organized into three single-responsibility scripts:

```text
./
├── patch_thai.py              <- Targets SPEED2.EXE (Windows x86 PE)
├── patch_subtitles.py         <- Targets nfsu2.aarch64 (Linux ARM64 ELF)
└── patch_thailand_bin.py      <- Targets LANGUAGES/Thailand.bin (Asset binary)
```

### Script Capabilities Matrix
| Capability | `patch_thai.py` | `patch_subtitles.py` | `patch_thailand_bin.py` |
| :--- | :---: | :---: | :---: |
| Target Type | Windows PE x86 | Linux ELF ARM64 | Custom EA BigChunk |
| Dynamic Symbol Table Resolution | N/A (Static PE VA) | Yes (`.symtab` parsing) | N/A |
| Verification Mode (`--verify`) | Supported | Supported | Supported |
| Revert Mode (`--revert`) | Supported | Supported | Supported |
| Automated Fallback Scanning | Yes | Yes (Prologue signature) | Yes |

---

## 6. Handheld Tools Suite (`tools/nfsu2_thai/`) & playOS Integration

### 6.1 Universal Stem-Matching Auto-Hide Standard
* **Constraint:** `clean_dir ⊆ clean_launcher`, `length(clean_dir) > 4`.
* Subfolder: `/roms/tools/nfsu2_thai/` $\rightarrow$ `clean_dir` = `"nfsu2thai"` (length 9).
* Launchers:
  * `Setup_NFSU2_Thai.sh` $\rightarrow$ `"setupnfsu2thai"` (Contains `"nfsu2thai"`) $\rightarrow$ **Auto-Hidden!**
  * `Uninstall_NFSU2_Thai.sh` $\rightarrow$ `"uninstallnfsu2thai"` (Contains `"nfsu2thai"`) $\rightarrow$ **Auto-Hidden!**
* `playfe` automatically skips scanning `/roms/tools/nfsu2_thai/`, keeping the TOOLS menu pristine without leaking internal files.

### 6.2 Deduplication & Save File Omission Rules
1. **Case-Sensitivity Deduplication:** Windows PC distributions often contain both `SPEED2.EXE` and `speed2.exe`. In `app/gamedata/`, only `SPEED2.EXE` is bundled. `Setup_NFSU2_Thai.sh` automatically copies and mirrors it as `speed2.exe` on target devices, reducing package size by 2.3 MB.
2. **No Bundled Save Games:** Tools packages must **never** bundle save games (`AppData/`). `Setup_NFSU2_Thai.sh` respects user progression and creates blank profile containers only if none exist.

---

## 7. Distribution Packages

| Package Name | Target Location | Size | Contents |
| :--- | :--- | :---: | :--- |
| **`nfsu2_thai_copy_paste.zip`** | `/roms/ports/` | ~63.6 MB | Drop-in copy-paste mod for R36H/R36S: `nfsu2/` (pre-patched `nfsu2.aarch64`, `nfsu2.aarch64.v10`, `gamedata/SPEED2.EXE`, `Thailand.bin`) & `README_INSTALL.txt` |
| **`NFSU2-R36S-Thai-v1.1.0.zip`** | `/roms/ports/` | ~98 MB | Full PortMaster port: `NFSU2.sh`, `nfsu2/` (pre-patched ARM64 binary, `SPEED2.EXE`, `Thailand.bin`, widescreen fix, 30 FPS config) |
| **`NFSU2-Thai-Dropin-Pack.zip`** | PC / Game Folder | ~4.6 MB | Drop-in mod: Patched `SPEED2.EXE`, `Thailand.bin`, Save profiles (Jane, Racer, svvv), `README_THAI_INSTALL.txt` |
| **`nfsu2_thai.zip`** | `/roms/tools/` | ~4.1 MB | playOS Tools installer: `Install_NFSU2_Thai.sh`, `nfsu2_thai/` (autonomous setup & language switchers) |
