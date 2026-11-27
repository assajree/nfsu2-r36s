---
name: nfsu2-attract-mode-patch
description: >-
  Diagnose and patch NFSU2 Title Screen Attract Mode (`sub_004C53B0` ->
  `UG_LS_IntroFMV.fng`) when Fast Boot causes Title music (Riders on the Storm)
  to restart every 30 seconds, or add conditional `FMVOpening.vp6` existence
  checks. Use when Title Screen audio loops/restarts without leaving the Title
  Screen, or when updating `patch_attract.py` / `overrides.c`.
---

# NFSU2 Title Screen Attract Mode Patch

## Root Cause
- In `SplashScreen::NotificationMessage` (`sub_004C53B0`), on `FE_TICK` (`0xc98356ba`), the game checks `(now - [esi+0x50]) * 0.00025f >= 30.0f` (`VA 0x00784478`) and switches to `"UG_LS_IntroFMV.fng"` (`FMVOpening.vp6`).
- When **Fast Boot** hides/renames `FMVOpening.vp6` (e.g. `_FMVOpening.vp6` via `NFSU2_Thai.sh`), the missing movie causes Attract Mode to finish immediately and reload the Title Screen, restarting *Riders on the Storm* every 30 seconds.

## Critical Patching Invariants
1. **Target `sub_004C53B0`, NOT `sub_004C50B0` / `sub_004C52E0`:**
   - `sub_004C50B0` (5.0s) and `sub_004C52E0` (4.0s, `THXMovieScreen`/`DemoPSAScreen`) are short logo-screen timers, not the Title Screen Attract Mode timer.
2. **Do NOT modify `30.0f` at `VA 0x00784478` in `.rdata`:**
   - Float constants in `.rdata` may be shared across unrelated functions.
3. **Do NOT early-return at the top of `sub_004C53B0`:**
   - `FE_TICK` code after `0x004c5465` still handles `PRESS_START` and first-time memory-card checks.
4. **Patch only the timeout conditional branch:**
   - Convert `b.ne +0x164` (`0x54000b21`) after the 30.0s check into unconditional `b +0x164` (`0x14000059`).
   - Verified offsets: `0x3c6e770` (`nfsu2.aarch64` / `.v10`) and `0x3d57960` (`nfsu2.aarch64.v12`).

## Conditional `FMVOpening.vp6` Check Approaches
When Attract Mode should only be suppressed if `FMVOpening.vp6` is missing:
1. **C Runtime Vtable Override + In-Memory Fast Boot (`source/nfsu2-recompiled-r36s`) — *Recommended for Recompiled Builds / PRs (Zero Guest Recompile, v10 & v12)*:**
   - `SplashScreen::NotificationMessage` (`0x004C53B0` v10 / `0x004C5580` v12) has **zero direct calls** and is 100% vtable-dispatched (`RECOMP_ICALL` -> `nfs_override_lookup`). Register `ov_splash_notify` in `k_overrides[]` (`src/runtime/overrides.c`) and map `0x004C53B0  0x004C5580  va` in `config/exe_functions.txt` (then run `python3 scripts/exe_variant.py header`). **Do NOT add it to `config/overrides.txt`** (which replaces the lifted body) and **do NOT wrap `sub_004C4EB0`** (which requires rebuilding guest `.o` files).
   - Inside `ov_splash_notify`: mark `g_splash_reached = 1`, and on `FE_TICK` (`MEM32(g_esp + 4u) == 0xC98356BAu`) when Attract Mode is suppressed, refresh `MEM32(g_ecx + 0x50u) = MEM32(0x008651ACu)` (identical FE tick global in both v10 and v12) before delegating to `recomp_lookup(NFS_VA(0x004C53B0))()`.
   - **Cross-Platform `FMVOpening.vp6` Detection:** Never use raw POSIX `access("MOVIES/FMVOpening.vp6", F_OK)` inside `overrides.c` (breaks case-sensitive Linux folders and Windows builds where `overrides.c` links without `guest_runtime.cpp`). Instead, probe via `gamePath("MOVIES/FMVOpening.vp6")` in `guest_runtime.cpp` (and `file_exists("MOVIES\\FMVOpening.vp6")` in `src/host/main.c`) and pass the boolean into `nfs_intro_init()`.
   - **In-Memory Fast Boot (`NFSU2_SKIP_INTRO=1`) & `NFSU2_ATTRACT_MODE=auto|0|1`:** Filter read-only opens/stats in `guest_files.inc` (`createFile`, `fileAttributes`, `longPath`, `findFirstFile`) and `src/shims/win32_shims.c` (`shim_CreateFileA`) for `MOVIES/` stems `ealogo`, `thx_logo`, `fmvopening`, `psa` (plus localized `_*` variants like `THX_logo_fr.vp6`). Never filter `blank.vp6` or `Scene*.vp6`. When both `NFSU2_SKIP_INTRO=1` and `NFSU2_ATTRACT_MODE=1` are set, unhide `fmvopening` once `g_splash_reached == 1` so Attract Mode can still play after 30s.
2. **Launcher / Manager Toggle (`NFSU2.sh` or `NFSU2_Thai.sh`) — *No Recompile Needed*:**
   - Check `[ -f "$GAMEDATA/MOVIES/FMVOpening.vp6" ]` before launch or inside the Skip/Restore Intro toggle.
   - If missing, apply `patch_attract.py` (`b +0x164`); if present, run `patch_attract.py --revert` (`b.ne +0x164`).

## Workflow & Verification
1. Apply / verify locally:
   - `python patch_attract.py --all`
   - `python patch_attract.py --all --verify`
2. Verify on R36H (`playos.local`) with GNU `objdump`:
   - `objdump -d --start-address=0x406e760 --stop-address=0x406e7a0 /roms/ports/nfsu2/nfsu2.aarch64`
   - Confirm `406e770: 14000059 b 406e8d4 <sub_004C53B0+0x474>`.
